(in-package :starprocessport)

(define-condition process-port-error (error)
  ((message :initarg :message :reader process-port-error-message))
  (:report (lambda (condition stream)
             (write-string (process-port-error-message condition) stream))))

(define-condition invalid-process-command-error (process-port-error) ())

(define-condition process-launch-error (process-port-error)
  ((cause :initarg :cause :reader process-launch-error-cause)))

(define-condition process-disposal-error (process-port-error) ())

(defstruct (managed-process (:constructor %make-managed-process))
  info
  stdin
  stdout
  stderr
  (reaped-p nil)
  exit-code)

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
           "Executable must be a non-empty string, got ~S." executable))
  (unless (%proper-list-p argv)
    ;; Do not print ARGV here: an invalid container may itself be circular.
    (%fail 'invalid-process-command-error
           "ARGV must be a proper finite list of strings."))
  (dolist (argument argv)
    (unless (stringp argument)
      (%fail 'invalid-process-command-error
             "ARGV contains non-string argument ~S." argument)))
  (cons executable (copy-list argv)))

(defun launch-process (executable argv
                       &key directory
                         (element-type 'character)
                         (external-format :utf-8))
  "Launch EXECUTABLE with exact ARGV without shell interpolation.

STDIN, STDOUT, and STDERR are separate streams. The returned process must be
reaped with WAIT-PROCESS or DISPOSE-PROCESS."
  (let ((command (%validate-command executable argv)))
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
           :stderr (uiop:process-info-error-output info)))
      (error (cause)
        (error 'process-launch-error
               :message (format nil "Failed to launch exact command ~S." command)
               :cause cause)))))

(defun process-stdin (process)
  (managed-process-stdin process))

(defun process-stdout (process)
  (managed-process-stdout process))

(defun process-stderr (process)
  (managed-process-stderr process))

(defun process-reaped-p (process)
  (managed-process-reaped-p process))

(defun process-exit-code (process)
  (managed-process-exit-code process))

(defun process-alive-p (process)
  (and (managed-process-p process)
       (not (managed-process-reaped-p process))
       (uiop:process-alive-p (managed-process-info process))))

(defun %deadline (seconds)
  (+ (get-internal-real-time)
     (ceiling (* seconds internal-time-units-per-second))))

(defun wait-process (process &key timeout (poll-interval 0.01d0))
  "Wait for PROCESS and reap it.

Returns EXIT-CODE and :EXITED. With TIMEOUT, returns NIL and :TIMEOUT if the
child is still running when the bounded wait expires."
  (check-type process managed-process)
  (when (managed-process-reaped-p process)
    (return-from wait-process
      (values (managed-process-exit-code process) :exited)))
  (when timeout
    (let ((deadline (%deadline timeout)))
      (loop while (and (uiop:process-alive-p (managed-process-info process))
                       (< (get-internal-real-time) deadline))
            do (sleep poll-interval))
      (when (uiop:process-alive-p (managed-process-info process))
        (return-from wait-process (values nil :timeout)))))
  (multiple-value-bind (exit-code signal)
      (uiop:wait-process (managed-process-info process))
    (declare (ignore signal))
    (setf (managed-process-exit-code process) exit-code
          (managed-process-reaped-p process) t)
    (ignore-errors (uiop:close-streams (managed-process-info process)))
    (values exit-code :exited)))

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

(defun dispose-process (process &key (terminate-timeout 1.0d0))
  "Unconditionally dispose of PROCESS, escalating to an urgent termination.

This is the error-path primitive. Orderly protocol shutdown should happen
before calling it; regardless, the child is reaped before this function returns."
  (check-type process managed-process)
  (unless (managed-process-reaped-p process)
    (when (process-alive-p process)
      (terminate-process process)
      (multiple-value-bind (exit status)
          (wait-process process :timeout terminate-timeout)
        (declare (ignore exit))
        (when (eq status :timeout)
          (kill-process process))))
    (unless (managed-process-reaped-p process)
      ;; After urgent termination, waiting is intentional: leaving an
      ;; asynchronously launched child unreaped is worse than blocking here.
      (handler-case
          (wait-process process)
        (error (cause)
          (%fail 'process-disposal-error
                 "Failed to reap subprocess after urgent termination: ~A"
                 cause)))))
  process)
