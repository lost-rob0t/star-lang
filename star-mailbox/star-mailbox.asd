(defsystem "star-mailbox"
  :description "Per-actor bounded FIFO mailbox and single-message dispatch primitive"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "mailbox"))))
  :in-order-to ((test-op (test-op "star-mailbox-tests"))))