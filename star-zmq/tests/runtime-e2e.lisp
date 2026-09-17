(defpackage :star-zmq-runtime-tests
  (:use :cl)
  (:export #:run-tests))

(in-package :star-zmq-runtime-tests)

(defvar *assertions* 0)

(defun check (value &optional (message "check failed"))
  (incf *assertions*)
  (unless value
    (error "~A" message))
  value)

(defun fails (type thunk)
  (let ((caught nil))
    (handler-case
        (funcall thunk)
      (error (condition)
        (unless (typep condition type)
          (error condition))
        (setf caught t)))
    (check caught (format nil "Expected ~S." type))))

(defun temporary-directory ()
  (string-trim '(#\Newline #\Return)
               (uiop:run-program '("mktemp" "-d") :output :string)))

(defun external-actor-source (endpoint)
  (format nil
          "(actor nim-echo
             (:runtime external
              :service-uri \"star://test:localhost:nim-echo\"
              :protocol star-message-v1
              :endpoint ~S
              :accepts (star.zmq/echo@1)
              :produces (star.zmq/echo@1)
              :restart permanent
              :mailbox (bounded 1)))"
          endpoint))

(defun compile-external-actor (endpoint)
  (starlangcompiler:compile-actor-source
   (external-actor-source endpoint)
   :source-id "star-zmq-runtime-e2e.star"))

(defun test-library ()
  '(:kind :spec-library
    :name "star.zmq/runtime-e2e@1"
    :version "1.0.0"
    :digest "sha256:star-zmq-runtime-e2e"
    :imports ()
    :declarations
    ((:kind :message
      :name "echo"
      :qualified-name "star.zmq/echo@1"
      :fields ((:name "text" :type "string" :required t))))))

(defun manifest-for (actor-ir)
  (starlangcompiler:emit-portable-manifest
   (test-library)
   (list actor-ir)))

(defun command (id text &key deadline)
  (staractorprotocol:make-command-envelope
   :message-id id
   :message-type "star.zmq/echo@1"
   :actor "nim-echo"
   :sender "runtime-e2e-caller"
   :reply-to "runtime-e2e-caller"
   :correlation-id (format nil "correlation/~A" id)
   :idempotency-key (format nil "runtime-e2e/~A" id)
   :dataset "runtime-e2e"
   :deadline deadline
   :payload (list (cons "text" text))))

(defun baseline-external-dispatch-is-not-magical (actor-ir)
  (let ((runtime (starlangruntime:make-runtime)))
    (unwind-protect
         (progn
           (starlangruntime:create-external-actor
            runtime
            (getf actor-ir :name)
            (getf actor-ir :service-uri)
            :accepts (copy-list (getf actor-ir :accepts))
            :produces (copy-list (getf actor-ir :produces))
            :restart-policy (getf actor-ir :restart)
            :mailbox-capacity (getf (getf actor-ir :mailbox) :capacity))
           (fails 'starlangruntime:actor-external-dispatch-required-error
                  (lambda ()
                    (starlangruntime:ask runtime "nim-echo" (command "baseline" "no-adapter")))))
      (starlangruntime:shutdown-runtime runtime))))

(defun reply-text (reply)
  (cdr (assoc "text" (getf reply :payload) :test #'string=)))

(defun e2e-tests (context executable directory)
  (let* ((endpoint (format nil "ipc://~A/runtime.sock" directory))
         (actor-ir (compile-external-actor endpoint))
         (manifest (manifest-for actor-ir))
         (runtime (starlangruntime:make-runtime))
         (binding nil))
    (check (eq :external (getf actor-ir :runtime)) "Compiler did not preserve external runtime.")
    (check (string= "star-message-v1" (getf actor-ir :protocol)) "Compiler lost external protocol.")
    (check (equal '(:kind :bounded :capacity 1) (getf actor-ir :mailbox))
           "Compiler lost mailbox policy.")
    (baseline-external-dispatch-is-not-magical actor-ir)
    (unwind-protect
         (progn
           (setf binding
                 (star-zmq-runtime:materialize-zmq-actor
                  runtime actor-ir manifest context executable
                  :identity "runtime-e2e"
                  :timeout-ms 5000))
           (let* ((actor (star-zmq-runtime:zmq-actor-binding-actor binding))
                  (reply (starlangruntime:ask runtime "nim-echo" (command "ask-1" "hello from StarLang"))))
             (check (eq :reply (getf reply :kind)) "E2E request did not return a lifecycle reply.")
             (check (string= "hello from StarLang" (reply-text reply)) "Nim reply payload did not round-trip.")
             (check (= 1 (starlangruntime:actor-instance-invocation-count actor))
                    "Real runtime handler did not execute exactly once.")
             (check (= 0 (star-zmq-runtime:zmq-actor-binding-peer-generation binding))
                    "Initial peer generation is wrong.")

             ;; Capacity one must be the real starlang-runtime/star-mailbox boundary.
             (let ((first (starlangruntime:tell runtime "nim-echo" (command "tell-1" "queued")))
                   (second (starlangruntime:tell runtime "nim-echo" (command "tell-2" "must-backpressure"))))
               (check (eq :accepted (starlangruntime:delivery-result-status first))
                      "First tell was not admitted.")
               (check (eq :mailbox-full (starlangruntime:delivery-result-status second))
                      "Second tell did not hit bounded mailbox backpressure.")
               (check (= 1 (starlangruntime:actor-mailbox-depth actor)) "Mailbox depth is not one."))
             (check (= 1 (starlangruntime:run-until-idle runtime)) "Queued tell did not drain exactly once.")
             (check (= 2 (starlangruntime:actor-instance-invocation-count actor))
                    "Queued tell did not execute through the proxy exactly once.")

             ;; Deadline rejection happens before the ZMQ request and must not poison the live peer.
             (fails 'starlangruntime:actor-contract-error
                    (lambda ()
                      (starlangruntime:ask
                       runtime "nim-echo"
                       (command "deadline" "reject" :deadline "2999-01-01T00:00:00Z"))))
             (check (= 2 (starlangruntime:actor-instance-invocation-count actor))
                    "Rejected deadline reached the external effect.")
             (check (string= "still alive"
                            (reply-text
                             (starlangruntime:ask runtime "nim-echo"
                                                 (command "ask-2" "still alive"))))
                    "Peer was poisoned by pre-effect rejection.")

             ;; Runtime restart is the generation authority. The adapter must replace the peer.
             (let ((before (starlangruntime:actor-instance-generation actor)))
               (starlangruntime:restart-actor runtime actor)
               (check (= (1+ before) (starlangruntime:actor-instance-generation actor))
                      "Runtime restart did not advance generation.")
               (let ((reply (starlangruntime:ask runtime "nim-echo"
                                                 (command "after-restart" "generation one"))))
                 (check (string= "generation one" (reply-text reply))
                        "Replacement peer failed after runtime restart."))
               (check (= (starlangruntime:actor-instance-generation actor)
                         (star-zmq-runtime:zmq-actor-binding-peer-generation binding))
                      "Peer generation did not follow the runtime actor generation."))))
      (when binding
        (star-zmq-runtime:close-zmq-actor-binding binding))
      (starlangruntime:shutdown-runtime runtime))))

(defun run-tests ()
  (setf *assertions* 0)
  (let* ((executable (or (uiop:getenv "STAR_ZMQ_ACTOR")
                         (error "STAR_ZMQ_ACTOR is required for the runtime E2E gate.")))
         (directory (temporary-directory))
         (context (star-zmq:make-context)))
    (unwind-protect
         (e2e-tests context executable directory)
      (star-zmq:close-context context)
      (uiop:delete-directory-tree
       (uiop:ensure-directory-pathname directory)
       :validate t
       :if-does-not-exist :ignore)))
  (format t "~&star-zmq StarLang runtime E2E: ~D assertions passed.~%" *assertions*)
  t)
