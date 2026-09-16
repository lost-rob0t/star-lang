(in-package :starhttpdexador-tests)

(defstruct (reuse-server
            (:constructor %make-reuse-server (&key listener port ready)))
  listener
  port
  ready
  thread
  client
  failure
  (accepted-count 0 :type fixnum)
  stopping-p)

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (car tail) key)))

(defun write-reuse-response (stream body &key close-p)
  (let* ((body-octets (ascii-to-octets body))
         (head
           (with-output-to-string (out)
             (format out "HTTP/1.1 200 Fixture~C~C" #\Return #\Newline)
             (format out "Content-Type: text/plain~C~C" #\Return #\Newline)
             (format out "Content-Length: ~D~C~C" (length body-octets) #\Return #\Newline)
             (format out "Connection: ~A~C~C~C~C"
                     (if close-p "close" "keep-alive")
                     #\Return
                     #\Newline
                     #\Return
                     #\Newline))))
    (write-sequence (ascii-to-octets head) stream)
    (write-sequence body-octets stream)
    (finish-output stream)))

(defun start-reuse-server ()
  (let* ((listener (socket-listen "127.0.0.1"
                                  0
                                  :reuse-address t
                                  :element-type '(unsigned-byte 8)))
         (ready (make-semaphore :count 0))
         (server (%make-reuse-server
                  :listener listener
                  :port (get-local-port listener)
                  :ready ready)))
    (setf (reuse-server-thread server)
          (make-thread
           (lambda ()
             (signal-semaphore ready)
             (handler-case
                 (let ((client (socket-accept listener
                                              :element-type '(unsigned-byte 8))))
                   (setf (reuse-server-client server) client)
                   (incf (reuse-server-accepted-count server))
                   (unwind-protect
                        (let ((stream (socket-stream client)))
                          (dotimes (index 2)
                            (read-fixture-request stream)
                            (write-reuse-response
                             stream
                             (format nil "reuse-~D" (1+ index))
                             :close-p (= index 1))))
                     (ignore-errors (socket-close client))
                     (setf (reuse-server-client server) nil)))
               (error (condition)
                 (unless (reuse-server-stopping-p server)
                   (setf (reuse-server-failure server) condition)))))
           :name "star-http-dexador-reuse-fixture"))
    (unless (wait-on-semaphore ready :timeout 2)
      (setf (reuse-server-stopping-p server) t)
      (socket-close listener)
      (join-thread (reuse-server-thread server))
      (error "HTTP reuse fixture failed its readiness handshake."))
    server))

(defun stop-reuse-server (server)
  (setf (reuse-server-stopping-p server) t)
  (when (reuse-server-client server)
    (ignore-errors (socket-close (reuse-server-client server))))
  (ignore-errors (socket-close (reuse-server-listener server)))
  (join-thread (reuse-server-thread server))
  (when (reuse-server-failure server)
    (error "HTTP reuse fixture failed: ~A"
           (reuse-server-failure server))))

(defun reuse-url (server target)
  (format nil "http://127.0.0.1:~D~A"
          (reuse-server-port server)
          target))

(defun clear-explicit-pool (pool)
  (let ((dexador.connection-cache:*connection-pool* pool)
        (dexador.connection-cache:*use-connection-pool* t))
    (dexador.connection-cache:clear-connection-pool)))

(defun test-default-client-bypasses-ambient-proxy (failures)
  (let ((server (start-fixture-server 1)))
    (unwind-protect
         (let ((dexador.util:*default-proxy* "http://127.0.0.1:1")
               (dexador.util:*not-verify-ssl* t))
           (handler-case
               (let* ((client (make-dexador-http-client))
                      (response
                        (perform-http-request
                         client
                         (make-http-request
                          (fixture-url server "/status/200")
                          :connect-timeout 1
                          :read-timeout 1
                          :max-redirects 0))))
                 (unless (= 200 (http-response-status response))
                   (record-failure failures
                                   "Default client under poisoned ambient proxy returned HTTP ~D."
                                   (http-response-status response))))
             (error (condition)
               (record-failure failures
                               "Default client inherited ambient Dexador proxy/TLS state: ~S."
                               (type-of condition)))))
      (stop-fixture-server server))))

(defun test-client-policy-is-explicit (failures)
  (let ((original-request (symbol-function 'dexador:request))
        (calls nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'dexador:request)
                 (lambda (uri &rest arguments)
                   (push (list :uri uri
                               :arguments arguments
                               :pool dexador.connection-cache:*connection-pool*)
                         calls)
                   (values "fixture" 200 nil uri nil)))
           (let ((dexador.util:*default-proxy* "http://127.0.0.1:1")
                 (dexador.util:*not-verify-ssl* t))
             (handler-case
                 (let ((client (make-dexador-http-client)))
                   (perform-http-request
                    client
                    (make-http-request "http://127.0.0.1/default"
                                       :connect-timeout 1
                                       :read-timeout 1
                                       :max-redirects 0)))
               (error (condition)
                 (record-failure failures
                                 "Default client policy mapping failed: ~S."
                                 (type-of condition)))))
           (when calls
             (let ((arguments (getf (car calls) :arguments)))
               (unless (and (plist-key-present-p arguments :proxy)
                            (null (getf arguments :proxy)))
                 (record-failure failures
                                 "Default client did not explicitly disable ambient proxy policy."))
               (unless (and (plist-key-present-p arguments :insecure)
                            (null (getf arguments :insecure)))
                 (record-failure failures
                                 "Default client did not explicitly require TLS verification."))
               (unless (and (plist-key-present-p arguments :use-connection-pool)
                            (null (getf arguments :use-connection-pool)))
                 (record-failure failures
                                 "Default client still relies on hidden Dexador connection pooling."))))
           (setf calls nil)
           (handler-case
               (let ((client
                       (make-dexador-http-client
                        :proxy "http://127.0.0.1:9"
                        :tls-policy :insecure)))
                 (perform-http-request
                  client
                  (make-http-request "http://127.0.0.1/explicit"
                                     :connect-timeout 1
                                     :read-timeout 1
                                     :max-redirects 0)))
             (error (condition)
               (record-failure failures
                               "Explicit client proxy/TLS policy was not accepted: ~S."
                               (type-of condition))))
           (when calls
             (let ((arguments (getf (car calls) :arguments)))
               (unless (string= "http://127.0.0.1:9" (getf arguments :proxy))
                 (record-failure failures
                                 "Explicit client proxy policy was not passed to Dexador."))
               (unless (eq t (getf arguments :insecure))
                 (record-failure failures
                                 "Explicit :insecure TLS policy was not passed to Dexador.")))))
      (setf (symbol-function 'dexador:request) original-request))))

(defun test-explicit-pools-are-client-local (failures)
  (let ((original-request (symbol-function 'dexador:request))
        (calls nil)
        (pool-a (dexador.connection-cache:make-connection-pool 2))
        (pool-b (dexador.connection-cache:make-connection-pool 2)))
    (unwind-protect
         (progn
           (setf (symbol-function 'dexador:request)
                 (lambda (uri &rest arguments)
                   (push (list :uri uri
                               :arguments arguments
                               :pool dexador.connection-cache:*connection-pool*)
                         calls)
                   (values "fixture" 200 nil uri nil)))
           (handler-case
               (let ((client-a (make-dexador-http-client :pool pool-a))
                     (client-b (make-dexador-http-client :pool pool-b)))
                 (perform-http-request
                  client-a
                  (make-http-request "http://127.0.0.1/a"
                                     :connect-timeout 1
                                     :read-timeout 1
                                     :max-redirects 0))
                 (perform-http-request
                  client-b
                  (make-http-request "http://127.0.0.1/b"
                                     :connect-timeout 1
                                     :read-timeout 1
                                     :max-redirects 0)))
             (error (condition)
               (record-failure failures
                               "Explicit per-client pool configuration was not accepted: ~S."
                               (type-of condition))))
           (when (= 2 (length calls))
             (let* ((ordered (nreverse calls))
                    (call-a (first ordered))
                    (call-b (second ordered)))
               (unless (and (eq pool-a (getf call-a :pool))
                            (getf (getf call-a :arguments) :use-connection-pool))
                 (record-failure failures
                                 "Client A did not execute with its own explicit connection pool."))
               (unless (and (eq pool-b (getf call-b :pool))
                            (getf (getf call-b :arguments) :use-connection-pool))
                 (record-failure failures
                                 "Client B did not execute with its own explicit connection pool.")))))
      (setf (symbol-function 'dexador:request) original-request)
      (clear-explicit-pool pool-a)
      (clear-explicit-pool pool-b))))

(defun test-explicit-pool-reuses-live-connection (failures)
  (let ((pool (dexador.connection-cache:make-connection-pool 2))
        (server nil))
    (unwind-protect
         (handler-case
             (let ((client (make-dexador-http-client :pool pool)))
               (setf server (start-reuse-server))
               (let ((first
                       (perform-http-request
                        client
                        (make-http-request
                         (reuse-url server "/one")
                         :connect-timeout 1
                         :read-timeout 1
                         :max-redirects 0)))
                     (second
                       (perform-http-request
                        client
                        (make-http-request
                         (reuse-url server "/two")
                         :connect-timeout 1
                         :read-timeout 1
                         :max-redirects 0))))
                 (unless (and (string= "reuse-1" (response-body-ascii first))
                              (string= "reuse-2" (response-body-ascii second)))
                   (record-failure failures
                                   "Explicit pool did not preserve two sequential responses."))
                 (unless (= 1 (reuse-server-accepted-count server))
                   (record-failure failures
                                   "Two requests used ~D TCP connections instead of reusing one."
                                   (reuse-server-accepted-count server)))))
           (error (condition)
             (record-failure failures
                             "Explicit-pool connection reuse failed: ~S."
                             (type-of condition))))
      (when server
        (stop-reuse-server server))
      (clear-explicit-pool pool))))

(defun test-legacy-body-representation-is-explicit (failures)
  (let ((server (start-fixture-server 2)))
    (unwind-protect
         (let ((client (make-dexador-http-client)))
           (handler-case
               (let* ((text-response
                        (perform-http-request
                         client
                         (make-http-request
                          (fixture-url server "/status/200")
                          :connect-timeout 1
                          :read-timeout 1
                          :max-redirects 0)))
                      (binary-response
                        (perform-http-request
                         client
                         (make-http-request
                          (fixture-url server "/binary")
                          :connect-timeout 1
                          :read-timeout 1
                          :max-redirects 0))))
                 (unless (stringp (http-response-body text-response))
                   (record-failure failures
                                   "Legacy text response body is no longer a string."))
                 (unless (typep (http-response-body binary-response)
                                '(vector (unsigned-byte 8)))
                   (record-failure failures
                                   "Legacy binary response body is no longer an octet vector.")))
             (error (condition)
               (record-failure failures
                               "Legacy mixed body representation oracle failed: ~S."
                               (type-of condition)))))
      (stop-fixture-server server))))

(defun run-ownership-tests ()
  (let ((*ownership-failures* nil))
    (declare (special *ownership-failures*))
    (test-default-client-bypasses-ambient-proxy '*ownership-failures*)
    (test-client-policy-is-explicit '*ownership-failures*)
    (test-explicit-pools-are-client-local '*ownership-failures*)
    (test-explicit-pool-reuses-live-connection '*ownership-failures*)
    (test-legacy-body-representation-is-explicit '*ownership-failures*)
    (when *ownership-failures*
      (error "star-http-dexador ownership regressions failed:~%~{ - ~A~%~}"
             (nreverse *ownership-failures*))))
  (format t "~&star-http-dexador ownership regression tests passed~%")
  t)
