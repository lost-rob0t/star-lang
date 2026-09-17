(defsystem "starlang-compiler"
  :description "The StarLang parser, IR, and compiler"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-actor-protocol" "star-logic-ir" "star-logic-protocol")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "core-surface")
     (:file "macro-expander")
     (:file "actor-ir")
     (:file "actor-manifest")
     (:file "actor-source")
     (:file "resolver-effects")
     (:file "lifecycle-bindings")
     (:file "object-bindings-core")
     (:file "object-bindings-web")
     (:file "object-bindings-lisp")
     (:file "object-bindings-jvm")
     (:file "object-bindings-native")
     (:file "object-bindings-api")
     (:file "logic-policy")
     (:file "public-surface"))))
  :in-order-to ((test-op (test-op "starlang-compiler-tests"))))