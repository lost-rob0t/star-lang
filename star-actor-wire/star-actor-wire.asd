(asdf:defsystem "star-actor-wire"
  :description "Shared bounded lifecycle JSON codec and Rabbit/ZMQ binding projection"
  :license "AGPL-3.0-only"
  :depends-on ("star-actor-protocol" "star-canonical-json" "babel" "yason")
  :serial t
  :components ((:file "src/wire") (:file "src/binding"))
  :in-order-to ((asdf:test-op (asdf:test-op "star-actor-wire/tests"))))

(asdf:defsystem "star-actor-wire/tests"
  :depends-on ("star-actor-wire")
  :serial t
  :components ((:file "tests/binding") (:file "tests/exact-json"))
  :perform (asdf:test-op (op component)
             (declare (ignore op component))
             (uiop:symbol-call :star-actor-wire-tests :run-tests)))
