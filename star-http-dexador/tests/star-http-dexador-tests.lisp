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
  (:import-from :starhttpport
                #:http-request-error
                #:http-response-body
                #:http-response-final-url
                #:http-response-headers
                #:http-response-status
                #:make-dexador-http-client
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

(defun octets-to-ascii (octets)
  (map 'string #'code-char octets))

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

(defun read-request-target (stream)
  (let* ((line (read-http-line stream))
         (first-space (position #\Space line))
         (second-space (and first-space
                            (position #\Space line :start (1+ first-space)))))
    (unless (and first-space second-space)
      (error "Malformed fixture request line ~S." line))
    (loop for header = (read-http-line stream)
          until (string= header ""))
    (subseq line (1+ first-space) second-space)))

(defun fixture-status (target)
  (let ((prefix "/status/"))
    (unless (and (>= (length target) (length prefix))
                 (string= prefix target :end2 (length prefix)))
      (error "Unexpected fixture target ~S." target))
    (parse-integer target :start (length prefix) :junk-allowed t)))

(defun write-status-response (stream status)
  (let* ((body (format nil "fixture-~D" status))
         (response
           (with-output-to-string (out)
             (format out "HTTP/1.1 ~D Fixture~C~C" status #\Return #\Newline)
             (format out "Content-Type: text/plain~C~C" #\Return #\Newline)
             (format out "X-Star-Fixture: yes~C~C" #\Return #\Newline)
             (when (= status 429)
               (format out "Retry-After: 17~C~C" #\Return #\Newline))
             (format out "Content-Length: ~D~C~C" (length body) #\Return #\Newline)
             (format out "Connection: close~C~C~C~C" #\Return #\Newline #\Return #\Newline)
             (write-string body out))))
    (write-sequence (string-to-octets response :encoding :utf-8) stream)
    (finish-output stream)))

(defun serve-one-request (listener)
  (let ((client (socket-accept listener :element-type '(unsigned-byte 8))))
    (unwind-protect
         (let* ((stream (socket-stream client))
                (target (read-request-target stream)))
           (unless (search "/disconnect" target :test #'char=)
             (write-status-response stream (fixture-status target))))
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
                 (dotimes (index request-count)
                   (declare (ignore index))
                   (serve-one-request listener))
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

(defun test-transport-error-redaction (client server failures)
  (let* ((sentinel "AUDIT_SECRET_DO_NOT_LOG")
         (url (fixture-url server
                           (format nil "/disconnect?apiKey=~A" sentinel)))
         (failure
           (handler-case
               (progn
                 (perform-http-request
                  client
                  (make-http-request url
                                     :headers `(("authorization" . ,sentinel)
                                                ("cookie" . ,sentinel))
                                     :connect-timeout 2
                                     :read-timeout 2
                                     :max-redirects 0))
                 nil)
             (http-request-error (condition)
               condition)
             (error (condition)
               (record-failure failures
                               "Transport failure escaped the HTTP port taxonomy as ~S."
                               (type-of condition))
               condition))))
    (unless failure
      (record-failure failures "Disconnect fixture did not produce an HTTP request failure."))
    (when (and failure
               (search sentinel (princ-to-string failure) :test #'char-equal))
      (record-failure failures
                      "Transport error text leaked the synthetic request secret."))))

(defun run-tests ()
  (let ((*failures* nil)
        (server nil))
    (declare (special *failures*))
    (setf server (start-fixture-server 5))
    (unwind-protect
         (let ((client (make-dexador-http-client)))
           (test-non-2xx-response-preservation client server '*failures*)
           (test-transport-error-redaction client server '*failures*))
      (stop-fixture-server server))
    (when *failures*
      (error "star-http-dexador RED regressions failed:~%~{ - ~A~%~}"
             (nreverse *failures*))))
  (format t "~&star-http-dexador regression tests passed~%")
  t)
