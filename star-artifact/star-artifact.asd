(defsystem "star-artifact"
  :description "Artifact storage, canonical JSON file output, and provenance attachment"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-canonical-json"
               "starlang-runtime"
               "uiop")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "json-file-output"))))
  :in-order-to ((test-op (test-op "star-artifact-tests"))))
