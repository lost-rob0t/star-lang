(defsystem "star-process-port"
  :description "Generic exact-argv external-process lifecycle port"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "process"))))
  :in-order-to ((test-op (test-op "star-process-port-tests"))))
