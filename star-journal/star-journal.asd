(defsystem "star-journal"
  :description "Durable write-ahead journal for recovery and replay"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-actor-protocol")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "journal"))))
  :in-order-to ((test-op (test-op "star-journal-tests"))))
