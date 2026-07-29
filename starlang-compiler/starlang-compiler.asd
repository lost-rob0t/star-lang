(defsystem "starlang-compiler"
  :description "The StarLang parser, IR, and compiler"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :version "0.0.0"
  :depends-on ()
  :components
  ((:module "src"
    :components
    ((:file "packages"))))
  :in-order-to ((test-op (test-op "starlang-compiler-tests"))))
