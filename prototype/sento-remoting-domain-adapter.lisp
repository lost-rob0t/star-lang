(in-package #:star-lang.core-surface.prototype)

(export '(make-sento-remoting-domain-port))

(defun make-sento-remoting-domain-port ()
  ;; Transitional domain-remoting composition only. Every concrete
  ;; Sento/cl-gserver operation is final-owned by star-sento-compat.
  (let ((port
          (make-domain-remoting-port
           :enable #'starsentocompat:sento-enable-remoting
           :actor-of #'starsentocompat:sento-actor-of
           :remote-ref #'starsentocompat:sento-make-remote-ref
           :tell #'starsentocompat:sento-tell
           :stop #'starsentocompat:sento-stop
           :disable #'starsentocompat:sento-disable-remoting)))
    (register-domain-remoting-runtime-port
     port
     #'starsentocompat:sento-remoting-port)
    port))
