(defsystem "starlang-cli"
  :description "First-class final-system starlang command-line interface"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-actor-protocol" "starlang-compiler" "starlang-runtime"
               "star-canonical-json" "ironclad")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "cli"))))
  :in-order-to ((test-op (test-op "starlang-cli-tests"))))
