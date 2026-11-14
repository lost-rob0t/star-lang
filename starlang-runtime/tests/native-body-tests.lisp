;;;; Native StarLang body execution, canonical resource-URI registration, and
;;;; keyed domain-engine tests over the real durable runtime (issues #69/#72).

(defpackage :starlangruntime-body-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:make-runtime
                #:make-body-actor-definition
                #:spawn
                #:ask
                #:tell
                #:restart-actor
                #:run-until-idle
                #:find-actor
                #:actor-instance-data
                #:body-fail-error
                #:body-fail-code
                #:body-fail-message
                #:body-unknown-message-error
                #:resolve-star-resource-uri
                #:make-runtime-directory-port
                #:runtime-directory-snapshot
                #:make-domain-server-engine
                #:invoke-domain-operation
                #:domain-server-engine-instance-count
                #:domain-server-engine-instance-state)
  (:import-from :staractorprotocol
                #:make-wire-envelope
                #:star-actor-reference-service-uri
                #:star-actor-reference-domain-id
                #:star-actor-reference-logical-path
                #:star-actor-reference-node-id)
  (:export #:run-tests))

(in-package :starlangruntime-body-tests)

(defun assert-test (condition label)
  (unless condition
    (error "starlang-runtime body test failed: ~A" label)))

(defun assert-equal (expected actual label)
  (assert-test (equal expected actual) label))

(defparameter *tracker-ir*
  '(:kind :actor
    :name "tracker"
    :runtime :native
    :resource-uri "star://starintel.dev/actor/tracker"
    :accepts ("ingest/record@1" "ingest/reset@1" "ingest/fail@1")
    :produces ("ingest/state@1")
    :restart :permanent
    :mailbox (:kind :bounded :capacity 16)
    :capabilities ()
    :states
    ((:name "lastSource" :type "string" :initial "" :persistence :journaled)
     (:name "sessionNote" :type "string" :initial "" :persistence :ephemeral))
    :handlers
    ((:message-type "ingest/record@1"
      :message-var "message"
      :context-var "context"
      :body
      (:do
       (:let (("source" . (:field (:context "message") "sourceId")))
         (:do
          (:if (:local "source")
               (:do (:state-write "lastSource" (:local "source")))
               (:const nil))))
       (:state-write "sessionNote" (:field (:context "message") "note"))
       (:reply
        (:construct "ingest/state@1"
                    (("lastSource" . (:state-read "lastSource"))
                     ("note" . (:state-read "sessionNote")))))))
     (:message-type "ingest/reset@1"
      :message-var "message"
      :context-var "context"
      :body
      (:do
       (:state-write "lastSource" (:const ""))
       (:reply
        (:construct "ingest/state@1"
                    (("lastSource" . (:state-read "lastSource")))))))
     (:message-type "ingest/fail@1"
      :message-var "message"
      :context-var "context"
      :body
      (:do
       (:fail "ingest/rejected"
              "records are not accepted in this state."))))))

(defun envelope (message-type payload)
  (make-wire-envelope :message-type message-type
                      :message-id (format nil "test-~A-~A"
                                          message-type
                                          (get-universal-time))
                      :actor "tracker"
                      :payload payload))

(defun record (source-id note)
  (envelope "ingest/record@1"
            (list (cons "sourceId" source-id)
                  (cons "note" note))))

(defun state-reply-value (result)
  result)

(defun body-actor-executes-starlang-handler ()
  "A native body actor executes through the real mailbox ask path."
  (let ((runtime (make-runtime)))
    (spawn runtime (make-body-actor-definition *tracker-ir*))
    (let ((result (ask runtime "tracker" (record "example.com" "first run"))))
      (assert-equal "example.com" (cdr (assoc "lastSource" result :test #'string=))
                    "journaled slot updated")
      (assert-equal "first run" (cdr (assoc "note" result :test #'string=))
                    "ephemeral slot updated"))))

(defun body-actor-state-commits-across-messages ()
  "State written by one transition is visible to the next."
  (let ((runtime (make-runtime)))
    (spawn runtime (make-body-actor-definition *tracker-ir*))
    (ask runtime "tracker" (record "a.example" "one"))
    (let ((result (ask runtime "tracker" (record "b.example" "two"))))
      (assert-equal "b.example" (cdr (assoc "lastSource" result :test #'string=))
                    "latest source wins")
      (assert-equal "two" (cdr (assoc "note" result :test #'string=))
                    "latest note wins"))))

(defun journaled-state-survives-restart-ephemeral-does-not ()
  "Restart semantics: journaled slots keep committed values, ephemeral
slots reset to their declared initial values (issue #69 gate 12)."
  (let ((runtime (make-runtime)))
    (spawn runtime (make-body-actor-definition *tracker-ir*))
    (ask runtime "tracker" (record "keep.example" "session value"))
    (restart-actor runtime "tracker")
    (let ((data (actor-instance-data (find-actor runtime "tracker"))))
      (assert-equal "keep.example"
                    (cdr (assoc "lastSource" data :test #'string=))
                    "journaled slot survived restart")
      (assert-equal ""
                    (cdr (assoc "sessionNote" data :test #'string=))
                    "ephemeral slot reset on restart"))
    (let ((result
            (ask runtime "tracker"
                 (envelope "ingest/reset@1" '()))))
      (assert-equal "" (cdr (assoc "lastSource" result :test #'string=))
                    "actor healthy and writable after restart"))))

(defun body-fail-is-typed-and-rolls-back-state ()
  "fail raises a typed error carrying code and message, and the failed
transition commits no state."
  (let ((runtime (make-runtime)))
    (spawn runtime (make-body-actor-definition *tracker-ir*))
    (ask runtime "tracker" (record "before.example" "kept"))
    (multiple-value-bind (value condition)
        (ignore-errors
          (ask runtime "tracker" (envelope "ingest/fail@1" '()))
          nil)
      (declare (ignore value))
      (assert-test condition "fail raises through ask")
      (assert-test (typep condition 'body-fail-error)
                   "fail surfaces as the typed body-fail-error")
      (assert-equal "ingest/rejected" (body-fail-code condition)
                    "fail code travels with the condition"))
    (let ((result (ask runtime "tracker" (record "after.example" "still here"))))
      (assert-equal "after.example"
                    (cdr (assoc "lastSource" result :test #'string=))
                    "failed transition committed no state")
      (assert-equal "still here"
                    (cdr (assoc "note" result :test #'string=))
                    "runtime stayed healthy after failed transition"))))

(defun unknown-message-type-is-typed ()
  "Messages outside the handler table fail with a typed error."
  (let ((runtime (make-runtime)))
    (spawn runtime (make-body-actor-definition *tracker-ir*))
    (assert-test
     (handler-case
         (progn (ask runtime "tracker" (envelope "ingest/other@1" '())) nil)
       (body-unknown-message-error () t))
     "unknown message type rejected")))

(defun send-delivers-through-the-real-mailbox ()
  "send enqueues to the target actor through the runtime tell path."
  (let ((runtime (make-runtime)))
    (spawn runtime
           (make-body-actor-definition
            '(:kind :actor
              :name "receiver"
              :runtime :native
              :accepts ("ping@1")
              :produces ("pong@1")
              :restart :permanent
              :mailbox (:kind :bounded :capacity 4)
              :capabilities ()
              :states
              ((:name "seen" :type "boolean" :initial nil
                :persistence :ephemeral))
              :handlers
              ((:message-type "ping@1"
                :message-var "message"
                :context-var "context"
                :body
                (:do
                 (:state-write "seen" (:const t))
                 (:reply (:construct "pong@1" (("seen" . (:state-read "seen")))))))))))
    (spawn runtime
           (make-body-actor-definition
            '(:kind :actor
              :name "sender"
              :runtime :native
              :accepts ("go@1")
              :produces ("pong@1")
              :restart :permanent
              :mailbox (:kind :bounded :capacity 4)
              :capabilities ()
              :states ()
              :handlers
              ((:message-type "go@1"
                :message-var "message"
                :context-var "context"
                :body
                (:do
                 (:send (:const "receiver")
                        (:construct "ping@1" (("ok" . (:const t)))))
                 (:ask (:const "receiver") (:construct "ping@1" (("ok" . (:const t)))))
                 (:reply (:construct "pong@1" (("via" . (:const "ask")))))))))))
    (let ((result (ask runtime "sender" (envelope "go@1" '()))))
      (assert-equal "ask" (cdr (assoc "via" result :test #'string=))
                    "nested ask executed through the real mailbox")
      (let ((pong (ask runtime "receiver" (envelope "ping@1" '()))))
        (assert-test (cdr (assoc "seen" pong :test #'string=))
                     "receiver processed the sent message")))))

(defun canonical-resource-uri-registration-and-resolution ()
  "Canonical actors register under their resource URI and resolve through
it; references serialize back to canonical form (issue #72 slice 4)."
  (let ((runtime (make-runtime)))
    (spawn runtime (make-body-actor-definition *tracker-ir*))
    (assert-test (find-actor runtime "star://starintel.dev/actor/tracker")
                 "canonical URI resolves")
    (assert-test (find-actor runtime "tracker") "name resolves")
    (let ((reference
            (starlangruntime:actor-reference
             (find-actor runtime "star://starintel.dev/actor/tracker"))))
      (assert-equal "star://starintel.dev/actor/tracker"
                    (star-actor-reference-service-uri reference)
                    "reference serializes canonically")
      (assert-equal "starintel.dev"
                    (star-actor-reference-domain-id reference)
                    "authority is the domain id")
      (assert-equal "tracker"
                    (star-actor-reference-logical-path reference)
                    "actor name is the logical path"))))

(defun runtime-directory-resolves-canonical-entries ()
  "The runtime directory resolves canonical resource URIs without
conflating liveness with identity (issue #72 slice 4)."
  (let ((port (make-runtime-directory-port
               :snapshot
               (lambda (context)
                 (declare (ignore context))
                 (list
                  (list :name "tracker"
                        :runtime :starlang
                        :resource-uri "star://starintel.dev/actor/tracker"
                        :alive t
                        :capabilities '("ingest"))
                  (list :name "stopped"
                        :runtime :starlang
                        :resource-uri "star://starintel.dev/actor/stopped"
                        :alive nil))))))
    (let ((entry (resolve-star-resource-uri
                  port nil "star://starintel.dev/actor/tracker")))
      (assert-equal "tracker" (getf entry :name) "entry resolved"))
    (assert-test
     (handler-case
         (progn (resolve-star-resource-uri
                 port nil "star://starintel.dev/actor/missing")
                nil)
       (starlangruntime:runtime-directory-service-not-found-error () t))
     "missing entry is typed not-found")
    (assert-test
     (handler-case
         (progn (resolve-star-resource-uri
                 port nil "star://starintel.dev/actor/stopped")
                nil)
       (starlangruntime:runtime-directory-service-unavailable-error () t))
     "non-alive entry is typed unavailable")))

(defun domain-engine-executes-keyed-bodies ()
  "The keyed domain engine scopes state per key and dispatches typed
commands through body IR."
  (let ((engine
          (make-domain-server-engine
           :definition
           '(:kind :domain-server
             :name "ingest"
             :key-type "org.starintel/ingest@1/program-id"
             :accepts ("ingest/record@1")
             :restart :permanent
             :mailbox (:kind :bounded :capacity 16)
             :states
             ((:name "lastSource" :type "string" :initial ""
               :persistence :journaled))
             :handlers
             ((:message-type "ingest/record@1"
               :key-var "key"
               :message-var "message"
               :context-var "context"
               :body
               (:do
                (:state-write "lastSource"
                              (:field (:context "message") "sourceId"))
                (:reply (:construct "ingest/count@1"
                                    (("last" . (:state-read "lastSource")))))))))
           :initializer
           (lambda (key engine)
             (declare (ignore engine))
             (list (cons "lastSource" (format nil "init:~A" key)))))))
    (let ((result (invoke-domain-operation
                   engine "program-1" "ingest/record@1"
                   (list (cons "sourceId" "one.example"))))
          (other (invoke-domain-operation
                  engine "program-2" "ingest/record@1"
                  (list (cons "sourceId" "two.example")))))
      (assert-equal "one.example" (cdr (assoc "last" result :test #'string=))
                    "program-1 sees its own source")
      (assert-equal "two.example" (cdr (assoc "last" other :test #'string=))
                    "program-2 state is keyed independently")
      (assert-equal 2 (domain-server-engine-instance-count engine)
                    "two keyed instances")
      (assert-equal "two.example"
                    (cdr (assoc "lastSource"
                                (domain-server-engine-instance-state
                                 engine "program-2")
                                :test #'string=))
                    "keyed state persists across operations"))))

(defun domain-engine-rejects-unknown-messages ()
  "The keyed engine rejects unknown message types and requires handlers."
  (let ((engine
          (make-domain-server-engine
           :definition
           '(:kind :domain-server
             :name "ingest"
             :key-type "k"
             :accepts ("ingest/record@1")
             :restart :permanent
             :mailbox (:kind :bounded :capacity 16)
             :states ()
             :handlers
             ((:message-type "ingest/record@1"
               :key-var "key"
               :message-var "message"
               :context-var "context"
               :body (:do (:reply (:const "done"))))))
           :initializer (lambda (key engine) (declare (ignore key engine)) '()))))
    (assert-test
     (handler-case
         (progn (invoke-domain-operation engine "k" "ingest/other@1" '()) nil)
       (starlangruntime:domain-server-core-error () t))
     "unknown domain message rejected")))

(defun run-tests ()
  (let ((tests
          (list
           (function body-actor-executes-starlang-handler)
           (function body-actor-state-commits-across-messages)
           (function journaled-state-survives-restart-ephemeral-does-not)
           (function body-fail-is-typed-and-rolls-back-state)
           (function unknown-message-type-is-typed)
           (function send-delivers-through-the-real-mailbox)
           (function canonical-resource-uri-registration-and-resolution)
           (function runtime-directory-resolves-canonical-entries)
           (function domain-engine-executes-keyed-bodies)
           (function domain-engine-rejects-unknown-messages))))
    (dolist (test tests)
      (funcall test))
    (format t "starlang-runtime body/domain tests passed (~D tests)~%"
            (length tests))
    t))
