(defsystem "star-logic-ir"
  :description "Normalized StarLang logic-call IR and backend materialization plans"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-logic-protocol" "star-canonical-json")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "logic-ir")
     (:file "canonical-json"))))
  :in-order-to ((test-op (test-op "star-logic-ir-tests"))))
