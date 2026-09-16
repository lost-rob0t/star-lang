(in-package :starhttpdexador)

(defun dexador-request-arguments (request proxy insecure use-connection-pool)
  (append
   (list :method (http-request-method request)
         :headers (http-request-headers request)
         :connect-timeout (http-request-connect-timeout request)
         :read-timeout (http-request-read-timeout request)
         :max-redirects (http-request-max-redirects request)
         :proxy proxy
         :insecure insecure
         :use-connection-pool use-connection-pool)
   (when (http-request-body request)
     (list :content (http-request-body request)))))

(defun make-port-response (body status headers final-uri)
  (make-http-response
   :body body
   :status status
   :headers headers
   :final-url (princ-to-string final-uri)))

(defun response-from-http-failure (condition)
  (make-port-response
   (response-body condition)
   (response-status condition)
   (response-headers condition)
   (request-uri condition)))

(defun transport-error-kind (condition)
  (cond
    #+sbcl
    ((typep condition 'sb-sys:io-timeout)
     :timeout)
    ((typep condition 'timeout-error)
     :timeout)
    ((or (typep condition 'ssl-error-verify)
         (typep condition 'ssl-error-initialize))
     :tls)
    ((typep condition 'fast-http-error)
     :protocol)
    ((typep condition 'socket-error)
     :connection)
    (t
     :backend)))

(defun signal-transport-error (condition)
  (let ((kind (transport-error-kind condition)))
    (error 'http-transport-error
           :kind kind
           :message (format nil "HTTP transport failed (~(~A~))." kind))))

(defun call-dexador-request (request pool proxy insecure)
  (let ((use-connection-pool (not (null pool))))
    (flet ((call-request ()
             (multiple-value-bind (body status headers final-uri stream)
                 (apply #'request
                        (http-request-url request)
                        (dexador-request-arguments
                         request
                         proxy
                         insecure
                         use-connection-pool))
               (declare (ignore stream))
               (make-port-response body status headers final-uri))))
      (if pool
          (let ((dexador.connection-cache:*connection-pool* pool))
            (call-request))
          (call-request)))))

(defun perform-dexador-request (request pool proxy insecure)
  (handler-case
      (call-dexador-request request pool proxy insecure)
    (http-request-failed (condition)
      (response-from-http-failure condition))
    (error (condition)
      (signal-transport-error condition))))

(defun make-dexador-http-client (&key pool (proxy nil) (tls-policy :verify))
  "Create the first-class synchronous Dexador implementation of STAR-HTTP-PORT.

POOL is an optional caller-owned Dexador connection pool.  When omitted, the
client explicitly disables Dexador's process-global connection pool.  PROXY is
client-local and defaults to NIL (direct connection).  TLS-POLICY is either
:VERIFY (the default) or :INSECURE."
  (let ((insecure
          (ecase tls-policy
            (:verify nil)
            (:insecure t))))
    (make-http-client
     "dexador"
     (lambda (request)
       (perform-dexador-request request pool proxy insecure)))))
