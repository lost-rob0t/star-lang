(defsystem "star-supervisor-tests"
  :description "Real final-runtime tests for the supervisor review prototype"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-supervisor" "fiveam")
  :components ((:file "star-supervisor-tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             ;; RUN! prints failures but returns NIL; ASDF must fail too.
             (unless (symbol-call :fiveam :run!
                                  (find-symbol "SUPERVISOR-SUITE" :starsupervisor-tests))
               (error "Supervisor suite failed."))))
