(defsystem "star-document-bus"
  :description "Transport-neutral document bus evidence and bounded observer guards"
  :license "AGPL-3.0-only"
  :depends-on ("star-actor-protocol")
  :serial t
  :components ((:file "src/document-bus"))
  :in-order-to ((test-op (test-op "star-document-bus/tests"))))

(defsystem "star-document-bus/tests"
  :depends-on ("star-document-bus")
  :components ((:file "tests/document-bus-tests"))
  :perform (test-op (o c)
             (declare (ignore o c))
             (uiop:symbol-call :star-document-bus-tests :run-tests)))
