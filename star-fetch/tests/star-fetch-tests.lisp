(defpackage :starfetch-tests
  (:use :cl)
  (:import-from :starhttpport
                #:make-http-client
                #:make-http-response)
  (:import-from :starlangruntime
                #:actor-contract-error
                #:actor-runtime-error
                #:make-runtime
                #:shutdown-runtime)
  (:import-from :starfetch
                #:make-fetch-request
                #:fetch-result-status
                #:fetch-result-body
                #:fetch-result-cache-status
                #:create-fetch-actor-system
                #:invoke-fetch)
  (:export #:run-tests))

(in-package :starfetch-tests)

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

(defun make-fixture-client (calls &key (body "fixture"))
  (make-http-client
   "fixture-http"
   (lambda (request)
     (incf (car calls))
     (make-http-response
      :body body
      :status 200
      :headers '(("content-type" . "text/plain"))
      :final-url (starhttpport:http-request-url request)))))

(defun request (id url &rest options)
  (apply #'make-fetch-request id url options))

(defun test-cache-hit-and-reload ()
  (let* ((now 1000)
         (calls (list 0))
         (runtime (make-runtime))
         (system
           (create-fetch-actor-system
            runtime "fixture"
            (make-fixture-client calls)
            :clock (lambda () now)
            :max-entries 8
            :max-cache-bytes 4096
            :max-entry-bytes 1024))
         (first (invoke-fetch runtime system (request "r1" "https://example.test/a")))
         (second (invoke-fetch runtime system (request "r2" "https://example.test/a")))
         (third
           (invoke-fetch
            runtime system
            (request "r3" "https://example.test/a" :cache-mode :reload))))
    (check (= 200 (fetch-result-status first)) "Initial fetch status was not preserved.")
    (check (eq :miss (fetch-result-cache-status first)) "Initial fetch was not a cache miss.")
    (check (eq :hit (fetch-result-cache-status second)) "Repeated fetch was not a cache hit.")
    (check (eq :reload (fetch-result-cache-status third)) "Reload did not report a reload result.")
    (check (= 2 (car calls)) "Expected two backend calls, got ~D." (car calls))))

(defun test-no-store-bypasses-cache ()
  (let* ((calls (list 0))
         (runtime (make-runtime))
         (system (create-fetch-actor-system runtime "no-store" (make-fixture-client calls))))
    (dotimes (index 2)
      (let ((result
              (invoke-fetch
               runtime system
               (request (format nil "n~D" index)
                        "https://example.test/no-store"
                        :cache-mode :no-store))))
        (check (eq :bypass (fetch-result-cache-status result))
               "No-store fetch did not report bypass.")))
    (check (= 2 (car calls)) "No-store request unexpectedly used cache.")))

(defun test-expiry-refetches ()
  (let* ((now 1000)
         (calls (list 0))
         (runtime (make-runtime))
         (system
           (create-fetch-actor-system
            runtime "expiry" (make-fixture-client calls)
            :clock (lambda () now))))
    (invoke-fetch runtime system (request "e1" "https://example.test/expiry" :ttl-seconds 2))
    (setf now 1003)
    (let ((result
            (invoke-fetch runtime system
                          (request "e2" "https://example.test/expiry" :ttl-seconds 2))))
      (check (eq :miss (fetch-result-cache-status result))
             "Expired entry was returned as a hit."))
    (check (= 2 (car calls)) "Expired entry did not trigger refetch.")))

(defun test-lru-eviction-is-deterministic ()
  (let* ((now 1000)
         (calls (list 0))
         (runtime (make-runtime))
         (system
           (create-fetch-actor-system
            runtime "lru" (make-fixture-client calls)
            :clock (lambda () now)
            :max-entries 2)))
    (invoke-fetch runtime system (request "a1" "https://example.test/a"))
    (incf now)
    (invoke-fetch runtime system (request "b1" "https://example.test/b"))
    (incf now)
    (check (eq :hit
               (fetch-result-cache-status
                (invoke-fetch runtime system (request "a2" "https://example.test/a"))))
           "Expected A to be a hit before eviction.")
    (incf now)
    (invoke-fetch runtime system (request "c1" "https://example.test/c"))
    (incf now)
    (check (eq :miss
               (fetch-result-cache-status
                (invoke-fetch runtime system (request "b2" "https://example.test/b"))))
           "Least-recently-used B entry was not evicted.")))

(defun test-oversized-body-is-not-cached ()
  (let* ((calls (list 0))
         (runtime (make-runtime))
         (system
           (create-fetch-actor-system
            runtime "oversize"
            (make-fixture-client calls :body "12345")
            :max-entry-bytes 4
            :max-cache-bytes 16)))
    (dotimes (index 2)
      (let ((result
              (invoke-fetch runtime system
                            (request (format nil "o~D" index)
                                     "https://example.test/large"))))
        (check (string= "12345" (fetch-result-body result))
               "Oversized response body was not returned intact.")
        (check (eq :miss (fetch-result-cache-status result))
               "Oversized response should remain a miss.")))
    (check (= 2 (car calls)) "Oversized body was cached unexpectedly.")))

(defun test-semantic-key-separation ()
  (let* ((calls (list 0))
         (runtime (make-runtime))
         (system (create-fetch-actor-system runtime "keys" (make-fixture-client calls))))
    (invoke-fetch runtime system
                  (request "h1" "https://example.test/key"
                           :headers '(("accept" . "text/plain"))))
    (invoke-fetch runtime system
                  (request "h2" "https://example.test/key"
                           :headers '(("accept" . "application/json"))))
    (invoke-fetch runtime system
                  (request "p1" "https://example.test/key"
                           :method :post :body "one"))
    (invoke-fetch runtime system
                  (request "p2" "https://example.test/key"
                           :method :post :body "two"))
    (check (= 4 (car calls))
           "Header/body/method variants aliased unexpectedly; calls=~D."
           (car calls))))

(defun test-contract-and-shutdown ()
  (let* ((runtime (make-runtime))
         (system
           (create-fetch-actor-system
            runtime "contract"
            (make-fixture-client (list 0)))))
    (check
     (signals-p 'actor-contract-error
                (lambda () (invoke-fetch runtime system '(:not :a :fetch-request))))
     "Fetch coordinator accepted a non-fetch request.")
    (shutdown-runtime runtime)
    (check
     (signals-p 'actor-runtime-error
                (lambda ()
                  (invoke-fetch runtime system
                                (request "late" "https://example.test/late"))))
     "Fetch system remained invokable after runtime shutdown.")))

(defun run-tests ()
  (test-cache-hit-and-reload)
  (test-no-store-bypasses-cache)
  (test-expiry-refetches)
  (test-lru-eviction-is-deterministic)
  (test-oversized-body-is-not-cached)
  (test-semantic-key-separation)
  (test-contract-and-shutdown)
  (format t "~&star-fetch tests passed~%")
  t)
