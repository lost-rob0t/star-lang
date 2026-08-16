(defsystem "star-logic-testing"
  :description "Engine-free fake backend for StarLang logic conformance tests"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-logic-protocol")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "fake-backend")))))
