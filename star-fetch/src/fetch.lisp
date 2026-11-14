(in-package :starfetch)

(define-condition fetch-error (error)
  ((message :initarg :message :reader fetch-error-message))
  (:report
   (lambda (condition stream)
     (write-string (fetch-error-message condition) stream))))

(defun fail-fetch (control &rest arguments)
  (error 'fetch-error :message (apply #'format nil control arguments)))

(defun proper-list-p (value)
  (loop
    for tail = value then (cdr tail)
    do (cond
         ((null tail) (return t))
         ((consp tail))
         (t (return nil)))))

(defun header-pair-p (header)
  (and (consp header)
       (stringp (car header))
       (stringp (cdr header))))

(defun valid-headers-p (headers)
  (and (proper-list-p headers)
       (every #'header-pair-p headers)))

(defun octet-vector-p (value)
  (typep value '(vector (unsigned-byte 8))))

(defun valid-body-p (body)
  (or (null body)
      (stringp body)
      (octet-vector-p body)))

(defstruct (fetch-request
            (:constructor %make-fetch-request
                (&key request-id
                      url
                      method
                      headers
                      body
                      connect-timeout
                      read-timeout
                      max-redirects
                      cache-mode
                      ttl-seconds
                      provenance)))
  (request-id "" :type string)
  (url "" :type string)
  (method :get :type keyword)
  headers
  body
  (connect-timeout 10 :type (integer 1 *))
  (read-timeout 10 :type (integer 1 *))
  (max-redirects 5 :type (integer 0 *))
  (cache-mode :default :type keyword)
  (ttl-seconds 300 :type (integer 0 *))
  provenance)

(defun make-fetch-request
    (request-id url
     &key
       (method :get)
       headers
       body
       (connect-timeout 10)
       (read-timeout 10)
       (max-redirects 5)
       (cache-mode :default)
       (ttl-seconds 300)
       provenance)
  (unless (and (stringp request-id) (> (length request-id) 0))
    (fail-fetch "Fetch request id must be a non-empty string."))
  (unless (valid-headers-p headers)
    (fail-fetch "Fetch headers must be a proper list of string cons pairs."))
  (unless (valid-body-p body)
    (fail-fetch "Fetch body must be NIL, a string, or an octet vector."))
  (unless (member cache-mode '(:default :reload :no-store) :test #'eq)
    (fail-fetch "Unsupported fetch cache mode ~S." cache-mode))
  (unless (and (integerp ttl-seconds) (>= ttl-seconds 0))
    (fail-fetch "Fetch TTL must be a non-negative integer."))
  (let ((request
          (starhttpport:make-http-request
           url
           :method method
           :headers headers
           :body body
           :connect-timeout connect-timeout
           :read-timeout read-timeout
           :max-redirects max-redirects)))
    (%make-fetch-request
     :request-id request-id
     :url (starhttpport:http-request-url request)
     :method (starhttpport:http-request-method request)
     :headers (copy-tree (starhttpport:http-request-headers request))
     :body (let ((value (starhttpport:http-request-body request)))
             (if (octet-vector-p value) (copy-seq value) value))
     :connect-timeout (starhttpport:http-request-connect-timeout request)
     :read-timeout (starhttpport:http-request-read-timeout request)
     :max-redirects (starhttpport:http-request-max-redirects request)
     :cache-mode cache-mode
     :ttl-seconds ttl-seconds
     :provenance provenance)))

(defstruct (fetch-result
            (:constructor %make-fetch-result
                (&key request-id
                      requested-url
                      final-url
                      status
                      headers
                      body
                      fetched-at
                      transport
                      cache-status
                      provenance)))
  (request-id "" :type string)
  (requested-url "" :type string)
  (final-url "" :type string)
  (status 0 :type (integer 0 999))
  headers
  body
  (fetched-at 0 :type integer)
  (transport "" :type string)
  (cache-status :miss :type keyword)
  provenance)

(defstruct (fetch-actor-system
            (:constructor %make-fetch-actor-system
                (&key coordinator cache worker)))
  (coordinator "" :type string)
  (cache "" :type string)
  (worker "" :type string))

(defstruct (cached-response
            (:constructor make-cached-response
                (&key final-url status headers body fetched-at transport)))
  (final-url "" :type string)
  (status 0 :type (integer 0 999))
  headers
  body
  (fetched-at 0 :type integer)
  (transport "" :type string))

(defstruct (cache-entry
            (:constructor make-cache-entry
                (&key key value expires-at size last-access)))
  (key "" :type string)
  value
  (expires-at 0 :type integer)
  (size 0 :type (integer 0 *))
  (last-access 0 :type (integer 0 *)))

(defstruct (cache-state
            (:constructor make-cache-state (&key entries bytes tick)))
  (entries '() :type list)
  (bytes 0 :type (integer 0 *))
  (tick 0 :type (integer 0 *)))

(defstruct (cache-command
            (:constructor make-cache-command
                (&key operation key value ttl-seconds now)))
  (operation :get :type keyword)
  (key "" :type string)
  value
  (ttl-seconds 0 :type (integer 0 *))
  (now 0 :type integer))

(defstruct (cache-reply
            (:constructor make-cache-reply (&key found-p value stored-p)))
  (found-p nil :type boolean)
  value
  (stored-p nil :type boolean))

(defun string-utf8-size (string)
  (loop
    for character across string
    for code = (char-code character)
    sum (cond
          ((<= code #x7f) 1)
          ((<= code #x7ff) 2)
          ((<= code #xffff) 3)
          (t 4))))

(defun body-byte-size (body)
  (cond
    ((null body) 0)
    ((stringp body) (string-utf8-size body))
    ((octet-vector-p body) (length body))
    (t (fail-fetch "Unsupported body representation ~S." body))))

(defun copy-body (body)
  (if (octet-vector-p body) (copy-seq body) body))

(defun write-key-part (stream value)
  (format stream "~D:" (length value))
  (write-string value stream))

(defun body-key-string (body)
  (cond
    ((null body) "N")
    ((stringp body)
     (with-output-to-string (stream)
       (write-char #\S stream)
       (write-key-part stream body)))
    ((octet-vector-p body)
     (with-output-to-string (stream)
       (write-char #\B stream)
       (format stream "~D:" (length body))
       (loop for octet across body do (format stream "~2,'0X" octet))))
    (t (fail-fetch "Unsupported body representation ~S." body))))

(defun canonical-headers (headers)
  (stable-sort
   (mapcar
    (lambda (header)
      (cons (string-downcase (car header)) (cdr header)))
    (copy-list headers))
   (lambda (left right)
     (let ((left-name (car left))
           (right-name (car right)))
       (if (string= left-name right-name)
           (string< (cdr left) (cdr right))
           (string< left-name right-name))))))

(defun fetch-cache-key (request)
  (with-output-to-string (stream)
    (dolist (part
             (list (symbol-name (fetch-request-method request))
                   (fetch-request-url request)
                   (write-to-string (fetch-request-connect-timeout request) :base 10 :radix nil)
                   (write-to-string (fetch-request-read-timeout request) :base 10 :radix nil)
                   (write-to-string (fetch-request-max-redirects request) :base 10 :radix nil)))
      (write-key-part stream part))
    (dolist (header (canonical-headers (fetch-request-headers request)))
      (write-key-part stream (car header))
      (write-key-part stream (cdr header)))
    (write-key-part stream (body-key-string (fetch-request-body request)))))

(defun active-cache-entries (entries now)
  (remove-if (lambda (entry) (<= (cache-entry-expires-at entry) now)) entries))

(defun entries-byte-size (entries)
  (reduce #'+ entries :key #'cache-entry-size :initial-value 0))

(defun refresh-entry-access (entries target tick)
  (mapcar
   (lambda (entry)
     (if (eq entry target)
         (make-cache-entry
          :key (cache-entry-key entry)
          :value (cache-entry-value entry)
          :expires-at (cache-entry-expires-at entry)
          :size (cache-entry-size entry)
          :last-access tick)
         entry))
   entries))

(defun least-recent-entry (entries)
  (reduce
   (lambda (left right)
     (if (< (cache-entry-last-access left)
            (cache-entry-last-access right))
         left
         right))
   entries))

(defun enforce-cache-bounds (entries max-entries max-cache-bytes)
  (loop
    with bounded = entries
    while (and bounded
               (or (> (length bounded) max-entries)
                   (> (entries-byte-size bounded) max-cache-bytes)))
    for victim = (least-recent-entry bounded)
    do (setf bounded (remove victim bounded :test #'eq :count 1))
    finally (return bounded)))

(defun cache-get (command state)
  (let* ((now (cache-command-now command))
         (entries (active-cache-entries (cache-state-entries state) now))
         (tick (1+ (cache-state-tick state)))
         (entry (find (cache-command-key command)
                      entries
                      :key #'cache-entry-key
                      :test #'string=))
         (next-entries
           (if entry
               (refresh-entry-access entries entry tick)
               entries)))
    (values
     (make-cache-reply
      :found-p (not (null entry))
      :value (and entry (cache-entry-value entry)))
     (make-cache-state
      :entries next-entries
      :bytes (entries-byte-size next-entries)
      :tick tick))))

(defun cache-put (command state max-entries max-cache-bytes max-entry-bytes)
  (let* ((now (cache-command-now command))
         (value (cache-command-value command))
         (size (body-byte-size (cached-response-body value)))
         (entries
           (remove (cache-command-key command)
                   (active-cache-entries (cache-state-entries state) now)
                   :key #'cache-entry-key
                   :test #'string=))
         (tick (1+ (cache-state-tick state)))
         (storable-p
           (and (> max-entries 0)
                (> max-cache-bytes 0)
                (> (cache-command-ttl-seconds command) 0)
                (<= size max-entry-bytes)
                (<= size max-cache-bytes)))
         (candidate
           (if storable-p
               (cons
                (make-cache-entry
                 :key (cache-command-key command)
                 :value value
                 :expires-at (+ now (cache-command-ttl-seconds command))
                 :size size
                 :last-access tick)
                entries)
               entries))
         (bounded
           (enforce-cache-bounds candidate max-entries max-cache-bytes)))
    (values
     (make-cache-reply
      :stored-p
      (and storable-p
           (not
            (null
             (find (cache-command-key command)
                   bounded
                   :key #'cache-entry-key
                   :test #'string=)))))
     (make-cache-state
      :entries bounded
      :bytes (entries-byte-size bounded)
      :tick tick))))

(defun fetch-contract-valid-p (contract value)
  (case contract
    (:fetch-request (fetch-request-p value))
    (:fetch-result (fetch-result-p value))
    (:fetch-cache-command (cache-command-p value))
    (:fetch-cache-reply (cache-reply-p value))
    (otherwise nil)))

(defun cached-response-from-result (result)
  (make-cached-response
   :final-url (fetch-result-final-url result)
   :status (fetch-result-status result)
   :headers (copy-tree (fetch-result-headers result))
   :body (copy-body (fetch-result-body result))
   :fetched-at (fetch-result-fetched-at result)
   :transport (fetch-result-transport result)))

(defun result-from-cached-response (request cached cache-status)
  (%make-fetch-result
   :request-id (fetch-request-request-id request)
   :requested-url (fetch-request-url request)
   :final-url (cached-response-final-url cached)
   :status (cached-response-status cached)
   :headers (copy-tree (cached-response-headers cached))
   :body (copy-body (cached-response-body cached))
   :fetched-at (cached-response-fetched-at cached)
   :transport (cached-response-transport cached)
   :cache-status cache-status
   :provenance (fetch-request-provenance request)))

(defun result-with-cache-status (result status)
  (%make-fetch-result
   :request-id (fetch-result-request-id result)
   :requested-url (fetch-result-requested-url result)
   :final-url (fetch-result-final-url result)
   :status (fetch-result-status result)
   :headers (copy-tree (fetch-result-headers result))
   :body (copy-body (fetch-result-body result))
   :fetched-at (fetch-result-fetched-at result)
   :transport (fetch-result-transport result)
   :cache-status status
   :provenance (fetch-result-provenance result)))

(defun execute-fetch (http-client request clock)
  (let* ((http-request
           (starhttpport:make-http-request
            (fetch-request-url request)
            :method (fetch-request-method request)
            :headers (copy-tree (fetch-request-headers request))
            :body (copy-body (fetch-request-body request))
            :connect-timeout (fetch-request-connect-timeout request)
            :read-timeout (fetch-request-read-timeout request)
            :max-redirects (fetch-request-max-redirects request)))
         (response (starhttpport:perform-http-request http-client http-request))
         (final-url (starhttpport:http-response-final-url response)))
    (%make-fetch-result
     :request-id (fetch-request-request-id request)
     :requested-url (fetch-request-url request)
     :final-url (if (> (length final-url) 0)
                    final-url
                    (fetch-request-url request))
     :status (starhttpport:http-response-status response)
     :headers (copy-tree (starhttpport:http-response-headers response))
     :body (copy-body (starhttpport:http-response-body response))
     :fetched-at (funcall clock)
     :transport (starhttpport:http-client-name http-client)
     :cache-status :miss
     :provenance (fetch-request-provenance request))))

(defun cacheable-request-p (request)
  (and (member (fetch-request-method request) '(:get :head) :test #'eq)
       (> (fetch-request-ttl-seconds request) 0)))

(defun cache-read (runtime cache-name request clock)
  (starlangruntime:invoke-actor
   runtime
   cache-name
   (make-cache-command
    :operation :get
    :key (fetch-cache-key request)
    :now (funcall clock))))

(defun cache-write (runtime cache-name request result clock)
  (starlangruntime:invoke-actor
   runtime
   cache-name
   (make-cache-command
    :operation :put
    :key (fetch-cache-key request)
    :value (cached-response-from-result result)
    :ttl-seconds (fetch-request-ttl-seconds request)
    :now (funcall clock))))

(defun execute-coordinated-fetch (runtime worker-name cache-name request clock)
  (labels ((fetch ()
             (starlangruntime:invoke-actor runtime worker-name request))
           (store (result)
             (cache-write runtime cache-name request result clock)
             result))
    (cond
      ((or (eq :no-store (fetch-request-cache-mode request))
           (not (cacheable-request-p request)))
       (result-with-cache-status (fetch) :bypass))
      ((eq :reload (fetch-request-cache-mode request))
       (result-with-cache-status (store (fetch)) :reload))
      (t
       (let ((reply (cache-read runtime cache-name request clock)))
         (if (cache-reply-found-p reply)
             (result-from-cached-response
              request (cache-reply-value reply) :hit)
             (store (fetch))))))))

(defun ensure-non-negative-integer (value label)
  (unless (and (integerp value) (>= value 0))
    (fail-fetch "~A must be a non-negative integer, received ~S." label value))
  value)

(defun create-fetch-actor-system
    (runtime name http-client
     &key
       (clock #'get-universal-time)
       (max-entries 256)
       (max-cache-bytes (* 16 1024 1024))
       (max-entry-bytes (* 1024 1024)))
  (unless (and (stringp name) (> (length name) 0))
    (fail-fetch "Fetch actor-system name must be a non-empty string."))
  (unless (starhttpport:http-client-p http-client)
    (fail-fetch "Expected a star-http-port HTTP client, received ~S." http-client))
  (unless (functionp clock)
    (fail-fetch "Fetch clock must be a function."))
  (ensure-non-negative-integer max-entries "max-entries")
  (ensure-non-negative-integer max-cache-bytes "max-cache-bytes")
  (ensure-non-negative-integer max-entry-bytes "max-entry-bytes")
  (let* ((cache-name (format nil "~A-cache" name))
         (worker-name (format nil "~A-worker" name))
         (coordinator-name (format nil "~A-coordinator" name))
         (cache-definition
           (starlangruntime:make-native-actor-definition
            cache-name
            (lambda (message state actor-runtime)
              (declare (ignore actor-runtime))
              (ecase (cache-command-operation message)
                (:get (cache-get message state))
                (:put
                 (cache-put message state
                            max-entries max-cache-bytes max-entry-bytes))))
            :accepts :fetch-cache-command
            :produces :fetch-cache-reply
            :input-validator #'fetch-contract-valid-p
            :output-validator #'fetch-contract-valid-p
            :initial-state
            (lambda () (make-cache-state :entries '() :bytes 0 :tick 0))))
         (worker-definition
           (starlangruntime:make-native-actor-definition
            worker-name
            (lambda (message state actor-runtime)
              (declare (ignore state actor-runtime))
              (execute-fetch http-client message clock))
            :accepts :fetch-request
            :produces :fetch-result
            :input-validator #'fetch-contract-valid-p
            :output-validator #'fetch-contract-valid-p))
         (coordinator-definition
           (starlangruntime:make-native-actor-definition
            coordinator-name
            (lambda (message state actor-runtime)
              (declare (ignore state))
              (execute-coordinated-fetch
               actor-runtime worker-name cache-name message clock))
            :accepts :fetch-request
            :produces :fetch-result
            :input-validator #'fetch-contract-valid-p
            :output-validator #'fetch-contract-valid-p)))
    (starlangruntime:create-actor runtime cache-definition)
    (starlangruntime:create-actor runtime worker-definition)
    (starlangruntime:create-actor runtime coordinator-definition)
    (%make-fetch-actor-system
     :coordinator coordinator-name
     :cache cache-name
     :worker worker-name)))

(defun invoke-fetch (runtime system request)
  (unless (fetch-actor-system-p system)
    (fail-fetch "Expected a fetch actor system, received ~S." system))
  (starlangruntime:invoke-actor
   runtime
   (fetch-actor-system-coordinator system)
   request))
