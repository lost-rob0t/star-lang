(asdf:defsystem "star-lang"
  :description "Side-effect-free aggregate system for the final StarLang compiler and runtime"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("starlang-compiler"
               "starlang-runtime")
  :components ()
  :in-order-to ((test-op (test-op "starlang-compiler-tests")
                         (test-op "starlang-runtime-tests")
                         (test-op "star-logic-protocol-tests")
                         (test-op "star-logic-ir-tests"))))
