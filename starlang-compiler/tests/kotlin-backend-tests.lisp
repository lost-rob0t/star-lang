(defpackage :starlang-kotlin-backend-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-kotlin-backend-tests)

(def-suite starlang-kotlin-backend-tests
  :description "Deterministic StarLang IR to Kotlin binding generation.")

(in-suite starlang-kotlin-backend-tests)

(defun actor-fixture ()
  (asdf:system-relative-pathname
   :starlang-compiler
   "../fixtures/actor-compiler/enrichment-worker.star"))

(test native-actor-generates-deterministic-kotlin
  (let* ((ir (starlangcompiler:compile-actor-file (actor-fixture)))
         (first (starlangcompiler:generate-kotlin-actor-binding ir))
         (second (starlangcompiler:generate-kotlin-actor-binding ir)))
    (is (string= first second))
    (is (search "object EnrichmentWorkerStarActor" first))
    (is (search "ActorDefinition.nativeActor(" first))
    (is (search "HANDLER_NAME: String = \"enrichment-worker-handler\"" first))
    (is (search "mailboxCapacity = 128" first))
    (is (search
         "metadata = mapOf(\"domain\" to PortableValue.Text(\"starintel\"), \"team\" to PortableValue.Text(\"enrichment\"))"
         first))
    (is (null (search "eval(" first)))))

(test external-actor-generates-kotlin-port-definition
  (let* ((ir
           (starlangcompiler:compile-actor-source
            "(actor fec-importer
               (:runtime external
                :service-uri \"star://fec:localhost:fec-importer\"
                :protocol star-message-v1
                :endpoint \"rabbitmq:star.fec.ingest\"
                :accepts (ingest-page)
                :produces (candidate)
                :restart permanent
                :mailbox (bounded 1024)))"))
         (source (starlangcompiler:generate-kotlin-actor-binding ir)))
    (is (search "ActorDefinition.externalActor(" source))
    (is (search "protocol = \"star-message-v1\"" source))
    (is (search "endpoint = \"rabbitmq:star.fec.ingest\"" source))
    (is (search "mailboxCapacity = 1024" source))))

(defun run-tests ()
  (unless (run! 'starlang-kotlin-backend-tests)
    (error "starlang-compiler Kotlin backend tests failed.")))
