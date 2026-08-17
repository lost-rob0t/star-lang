(in-package :starsentocompat-integration-tests)

(def-suite starsentocompat-integration-tests
  :description "Real Sento actor-system contract for the final compatibility boundary.")

(in-suite starsentocompat-integration-tests)

(defparameter *integration-timeout-seconds* 5.0)

(defun unique-actor-name (prefix)
  (format nil "starlang-~A-~A" prefix (gensym)))

(defun monotonic-seconds ()
  (/ (get-internal-real-time)
     (coerce internal-time-units-per-second 'double-float)))

(defun await-future
    (future &key (timeout *integration-timeout-seconds*) operation)
  (let ((deadline (+ (monotonic-seconds) timeout)))
    (loop
      (when (sento-future-complete-p future)
        (return (sento-future-result future)))
      (when (>= (monotonic-seconds) deadline)
        (error "Timed out after ~,3F seconds waiting for ~A."
               timeout (or operation "Sento future")))
      ;; Scheduler backoff only. Completion, not elapsed sleep, is the oracle.
      (sleep 0.001))))

(defun shutdown-real-actor-system (system)
  (sento-shutdown system :wait t)
  (let ((remaining (sento-all-actors system)))
    (when remaining
      (error "Sento teardown leaked actors: ~S" remaining))))

(defmacro with-real-actor-system ((system) &body body)
  `(let ((,system nil))
     (unwind-protect
          (progn
            (setf ,system (sento-make-actor-system))
            ,@body)
       (when ,system
         (shutdown-real-actor-system ,system)))))

(defun ask-result (port actor message &key timeout operation)
  (await-future
   (runtime-ask port actor message :timeout timeout)
   :timeout (or timeout *integration-timeout-seconds*)
   :operation operation))

(defun probe-events (port probe)
  (ask-result port probe :events :operation "probe event snapshot"))

(defun await-probe-events (port probe minimum)
  (let ((deadline (+ (monotonic-seconds) *integration-timeout-seconds*)))
    (loop
      for events = (probe-events port probe)
      when (>= (length events) minimum)
        return events
      when (>= (monotonic-seconds) deadline)
        do (error "Timed out waiting for ~D probe events; observed ~S."
                  minimum events)
      do (sleep 0.001))))

