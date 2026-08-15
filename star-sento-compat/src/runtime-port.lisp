(in-package :starsentocompat)

(define-condition star-sento-compat-error (error)
  ((message :initarg :message :reader star-sento-compat-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-sento-compat-error-message condition) stream))))

(define-condition unsupported-sento-operation-error (star-sento-compat-error) ())

(defun fail-sento (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defstruct (runtime-port (:constructor %make-runtime-port))
  spawn-fn
  tell-fn
  ask-fn
  stop-fn
  watch-fn
  unwatch-fn
  link-fn
  resolve-fn
  mailbox-metrics-fn
  shutdown-fn)

(defun require-operation (operation name &key optional-p)
  (cond
    ((functionp operation) operation)
    (optional-p nil)
    (t
     (fail-sento
      'star-sento-compat-error
      "Sento compatibility operation ~A must be a function."
      name))))

(defun make-runtime-port
    (&key spawn tell ask stop watch unwatch link resolve mailbox-metrics shutdown)
  (%make-runtime-port
   :spawn-fn (require-operation spawn "spawn")
   :tell-fn (require-operation tell "tell")
   :ask-fn (require-operation ask "ask" :optional-p t)
   :stop-fn (require-operation stop "stop")
   :watch-fn (require-operation watch "watch" :optional-p t)
   :unwatch-fn (require-operation unwatch "unwatch" :optional-p t)
   :link-fn (require-operation link "link" :optional-p t)
   :resolve-fn (require-operation resolve "resolve" :optional-p t)
   :mailbox-metrics-fn
   (require-operation mailbox-metrics "mailbox-metrics" :optional-p t)
   :shutdown-fn (require-operation shutdown "shutdown")))

(defun invoke-runtime-operation (port accessor name arguments &key optional-p)
  (unless (runtime-port-p port)
    (fail-sento 'star-sento-compat-error
                "Expected a Sento compatibility runtime port, received ~S."
                port))
  (let ((operation (funcall accessor port)))
    (unless operation
      (if optional-p
          (fail-sento
           'unsupported-sento-operation-error
           "Sento compatibility operation ~A is not supported by this port."
           name)
          (fail-sento
           'star-sento-compat-error
           "Sento compatibility operation ~A is missing."
           name)))
    (handler-case
        (apply operation arguments)
      (star-sento-compat-error (condition)
        (error condition))
      (error (condition)
        (fail-sento
         'star-sento-compat-error
         "Sento compatibility operation ~A failed: ~A"
         name condition)))))

(defun runtime-spawn (port context name receive &rest options)
  (invoke-runtime-operation
   port #'runtime-port-spawn-fn "spawn"
   (list context name receive options)))

(defun runtime-tell (port actor message &optional sender)
  (invoke-runtime-operation
   port #'runtime-port-tell-fn "tell"
   (list actor message sender)))

(defun runtime-ask (port actor message &key timeout sender)
  (invoke-runtime-operation
   port #'runtime-port-ask-fn "ask"
   (list actor message timeout sender)
   :optional-p t))

(defun runtime-stop (port context actor)
  (invoke-runtime-operation
   port #'runtime-port-stop-fn "stop"
   (list context actor)))

(defun runtime-watch (port watcher actor)
  (invoke-runtime-operation
   port #'runtime-port-watch-fn "watch"
   (list watcher actor)
   :optional-p t))

(defun runtime-unwatch (port watcher actor)
  (invoke-runtime-operation
   port #'runtime-port-unwatch-fn "unwatch"
   (list watcher actor)
   :optional-p t))

(defun runtime-link (port left right)
  (invoke-runtime-operation
   port #'runtime-port-link-fn "link"
   (list left right)
   :optional-p t))

(defun runtime-resolve (port context target)
  (invoke-runtime-operation
   port #'runtime-port-resolve-fn "resolve"
   (list context target)
   :optional-p t))

(defun runtime-mailbox-metrics (port actor)
  (invoke-runtime-operation
   port #'runtime-port-mailbox-metrics-fn "mailbox-metrics"
   (list actor)
   :optional-p t))

(defun runtime-shutdown (port context)
  (invoke-runtime-operation
   port #'runtime-port-shutdown-fn "shutdown"
   (list context)))