(defsystem "star-sento-compat"
  :description "Compatibility shim for the Sento / CL-GServer actor model"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.0.0"
  :depends-on ()
  :components
  ((:module "src"
    :components
    ((:file "packages"))))
  :in-order-to ((test-op (test-op "star-sento-compat-tests"))))
