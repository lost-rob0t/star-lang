(defsystem "star-sento-compat-integration-tests"
  :description "Real actor-system integration tests for star-sento-compat"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-sento-compat" "sento" "fiveam" "bordeaux-threads")
  :serial t
  :components
  ((:module "integration"
    :components
    ((:file "packages")
     (:file "harness")
     (:file "real-actor-system-tests"))))
  :perform (test-op (op c)
             (declare (ignore op c))
             (unless (symbol-call :fiveam '#:run!
                                  'starsentocompat-integration-tests)
               (error "Real Sento actor-system integration tests failed."))))

