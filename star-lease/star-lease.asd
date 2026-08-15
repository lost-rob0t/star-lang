(defsystem "star-lease"
  :description "Time-bound leases for actors and resources"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "heartbeat-lease"))))
  :in-order-to ((test-op (test-op "star-lease-tests"))))
