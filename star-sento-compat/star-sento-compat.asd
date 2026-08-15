(defsystem "star-sento-compat"
  :description "Narrow StarLang actor compatibility API over Sento/cl-gserver"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.2.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "runtime-port")
     (:file "sento-adapter"))))
  :in-order-to ((test-op (test-op "star-sento-compat-tests"))))