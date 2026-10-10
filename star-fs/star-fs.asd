(defsystem "star-fs"
  :description "Provider-neutral StarLang unified filesystem and map/reduce execution contract"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("babel" "starlang-runtime")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "map-reduce"))))
  :in-order-to ((test-op (test-op "star-fs-tests"))))
