(defsystem "star-supervisor-tests"
  :description "Final one-for-one supervision semantics tests"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-supervisor" "starlang-runtime" "star-actor-protocol" "fiveam")
  :components
  ((:file "star-supervisor-tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (let ((suite (find-symbol "STARSUPERVISOR-TESTS"
                                       :starsupervisor-tests)))
               (unless (and suite (symbol-call :fiveam '#:run! suite))
                 (error "Final star-supervisor tests failed.")))))
