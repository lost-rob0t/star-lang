(defsystem "starlang-runtime"
  :description "The durable actor runtime that executes compiled StarLang"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :version "0.0.0"
  :depends-on ()
  :components
  ((:module "src"
    :components
    ((:file "packages"))))
  :in-order-to ((test-op (test-op "starlang-runtime-tests"))))
