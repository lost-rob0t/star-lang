(defsystem "star-sento-compat-integration-tests"
  :description "Real actor-system integration tests for star-sento-compat"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-sento-compat" "star-supervisor" "star-supervisor-tests"
               "sento" "fiveam" "bordeaux-threads")
  :serial t
  :components
  ((:module "integration"
    :components
    ((:file "packages")
     (:file "harness")
     (:file "real-actor-system-tests")
     (:file "supervisor-integration-tests"))))
  :perform (test-op (op c)
             (declare (ignore op c))
             (let ((integration-suite
                     (find-symbol "STARSENTOCOMPAT-INTEGRATION-TESTS"
                                  :starsentocompat-integration-tests))
                   (supervisor-suite
                     (find-symbol "STARSUPERVISOR-TESTS"
                                  :starsupervisor-tests)))
               (unless (and integration-suite
                            (symbol-call :fiveam '#:run! integration-suite))
                 (error "Real Sento actor-system integration tests failed."))
               (unless (and supervisor-suite
                            (symbol-call :fiveam '#:run! supervisor-suite))
                 (error "Final star-supervisor tests failed.")))))
