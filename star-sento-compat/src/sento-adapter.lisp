(in-package :starsentocompat)

(define-condition sento-backend-unavailable-error (star-sento-compat-error) ())

(defun sento-operation (package-name symbol-name)
  "Resolve a public Sento/cl-gserver operation only when the backend is loaded."
  (let ((package (find-package package-name)))
    (unless package
      (fail-sento
       'sento-backend-unavailable-error
       "Sento backend package ~A is not loaded. Load the Sento system that owns this operation before selecting the backend."
       package-name))
    (multiple-value-bind (symbol status) (find-symbol symbol-name package)
      (unless (and (eq status :external) symbol (fboundp symbol))
        (fail-sento
         'sento-backend-unavailable-error
         "Sento backend operation ~A::~A is unavailable."
         package-name symbol-name))
      (symbol-function symbol))))

(defun sento-operation-available-p (package-name symbol-name)
  (let ((package (find-package package-name)))
    (when package
      (multiple-value-bind (symbol status)
          (find-symbol symbol-name package)
        (and (eq status :external) symbol (fboundp symbol))))))

(defun sento-backend-available-p ()
  "Return true when the local actor-system backend is loaded.
Remoting is an optional, separately loaded Sento subsystem."
  (and (sento-operation-available-p "ASYS" "MAKE-ACTOR-SYSTEM")
       (sento-operation-available-p "AC" "ACTOR-OF")
       (sento-operation-available-p "AC" "FIND-ACTORS")
       (sento-operation-available-p "AC" "ALL-ACTORS")
       (sento-operation-available-p "AC" "STOP")
       (sento-operation-available-p "AC" "SHUTDOWN")
       (sento-operation-available-p "ACT" "TELL")
       (sento-operation-available-p "ACT" "ASK")
       (sento-operation-available-p "ACT" "REPLY")
       (sento-operation-available-p "FUTURE" "COMPLETE-P")
       (sento-operation-available-p "FUTURE" "FRESULT")
       t))

(defun sento-remoting-backend-available-p ()
  (and (sento-backend-available-p)
       (sento-operation-available-p "REM" "ENABLE-REMOTING")
       (sento-operation-available-p "REM" "DISABLE-REMOTING")
       (sento-operation-available-p "REM" "MAKE-REMOTE-REF")
       (sento-operation-available-p "REM" "REMOTING-PORT")
       t))

(defun sento-make-actor-system (&optional config)
  (funcall (sento-operation "ASYS" "MAKE-ACTOR-SYSTEM") config))

(defun sento-enable-remoting (system options)
  (apply (sento-operation "REM" "ENABLE-REMOTING") system options))

(defun sento-actor-of (system name receive options)
  (apply (sento-operation "AC" "ACTOR-OF")
         system
         :name name
         :receive receive
         options))

(defun sento-make-remote-ref (system uri options)
  (apply (sento-operation "REM" "MAKE-REMOTE-REF") system uri options))

(defun sento-tell (actor message &optional sender)
  (funcall (sento-operation "ACT" "TELL") actor message sender))

(defun sento-ask (actor message timeout sender)
  "Return Sento's asynchronous future for MESSAGE.

The concrete backend creates a temporary reply actor.  This operation never
blocks the caller or the caller's actor mailbox.  Sento does not accept an
explicit sender for asynchronous ask, so a non-NIL SENDER is rejected rather
than silently changing correlation semantics."
  (when sender
    (fail-sento 'star-sento-compat-error
                "Sento asynchronous ask does not accept an explicit sender."))
  (funcall (sento-operation "ACT" "ASK")
           actor message :time-out timeout))

(defun sento-reply (message &optional (sender nil sender-supplied-p))
  (if sender-supplied-p
      (funcall (sento-operation "ACT" "REPLY") message sender)
      (funcall (sento-operation "ACT" "REPLY") message)))

(defun sento-find-actors (context target)
  (funcall (sento-operation "AC" "FIND-ACTORS") context target))

(defun sento-all-actors (context)
  (funcall (sento-operation "AC" "ALL-ACTORS") context))

(defun sento-actor-live-p (context actor)
  (not (null (member actor (sento-all-actors context) :test #'eq))))

(defun sento-future-complete-p (future)
  (funcall (sento-operation "FUTURE" "COMPLETE-P") future))

(defun sento-future-result (future)
  "Return a completed ask result or map Sento's failure tuple to a condition."
  (unless (sento-future-complete-p future)
    (fail-sento 'star-sento-compat-error
                "Sento ask future is not complete."))
  (let ((result (funcall (sento-operation "FUTURE" "FRESULT") future)))
    (if (and (consp result) (eq (car result) :handler-error))
        (error 'sento-ask-failure-error
               :message (format nil "Sento ask failed: ~A" (cdr result))
               :cause (cdr result))
        result)))

(defun sento-stop (system actor &key wait)
  (funcall (sento-operation "AC" "STOP")
           system actor :wait wait))

(defun sento-disable-remoting (system)
  (funcall (sento-operation "REM" "DISABLE-REMOTING") system))

(defun sento-remoting-port (system)
  (funcall (sento-operation "REM" "REMOTING-PORT") system))

(defun sento-shutdown (system &key wait)
  (funcall (sento-operation "AC" "SHUTDOWN")
           system :wait wait))

(defun make-sento-runtime-port ()
  "Construct the StarLang semantic runtime port backed by public Sento calls.
The Sento system must be loaded before an operation is invoked, but this final
ASDF system itself deliberately has no hard dependency on Sento."
  (make-runtime-port
   :spawn #'sento-actor-of
   :tell #'sento-tell
   :ask #'sento-ask
   :stop #'sento-stop
   :resolve #'sento-find-actors
   :shutdown #'sento-shutdown))
