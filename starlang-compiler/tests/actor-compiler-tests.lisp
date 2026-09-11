;;;; Final actor compiler tests: a real .star actor declaration compiles
;;;; through the closed parser and final lowering without starlang-prototype.

(defpackage :starlang-actor-compiler-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-actor-compiler-tests)

(def-suite starlang-actor-compiler-tests
  :description "Final starlang-compiler actor compilation over .star source.")

(in-suite starlang-actor-compiler-tests)

(defun actor-fixture ()
  (asdf:system-relative-pathname :starlang-compiler
                                 "../fixtures/actor-compiler/enrichment-worker.star"))

(defparameter *expected-actor-ir*
  '(:kind :actor
    :name "enrichment-worker"
    :runtime :native
    :service-uri "star://starintel:localhost:enrichment-worker"
    :accepts ("org.starintel/person@1")
    :produces ("org.starintel/person@1")
    :restart :permanent
    :mailbox (:kind :bounded :capacity 128)
    :capabilities ()
    :handler "enrichment-worker-handler"
    :metadata (("domain" . "starintel") ("team" . "enrichment"))))

(defun data-only-p (value)
  (typecase value
    ((or null boolean string integer keyword symbol) t)
    (cons (and (data-only-p (car value)) (data-only-p (cdr value))))
    (t nil)))

