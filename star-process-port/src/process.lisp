(in-package :starprocessport)

(define-condition process-port-error (error)
  ((message :initarg :message :reader process-port-error-message))
  (:report (lambda (condition stream)
             (write-string (process-port-error-message condition) stream))))

(define-condition invalid-process-command-error (process-port-error) ())

(define-condition process-launch-error (process-port-error)
  ((cause :initarg :cause :reader process-launch-error-cause)))

(define-condition process-disposal-error (process-port-error)
  ((cause :initarg :cause :reader process-disposal-error-cause)))

(define-condition process-result-error (process-port-error)
  ((result :initarg :result :reader process-result-error-result)))

(define-condition process-exit-error (process-result-error) ())
(define-condition process-timeout-error (process-result-error) ())
(define-condition process-cancelled-error (process-result-error) ())

(define-condition process-output-error (process-port-error)
  ((cause :initarg :cause :reader process-output-error-cause)))

(defvar *process-instance-lock* (make-lock "star-process-port instance ids"))
(defvar *process-instance-sequence* 0)

(defstruct (process-cancellation-token
            (:constructor %make-process-cancellation-token (lock)))
  lock
  (requested-p nil))

(defstruct (managed-process (:constructor %make-managed-process))
  info
  stdin
  stdout
  stderr
  instance-id
  (generation 0 :type (integer 0 *))
  executable
  (reaped-p nil)
  exit-code
  signal)

(defstruct (process-result (:constructor %make-process-result))
  outcome
  exit-code
  signal
  stdout
  stderr
  (stdout-truncated-p nil)
  (stderr-truncated-p nil)
  instance-id
  generation
  provenance)

(defstruct (capture-state (:constructor %make-capture-state (limit)))
  limit
  (stream (make-string-output-stream))
  (retained-count 0)
  (truncated-p nil)
  error)

(defun %fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun %non-empty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun %proper-list-p (value)
  ;; LIST-LENGTH returns NIL for circular lists and signals TYPE-ERROR for an
  ;; improper dotted tail. Both are invalid argv containers.
  (handler-case
      (integerp (list-length value))
    (type-error () nil)))

(defun %validate-command (executable argv)
  (unless (%non-empty-string-p executable)
    (%fail 'invalid-process-command-error
           "Executable must be a non-empty string."))
  (unless (%proper-list-p argv)
    ;; Do not print ARGV here: an invalid container may itself be circular.
    (%fail 'invalid-process-command-error
           "ARGV must be a proper finite list of strings."))
  (dolist (argument argv)
    (unless (stringp argument)
      ;; The argument value can itself be sensitive. Report only its position.
      (%fail 'invalid-process-command-error
             "ARGV contains a non-string argument.")))
  (cons executable (copy-list argv)))

(defun %validate-generation (generation)
  (unless (and (integerp generation) (not (minusp generation)))
    (%fail 'invalid-process-command-error
           "Process generation must be a non-negative integer."))
  generation)

(defun %validate-limit (name value)
  (unless (and (integerp value) (not (minusp value)))
    (%fail 'invalid-process-command-error
           "~A must be a non-negative integer." name))
  value)

