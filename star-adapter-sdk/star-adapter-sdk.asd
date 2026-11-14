(defsystem "star-adapter-sdk"
  :description "SDK for building inbound and outbound adapter ports"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "transport"))))
  :in-order-to ((test-op (test-op "star-adapter-sdk-tests"))))
