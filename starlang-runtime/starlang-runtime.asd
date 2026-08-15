(defsystem "starlang-runtime"
  :description "The durable actor runtime that executes compiled StarLang"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.3.0"
  :depends-on ("star-actor-protocol" "star-mailbox")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "runtime")
     (:file "wire-dispatcher")
     (:file "runtime-directory"))))
  :in-order-to ((test-op (test-op "starlang-runtime-tests"))))
