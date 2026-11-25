(in-package :starlogicadapternprolog)

(define-condition nprolog-adapter-error (starlogicprotocol:star-logic-error)
  ((diagnostic :initarg :diagnostic :initform nil
               :reader nprolog-adapter-error-diagnostic)))

(define-condition nprolog-session-error
    (nprolog-adapter-error starlogicprotocol:logic-session-error) ())

(define-condition nprolog-executable-unavailable-error (nprolog-adapter-error) ())
(define-condition nprolog-bridge-unavailable-error (nprolog-adapter-error) ())
(define-condition nprolog-worker-launch-error (nprolog-session-error) ())
(define-condition nprolog-worker-exited-during-startup-error (nprolog-session-error) ())
(define-condition nprolog-malformed-startup-data-error (nprolog-session-error) ())
(define-condition nprolog-backend-identity-mismatch-error (nprolog-session-error) ())
(define-condition nprolog-package-mismatch-error (nprolog-session-error) ())
(define-condition nprolog-handshake-error (nprolog-session-error) ())
(define-condition nprolog-bridge-port-error (nprolog-session-error) ())
(define-condition nprolog-bridge-wire-error (nprolog-session-error) ())
(define-condition nprolog-bridge-handshake-error (nprolog-session-error) ())
(define-condition nprolog-request-too-large-error (nprolog-session-error) ())
(define-condition nprolog-canary-failure-error (nprolog-session-error) ())
(define-condition nprolog-shutdown-failure-error (nprolog-session-error) ())

(defparameter +max-native-diagnostic-chars+ 512)

(defun %nprolog-fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun %nprolog-fail-diagnostic (condition-type diagnostic control &rest arguments)
  (error condition-type
         :message (apply #'format nil control arguments)
         :diagnostic diagnostic))

(defun %bounded-diagnostic (value)
  (let ((string (princ-to-string (or value ""))))
    (if (> (length string) +max-native-diagnostic-chars+)
        (concatenate 'string
                     (subseq string 0 +max-native-diagnostic-chars+)
                     "…")
        string)))
