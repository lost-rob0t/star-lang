(in-package :starhttpdexador)

(defun dexador-request-arguments (request)
  (append
   (list :method (http-request-method request)
         :headers (http-request-headers request)
         :connect-timeout (http-request-connect-timeout request)
         :read-timeout (http-request-read-timeout request)
         :max-redirects (http-request-max-redirects request))
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

(defun perform-dexador-request (request)
  (handler-case
      (multiple-value-bind (body status headers final-uri stream)
          (apply #'request
                 (http-request-url request)
                 (dexador-request-arguments request))
        (declare (ignore stream))
        (make-port-response body status headers final-uri))
    (http-request-failed (condition)
      (response-from-http-failure condition))
    (error (condition)
      (signal-transport-error condition))))

(defun make-dexador-http-client ()
  "Create the first-class synchronous Dexador implementation of STAR-HTTP-PORT."
  (make-http-client "dexador" #'perform-dexador-request))
