(defsystem "star-logic-adapter-swi"
  :description "Final Common Lisp SWI-Prolog MQI worker adapter foundation"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-logic-protocol"
               "star-process-port"
               "babel"
               "ironclad"
               "usocket"
               "yason")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "conditions")
     (:file "mqi-codec")
     (:file "identity")
     (:file "bootstrap")
     (:file "worker")
     (:file "adapter"))))
  :in-order-to ((test-op (test-op "star-logic-adapter-swi-tests"
                                  "star-logic-adapter-swi-integration-tests"))))