(defun %validate-duration (name value &key allow-zero)
  (unless (and (typep value 'real)
               (if allow-zero (not (minusp value)) (plusp value)))
    (%fail 'invalid-process-command-error
           "~A must be a ~:[positive~;non-negative~] real number."
           name allow-zero))
  value)

(defun %next-process-instance-id ()
  (with-lock-held (*process-instance-lock*)
    (format nil "process-~D" (incf *process-instance-sequence*))))

(defun make-process-cancellation-token ()
  (%make-process-cancellation-token
   (make-lock "star-process-port cancellation token")))

(defun cancel-process-operation (token)
  (check-type token process-cancellation-token)
  (with-lock-held ((process-cancellation-token-lock token))
    (setf (process-cancellation-token-requested-p token) t))
  token)

(defun process-cancellation-requested-p (token)
  (check-type token process-cancellation-token)
  (with-lock-held ((process-cancellation-token-lock token))
    (process-cancellation-token-requested-p token)))

(defun launch-process (executable argv
                       &key directory
                         (element-type 'character)
                         (external-format :utf-8)
                         (generation 0))
  "Launch EXECUTABLE with exact ARGV without shell interpolation.

STDIN, STDOUT, and STDERR are separate streams. GENERATION is caller-owned
lifecycle metadata; each launch receives a fresh process-local INSTANCE-ID.
The returned process must be reaped with WAIT-PROCESS or DISPOSE-PROCESS."
  (let* ((command (%validate-command executable argv))
         (safe-generation (%validate-generation generation))
         (instance-id (%next-process-instance-id)))
    (handler-case
        (let ((info (uiop:launch-program
                     command
                     :input :stream
                     :output :stream
                     :error-output :stream
                     :directory directory
                     :element-type element-type
                     :external-format external-format)))
          (%make-managed-process
           :info info
           :stdin (uiop:process-info-input info)
           :stdout (uiop:process-info-output info)
           :stderr (uiop:process-info-error-output info)
           :instance-id instance-id
           :generation safe-generation
           :executable executable))
      (error (cause)
        ;; Never render ARGV or DIRECTORY here: either may contain secrets.
        (error 'process-launch-error
               :message (format nil
                                "Failed to launch executable ~S with ~D argument~:P."
                                executable (length argv))
               :cause cause)))))

(defun process-stdin (process)
  (managed-process-stdin process))

(defun process-stdout (process)
  (managed-process-stdout process))

(defun process-stderr (process)
  (managed-process-stderr process))

(defun process-instance-id (process)
  (managed-process-instance-id process))

(defun process-generation (process)
  (managed-process-generation process))

(defun process-reaped-p (process)
  (managed-process-reaped-p process))

(defun process-exit-code (process)
  (managed-process-exit-code process))

(defun process-signal (process)
  (managed-process-signal process))

(defun process-provenance (process)
  "Return secret-safe lifecycle provenance for PROCESS.

ARGV, environment, working directory, and captured output are intentionally not
part of provenance."
  (check-type process managed-process)
  (list :instance-id (managed-process-instance-id process)
        :generation (managed-process-generation process)
        :executable (managed-process-executable process)))

(defun process-alive-p (process)
  (and (managed-process-p process)
       (not (managed-process-reaped-p process))
       (uiop:process-alive-p (managed-process-info process))))

(defun %deadline (seconds)
  (+ (get-internal-real-time)
     (ceiling (* seconds internal-time-units-per-second))))

(defun %deadline-expired-p (deadline)
  (and deadline
       (>= (get-internal-real-time) deadline)))

(defun %close-process-streams (process)
  (ignore-errors (uiop:close-streams (managed-process-info process))))

(defun wait-process (process &key timeout (poll-interval 0.01d0) (close-streams t))
  "Wait for PROCESS and reap it.

Returns EXIT-CODE, :EXITED, and SIGNAL. With TIMEOUT, returns NIL and :TIMEOUT
if the child is still running when the bounded wait expires. CLOSE-STREAMS is
true by default; bounded collectors set it false until their drainers finish."
  (check-type process managed-process)
  (when timeout
    (%validate-duration "TIMEOUT" timeout :allow-zero t)
    (%validate-duration "POLL-INTERVAL" poll-interval))
  (when (managed-process-reaped-p process)
    (when close-streams
      (%close-process-streams process))
    (return-from wait-process
      (values (managed-process-exit-code process)
              :exited
              (managed-process-signal process))))
  (when timeout
    (let ((deadline (%deadline timeout)))
      (loop while (and (uiop:process-alive-p (managed-process-info process))
                       (not (%deadline-expired-p deadline)))
            do (sleep poll-interval))
      (when (uiop:process-alive-p (managed-process-info process))
        (return-from wait-process (values nil :timeout nil)))))
  (multiple-value-bind (exit-code signal)
      (uiop:wait-process (managed-process-info process))
    (setf (managed-process-exit-code process) exit-code
          (managed-process-signal process) signal
          (managed-process-reaped-p process) t)
    (when close-streams
      (%close-process-streams process))
    (values exit-code :exited signal)))

(defun terminate-process (process)
  (check-type process managed-process)
  (when (process-alive-p process)
    (uiop:terminate-process (managed-process-info process) :urgent nil))
  process)

(defun kill-process (process)
  (check-type process managed-process)
  (when (process-alive-p process)
    (uiop:terminate-process (managed-process-info process) :urgent t))
  process)

(defun %stop-and-reap (process terminate-timeout &key (close-streams t))
  (check-type process managed-process)
  (%validate-duration "TERMINATE-TIMEOUT" terminate-timeout :allow-zero t)
  (unless (managed-process-reaped-p process)
    (when (process-alive-p process)
      (handler-case
          (terminate-process process)
        (error ()
          ;; A graceful-stop failure must not suppress the urgent attempt.
          nil))
      (multiple-value-bind (exit status)
          (wait-process process
                        :timeout terminate-timeout
                        :close-streams close-streams)
        (declare (ignore exit))
        (when (eq status :timeout)
          (handler-case
              (kill-process process)
            (error (cause)
              (error 'process-disposal-error
                     :message "Failed to urgently terminate subprocess."
                     :cause cause))))))
    (unless (managed-process-reaped-p process)
      (handler-case
          (wait-process process :close-streams close-streams)
        (error (cause)
          (error 'process-disposal-error
                 :message "Failed to reap subprocess after termination."
                 :cause cause)))))
  (when (and close-streams (managed-process-reaped-p process))
    (%close-process-streams process))
  process)

(defun dispose-process (process &key (terminate-timeout 1.0d0))
  "Unconditionally dispose of PROCESS, escalating to an urgent termination.

This is the error-path primitive. Orderly protocol shutdown should happen
before calling it; regardless, the child is reaped before this function returns."
  (%stop-and-reap process terminate-timeout :close-streams t))

(defun %drain-stream-bounded (stream state)
  (handler-case
      (loop for character = (read-char stream nil nil)
            while character
            do (if (< (capture-state-retained-count state)
                      (capture-state-limit state))
                   (progn
                     (write-char character (capture-state-stream state))
                     (incf (capture-state-retained-count state)))
                   (setf (capture-state-truncated-p state) t)))
    (error (cause)
      (setf (capture-state-error state) cause)))
  state)

(defun %start-capture-thread (stream state name)
  (make-thread (lambda () (%drain-stream-bounded stream state)) :name name))

(defun %join-capture-thread (thread state)
  (join-thread thread)
  (when (capture-state-error state)
    (error 'process-output-error
           :message "Failed while draining subprocess output."
           :cause (capture-state-error state)))
  state)

(defun %capture-string (state)
  (get-output-stream-string (capture-state-stream state)))

(defun %make-result-from-process (process outcome stdout-state stderr-state)
  (%make-process-result
   :outcome outcome
   :exit-code (managed-process-exit-code process)
   :signal (managed-process-signal process)
   :stdout (%capture-string stdout-state)
   :stderr (%capture-string stderr-state)
   :stdout-truncated-p (capture-state-truncated-p stdout-state)
   :stderr-truncated-p (capture-state-truncated-p stderr-state)
   :instance-id (managed-process-instance-id process)
   :generation (managed-process-generation process)
   :provenance (process-provenance process)))

(defun run-process (executable argv
                    &key directory
                      timeout
                      cancellation-token
                      (generation 0)
                      (stdout-limit 65536)
                      (stderr-limit 65536)
                      (poll-interval 0.01d0)
                      (terminate-timeout 1.0d0))
  "Run an exact-argv subprocess with bounded text observation and lifecycle fencing.

STDOUT-LIMIT and STDERR-LIMIT bound retained characters; output beyond either
limit is drained and discarded so the child cannot block on a full pipe. TIMEOUT
is a monotonic deadline budget. CANCELLATION-TOKEN may be cancelled from another
thread. Timeout and cancellation always stop, escalate if necessary, and reap the
child before returning a PROCESS-RESULT."
  (%validate-limit "STDOUT-LIMIT" stdout-limit)
  (%validate-limit "STDERR-LIMIT" stderr-limit)
  (%validate-duration "POLL-INTERVAL" poll-interval)
  (%validate-duration "TERMINATE-TIMEOUT" terminate-timeout :allow-zero t)
  (when timeout
    (%validate-duration "TIMEOUT" timeout :allow-zero t))
  (when cancellation-token
    (check-type cancellation-token process-cancellation-token))
  (let* ((process nil)
         (stdout-state (%make-capture-state stdout-limit))
         (stderr-state (%make-capture-state stderr-limit))
         (stdout-thread nil)
         (stderr-thread nil)
         (deadline (and timeout (%deadline timeout)))
         (outcome nil)
         (streams-closed-p nil))
    (unwind-protect
         (progn
           (setf process (launch-process executable argv
                                         :directory directory
                                         :generation generation))
           ;; RUN-PROCESS is a closed-input one-shot operation. Long-lived
           ;; protocol adapters continue to use LAUNCH-PROCESS directly.
           (ignore-errors (close (managed-process-stdin process)))
           (setf stdout-thread
                 (%start-capture-thread (managed-process-stdout process)
                                        stdout-state
                                        "star-process-port stdout drainer")
                 stderr-thread
                 (%start-capture-thread (managed-process-stderr process)
                                        stderr-state
                                        "star-process-port stderr drainer"))
           (loop
             (cond
               ((and cancellation-token
                     (process-cancellation-requested-p cancellation-token))
                (setf outcome :cancelled)
                (return))
               ((%deadline-expired-p deadline)
                (setf outcome :timeout)
                (return))
               ((not (process-alive-p process))
                (setf outcome :exited)
                (return)))
             (sleep poll-interval))
           (if (member outcome '(:timeout :cancelled))
               (%stop-and-reap process terminate-timeout :close-streams nil)
               (wait-process process :close-streams nil))
           (when (and (eq outcome :exited) (managed-process-signal process))
             (setf outcome :signaled))
           (%join-capture-thread stdout-thread stdout-state)
           (%join-capture-thread stderr-thread stderr-state)
           (%close-process-streams process)
           (setf streams-closed-p t)
           (%make-result-from-process process outcome stdout-state stderr-state))
      (when process
        (unless (managed-process-reaped-p process)
          (ignore-errors
            (%stop-and-reap process terminate-timeout :close-streams nil)))
        (when stdout-thread
          (ignore-errors (join-thread stdout-thread)))
        (when stderr-thread
          (ignore-errors (join-thread stderr-thread)))
        (unless streams-closed-p
          (%close-process-streams process))))))

(defun process-result-success-p (result)
  (check-type result process-result)
  (and (eq (process-result-outcome result) :exited)
       (eql (process-result-exit-code result) 0)))

(defun ensure-process-success (result)
  "Return RESULT on success, otherwise signal a typed secret-safe lifecycle error."
  (check-type result process-result)
  (when (process-result-success-p result)
    (return-from ensure-process-success result))
  (let ((message (format nil
                         "Process ~A generation ~D ended with outcome ~S, exit ~S, signal ~S."
                         (process-result-instance-id result)
                         (process-result-generation result)
                         (process-result-outcome result)
                         (process-result-exit-code result)
                         (process-result-signal result))))
    (error (case (process-result-outcome result)
             (:timeout 'process-timeout-error)
             (:cancelled 'process-cancelled-error)
             (otherwise 'process-exit-error))
           :message message
           :result result)))
