(defsystem "star-actor-protocol"
  :description "Actor message and protocol definitions"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.4.0"
  :depends-on ()
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "service-uri")
     (:file "actor-reference")
     (:file "message-lifecycle")
     (:file "portable-wire"))))
  :in-order-to ((test-op (test-op "star-actor-protocol-tests"))))
