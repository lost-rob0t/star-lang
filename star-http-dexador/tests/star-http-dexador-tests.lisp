(defpackage :starhttpdexador-tests
  (:use :cl)
  (:import-from :babel
                #:string-to-octets)
  (:import-from :bordeaux-threads
                #:join-thread
                #:make-semaphore
                #:make-thread
                #:signal-semaphore
                #:wait-on-semaphore)
  (:import-from :starhttpdexador
                #:make-dexador-http-client)
  (:import-from :starhttpport
                #:http-request-error
                #:http-response-body
                #:http-response-final-url
                #:http-response-headers
                #:http-response-status
                #:http-transport-error
                #:http-transport-error-kind
                #:make-http-request
                #:perform-http-request)
  (:import-from :usocket
                #:get-local-port
                #:socket-accept
                #:socket-close
                #:socket-listen
                #:socket-stream)
  (:export #:run-tests))

(in-package :starhttpdexador-tests)

(defstruct (fixture-server
            (:constructor %make-fixture-server (&key listener port ready)))
  listener
  port
  ready
  thread
  failure
  stopping-p)

(defstruct fixture-request
  method
  target
  headers
  body)

(defun octets-to-ascii (octets)
  (map 'string #'code-char octets))

(defun ascii-to-octets (string)
  (string-to-octets string :encoding :utf-8))

(defun read-http-line (stream)
  (let ((bytes (make-array 64
                           :element-type '(unsigned-byte 8)
                           :adjustable t
                           :fill-pointer 0))
        (previous nil))
    (loop
      for byte = (read-byte stream nil nil)
      do (cond
           ((null byte)
            (return))
           ((and (eql previous 13) (= byte 10))
            (decf (fill-pointer bytes))
            (return))
           (t
            (vector-push-extend byte bytes)
            (setf previous byte))))
    (octets-to-ascii bytes)))

(defun read-exact-octets (stream count)
  (let ((octets (make-array count :element-type '(unsigned-byte 8)))
        (offset 0))
    (loop while (< offset count)
          for next = (read-sequence octets stream :start offset :end count)
          do (when (= next offset)
               (error "Fixture request body ended after ~D of ~D bytes." offset count))
             (setf offset next))
    octets))

(defun parse-request-line (line)
  (let* ((first-space (position #\Space line))
         (second-space (and first-space
                            (position #\Space line :start (1+ first-space)))))
    (unless (and first-space second-space)
      (error "Malformed fixture request line ~S." line))
    (values (subseq line 0 first-space)
            (subseq line (1+ first-space) second-space))))

(defun read-request-headers (stream)
  (let ((headers (make-hash-table :test #'equal)))
    (loop for line = (read-http-line stream)
          until (string= line "")
          do (let ((colon (position #\: line)))
               (unless colon
                 (error "Malformed fixture header ~S." line))
               (setf (gethash (string-downcase (subseq line 0 colon)) headers)
                     (string-trim '(#\Space #\Tab) (subseq line (1+ colon))))))
    headers))

(defun read-fixture-request (stream)
  (multiple-value-bind (method target)
      (parse-request-line (read-http-line stream))
    (let* ((headers (read-request-headers stream))
           (length-text (gethash "content-length" headers))
           (body-length (if length-text (parse-integer length-text) 0))
           (body (read-exact-octets stream body-length)))
      (make-fixture-request
       :method method
       :target target
       :headers headers
       :body body))))

(defun fixture-status (target)
  (let ((prefix "/status/"))
    (unless (and (>= (length target) (length prefix))
                 (string= prefix target :end2 (length prefix)))
      (error "Unexpected fixture target ~S." target))
    (parse-integer target :start (length prefix) :junk-allowed t)))

(defun write-http-response (stream status headers body)
  (let* ((body-octets
           (etypecase body
             (string (ascii-to-octets body))
             ((vector (unsigned-byte 8)) body)))
         (head
           (with-output-to-string (out)
             (format out "HTTP/1.1 ~D Fixture~C~C" status #\Return #\Newline)
             (dolist (header headers)
               (format out "~A: ~A~C~C"
                       (car header)
                       (cdr header)
                       #\Return
                       #\Newline))
             (format out "Content-Length: ~D~C~C" (length body-octets) #\Return #\Newline)
             (format out "Connection: close~C~C~C~C" #\Return #\Newline #\Return #\Newline))))
    (write-sequence (ascii-to-octets head) stream)
    (write-sequence body-octets stream)
    (finish-output stream)))

(defun write-status-response (stream status)
  (let ((headers '(("Content-Type" . "text/plain")
                   ("X-Star-Fixture" . "yes"))))
    (when (= status 429)
      (push '("Retry-After" . "17") headers))
    (write-http-response stream status headers (format nil "fixture-~D" status))))

(defun request-header (request name)
  (gethash (string-downcase name) (fixture-request-headers request)))

(defun serve-fixture-request (stream request)
  (let ((target (fixture-request-target request)))
    (cond
      ((search "/disconnect" target :test #'char=)
       nil)
      ((string= target "/malformed")
       (write-sequence (ascii-to-octets "not-an-http-response\r\n\r\n") stream)
       (finish-output stream))
      ((string= target "/slow")
       (sleep 2)
       (ignore-errors (write-status-response stream 200)))
      ((string= target "/redirect")
       (write-http-response stream
                            302
                            '(("Location" . "/status/200")
                              ("Content-Type" . "text/plain"))
                            "redirect"))
      ((string= target "/binary")
       (write-http-response stream
                            200
                            '(("Content-Type" . "application/octet-stream"))
                            (make-array 4
                                        :element-type '(unsigned-byte 8)
                                        :initial-contents '(0 1 2 255))))
      ((string= target "/echo")
       (let* ((method (fixture-request-method request))
              (marker (request-header request "x-star-request"))
              (body (octets-to-ascii (fixture-request-body request)))
              (valid-p (and (string= method "POST")
                            (string= marker "present")
                            (string= body "payload"))))
         (write-http-response stream
                              (if valid-p 200 422)
                              '(("Content-Type" . "text/plain"))
                              (format nil "~A|~A|~A" method marker body))))
      ((search "/status/" target :test #'char=)
       (write-status-response stream (fixture-status target)))
      (t
       (write-status-response stream 404)))))

(defun serve-one-request (listener)
  (let ((client (socket-accept listener :element-type '(unsigned-byte 8))))
    (unwind-protect
         (let ((stream (socket-stream client)))
           (serve-fixture-request stream (read-fixture-request stream)))
      (socket-close client))))

(defun start-fixture-server (request-count)
  (let* ((listener (socket-listen "127.0.0.1"
                                  0
                                  :reuse-address t
                                  :element-type '(unsigned-byte 8)))
         (ready (make-semaphore :count 0))
         (server (%make-fixture-server
                  :listener listener
                  :port (get-local-port listener)
                  :ready ready)))
    (setf (fixture-server-thread server)
          (make-thread
           (lambda ()
             (signal-semaphore ready)
             (handler-case
                 (loop repeat request-count
                       do (serve-one-request listener))
               (error (condition)
                 (unless (fixture-server-stopping-p server)
                   (setf (fixture-server-failure server) condition)))))
           :name "star-http-dexador-loopback-fixture"))
    (unless (wait-on-semaphore ready :timeout 2)
      (setf (fixture-server-stopping-p server) t)
      (socket-close listener)
      (join-thread (fixture-server-thread server))
      (error "Loopback HTTP fixture failed its readiness handshake."))
    server))

(defun stop-fixture-server (server)
  (setf (fixture-server-stopping-p server) t)
  (ignore-errors (socket-close (fixture-server-listener server)))
  (join-thread (fixture-server-thread server))
  (when (fixture-server-failure server)
    (error "Loopback HTTP fixture failed: ~A"
           (fixture-server-failure server))))

(defun fixture-url (server target)
  (format nil "http://127.0.0.1:~D~A"
          (fixture-server-port server)
          target))

(defun response-body-ascii (response)
  (let ((body (http-response-body response)))
    (etypecase body
      (string body)
      ((vector (unsigned-byte 8))
       (octets-to-ascii body)))))

(defun response-header (response name)
  (let ((headers (http-response-headers response)))
    (etypecase headers
      (hash-table
       (gethash (string-downcase name) headers))
      (list
       (cdr (assoc name headers :test #'string-equal))))))

(defun record-failure (failures control &rest arguments)
  (push (apply #'format nil control arguments) (symbol-value failures)))

(defun capture-request-error (client request failures label)
  (handler-case
      (progn
        (perform-http-request client request)
        (record-failure failures "~A did not signal an HTTP request error." label)
        nil)
    (http-request-error (condition)
      condition)
    (error (condition)
      (record-failure failures
                      "~A escaped the HTTP port taxonomy as ~S."
                      label
                      (type-of condition))
      condition)))

(defun test-non-2xx-response-preservation (client server failures)
  (dolist (status '(403 404 429 500))
    (let ((url (fixture-url server (format nil "/status/~D" status))))
      (handler-case
          (let ((response
                  (perform-http-request
                   client
                   (make-http-request url
                                      :connect-timeout 2
                                      :read-timeout 2
                                      :max-redirects 0))))
            (unless (= status (http-response-status response))
              (record-failure failures
                              "Status ~D became ~D."
                              status
                              (http-response-status response)))
            (unless (string= (format nil "fixture-~D" status)
                             (response-body-ascii response))
              (record-failure failures "Status ~D body was not preserved." status))
            (unless (string= "yes" (response-header response "x-star-fixture"))
              (record-failure failures "Status ~D response headers were not preserved." status))
            (when (= status 429)
              (unless (string= "17" (response-header response "retry-after"))
                (record-failure failures "HTTP 429 Retry-After was not preserved.")))
            (unless (string= url (http-response-final-url response))
              (record-failure failures "Status ~D final URL was not preserved." status)))
        (error (condition)
          (record-failure failures
                          "Valid HTTP ~D response signaled ~S: ~A"
                          status
                          (type-of condition)
                          condition))))))

(defun test-request-mapping (client server failures)
  (let* ((url (fixture-url server "/echo"))
         (response
           (perform-http-request
            client
            (make-http-request url
                               :method :post
                               :headers '(("X-Star-Request" . "present"))
                               :body "payload"
                               :connect-timeout 2
                               :read-timeout 2
                               :max-redirects 0))))
    (unless (= 200 (http-response-status response))
      (record-failure failures "POST request mapping returned status ~D."
                      (http-response-status response)))
    (unless (string= "POST|present|payload" (response-body-ascii response))
      (record-failure failures "POST method, header, or body was not preserved."))))

(defun test-redirects (client server failures)
  (let* ((start-url (fixture-url server "/redirect"))
         (final-url (fixture-url server "/status/200"))
         (followed
           (perform-http-request
            client
            (make-http-request start-url
                               :connect-timeout 2
                               :read-timeout 2
                               :max-redirects 1))))
    (unless (= 200 (http-response-status followed))
      (record-failure failures "One-hop redirect did not resolve to HTTP 200."))
    (unless (string= final-url (http-response-final-url followed))
      (record-failure failures "Redirect final URL was not preserved: ~S."
                      (http-response-final-url followed)))
    (let ((ceiling
            (perform-http-request
             client
             (make-http-request start-url
                                :connect-timeout 2
                                :read-timeout 2
                                :max-redirects 0))))
      (unless (= 302 (http-response-status ceiling))
        (record-failure failures "Redirect ceiling did not preserve final HTTP 302."))
      (unless (string= start-url (http-response-final-url ceiling))
        (record-failure failures "Redirect-ceiling final URL changed unexpectedly.")))))

(defun test-binary-response (client server failures)
  (let* ((expected (make-array 4
                               :element-type '(unsigned-byte 8)
                               :initial-contents '(0 1 2 255)))
         (response
           (perform-http-request
            client
            (make-http-request (fixture-url server "/binary")
                               :connect-timeout 2
                               :read-timeout 2
                               :max-redirects 0)))
         (body (http-response-body response)))
    (unless (and (typep body '(vector (unsigned-byte 8)))
                 (equalp expected body))
      (record-failure failures "Binary HTTP response body was not preserved."))))

(defun test-protocol-failure (client server failures)
  (let ((failure
          (capture-request-error
           client
           (make-http-request (fixture-url server "/malformed")
                              :connect-timeout 2
                              :read-timeout 2
                              :max-redirects 0)
           failures
           "Malformed HTTP response")))
    (when (and failure (not (typep failure 'http-transport-error)))
      (record-failure failures "Malformed response did not signal http-transport-error."))
    (when (and (typep failure 'http-transport-error)
               (not (eq :protocol (http-transport-error-kind failure))))
      (record-failure failures
                      "Malformed response was classified as ~S instead of :protocol."
                      (http-transport-error-kind failure)))))

(defun test-read-timeout (client server failures)
  (let ((failure
          (capture-request-error
           client
           (make-http-request (fixture-url server "/slow")
                              :connect-timeout 2
                              :read-timeout 1
                              :max-redirects 0)
           failures
           "Read timeout")))
    (when (and (typep failure 'http-transport-error)
               (not (eq :timeout (http-transport-error-kind failure))))
      (record-failure failures
                      "Read timeout was classified as ~S instead of :timeout."
                      (http-transport-error-kind failure)))))

(defun test-connection-failure (client failures)
  (unless (eq :connection
              (starhttpdexador::transport-error-kind
               (make-condition 'usocket:connection-refused-error :socket nil)))
    (record-failure failures
                    "USOCKET connection-refused condition did not map to :connection."))
  (let* ((listener (socket-listen "127.0.0.1"
                                  0
                                  :reuse-address t
                                  :element-type '(unsigned-byte 8)))
         (port (get-local-port listener)))
    (socket-close listener)
    (let ((failure
            (capture-request-error
             client
             (make-http-request (format nil "http://127.0.0.1:~D/unbound" port)
                                :connect-timeout 1
                                :read-timeout 1
                                :max-redirects 0)
             failures
             "Closed loopback endpoint")))
      (when (and (typep failure 'http-transport-error)
                 (not (member (http-transport-error-kind failure)
                              '(:connection :timeout))))
        (record-failure failures
                        "Closed loopback endpoint was classified outside connection/timeout: ~S."
                        (http-transport-error-kind failure))))))

(defun test-transport-error-redaction (client server failures)
  (let* ((sentinel "AUDIT_SECRET_DO_NOT_LOG")
         (url (fixture-url server
                           (format nil "/disconnect?apiKey=~A" sentinel)))
         (failure
           (capture-request-error
            client
            (make-http-request url
                               :headers `(("authorization" . ,sentinel)
                                          ("cookie" . ,sentinel))
                               :connect-timeout 2
                               :read-timeout 2
                               :max-redirects 0)
            failures
            "Disconnect fixture")))
    (when (and failure (not (typep failure 'http-transport-error)))
      (record-failure failures
                      "Transport failure was not the typed HTTP transport condition: ~S."
                      (type-of failure)))
    (when (typep failure 'http-transport-error)
      (unless (member (http-transport-error-kind failure)
                      '(:connection :timeout :tls :protocol :backend))
        (record-failure failures
                        "Transport failure had an unknown kind ~S."
                        (http-transport-error-kind failure))))
    (when (and failure
               (search sentinel (princ-to-string failure) :test #'char-equal))
      (record-failure failures
                      "Transport error text leaked the synthetic request secret."))))

(defun run-tests ()
  (let ((*failures* nil)
        (server nil))
    (declare (special *failures*))
    (setf server (start-fixture-server 12))
    (unwind-protect
         (let ((client (make-dexador-http-client)))
           (test-non-2xx-response-preservation client server '*failures*)
           (test-request-mapping client server '*failures*)
           (test-redirects client server '*failures*)
           (test-binary-response client server '*failures*)
           (test-protocol-failure client server '*failures*)
           (test-read-timeout client server '*failures*)
           (test-transport-error-redaction client server '*failures*)
           (test-connection-failure client '*failures*))
      (stop-fixture-server server))
    (when *failures*
      (error "star-http-dexador regressions failed:~%~{ - ~A~%~}"
             (nreverse *failures*))))
  (format t "~&star-http-dexador regression tests passed~%")
  t)
