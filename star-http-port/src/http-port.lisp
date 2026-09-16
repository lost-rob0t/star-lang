(in-package :starhttpport)

(define-condition http-port-error (error)
  ((message :initarg :message :reader http-port-error-message))
  (:report
   (lambda (condition stream)
     (write-string (http-port-error-message condition) stream))))

(define-condition http-backend-unavailable-error (http-port-error) ())
(define-condition http-request-error (http-port-error) ())

(define-condition http-transport-error (http-request-error)
  ((kind :initarg :kind :reader http-transport-error-kind)))

(defun fail-http (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defparameter +http-methods+
  '(:get :head :options :put :post :delete :patch))

(defstruct (http-request
            (:constructor %make-http-request
                (&key url method headers body connect-timeout read-timeout max-redirects)))
  (url "" :type string)
  (method :get :type keyword)
  headers
  body
  (connect-timeout 10 :type (integer 1 *))
  (read-timeout 10 :type (integer 1 *))
  (max-redirects 5 :type (integer 0 *)))

(defun make-http-request
    (url
     &key
       (method :get)
       headers
       body
       (connect-timeout 10)
       (read-timeout 10)
       (max-redirects 5))
  (unless (and (stringp url) (> (length url) 0))
    (fail-http 'http-request-error "HTTP URL must be a non-empty string."))
  (unless (member method +http-methods+ :test #'eq)
    (fail-http 'http-request-error "Unsupported HTTP method ~S." method))
  (unless (and (integerp connect-timeout) (> connect-timeout 0))
    (fail-http 'http-request-error "Connect timeout must be a positive integer."))
  (unless (and (integerp read-timeout) (> read-timeout 0))
    (fail-http 'http-request-error "Read timeout must be a positive integer."))
  (unless (and (integerp max-redirects) (>= max-redirects 0))
    (fail-http 'http-request-error "Max redirects must be a nonnegative integer."))
  (%make-http-request
   :url url
   :method method
   :headers headers
   :body body
   :connect-timeout connect-timeout
   :read-timeout read-timeout
   :max-redirects max-redirects))

(defstruct (http-response
            (:constructor make-http-response
                (&key body status headers final-url)))
  body
  (status 0 :type (integer 0 999))
  headers
  (final-url "" :type string))

(defun http-response-success-p (response)
  (and (http-response-p response)
       (<= 200 (http-response-status response) 299)))

(defstruct (http-client
            (:constructor %make-http-client (&key name request-fn)))
  (name "" :type string)
  request-fn)

(defun make-http-client (name request-fn)
  (unless (and (stringp name) (> (length name) 0))
    (fail-http 'http-request-error "HTTP client name must be a non-empty string."))
  (unless (functionp request-fn)
    (fail-http 'http-request-error "HTTP client request operation must be a function."))
  (%make-http-client :name name :request-fn request-fn))

(defun perform-http-request (client request)
  (unless (http-client-p client)
    (fail-http 'http-request-error "Expected an HTTP client, received ~S." client))
  (unless (http-request-p request)
    (fail-http 'http-request-error "Expected an HTTP request, received ~S." request))
  (let ((response (funcall (http-client-request-fn client) request)))
    (unless (http-response-p response)
      (fail-http 'http-request-error
                 "HTTP client ~A returned ~S instead of an HTTP response."
                 (http-client-name client)
                 response))
    response))

(defun http-get (client url &rest options)
  (perform-http-request
   client
   (apply #'make-http-request url :method :get options)))
