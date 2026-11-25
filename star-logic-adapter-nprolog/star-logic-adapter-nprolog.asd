(defsystem "star-logic-adapter-nprolog"
  :description "Final Common Lisp N-Prolog process worker adapter foundation"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.2.0"
  :depends-on ("star-logic-protocol"
               "star-process-port"
               "ironclad"
               "usocket"
               "babel")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "conditions")
     (:file "identity")
     (:file "bridge")
     (:file "worker")
     (:file "adapter")
     (:file "batch"))))
  :in-order-to ((test-op (test-op "star-logic-adapter-nprolog-tests"
                                  "star-logic-adapter-nprolog-integration-tests"))))
