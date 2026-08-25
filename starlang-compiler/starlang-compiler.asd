(defsystem "starlang-compiler"
  :description "The StarLang parser, IR, and compiler"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.0.0"
  :depends-on ("star-logic-ir" "star-logic-protocol")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "resolver-effects")
     (:file "logic-policy"))))
  :in-order-to ((test-op (test-op "starlang-compiler-tests"))))
