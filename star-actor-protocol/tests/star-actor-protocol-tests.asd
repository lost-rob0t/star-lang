(defsystem "star-actor-protocol-tests"
  :description "Unit tests for star-actor-protocol"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-actor-protocol")
  :serial t
  :components
  ((:file "star-actor-protocol-tests")
   (:file "portable-wire-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :staractorprotocol-tests :run-tests)
    (uiop:symbol-call :staractorprotocol-wire-tests :run-tests)))
