(in-package :starsentocompat)

(define-condition sento-backend-unavailable-error (star-sento-compat-error) ())

(defun sento-operation (package-name symbol-name)
  "Resolve a public Sento/cl-gserver operation only when the backend is loaded."
  (let ((package (find-package package-name)))
    (unless package
      (fail-sento
       'sento-backend-unavailable-error
       "Sento backend package ~A is not loaded. Load SENTO-REMOTING before selecting the Sento backend."
       package-name))
    (multiple-value-bind (symbol status) (find-symbol symbol-name package)
      (unless (and status symbol (fboundp symbol))
        (fail-sento
         'sento-backend-unavailable-error
         "Sento backend operation ~A::~A is unavailable."
         package-name symbol-name))
      (symbol-function symbol))))

(defun sento-backend-available-p ()
  (and (find-package "ASYS")
       (find-package "AC")
       (find-package "ACT")
       (find-package "REM")
       t))

(defun sento-make-actor-system (&rest options)
  (apply (sento-operation "ASYS" "MAKE-ACTOR-SYSTEM") options))

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

(defun sento-stop (system actor)
  (funcall (sento-operation "AC" "STOP") system actor))

(defun sento-disable-remoting (system)
  (funcall (sento-operation "REM" "DISABLE-REMOTING") system))

(defun sento-remoting-port (system)
  (funcall (sento-operation "REM" "REMOTING-PORT") system))

(defun sento-shutdown (system)
  (funcall (sento-operation "AC" "SHUTDOWN") system))

(defun make-sento-runtime-port ()
  "Construct the StarLang semantic runtime port backed by public Sento calls.
The Sento system must be loaded before an operation is invoked, but this final
ASDF system itself deliberately has no hard dependency on Sento."
  (make-runtime-port
   :spawn #'sento-actor-of
   :tell #'sento-tell
   :stop #'sento-stop
   :shutdown #'sento-shutdown))