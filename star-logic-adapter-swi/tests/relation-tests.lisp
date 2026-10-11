(in-package :starlogicadapterswi-integration-tests)
(in-suite starlogicadapterswi-integration-tests)

;; Every test below uses the real pinned SWI process, the public protocol, and
;; the production adapter. No fake query evaluator stands in for Prolog.
(defmacro with-relation-session ((backend session) &body body)
  `(let* ((*print-circle* t) (*print-level* 4) (*print-length* 8)
          (,backend (fresh-backend))
          (,session (open-logic-session ,backend "relations")))
     (unwind-protect (progn ,@body)
       (ignore-errors (close-logic-session ,backend ,session)))))

(defun relation-row (id source predicate destination)
  (list (cons "id" (copy-seq id)) (cons "source" (copy-seq source))
        (cons "predicate" (copy-seq predicate)) (cons "destination" (copy-seq destination))))

(defun relation-snapshot (&rest rows)
  (list (cons "relations" rows)))

(defun neighbor-parameters (node &optional (direction "out") (predicate "owns"))
  (list (cons "node" node) (cons "predicate" predicate)
        (cons "direction" direction)))

(defun invoke-neighbors (backend session node &key (direction "out")
                                               (predicate "owns") limits)
  (starlogicprotocol:invoke-logic-operation
   backend session "relation-neighbors"
   (neighbor-parameters node direction predicate) :limits limits))

(defun collect-neighbors (backend session operation)
  (loop with answers = '()
        do (multiple-value-bind (answer state)
               (starlogicprotocol:next-logic-result backend session operation)
             (if (eq state :answer)
                 (push answer answers)
                 (return (values (nreverse answers) state))))))

(test relation-neighbors-executes-real-swi-and-replays-snapshot
  (with-relation-session (backend session)
    (let* ((rows (list (relation-row "r2" "alice" "owns" "beta")
                       (relation-row "r1" "alice" "owns" "alpha")
                       (relation-row "r3" "bob" "owns" "alice")
                       (relation-row "r4" "alice" "knows" "bob")))
           (delta (cons (cons "relations" rows) nil))
           (digest (nth-value 1 (starlogicprotocol:apply-logic-fact-delta
                                 backend session delta))))
      (is (uiop:string-prefix-p "sha256:" digest))
      (is (= 71 (length digest)))
      (is (string= digest
                   (nth-value 1 (starlogicprotocol:apply-logic-fact-delta
                                 backend session
                                 (list (cons "relations" (reverse rows)))))))
      ;; The adapter owns the admitted bytes, not caller aliases.
      (setf (char (cdr (assoc "source" (second rows) :test #'string=)) 0) #\X)
      (let ((operation (invoke-neighbors backend session "alice")))
        (is (eq :pending (starlogicprotocol:logic-operation-status
                          backend session operation)))
        (multiple-value-bind (answers state)
            (collect-neighbors backend session operation)
          (is (eq :completed state))
          (is (equal '("r1" "r2")
                     (mapcar (lambda (row) (cdr (assoc "id" row :test #'string=)))
                             answers)))
          (is (every (lambda (row)
                       (string= "owns" (cdr (assoc "predicate" row :test #'string=))))
                     answers)))
        (is (eq :completed (starlogicprotocol:cancel-logic-operation
                            backend session operation "late cancellation")))
        (is (eq :completed (nth-value 1 (starlogicprotocol:next-logic-result
                                        backend session operation)))))
      (multiple-value-bind (answers state)
          (collect-neighbors backend session
                             (invoke-neighbors backend session "alice" :direction "in"))
        (is (eq :completed state))
        (is (equal '("r3") (mapcar (lambda (row) (cdr (assoc "id" row :test #'string=))) answers)))))))

(test relation-snapshot-and-query-boundaries-fail-closed
  (with-relation-session (backend session)
    (signals starlogicprotocol:logic-session-error
      (invoke-neighbors backend session "alice"))
    (starlogicprotocol:apply-logic-fact-delta
     backend session (relation-snapshot (relation-row "r1" "alice" "owns" "bob")))
    (signals starlogicprotocol:unsupported-logic-operation-error
      (starlogicprotocol:invoke-logic-operation backend session "halt" nil))
    (dolist (parameters (list (neighbor-parameters "alice" "sideways")
                             (append (neighbor-parameters "alice") '(("rawGoal" . "halt")))
                             (append (neighbor-parameters "alice") '(("node" . "bob")))))
      (signals starlogicprotocol:logic-session-error
        (starlogicprotocol:invoke-logic-operation
         backend session "relation-neighbors" parameters)))
    (signals starlogicprotocol:logic-session-error
      (starlogicprotocol:apply-logic-fact-delta
       backend session
       (relation-snapshot (relation-row "same" "a" "owns" "b")
                          (relation-row "same" "b" "owns" "c"))))
    (signals starlogicprotocol:logic-session-error
      (starlogicprotocol:apply-logic-fact-delta
       backend session
       (relation-snapshot (relation-row "bad" (make-string 513 :initial-element #\x) "owns" "b"))))
    (let ((cycle (list (relation-row "r" "a" "owns" "b"))))
      (setf (cdr cycle) cycle)
      (signals starlogicprotocol:logic-session-error
        (starlogicprotocol:apply-logic-fact-delta backend session (list (cons "relations" cycle)))))
    (multiple-value-bind (answers state)
        (collect-neighbors backend session (invoke-neighbors backend session "alice"))
      (is (eq :completed state))
      (is (= 1 (length answers))))))

(test relation-lifecycle-cancellation-isolation-and-recovery
  (with-relation-session (backend session)
    (starlogicprotocol:apply-logic-fact-delta
     backend session (relation-snapshot (relation-row "r1" "a" "owns" "b")))
    (let ((operation (invoke-neighbors backend session "a")))
      (signals starlogicprotocol:logic-session-error
        (starlogicprotocol:apply-logic-fact-delta backend session (relation-snapshot)))
      (is (eq :cancelled (starlogicprotocol:cancel-logic-operation backend session operation "stop")))
      (is (eq :cancelled (nth-value 1 (starlogicprotocol:next-logic-result backend session operation))))
      (starlogicprotocol:apply-logic-fact-delta backend session (relation-snapshot))
      (is (eq :no-answer (nth-value 1 (collect-neighbors backend session
                                                       (invoke-neighbors backend session "a"))))))
    (let ((second (open-logic-session backend "other")))
      (unwind-protect
           (progn
             (starlogicprotocol:apply-logic-fact-delta backend second (relation-snapshot))
             (starlogicprotocol:apply-logic-fact-delta
              backend session (relation-snapshot (relation-row "r2" "a" "owns" "c")))
             (let ((operation (invoke-neighbors backend session "a")))
               (signals starlogicprotocol:logic-session-error
                 (starlogicprotocol:next-logic-result backend second operation))
               (is (eq :no-answer (nth-value 1 (collect-neighbors backend second
                                                                (invoke-neighbors backend second "a")))))
               (is (= 1 (length (collect-neighbors backend session operation))))))
        (close-logic-session backend second)))
    (let ((operation (invoke-neighbors backend session "a")))
      (close-logic-session backend session)
      (signals starlogicprotocol:logic-session-error
        (starlogicprotocol:next-logic-result backend session operation)))))

(test relation-answer-and-output-limits-never-silently-truncate
  (with-relation-session (backend session)
    (starlogicprotocol:apply-logic-fact-delta
     backend session (relation-snapshot (relation-row "r1" "a" "owns" "b")
                                        (relation-row "r2" "a" "owns" "c")))
    (dolist (limits '((("answers" . 1)) (("output-bytes" . 1))))
      (let ((operation (invoke-neighbors backend session "a" :limits limits)))
        (signals starlogicprotocol:logic-session-error
          (starlogicprotocol:next-logic-result backend session operation))
        (is (eq :failed (starlogicprotocol:logic-operation-status backend session operation)))
        (is (eq :failed (nth-value 1 (starlogicprotocol:next-logic-result backend session operation))))))
    (is (= 2 (length (collect-neighbors backend session (invoke-neighbors backend session "a")))))))

(test relation-strings-remain-data-and-self-loop-is-not-duplicated
  (with-relation-session (backend session)
    (let ((node (format nil "é雪'\\\"),halt.~%")))
      (starlogicprotocol:apply-logic-fact-delta
       backend session (relation-snapshot (relation-row "quoted" node "owns" node)))
      (let ((answers (collect-neighbors backend session
                                        (invoke-neighbors backend session node :direction "both"))))
        (is (= 1 (length answers)))
        (is (string= node (cdr (assoc "source" (first answers) :test #'string=)))))
      (is (process-alive-p (worker-process session))))))

(test relation-worker-crash-is-failed-and-reaped
  (with-relation-session (backend session)
    (starlogicprotocol:apply-logic-fact-delta
     backend session (relation-snapshot (relation-row "r1" "a" "owns" "b")))
    (let ((operation (invoke-neighbors backend session "a"))
          (process (worker-process session)))
      (kill-process process)
      (signals starlogicprotocol:logic-session-error
        (starlogicprotocol:next-logic-result backend session operation))
      (is (eq :failed (starlogicprotocol:logic-operation-status backend session operation)))
      (is (process-reaped-p process)))))

(test relation-count-bytes-and-operation-budgets-are-bounded
  (with-relation-session (backend session)
    (signals starlogicprotocol:logic-session-error
      (starlogicprotocol:apply-logic-fact-delta
       backend session
       (list (cons "relations" (loop for i below 257 collect
                                 (relation-row (format nil "r~3,'0D" i) "a" "owns" "b"))))))
    (signals starlogicprotocol:logic-session-error
      (starlogicprotocol:apply-logic-fact-delta
       backend session
       (list (cons "relations" (loop for i below 100 collect
                                 (relation-row (format nil "r~D" i)
                                               (make-string 512 :initial-element #\a)
                                               (make-string 512 :initial-element #\p)
                                               (make-string 512 :initial-element #\b)))))))
    (starlogicprotocol:apply-logic-fact-delta backend session (relation-snapshot))
    (dolist (limits '((("answers" . 0)) (("answers" . 129))
                     (("output-bytes" . 65537)) (("unknown" . 1))
                     (("answers" . 1) ("answers" . 2))))
      (signals starlogicprotocol:logic-session-error
        (invoke-neighbors backend session "a" :limits limits)))
    (let ((operations (loop repeat 128 collect (invoke-neighbors backend session "a"))))
      (signals starlogicprotocol:logic-session-error (invoke-neighbors backend session "a"))
      (dolist (operation operations)
        (starlogicprotocol:cancel-logic-operation backend session operation "budget test"))
      (is (every (lambda (operation)
                   (eq :cancelled (starlogicprotocol:logic-operation-status backend session operation)))
                 operations)))))

(test relation-owned-results-and-fresh-worker-snapshot-replay
  (with-relation-session (backend session)
    (let* ((snapshot (relation-snapshot (relation-row "r1" "a" "owns" "b")))
           (digest (nth-value 1 (starlogicprotocol:apply-logic-fact-delta backend session snapshot)))
           (first (collect-neighbors backend session (invoke-neighbors backend session "a"))))
      (setf (char (cdr (assoc "source" (first first) :test #'string=)) 0) #\X)
      (let ((again (collect-neighbors backend session (invoke-neighbors backend session "a"))))
        (is (string= "a" (cdr (assoc "source" (first again) :test #'string=)))))
      (let ((fresh (open-logic-session backend "replay")))
        (unwind-protect
             (progn
               (is (string= digest (nth-value 1 (starlogicprotocol:apply-logic-fact-delta backend fresh snapshot))))
               (let ((answers (collect-neighbors backend fresh (invoke-neighbors backend fresh "a"))))
                 (is (= 1 (length answers)))
                 (is (string= "r1" (cdr (assoc "id" (first answers) :test #'string=))))))
          (close-logic-session backend fresh))))))
