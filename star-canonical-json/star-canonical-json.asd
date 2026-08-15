(defsystem "star-canonical-json"
  :description "Canonical JSON serialization for deterministic interchange"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.2.0"
  :depends-on ("star-actor-protocol")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "canonical-json")
     (:file "starlang-wire-json"))))
  :in-order-to ((test-op (test-op "star-canonical-json-tests"))))
