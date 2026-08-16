(defpackage :starlogicprotocol-tests
  (:use :cl)
  (:import-from :starlogicprotocol
                #:+logic-operation-running+
                #:+logic-operation-completed+
                #:+logic-operation-no-answer+
                #:+logic-operation-cancelled+
                #:invalid-logic-backend-descriptor-error
                #:duplicate-logic-backend-error
                #:logic-backend-not-found-error
                #:logic-backend-incompatible-error
                #:logic-backend-selection-error
                #:make-logic-backend-descriptor
                #:logic-backend-descriptor-id
                #:logic-backend-descriptor-semantic-profiles
                #:logic-backend-descriptor-capabilities
                #:make-logic-backend-registry
                #:register-logic-backend
                #:find-logic-backend
                #:list-logic-backends
                #:make-logic-selection-request
                #:select-logic-backend
                #:logic-selection-evidence-selected
                #:logic-selection-evidence-candidates
                #:logic-selection-candidate-backend-id
                #:logic-selection-candidate-status
                #:logic-backend-descriptor-of
                #:open-logic-session
                #:close-logic-session
                #:apply-logic-fact-delta
                #:invoke-logic-operation
                #:next-logic-result
                #:cancel-logic-operation
                #:logic-operation-status
                #:logic-backend-health)
  (:import-from :starlogictesting
                #:make-fake-logic-backend
                #:fake-logic-session-deltas)
  (:export #:run-tests))

(in-package :starlogicprotocol-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun make-query-backend
    (id &key
          (profiles '("star.logic.query/1"))
          (capabilities '("named-query"))
          (isolation '("process"))
          (hard-limits '("answers")))
  (make-fake-logic-backend
   :id id
   :semantic-profiles profiles
   :capabilities capabilities
   :isolation-classes isolation
   :hard-limits hard-limits
   :scripts '(("lookup" . ((("name" . "alice"))
                            (("name" . "bob"))))
              ("empty" . ()))))

(defun test-descriptor-validation-and-normalization ()
  (let ((descriptor
          (make-logic-backend-descriptor
           :id "swi-prolog"
           :version "9.0"
           :build-id "build-1"
           :semantic-profiles '("star.logic.tabled/1" "star.logic.query/1"
                                "star.logic.query/1")
           :capabilities '("tabling" "named-query" "tabling")
           :isolation-classes '("process")
           :hard-limits '("answers")
           :cooperative-limits '("wall-time"))))
    (check (equal '("star.logic.query/1" "star.logic.tabled/1")
                  (logic-backend-descriptor-semantic-profiles descriptor))
           "Descriptor semantic profiles were not normalized deterministically.")
    (check (equal '("named-query" "tabling")
                  (logic-backend-descriptor-capabilities descriptor))
           "Descriptor capabilities were not normalized deterministically."))
  (check
   (signals-p
    'invalid-logic-backend-descriptor-error
    (lambda ()
      (make-logic-backend-descriptor
       :id ""
       :version "1"
       :build-id "build"
       :semantic-profiles '()
       :capabilities '()
       :isolation-classes '()
       :hard-limits '()
       :cooperative-limits '())))
   "Descriptor accepted an empty backend id."))

(defun test-registry-is-deterministic-and-rejects-duplicates ()
  (let ((registry (make-logic-backend-registry))
        (zeta (make-query-backend "zeta"))
        (alpha (make-query-backend "alpha")))
    (register-logic-backend registry zeta)
    (register-logic-backend registry alpha)
    (check (equal '("alpha" "zeta")
                  (mapcar (lambda (backend)
                            (logic-backend-descriptor-id
                             (logic-backend-descriptor-of backend)))
                          (list-logic-backends registry)))
           "Registry order is not stable by backend id.")
    (check (eq alpha (find-logic-backend registry "alpha"))
           "Registry lookup did not return the registered backend.")
    (check
     (signals-p 'duplicate-logic-backend-error
                (lambda () (register-logic-backend registry alpha)))
     "Registry accepted a duplicate backend without :REPLACE.")))

(defun test-explicit-selection-and-evidence ()
  (let* ((registry (make-logic-backend-registry))
         (backend (make-query-backend "swi-prolog"
                                      :capabilities '("named-query" "tabling")
                                      :hard-limits '("answers" "output-bytes"))))
    (register-logic-backend registry backend)
    (multiple-value-bind (selected evidence)
        (select-logic-backend
         registry
         (make-logic-selection-request
          :backend-policy "swi-prolog"
          :semantic-profile "star.logic.query/1"
          :required-capabilities '("named-query")
          :required-hard-limits '("answers")
          :required-isolation "process"))
      (check (eq selected backend)
             "Explicit backend selection returned the wrong backend.")
      (check (string= "swi-prolog" (logic-selection-evidence-selected evidence))
             "Selection evidence did not record the selected backend.")
      (let ((candidate (first (logic-selection-evidence-candidates evidence))))
        (check (and (string= "swi-prolog"
                            (logic-selection-candidate-backend-id candidate))
                    (eq :accepted
                        (logic-selection-candidate-status candidate)))
               "Selection evidence did not record the accepted candidate.")))))

(defun test-incompatible-and-missing-pins-fail-before-execution ()
  (let ((registry (make-logic-backend-registry)))
    (register-logic-backend
     registry
     (make-query-backend "n-prolog" :capabilities '("named-query")))
    (check
     (signals-p
      'logic-backend-incompatible-error
      (lambda ()
        (select-logic-backend
         registry
         (make-logic-selection-request
          :backend-policy "n-prolog"
          :semantic-profile "star.logic.query/1"
          :required-capabilities '("tabling")))))
     "Explicit selection accepted a backend missing a required capability.")
    (check
     (signals-p
      'logic-backend-not-found-error
      (lambda ()
        (select-logic-backend
         registry
         (make-logic-selection-request
          :backend-policy "missing"
          :semantic-profile "star.logic.query/1"))))
     "Explicit selection accepted an unknown backend id.")))

(defun test-auto-selection-is-deterministic-and-refuses-ties ()
  (let ((registry (make-logic-backend-registry)))
    (let ((only (make-query-backend "only")))
      (register-logic-backend registry only)
      (multiple-value-bind (selected evidence)
          (select-logic-backend
           registry
           (make-logic-selection-request
            :backend-policy "auto"
            :semantic-profile "star.logic.query/1"
            :required-capabilities '("named-query")))
        (check (eq selected only)
               "AUTO did not select the sole compatible backend.")
        (check (string= "only" (logic-selection-evidence-selected evidence))
               "AUTO evidence did not record the selected backend.")))
    (register-logic-backend registry (make-query-backend "second"))
    (check
     (signals-p
      'logic-backend-selection-error
      (lambda ()
        (select-logic-backend
         registry
         (make-logic-selection-request
          :backend-policy "auto"
          :semantic-profile "star.logic.query/1"
          :required-capabilities '("named-query")))))
     "AUTO silently chose between multiple equally compatible backends.")))

(defun test-fake-backend-stream-and-terminal-states ()
  (let* ((backend (make-query-backend "fake"))
         (session (open-logic-session backend "session-1")))
    (check (equal '(:status :ok :backend-id "fake")
                  (logic-backend-health backend))
           "Fake backend health is not normalized as expected.")
    (check (eq :applied
               (apply-logic-fact-delta backend session
                                       '(:sequence 1 :kind :assert :fact-id "f-1")))
           "Fake fact delta was not applied.")
    (check (equal '((:sequence 1 :kind :assert :fact-id "f-1"))
                  (fake-logic-session-deltas session))
           "Fake backend did not retain ordered fact deltas defensively.")
    (let ((operation (invoke-logic-operation backend session "lookup" '())))
      (check (eq +logic-operation-running+
                 (logic-operation-status backend session operation))
             "Fake operation did not start RUNNING.")
      (multiple-value-bind (answer status)
          (next-logic-result backend session operation)
        (check (and (eq :answer status)
                    (equal '(("name" . "alice")) answer))
               "First fake answer was incorrect: ~S / ~S" answer status))
      (multiple-value-bind (answer status)
          (next-logic-result backend session operation)
        (check (and (eq :answer status)
                    (equal '(("name" . "bob")) answer))
               "Second fake answer was incorrect: ~S / ~S" answer status))
      (check (eq +logic-operation-completed+
                 (logic-operation-status backend session operation))
             "Fake operation did not become COMPLETED after its final answer.")
      (multiple-value-bind (answer status)
          (next-logic-result backend session operation)
        (check (and (null answer)
                    (eq +logic-operation-completed+ status))
               "Completed fake operation returned another result.")))
    (let ((empty-operation
            (invoke-logic-operation backend session "empty" '())))
      (multiple-value-bind (answer status)
          (next-logic-result backend session empty-operation)
        (check (and (null answer)
                    (eq +logic-operation-no-answer+ status)
                    (eq +logic-operation-no-answer+
                        (logic-operation-status
                         backend session empty-operation)))
               "Zero-answer query did not terminate as NO-ANSWER.")))
    (check (eq :closed (close-logic-session backend session))
           "Fake session did not close cleanly.")))

(defun test-cancellation-is-terminal ()
  (let* ((backend (make-query-backend "fake-cancel"))
         (session (open-logic-session backend "session-cancel"))
         (operation (invoke-logic-operation backend session "lookup" '())))
    (check (eq +logic-operation-cancelled+
               (cancel-logic-operation backend session operation "operator"))
           "Cancellation did not return CANCELLED.")
    (check (eq +logic-operation-cancelled+
               (logic-operation-status backend session operation))
           "Cancelled operation did not remain terminal.")
    (multiple-value-bind (answer status)
        (next-logic-result backend session operation)
      (check (and (null answer)
                  (eq +logic-operation-cancelled+ status))
             "Cancelled operation returned a result."))))

(defun test-final-systems-are-prototype-independent ()
  (check (null (find-package "STAR-LANG.PROTOTYPE"))
         "Portable logic systems loaded STAR-LANG.PROTOTYPE transitively.")
  (check (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
         "Portable logic systems loaded the core-surface prototype transitively."))

(defun run-tests ()
  (test-descriptor-validation-and-normalization)
  (test-registry-is-deterministic-and-rejects-duplicates)
  (test-explicit-selection-and-evidence)
  (test-incompatible-and-missing-pins-fail-before-execution)
  (test-auto-selection-is-deterministic-and-refuses-ties)
  (test-fake-backend-stream-and-terminal-states)
  (test-cancellation-is-terminal)
  (test-final-systems-are-prototype-independent)
  (format t "~&star-logic-protocol tests passed.~%")
  t)
