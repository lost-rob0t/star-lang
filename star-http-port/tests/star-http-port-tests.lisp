(defpackage :starhttpport-tests
  (:use :cl)
  (:import-from :starhttpport
                #:http-request-error
                #:http-request-url
                #:http-request-method
                #:http-request-headers
                #:http-request-connect-timeout
                #:http-request-read-timeout
                #:http-request-max-redirects
                #:http-response-body
                #:http-response-status
                #:http-response-final-url
                #:http-response-success-p
                #:make-http-client
                #:make-http-request
                #:make-http-response
                #:perform-http-request
                #:http-get)
  (:export #:run-tests))

(in-package :starhttpport-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun run-tests ()
  (let ((seen nil)
        (client nil))
    (setf client
          (make-http-client
           "fixture"
           (lambda (request)
             (setf seen request)
             (make-http-response
              :body "<html><title>Star</title></html>"
              :status 200
              :headers '(("content-type" . "text/html"))
              :final-url (http-request-url request)))))

    (let ((response
            (http-get client
                      "https://example.test/page"
                      :headers '(("user-agent" . "StarLang-Test"))
                      :connect-timeout 3
                      :read-timeout 7
                      :max-redirects 2)))
      (check (string= "https://example.test/page" (http-request-url seen))
             "HTTP client did not receive the requested URL.")
      (check (eq :get (http-request-method seen))
             "HTTP GET helper emitted the wrong method.")
      (check (equal '(("user-agent" . "StarLang-Test"))
                    (http-request-headers seen))
             "HTTP request headers changed unexpectedly.")
      (check (= 3 (http-request-connect-timeout seen))
             "Connect timeout was not preserved.")
      (check (= 7 (http-request-read-timeout seen))
             "Read timeout was not preserved.")
      (check (= 2 (http-request-max-redirects seen))
             "Redirect limit was not preserved.")
      (check (= 200 (http-response-status response))
             "Fixture response status changed unexpectedly.")
      (check (http-response-success-p response)
             "HTTP 200 response was not considered successful.")
      (check (string= "<html><title>Star</title></html>"
                      (http-response-body response))
             "Fixture response body changed unexpectedly.")
      (check (string= "https://example.test/page"
                      (http-response-final-url response))
             "Final URL was not preserved."))

    (check
     (signals-p 'http-request-error
                (lambda () (make-http-request "")))
     "Empty URL was not rejected.")
    (check
     (signals-p 'http-request-error
                (lambda ()
                  (make-http-request "https://example.test" :method :explode)))
     "Unknown HTTP method was not rejected.")
    (check
     (signals-p 'http-request-error
                (lambda ()
                  (make-http-request "https://example.test" :read-timeout 0)))
     "Invalid timeout was not rejected.")
    (check
     (signals-p 'http-request-error
                (lambda ()
                  (perform-http-request
                   (make-http-client "broken" (lambda (request)
                                                (declare (ignore request))
                                                :not-a-response))
                   (make-http-request "https://example.test"))))
     "Invalid backend return value was not rejected."))

  (format t "~&star-http-port tests passed~%")
  t)
