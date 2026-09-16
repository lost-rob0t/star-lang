(defsystem "star-supervisor"
  :description "Review prototype: bounded one-for-one supervision on the final runtime"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.0.0"
  :depends-on ("starlang-runtime")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "supervisor"))))
  :in-order-to ((test-op (test-op "star-supervisor-tests"))))