(defun minimal-test-library ()
  (list :kind :spec-library
        :name "org.starintel/core@1"
        :version "1.0.0"
        :digest "sha256:actor-compiler-test"
        :imports '()
        :declarations '()))

(test actor-fixture-compiles-through-the-closed-parser
  "A .star actor declaration is read by the closed parser and lowered."
  (let ((ir (starlangcompiler:compile-actor-file (actor-fixture))))
    (is (equal *expected-actor-ir* ir))))

(test actor-ir-is-deterministic
  "Repeated compilation of the same source produces identical IR."
  (let ((first (starlangcompiler:compile-actor-file (actor-fixture)))
        (second (starlangcompiler:compile-actor-file (actor-fixture))))
    (is (equal first second))))

(test actor-ir-is-runtime-neutral
  "The actor IR contains only plain data, never runtime objects."
  (is (data-only-p (starlangcompiler:compile-actor-file (actor-fixture)))))

(test actor-service-uri-is-canonical
  "star://domain:address:actor-name survives lowering unchanged."
  (let ((ir (starlangcompiler:compile-actor-file (actor-fixture))))
    (is (string= "star://starintel:localhost:enrichment-worker"
                 (getf ir :service-uri)))))

(test actor-service-uri-mismatch-is-rejected
  "A service URI naming a different actor is rejected deterministically."
  (signals star-lang.compiler.core:invalid-star-service-uri-error
    (starlangcompiler:compile-actor-source
     "(actor enrichment-worker
        (:runtime native
         :service-uri \"star://starintel:localhost:other-worker\"
         :accepts (org.starintel/person@1)
         :produces (org.starintel/person@1)
         :handler enrichment-worker-handler
         :restart permanent
         :mailbox (bounded 128)))")))

(test malformed-actor-declarations-fail-deterministically
  "Every malformed actor shape fails with a typed compiler condition."
  (loop for (label . source) in
        `(("unknown head" . "(document enrichment-worker (:schema \"x\" :persistence :persistent))")
          ("bad shape" . "(actor enrichment-worker)")
          ("odd options" . "(actor enrichment-worker (:runtime native :accepts))")
          ("missing accepts" . "(actor enrichment-worker (:runtime native :produces (x) :handler h :restart permanent :mailbox (bounded 1)))")
          ("bad runtime" . "(actor enrichment-worker (:runtime robotic :accepts (x) :produces (x) :handler h :restart permanent :mailbox (bounded 1)))")
          ("bad restart" . "(actor enrichment-worker (:runtime native :accepts (x) :produces (x) :handler h :restart eventually :mailbox (bounded 1)))")
          ("zero mailbox" . "(actor enrichment-worker (:runtime native :accepts (x) :produces (x) :handler h :restart permanent :mailbox (bounded 0)))")
          ("bad mailbox shape" . "(actor enrichment-worker (:runtime native :accepts (x) :produces (x) :handler h :restart permanent :mailbox (unbounded)))")
          ("native without handler" . "(actor enrichment-worker (:runtime native :accepts (x) :produces (x) :restart permanent :mailbox (bounded 1)))")
          ("external without protocol" . "(actor enrichment-worker (:runtime external :accepts (x) :produces (x) :endpoint \"e\" :restart permanent :mailbox (bounded 1)))")
          ("external non-string endpoint" . "(actor enrichment-worker (:runtime external :accepts (x) :produces (x) :protocol p :endpoint 42 :restart permanent :mailbox (bounded 1)))")
          ("metadata not a list" . "(actor enrichment-worker (:runtime native :accepts (x) :produces (x) :handler h :restart permanent :mailbox (bounded 1) :metadata 42))")
          ("metadata bad key" . "(actor enrichment-worker (:runtime native :accepts (x) :produces (x) :handler h :restart permanent :mailbox (bounded 1) :metadata ((NotCamel \"x\"))))")
          ("metadata bad value" . "(actor enrichment-worker (:runtime native :accepts (x) :produces (x) :handler h :restart permanent :mailbox (bounded 1) :metadata ((team (nested)))))"))
        do (signals star-lang.compiler.core:star-lang-core-error
             (starlangcompiler:compile-actor-source source))))

(test unknown-source-keyword-is-rejected-by-the-closed-parser
  "The closed parser rejects option keywords outside its vocabulary."
  (signals star-lang.compiler.core:star-lang-source-error
    (starlangcompiler:compile-actor-source
     "(actor enrichment-worker (:runtime native :mystery 1))")))

(test multiple-top-level-forms-are-rejected
  "A .star actor unit must contain exactly one top-level form."
  (signals star-lang.compiler.core:star-lang-source-error
    (starlangcompiler:compile-actor-source
     "(actor a (:runtime native :accepts (x) :produces (x) :handler h :restart permanent :mailbox (bounded 1))) (actor b (:runtime native :accepts (x) :produces (x) :handler h :restart permanent :mailbox (bounded 1)))")))

(test external-actor-compiles-through-the-closed-parser
  "An external actor keeps protocol and endpoint data."
  (let ((ir (starlangcompiler:compile-actor-source
             "(actor fec-importer
                (:runtime external
                 :service-uri \"star://fec:localhost:fec-importer\"
                 :protocol star-message-v1
                 :endpoint \"rabbitmq:star.fec.ingest\"
                 :accepts (ingest-page)
                 :produces (candidate committee filing)
                 :restart permanent
                 :mailbox (bounded 1024)))")))
    (is (equal '(:kind :actor
                 :name "fec-importer"
                 :runtime :external
                 :service-uri "star://fec:localhost:fec-importer"
                 :accepts ("ingest-page")
                 :produces ("candidate" "committee" "filing")
                 :restart :permanent
                 :mailbox (:kind :bounded :capacity 1024)
                 :capabilities ()
                 :protocol "star-message-v1"
                 :endpoint "rabbitmq:star.fec.ingest")
              ir))))

(test actor-metadata-round-trips-through-the-portable-manifest
  "Portable actor manifests carry service URI and metadata in camelCase JSON."
  (let* ((ir (starlangcompiler:compile-actor-file (actor-fixture)))
         (manifest (starlangcompiler:emit-portable-manifest
                    (minimal-test-library) (list ir)))
         (portable (first (getf manifest :actors)))
         (json (starcanonicaljson:canonical-manifest-json manifest)))
    (is (string= "star://starintel:localhost:enrichment-worker"
                 (getf portable :service-uri)))
    (is (equal '(("domain" . "starintel") ("team" . "enrichment"))
               (getf portable :metadata)))
    (is (search "\"serviceUri\":\"star://starintel:localhost:enrichment-worker\"" json))
    (is (search "\"metadata\":{\"domain\":\"starintel\",\"team\":\"enrichment\"}" json))
    (is (null (search "service_uri" json)))))

(test actor-compiler-path-does-not-load-prototype
  "The final actor compiler stays prototype-independent in-process."
  (is (null (find-package "STAR-LANG.PROTOTYPE")))
  (is (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))))

(test fresh-sbcl-process-compiles-actor-without-prototype
  "A fresh SBCL process loads starlang-compiler, compiles the fixture, and
never sees the prototype packages."
  (let* ((script
           (asdf:system-relative-pathname :starlang-compiler
                                          "tests/actor-compiler-proof.lisp"))
         (output
           (with-output-to-string (sink)
             (uiop:run-program
              (list (namestring sb-ext:*runtime-pathname*)
                    "--non-interactive"
                    "--load" (namestring script))
              :output sink
              :error-output sink
              :ignore-error-status nil))))
    (is (search "ACTOR-COMPILER-PROOF-OK" output))))

(defun run-tests ()
  ;; fiveam's run! returns T only when every check passed; surface failures
  ;; through the process exit code so ASDF/Nix/CI gates cannot pass silently.
  (unless (run! 'starlang-actor-compiler-tests)
    (error "starlang-compiler actor tests failed.")))
