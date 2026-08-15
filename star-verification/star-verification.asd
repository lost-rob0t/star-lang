(defsystem "star-verification"
  :description "Immutable verification certificate and claim vocabulary"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "certificate"))))
  :in-order-to ((test-op (test-op "star-verification-tests"))))
