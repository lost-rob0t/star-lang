(in-package :starlogicadapterswi)

;; This is a deliberately closed adapter primitive, not general Prolog query
;; conformance. The row bridge matches star-prolog-kb's star_relation/4.
(defparameter +max-relation-count+ 256)
(defparameter +max-relation-string-chars+ 512)
(defparameter +max-relation-input-bytes+ 131072)
(defparameter +max-relation-answers+ 128)
(defparameter +max-relation-output-bytes+ 65536)
(defparameter +max-session-operations+ 128)

(defun %bounded-list (value maximum)
  "Reject improper, circular and over-budget lists without traversing forever."
  (loop with result = '()
        for tail = value then (cdr tail)
        for count from 0
        do (cond ((null tail) (return (nreverse result)))
                 ((or (not (consp tail)) (>= count maximum))
                  (%swi-fail 'swi-session-error "Expected a bounded proper list."))
                 (t (push (car tail) result)))))

(defun %closed-relation-record (value required &optional optional)
  (let ((entries (%bounded-list value (+ (length required) (length optional))))
        (seen '()))
    (dolist (entry entries)
      (unless (and (consp entry) (stringp (car entry))
                   (member (car entry) (append required optional) :test #'string=)
                   (not (member (car entry) seen :test #'string=)))
        (%swi-fail 'swi-session-error "Unknown, duplicate or malformed relation field."))
      (push (car entry) seen))
    (unless (every (lambda (key) (member key seen :test #'string=)) required)
      (%swi-fail 'swi-session-error "Missing required relation field."))
    entries))

(defun %relation-field (record key)
  (cdr (assoc key record :test #'string=)))

(defun %relation-string (value)
  (unless (and (stringp value)
               (<= 1 (length value) +max-relation-string-chars+)
               (every (lambda (char)
                        (let ((code (char-code char)))
                          (and (<= 1 code #x10ffff)
                               (not (<= #xd800 code #xdfff)))))
                      value))
    (%swi-fail 'swi-session-error "Relation strings must be bounded Unicode scalar text."))
  (copy-seq value))

(defun %relation-row (value)
  (let ((record (%closed-relation-record value '("id" "source" "predicate" "destination"))))
    (mapcar (lambda (key) (cons key (%relation-string (%relation-field record key))))
            '("id" "source" "predicate" "destination"))))

(defun %row-strings (row)
  (mapcar (lambda (key) (%relation-field row key))
          '("id" "source" "predicate" "destination")))

(defun %write-code-list (string stream)
  ;; Only decimal Unicode code points enter the private MQI grammar. Quotes,
  ;; backslashes and Prolog syntax in data cannot become executable source.
  (write-char #\[ stream)
  (loop for char across string for first-p = t then nil
        do (unless first-p (write-char #\, stream))
           (format stream "~D" (char-code char)))
  (write-char #\] stream))

(defun %rows-code-text (rows)
  (with-output-to-string (out)
    (write-char #\[ out)
    (loop for row in rows for first-row-p = t then nil
          do (unless first-row-p (write-char #\, out))
             (write-char #\[ out)
             (loop for string in (%row-strings row) for first-p = t then nil
                   do (unless first-p (write-char #\, out))
                      (%write-code-list string out))
             (write-char #\] out))
    (write-char #\] out)))

(defun %relation-digest (text)
  (format nil "sha256:~A"
          (string-downcase
           (ironclad:byte-array-to-hex-string
            (ironclad:digest-sequence
             :sha256 (babel:string-to-octets text :encoding :utf-8))))))

(defun %normalize-relation-snapshot (delta)
  (let* ((record (%closed-relation-record delta '("relations")))
         (rows (mapcar #'%relation-row
                       (%bounded-list (%relation-field record "relations")
                                      +max-relation-count+)))
         (bytes 0))
    (dolist (row rows)
      (dolist (string (%row-strings row))
        (incf bytes (length (babel:string-to-octets string :encoding :utf-8)))
        (when (> bytes +max-relation-input-bytes+)
          (%swi-fail 'swi-session-error "Relation snapshot exceeds its byte budget."))))
    (setf rows (sort rows #'string< :key (lambda (row) (%relation-field row "id"))))
    (loop for tail on rows while (cdr tail)
          when (string= (%relation-field (car tail) "id")
                        (%relation-field (cadr tail) "id"))
            do (%swi-fail 'swi-session-error "Duplicate source relation ID."))
    (let ((text (%rows-code-text rows)))
      (values text (%relation-digest text)))))

(defun %require-relation-session (backend session &key (open t))
  (unless (and (swi-session-p session) (eq backend (swi-session-backend session)))
    (%swi-fail 'swi-session-error "Logic session belongs to another backend."))
  (when (and open (not (eq :open (swi-session-state session))))
    (%swi-fail 'swi-session-error "Logic session is not open."))
  session)

(defun %relation-operation (backend session operation)
  (%require-relation-session backend session :open nil)
  (unless (and (swi-relation-operation-p operation)
               (eq session (swi-relation-operation-session operation))
               (member operation (swi-session-operations session) :test #'eq))
    (%swi-fail 'swi-session-error "Logic operation is not owned by this session."))
  operation)

(defun %invalidate-relation-worker (session)
  (setf (swi-session-state session) :failed)
  (dolist (operation (swi-session-operations session))
    (when (member (swi-relation-operation-state operation) '(:pending :running))
      (setf (swi-relation-operation-state operation) :failed
            (swi-relation-operation-answers operation) nil)))
  (%dispose-worker (swi-session-worker session)))

(defun %relation-request (session message)
  (handler-case
      (progn
        (unless (process-alive-p (swi-worker-process (swi-session-worker session)))
          (%swi-fail 'swi-worker-crash-error "SWI relation worker has exited."))
        ;; MQI's two-second query limit is complemented by a transport watchdog
        ;; on SBCL. A timed-out stream is never reused: disposal reaps the child.
        #+sbcl (sb-ext:with-timeout 5
                 (%send-private-message (swi-session-worker session) message))
        #-sbcl (%send-private-message (swi-session-worker session) message))
    (error (cause)
      (%invalidate-relation-worker session)
      (if (typep cause 'swi-adapter-error)
          (error cause)
          (%swi-fail-diagnostic 'swi-session-error (%bounded-diagnostic cause)
                                "SWI relation transport failed; session retired.")))))

(defmethod starlogicprotocol:apply-logic-fact-delta
    ((backend swi-backend) session delta)
  (%require-relation-session backend session :open nil)
  (bordeaux-threads:with-lock-held ((swi-session-lock session))
    (%require-relation-session backend session)
    (when (some (lambda (operation)
                  (member (swi-relation-operation-state operation) '(:pending :running)))
                (swi-session-operations session))
      (%swi-fail 'swi-session-error "Finish or cancel pending results before replacing facts."))
    (multiple-value-bind (text digest) (%normalize-relation-snapshot delta)
      ;; Replaying a snapshot is safe and deterministic. Still verify liveness;
      ;; an unchanged digest must not turn a dead worker into apparent success.
      (unless (process-alive-p (swi-worker-process (swi-session-worker session)))
        (%invalidate-relation-worker session)
        (%swi-fail 'swi-worker-crash-error "SWI relation worker has exited."))
      (if (equal digest (swi-session-snapshot-digest session))
          (values :unchanged (copy-seq digest))
          (let ((response (%relation-request
                           session (format nil "run(star_logic_bootstrap:star_logic_replace_relations(~A),2)" text))))
            (unless (%simple-true-response-p response)
              (%invalidate-relation-worker session)
              (%swi-fail 'swi-session-error "SWI rejected the relation snapshot; session retired."))
            (setf (swi-session-snapshot-digest session) digest)
            (values :applied (copy-seq digest)))))))

(defun %relation-limit (record key maximum)
  (let* ((entry (assoc key record :test #'string=))
         (value (if entry (cdr entry) maximum)))
    (unless (and (integerp value) (<= 1 value maximum))
      (%swi-fail 'swi-session-error "Relation query limit is outside its supported range."))
    value))

(defmethod starlogicprotocol:invoke-logic-operation
    ((backend swi-backend) session operation-id parameters &key limits)
  (%require-relation-session backend session :open nil)
  (bordeaux-threads:with-lock-held ((swi-session-lock session))
    (%require-relation-session backend session)
    (unless (and (stringp operation-id) (string= operation-id "relation-neighbors"))
      (error 'starlogicprotocol:unsupported-logic-operation-error
             :message "Only the fixed relation-neighbors operation is implemented."))
    (unless (swi-session-snapshot-digest session)
      (%swi-fail 'swi-session-error "Admit a relation snapshot before querying."))
    (when (>= (length (swi-session-operations session)) +max-session-operations+)
      (%swi-fail 'swi-session-error "Session operation budget exhausted; open a fresh session."))
    (let* ((record (%closed-relation-record parameters '("node" "predicate" "direction")))
           (node (%relation-string (%relation-field record "node")))
           (predicate (%relation-string (%relation-field record "predicate")))
           (direction (%relation-string (%relation-field record "direction")))
           (limits (%closed-relation-record limits nil '("answers" "output-bytes"))))
      (unless (member direction '("out" "in" "both") :test #'string=)
        (%swi-fail 'swi-session-error "Relation direction must be out, in or both."))
      (let ((operation
              (%make-relation-operation
               :session session :node node :predicate predicate :direction direction
               :snapshot-digest (copy-seq (swi-session-snapshot-digest session))
               :package-digest (copy-seq (swi-backend-bootstrap-digest backend))
               :answer-limit (%relation-limit limits "answers" +max-relation-answers+)
               :output-limit (%relation-limit limits "output-bytes" +max-relation-output-bytes+))))
        (push operation (swi-session-operations session))
        operation))))

(defun %neighbor-message (operation)
  (with-output-to-string (out)
    (write-string "run(star_logic_bootstrap:star_logic_neighbors(" out)
    (%write-code-list (swi-relation-operation-node operation) out)
    (write-char #\, out)
    (%write-code-list (swi-relation-operation-predicate operation) out)
    ;; Direction is an enumerated adapter literal, not caller Prolog source.
    (format out ",~A,~D,Rows),2)"
            (swi-relation-operation-direction operation)
            (1+ (swi-relation-operation-answer-limit operation)))))

(defun %neighbor-response-rows (response)
  (unless (and (%compound-p response "true")
               (= 1 (length (%compound-args response))))
    (%swi-fail 'swi-mqi-malformed-response-error "SWI relation query did not return one result."))
  (let* ((answers (%bounded-list (first (%compound-args response)) 1))
         (bindings (and (= 1 (length answers)) (%bounded-list (first answers) 1)))
         (binding (first bindings)))
    (unless (and (= 1 (length bindings)) (%compound-p binding "=")
                 (= 2 (length (%compound-args binding)))
                 (equal "Rows" (first (%compound-args binding))))
      (%swi-fail 'swi-mqi-malformed-response-error "SWI returned unexpected relation bindings."))
    (%bounded-list (second (%compound-args binding)) (1+ +max-relation-answers+))))

(defun %execute-neighbors (session operation)
  (setf (swi-relation-operation-state operation) :running)
  (handler-case
      (let* ((response (%relation-request session (%neighbor-message operation)))
             (raw-rows (%neighbor-response-rows response))
             (answers '())
             (bytes 0))
        (when (> (length raw-rows) (swi-relation-operation-answer-limit operation))
          (%swi-fail 'swi-query-limit-error "Relation answer limit exceeded; no partial result published."))
        (dolist (raw raw-rows)
          (let ((strings (%bounded-list raw 4)))
            (unless (= 4 (length strings))
              (%swi-fail 'swi-mqi-malformed-response-error "SWI returned an invalid relation row."))
            (let ((row (mapcar (lambda (key value) (cons (copy-seq key) value))
                               '("id" "source" "predicate" "destination")
                               (mapcar #'%relation-string strings))))
              ;; The declared output budget measures the exact UTF-8 JSON row
              ;; array. Counting Yason output includes all escaping and syntax.
              (push row answers))))
        (setf answers (nreverse answers))
        (setf bytes (length (babel:string-to-octets
                             (with-output-to-string (out)
                               (yason:encode
                                (coerce (mapcar (lambda (row)
                                                  (let ((object (make-hash-table :test #'equal)))
                                                    (dolist (entry row object)
                                                      (setf (gethash (car entry) object) (cdr entry)))))
                                                answers) 'vector)
                                out))
                             :encoding :utf-8)))
        (when (> bytes (swi-relation-operation-output-limit operation))
          (%swi-fail 'swi-query-limit-error "Relation output limit exceeded; no partial result published."))
        (setf (swi-relation-operation-answers operation) answers
              (swi-relation-operation-state operation) (if answers :running :no-answer)))
    (swi-query-limit-error (cause)
      (setf (swi-relation-operation-state operation) :failed)
      (error cause))
    (error (cause)
      (setf (swi-relation-operation-state operation) :failed)
      (%invalidate-relation-worker session)
      (if (typep cause 'swi-adapter-error) (error cause)
          (%swi-fail-diagnostic 'swi-session-error (%bounded-diagnostic cause)
                                "SWI relation operation failed; session retired.")))))

(defmethod starlogicprotocol:next-logic-result
    ((backend swi-backend) session operation)
  (%require-relation-session backend session :open nil)
  (bordeaux-threads:with-lock-held ((swi-session-lock session))
    (%require-relation-session backend session)
    (%relation-operation backend session operation)
    (when (eq :pending (swi-relation-operation-state operation))
      (%execute-neighbors session operation))
    (if (eq :running (swi-relation-operation-state operation))
        (let ((answer (pop (swi-relation-operation-answers operation))))
          (unless (swi-relation-operation-answers operation)
            (setf (swi-relation-operation-state operation) :completed))
          ;; Each answer is transferred only once; no internal alias survives.
          (values answer :answer))
        (values nil (swi-relation-operation-state operation)))))

(defmethod starlogicprotocol:cancel-logic-operation
    ((backend swi-backend) session operation reason)
  (%require-relation-session backend session :open nil)
  (bordeaux-threads:with-lock-held ((swi-session-lock session))
    (%relation-operation backend session operation)
    (%relation-string reason)
    (when (member (swi-relation-operation-state operation) '(:pending :running))
      (setf (swi-relation-operation-state operation) :cancelled
            (swi-relation-operation-answers operation) nil))
    (swi-relation-operation-state operation)))

(defmethod starlogicprotocol:logic-operation-status
    ((backend swi-backend) session operation)
  (%require-relation-session backend session :open nil)
  (bordeaux-threads:with-lock-held ((swi-session-lock session))
    (swi-relation-operation-state (%relation-operation backend session operation))))
