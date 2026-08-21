(in-package :starlogicadapterswi)

(define-condition swi-adapter-error (starlogicprotocol:star-logic-error)
  ((diagnostic :initarg :diagnostic :initform nil
               :reader swi-adapter-error-diagnostic)))

(define-condition swi-session-error
    (swi-adapter-error starlogicprotocol:logic-session-error) ())

(define-condition swi-executable-unavailable-error (swi-adapter-error) ())
(define-condition swi-worker-launch-error (swi-session-error) ())
(define-condition swi-worker-exited-during-startup-error (swi-session-error) ())
(define-condition swi-malformed-startup-data-error (swi-session-error) ())
(define-condition swi-socket-connection-error (swi-session-error) ())
(define-condition swi-authentication-error (swi-session-error) ())
(define-condition swi-unsupported-mqi-protocol-error (swi-session-error) ())
(define-condition swi-backend-identity-mismatch-error (swi-session-error) ())
(define-condition swi-bootstrap-package-mismatch-error (swi-session-error) ())
(define-condition swi-bootstrap-handshake-error (swi-session-error) ())
(define-condition swi-mqi-malformed-frame-error (swi-session-error) ())
(define-condition swi-mqi-malformed-response-error (swi-session-error) ())
(define-condition swi-unexpected-eof-error (swi-session-error) ())
(define-condition swi-shutdown-failure-error (swi-session-error) ())
(define-condition swi-worker-crash-error (swi-session-error) ())

(defun %swi-fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun %swi-fail-diagnostic (condition-type diagnostic control &rest arguments)
  (error condition-type
         :message (apply #'format nil control arguments)
         :diagnostic diagnostic))
