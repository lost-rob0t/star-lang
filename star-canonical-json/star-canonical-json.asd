(defsystem "star-canonical-json"
  :description "Canonical JSON serialization for deterministic interchange"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "canonical-json"))))
  :in-order-to ((test-op (test-op "star-canonical-json-tests"))))
