(defsystem "star-http-port"
  :description "Backend-neutral synchronous HTTP request/response port"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "http-port"))))
  :in-order-to ((test-op (test-op "star-http-port-tests"))))
