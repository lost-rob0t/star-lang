(defpackage :starlangruntime-wire-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:wire-dispatcher-error
                #:wire-dispatcher-invalid-actor-error
                #:wire-dispatcher-idempotency-conflict-error
                #:make-deterministic-dispatcher
                #:deterministic-dispatcher-queue
                #:deterministic-dispatcher-handler-count
                #:register-dispatch-actor
                #:complete-dispatch
                #:retry-dispatch
                #:defer-dispatch
                #:submit-dispatch-envelope
                #:run-dispatcher
                #:run-dispatcher-next
                #:drain-dispatcher-emitted
                #:redeliver-command
                #:finish-deferred-dispatch
                #:deferred-dispatch-status
                #:advance-dispatcher-clock)
  (:export #:run-tests))

(in-package :starlangruntime-wire-tests)

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

(defun dispatcher-manifest ()
  (list
   :wire-version 1
   :types '()
   :messages
   (list
    (list :kind :message
          :name "test/run@1"
          :fields
          (list (list :name "target" :type "string" :required t)))
    (list :kind :message
          :name "test/result@1"
          :fields
          (list (list :name "value" :type "string" :required t))))
   :actors
   (list
    (list :name "worker"
          :service-uri "star://test:localhost:worker"
          :runtime :external
          :accepts '("test/run@1")
          :produces '("test/result@1")))))

(defun dispatcher-command
    (&key
       (message-id "command-1")
       (idempotency-key "idem-1")
       (actor "worker")
       deadline
       (target "example.org"))
  (staractorprotocol:make-command-envelope
   :message-id message-id
   :message-type "test/run@1"
   :actor actor
   :sender "caller"
   :idempotency-key idempotency-key
   :deadline deadline
   :payload (list (cons "target" target))))

(defun emitted-kinds (dispatcher)
  (mapcar (lambda (envelope) (getf envelope :kind))
          (drain-dispatcher-emitted dispatcher)))

(defun test-completion-terminal-replay-and-identity-conflict ()
  (let* ((dispatcher (make-deterministic-dispatcher (dispatcher-manifest)))
         (command (dispatcher-command))
         (calls 0))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (incf calls)
       (complete-dispatch
        :message-type "test/result@1"
        :payload '(("value" . "ok")))))
    (submit-dispatch-envelope dispatcher command)
    (check (equal '(:completed) (run-dispatcher dispatcher))
           "Initial command did not complete.")
    (check (equal '(:ack :reply :ack) (emitted-kinds dispatcher))
           "Completion did not emit accepted/reply/completed.")
    (check (= 1 calls) "Initial handler count changed.")
    (let ((redelivery
            (redeliver-command
             dispatcher command :message-id "command-redelivery")))
      (submit-dispatch-envelope dispatcher redelivery)
      (check (eq :duplicate (run-dispatcher-next dispatcher))
             "Compatible terminal redelivery was not replayed.")
      (check (equal '(:reply :ack) (emitted-kinds dispatcher))
             "Terminal replay emitted the wrong outcomes.")
      (check (= 1 calls) "Terminal replay reran the handler."))
    (let ((conflict (copy-tree command)))
      (setf (getf conflict :message-id) "conflict-redelivery"
            (getf conflict :causation-id) (getf command :message-id)
            (getf conflict :attempt) 2
            (cdr (assoc "target" (getf conflict :payload) :test #'string=))
            "other.example.org")
      (submit-dispatch-envelope dispatcher conflict)
      (check
       (signals-p 'wire-dispatcher-idempotency-conflict-error
                  (lambda () (run-dispatcher-next dispatcher)))
       "Changed semantic command identity reused an idempotency key."))))

(defun test-retry-and_redelivery_metadata ()
  (let* ((dispatcher (make-deterministic-dispatcher (dispatcher-manifest)))
         (command
           (dispatcher-command
            :message-id "retry-1"
            :idempotency-key "retry-key"))
         (calls 0))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (incf calls)
       (if (= calls 1)
           (retry-dispatch :retry-after-ms 1000 :reason "retry")
           (complete-dispatch
            :message-type "test/result@1"
            :payload '(("value" . "ok"))))))
    (submit-dispatch-envelope dispatcher command)
    (check (eq :retry (run-dispatcher-next dispatcher))
           "First attempt did not enter retry state.")
    (check (equal '(:ack :ack) (emitted-kinds dispatcher))
           "Retry emitted the wrong ACK chain.")
    (let ((redelivery
            (redeliver-command
             dispatcher command :message-id "retry-2")))
      (check (= 2 (getf redelivery :attempt))
             "Redelivery did not increment attempt.")
      (check (string= "retry-1" (getf redelivery :correlation-id))
             "Redelivery changed correlation identity.")
      (check (string= "retry-1" (getf redelivery :causation-id))
             "Redelivery did not record prior delivery as cause.")
      (submit-dispatch-envelope dispatcher redelivery)
      (check (eq :completed (run-dispatcher-next dispatcher))
             "Retry redelivery did not complete.")
      (check (equal '(:ack :reply :ack) (emitted-kinds dispatcher))
             "Successful retry redelivery emitted wrong outcomes."))))

(defun test_deferred_cancel_and_late_completion ()
  (let* ((dispatcher (make-deterministic-dispatcher (dispatcher-manifest)))
         (command
           (dispatcher-command
            :message-id "deferred-1"
            :idempotency-key "deferred-key")))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (defer-dispatch)))
    (submit-dispatch-envelope dispatcher command)
    (check (eq :deferred (run-dispatcher-next dispatcher))
           "Deferred handler did not remain in progress.")
    (drain-dispatcher-emitted dispatcher)
    (check (eq :in-progress (deferred-dispatch-status dispatcher command))
           "Deferred command did not expose in-progress status.")
    (let ((cancel
            (staractorprotocol:make-cancel-envelope
             command
             :message-id "cancel-1"
             :actor "worker"
             :sender "caller"
             :reason "test")))
      (check (eq :cancel-requested
                 (submit-dispatch-envelope dispatcher cancel))
             "Cancel was not applied.")
      (let ((outcomes (drain-dispatcher-emitted dispatcher)))
        (check (equal '(:error)
                      (mapcar (lambda (item) (getf item :kind)) outcomes))
               "Cancellation did not produce one terminal error.")
        (check (string= "star.cancelled"
                        (getf (getf (first outcomes) :payload) :code))
               "Cancellation error code changed.")))
    (check
     (eq :late-terminal
         (finish-deferred-dispatch
          dispatcher command
          (complete-dispatch
           :message-type "test/result@1"
           :payload '(("value" . "late")))))
     "Late deferred completion was not ignored as terminal metadata.")))

(defun test_deadline_and_queue_boundary ()
  (let* ((dispatcher
           (make-deterministic-dispatcher
            (dispatcher-manifest)
            :now "2026-08-15T10:00:00Z"))
         (expired
           (dispatcher-command
            :message-id "expired-1"
            :idempotency-key "expired-key"
            :deadline "2026-08-15T09:59:59Z"))
         (calls 0))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (incf calls)
       (complete-dispatch)))
    (submit-dispatch-envelope dispatcher expired)
    (check (listp (deterministic-dispatcher-queue dispatcher))
           "Dispatcher work queue stopped being its list/FIFO abstraction.")
    (check (eq :deadline-exceeded (run-dispatcher-next dispatcher))
           "Expired command did not fail before handler execution.")
    (check (= 0 calls) "Expired command invoked its handler.")
    (let ((outcomes (drain-dispatcher-emitted dispatcher)))
      (check (string= "star.deadline-exceeded"
                      (getf (getf (first outcomes) :payload) :code))
             "Deadline error code changed."))
    (check
     (signals-p 'wire-dispatcher-error
                (lambda ()
                  (advance-dispatcher-clock
                   dispatcher "2026-08-15T09:00:00Z")))
     "Dispatcher clock moved backward.")))

(defun test_route_validation ()
  (let ((dispatcher (make-deterministic-dispatcher (dispatcher-manifest))))
    (check
     (signals-p
      'wire-dispatcher-invalid-actor-error
      (lambda ()
        (register-dispatch-actor dispatcher "missing" #'identity)))
     "Unmanifested handler registration was accepted.")
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (complete-dispatch)))
    (let ((command (dispatcher-command :actor "missing")))
      (submit-dispatch-envelope dispatcher command)
      (check
       (signals-p 'wire-dispatcher-invalid-actor-error
                  (lambda () (run-dispatcher-next dispatcher)))
       "Unknown command route was accepted."))))

(defun test_final_dispatcher_is_prototype_independent ()
  (check
   (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
   "Final deterministic wire dispatcher loaded the prototype package."))

(defun test-real-dispatcher-outcomes-pass-canonical-correlation-guard ()
  ;; Exercise actual admission and settlement, not hand-constructed outcomes.
  ;; Actor identity names the invoked actor across the lifecycle; transport
  ;; reply routing is independent. Canonical lifecycle-v1 fixtures agree.
  (dolist (actor '("worker" "star://test:localhost:worker"))
    (dolist (mode '(:complete :retry :fail :deadline :cancel))
      (let* ((dispatcher
               (make-deterministic-dispatcher
                (dispatcher-manifest) :now "2026-08-15T10:00:00Z"))
             (command
               (dispatcher-command
                :actor actor
                :deadline (when (eq mode :deadline) "2026-08-15T09:59:59Z")))
             (calls 0))
        (setf (getf command :dataset) "fixture")
        (register-dispatch-actor
         dispatcher "worker"
         (lambda (runtime envelope)
           (declare (ignore runtime envelope))
           (incf calls)
           (ecase mode
             (:complete (complete-dispatch :message-type "test/result@1"
                                           :payload '(("value" . "ok"))))
             (:retry (retry-dispatch :retry-after-ms 10 :reason "busy"))
             (:fail (starlangruntime:fail-dispatch :code "fixture.failed"
                                                  :message "Synthetic failure"))
             (:cancel (defer-dispatch))
             (:deadline (error "Expired request invoked handler.")))))
        (submit-dispatch-envelope dispatcher command)
        (run-dispatcher-next dispatcher)
        (when (eq mode :cancel)
          (submit-dispatch-envelope
           dispatcher
           (staractorprotocol:make-cancel-envelope
            command :message-id "cancel-guard" :actor actor :sender "caller")))
        (let* ((outcomes (drain-dispatcher-emitted dispatcher))
               (kinds (mapcar (lambda (value) (getf value :kind)) outcomes)))
          (check (equal kinds
                        (ecase mode
                          (:complete '(:ack :reply :ack))
                          (:retry '(:ack :ack))
                          ((:fail :cancel) '(:ack :error))
                          (:deadline '(:error))))
                 "Unexpected actual lifecycle chain for ~A: ~S" mode kinds)
          (check (= calls (if (eq mode :deadline) 0 1))
                 "Handler count differs for ~A." mode)
          (dolist (outcome outcomes)
            (check (staractorprotocol:validate-correlated-lifecycle-outcome
                    command outcome)
                   "Actual ~A outcome failed canonical correlation guard." mode)
            (check (equal actor (getf outcome :actor))
                   "Outcome actor was replaced by a reply routing identity.")))))))

(defun test-public-command-identity-validation ()
  (let* ((original (dispatcher-command :deadline "2026-08-15T10:00:00Z"))
         (retry (copy-tree original)))
    (setf (getf retry :message-id) "retry-identity"
          (getf retry :causation-id) (getf original :message-id)
          (getf retry :attempt) 2)
    (check (eq retry (starlangruntime:validate-command-idempotency-identity
                     original retry))
           "Public identity validator rejected compatible retry metadata.")
    (dolist (change '((:actor . "other") (:sender . "other")
                      (:correlation-id . "other") (:idempotency-key . "other")
                      (:dataset . "other") (:reply-to . "other")
                      (:deadline . "2026-08-16T10:00:00Z")
                      (:message-type . "other/run@1")
                      (:payload . (("target" . "changed")))))
      (let ((conflict (copy-tree original)))
        (setf (getf conflict (car change)) (cdr change))
        (check (signals-p
                'wire-dispatcher-idempotency-conflict-error
                (lambda ()
                  (starlangruntime:validate-command-idempotency-identity
                   original conflict)))
               "Public validator accepted changed identity field ~A." (car change))))))

(defun test-canonical-payload-identity-survives-wire-replay ()
  (let* ((manifest (dispatcher-manifest))
         (calls 0)
         (dispatcher nil)
         (command nil))
    (setf (getf (first (getf manifest :messages)) :fields)
          '((:name "data" :type "map" :required t)))
    (labels ((wire-copy (envelope)
               (star-actor-wire:decode-envelope
                manifest (star-actor-wire:encode-envelope manifest envelope)))
             (make-runtime ()
               (let ((runtime (make-deterministic-dispatcher manifest)))
                 (register-dispatch-actor
                  runtime "worker"
                  (lambda (owner envelope)
                    (declare (ignore owner envelope))
                    (incf calls)
                    (complete-dispatch :message-type "test/result@1"
                                       :payload '(("value" . "ok")))))
                 runtime))
             (data (envelope)
               (cdr (assoc "data" (getf envelope :payload) :test #'string=)))
             (field (envelope name)
               (assoc name (data envelope) :test #'string=)))
      (setf dispatcher (make-runtime)
            command (dispatcher-command))
      (setf (getf command :payload)
            (list
             (cons "data"
                   (list (cons "items" (vector "CaseSensitive" 7))
                         (cons "number" (staractorprotocol:make-portable-json-number "1.2300"))
                         (cons "flag" staractorprotocol:+portable-json-false+)
                         (cons "nullable" staractorprotocol:+portable-json-null+)
                         (cons "empty" #())))))
      (setf command (wire-copy command))
      (submit-dispatch-envelope dispatcher command)
      (check (eq :completed (run-dispatcher-next dispatcher))
             "Canonical array fixture did not execute the real dispatcher.")
      (check (= calls 1) "Initial canonical fixture did not invoke its handler once.")
      ;; Reconstruct a new runtime record from the real dispatcher's command and
      ;; outcomes through the supported encoder/decoder. This is a wire replay
      ;; regression, not a claim of a database restart test.
      (let* ((record (starlangruntime:command-idempotency-record dispatcher command))
             (restored-command (wire-copy (getf record :command)))
             (restored (make-runtime)))
        (starlangruntime:set-command-idempotency-record
         restored restored-command
         (list :status (getf record :status)
               :command restored-command
               :outcomes (mapcar #'wire-copy (getf record :outcomes))))
        (setf dispatcher restored))
      (let ((retry (wire-copy command)))
        (check (not (eq (cdr (field command "items"))
                        (cdr (field retry "items"))))
               "Wire replay fixture accidentally reused the same array object.")
        (check (not (eq (cdr (field command "number"))
                        (cdr (field retry "number"))))
               "Wire replay fixture accidentally reused the same numeric token object.")
        (setf (getf retry :message-id) "canonical-replay"
              (getf retry :causation-id) (getf command :message-id)
              (getf retry :attempt) 2)
        (submit-dispatch-envelope dispatcher retry)
        (check (eq :duplicate (run-dispatcher-next dispatcher))
               "Equivalent decoded array/number payload was rejected after restore.")
        (check (= calls 1) "Canonical replay repeated the handler effect."))
      ;; Object key ordering and portable array list/vector representation have
      ;; the same canonical payload bytes, while empty array is not null.
      (let ((equivalent (wire-copy command)))
        (setf (cdr (field equivalent "items"))
              (coerce (cdr (field equivalent "items")) 'list)
              (cdr (assoc "data" (getf equivalent :payload) :test #'string=))
              (reverse (data equivalent)))
        (check (eq equivalent
                   (starlangruntime:validate-command-idempotency-identity
                    command equivalent))
               "Canonical map/array equivalence changed command identity."))
      (dolist (mutation '(:element :case :number-lexeme :number-type :false :null :absence :empty))
        (let ((conflict (wire-copy command)))
          (ecase mutation
            (:element (setf (aref (cdr (field conflict "items")) 1) 8))
            (:case (setf (aref (cdr (field conflict "items")) 0) "casesensitive"))
            (:number-lexeme
             (setf (cdr (field conflict "number"))
                   (staractorprotocol:make-portable-json-number "1.230")))
            (:number-type (setf (cdr (field conflict "number")) "1.2300"))
            (:false (setf (cdr (field conflict "flag")) t))
            (:null (setf (cdr (field conflict "nullable")) staractorprotocol:+portable-json-false+))
            (:absence
             (setf (cdr (assoc "data" (getf conflict :payload) :test #'string=))
                   (remove "nullable" (data conflict) :key #'car :test #'string=)))
            (:empty (setf (cdr (field conflict "empty")) staractorprotocol:+portable-json-null+)))
          (setf conflict (wire-copy conflict))
          (submit-dispatch-envelope dispatcher conflict)
          (check (signals-p 'wire-dispatcher-idempotency-conflict-error
                            (lambda () (run-dispatcher-next dispatcher)))
                 "Changed portable JSON value (~A) reused a command identity." mutation)
          (check (= calls 1) "Conflicting ~A payload invoked handler." mutation))))))

(defun run-tests ()
  (test-canonical-payload-identity-survives-wire-replay)
  (test-real-dispatcher-outcomes-pass-canonical-correlation-guard)
  (test-public-command-identity-validation)
  (test-completion-terminal-replay-and-identity-conflict)
  (test-retry-and_redelivery_metadata)
  (test_deferred_cancel_and_late_completion)
  (test_deadline_and_queue_boundary)
  (test_route_validation)
  (test_final_dispatcher_is_prototype_independent)
  (format t "~&starlang-runtime wire dispatcher tests passed~%")
  t)
