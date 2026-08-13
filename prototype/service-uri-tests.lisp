(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "service-uri-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "runtime-directory-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun service-uri-condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun service-uri-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun service-uri-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun service-uri-test-library ()
  (load-star-form
   (merge-pathnames "../fixtures/fec-core.star" *load-truename*)))

(defun service-uri-test-actor (library)
  (compile-actor
   '(actor user-hunt
     (:runtime external
      :service-uri "star://quasar:localhost:user-hunt"
      :protocol star-message-v1
      :endpoint "fake:user-hunt"
      :accepts (ingest-page)
      :produces (index-fec-record)
      :restart permanent
      :mailbox (bounded 128)
      :capabilities (username-search social-account-discovery)))
   library))

(defun service-uri-test-manifest ()
  (let* ((library (service-uri-test-library))
         (actor (service-uri-test-actor library)))
    (emit-portable-manifest library (list actor))))

(defun test-service-uri-round-trip ()
  (dolist (value '("star://quasar:localhost:user-hunt"
                   "star://bbp:localhost:nmap"))
    (let ((uri (parse-star-service-uri value)))
      (service-uri-assert-equal value
                                (star-service-uri-string uri)
                                "STAR service URI canonical round trip")))
  (let ((uri (parse-star-service-uri
              "star://quasar:localhost:user-hunt")))
    (service-uri-assert-equal "quasar"
                              (star-service-uri-domain uri)
                              "service domain")
    (service-uri-assert-equal "localhost"
                              (star-service-uri-address uri)
                              "service address")
    (service-uri-assert-equal "user-hunt"
                              (star-service-uri-actor-name uri)
                              "service actor name")))

(defun test-service-uri-invalid-input ()
  (dolist (value '("http://quasar:localhost:user-hunt"
                   "star://quasar:user-hunt"
                   "star://quasar:localhost:user-hunt:extra"
                   "star://Quasar:localhost:user-hunt"
                   "star://quasar:local host:user-hunt"
                   "star://quasar:localhost:"))
    (service-uri-assert-true
     (service-uri-condition-signaled-p
      'invalid-star-service-uri-error
      (lambda () (parse-star-service-uri value)))
     (format nil "invalid STAR service URI rejected: ~A" value))))

(defun test-service-uri-actor-manifest ()
  (let* ((library (service-uri-test-library))
         (actor (service-uri-test-actor library))
         (manifest (emit-portable-manifest library (list actor)))
         (portable (first (getf manifest :actors))))
    (service-uri-assert-equal
     "star://quasar:localhost:user-hunt"
     (getf actor :service-uri)
     "compiled actor service URI")
    (service-uri-assert-equal
     "star://quasar:localhost:user-hunt"
     (getf portable :service-uri)
     "portable actor service URI")
    (service-uri-assert-equal
     '("username-search" "social-account-discovery")
     (getf portable :capabilities)
     "portable actor capabilities")
    (service-uri-assert-true
     (service-uri-condition-signaled-p
      'invalid-star-service-uri-error
      (lambda ()
        (compile-actor
         '(actor user-hunt
           (:runtime external
            :service-uri "star://quasar:localhost:nmap"
            :protocol star-message-v1
            :endpoint "fake:user-hunt"
            :accepts (ingest-page)
            :produces (index-fec-record)
            :restart permanent
            :mailbox (bounded 128)))
         library)))
     "manifest actor/service mismatch rejected")))

(defun live-service-directory ()
  (make-runtime-directory-port
   :snapshot
   (lambda (context)
     (declare (ignore context))
     (list
      (list :name "user-hunt"
            :service-uri "star://quasar:localhost:user-hunt"
            :domain "quasar"
            :address "localhost"
            :runtime :cl-gserver
            :alive t
            :capabilities '("username-search" "social-account-discovery")
            :ref :user-hunt-ref)
      (list :name "nmap"
            :service-uri "star://bbp:localhost:nmap"
            :domain "bbp"
            :address "localhost"
            :runtime :cl-gserver
            :alive nil
            :capabilities '("port-scan")
            :ref :nmap-ref)))))

(defun test-runtime-directory-service-resolution ()
  (let* ((directory (live-service-directory))
         (entry
           (resolve-star-service-uri
            directory nil "star://quasar:localhost:user-hunt")))
    (service-uri-assert-equal "user-hunt" (getf entry :name)
                              "runtime directory resolves actor name")
    (service-uri-assert-equal :user-hunt-ref (getf entry :ref)
                              "runtime directory preserves opaque ref")
    (service-uri-assert-true
     (service-uri-condition-signaled-p
      'star-service-unavailable-error
      (lambda ()
        (resolve-star-service-uri
         directory nil "star://bbp:localhost:nmap")))
     "stopped STAR service distinguished from missing")
    (service-uri-assert-true
     (service-uri-condition-signaled-p
      'star-service-not-found-error
      (lambda ()
        (resolve-star-service-uri
         directory nil "star://quasar:localhost:missing")))
     "missing STAR service rejected")))

(defun service-uri-test-command ()
  (make-command-envelope
   :message-id "service-uri-command-0001"
   :message-type "org.starintel/fec@1/ingest-page"
   :actor "star://quasar:localhost:user-hunt"
   :sender "service-uri-test"
   :idempotency-key "service-uri:test:0001"
   :dataset "fec-2026"
   :payload '(("endpoint" . "/candidates/search/")
              ("cycle" . 2026)
              ("page" . 1)
              ("results" . ())
              ("retrievedAt" . "2026-08-12T00:00:00Z"))))

(defun test-deterministic-service-uri-dispatch ()
  (let* ((manifest (service-uri-test-manifest))
         (dispatcher (make-deterministic-dispatcher manifest))
         (command (service-uri-test-command)))
    (register-dispatch-actor
     dispatcher "user-hunt"
     (lambda (runtime envelope)
       (declare (ignore runtime))
       (service-uri-assert-equal
        "star://quasar:localhost:user-hunt"
        (getf envelope :actor)
        "handler receives logical STAR target")
       (complete-dispatch)))
    (submit-dispatch-envelope dispatcher command)
    (service-uri-assert-equal '(:completed)
                              (run-dispatcher dispatcher)
                              "STAR URI command completes")
    (service-uri-assert-equal
     1
     (gethash "star://quasar:localhost:user-hunt"
              (deterministic-dispatcher-handler-count dispatcher))
     "STAR URI handler invocation counted")
    (let ((outcomes (drain-dispatcher-emitted dispatcher)))
      (service-uri-assert-equal '(:ack :ack)
                                (mapcar (lambda (entry) (getf entry :kind)) outcomes)
                                "STAR URI dispatch emits accepted/completed")
      (service-uri-assert-equal
       "star://quasar:localhost:user-hunt"
       (getf (first outcomes) :sender)
       "acknowledgement preserves logical STAR sender"))))

(defun run-service-uri-tests ()
  (test-service-uri-round-trip)
  (test-service-uri-invalid-input)
  (test-service-uri-actor-manifest)
  (test-runtime-directory-service-resolution)
  (test-deterministic-service-uri-dispatch)
  (format t "STAR service URI discovery and dispatch tests passed.~%")
  t)

(unless (run-service-uri-tests)
  (error "STAR service URI tests failed."))
