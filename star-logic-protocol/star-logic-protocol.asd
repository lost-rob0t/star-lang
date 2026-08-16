(defsystem "star-logic-protocol"
  :description "Portable StarLang logic backend protocol and deterministic selection"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "protocol"))))
  :in-order-to ((test-op (test-op "star-logic-protocol-tests"))))
