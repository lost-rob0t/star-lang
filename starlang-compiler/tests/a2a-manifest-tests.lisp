;;;; A2A v1 projection coverage for compiled StarLang actors.

(defpackage :starlang-a2a-manifest-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-a2a-manifest-tests)

(def-suite starlang-a2a-manifest-tests
  :description "A2A v1 Agent Card projection from final actor IR.")

(in-suite starlang-a2a-manifest-tests)

(defun a2a-test-actor (&optional (protocol 'a2a-v1))
  (star-lang.compiler.core:compile-actor
   `(actor gov-catalog
      (:runtime external
       :service-uri "star://starintel:beast:gov-catalog"
       :protocol ,protocol
       :endpoint "env:STARINTEL_A2A_GOV_CATALOG_URL"
       :accepts (org.starintel/jurisdiction-target@1
                 org.starintel/source-seed@1)
       :produces (org.starintel/source-catalog@1)
       :restart permanent
       :mailbox (bounded 128)
       :capabilities (socrata ckan arcgis)))))

(defun json-field (name object)
  (cdr (assoc name object :test #'string=)))

(test projects-valid-v1-agent-card
  (let* ((actor (a2a-test-actor))
         (card (starlangcompiler:emit-a2a-agent-card
                actor "https://workers.starintel.actor/gov-catalog"))
         (interface (first (json-field "supportedInterfaces" card)))
         (skills (json-field "skills" card)))
    (is (starlangcompiler:a2a-actor-p actor))
    (is (string= "gov-catalog" (json-field "name" card)))
    (is (string= "1.0" (json-field "protocolVersion" interface)))
    (is (string= "JSONRPC" (json-field "protocolBinding" interface)))
    (is (string= "https://workers.starintel.actor/gov-catalog"
                 (json-field "url" interface)))
    (is (= 2 (length skills)))
    (is (string= "org.starintel/jurisdiction-target@1"
                 (json-field "id" (first skills))))
    (is (member "socrata" (json-field "tags" (first skills)) :test #'string=))))

(test rejects-non-a2a-actors
  (signals star-lang.compiler.core:invalid-actor-error
    (starlangcompiler:emit-a2a-agent-card
     (a2a-test-actor 'star-message-v1)
     "https://workers.starintel.actor/gov-catalog")))

(test production-interface-requires-https
  (signals star-lang.compiler.core:invalid-actor-error
    (starlangcompiler:emit-a2a-agent-card
     (a2a-test-actor)
     "http://workers.starintel.actor/gov-catalog"))
  (is (not (starlangcompiler:valid-a2a-interface-url-p
            "http://localhost.evil.example/gov-catalog")))
  (is (starlangcompiler:valid-a2a-interface-url-p
       "http://127.0.0.1:9999/gov-catalog"))
  (is (starlangcompiler:valid-a2a-interface-url-p
       "http://localhost:9999/gov-catalog"))
  (is (starlangcompiler:valid-a2a-interface-url-p
       "https://workers.starintel.actor/gov-catalog")))

(test explicit-skills-must-be-nonempty-and-unique
  (signals star-lang.compiler.core:invalid-actor-error
    (starlangcompiler:emit-a2a-agent-card
     (a2a-test-actor)
     "https://workers.starintel.actor/gov-catalog"
     :skills '()))
  (signals star-lang.compiler.core:invalid-actor-error
    (starlangcompiler:emit-a2a-agent-card
     (a2a-test-actor)
     "https://workers.starintel.actor/gov-catalog"
     :skills '((("id" . "dup"))
               (("id" . "dup"))))))

(defun run-tests ()
  (unless (run! 'starlang-a2a-manifest-tests)
    (error "starlang A2A manifest tests failed.")))
