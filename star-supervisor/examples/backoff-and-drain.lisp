(require :asdf)
(asdf:load-system "star-supervisor")

;; The only simulated port is the clock. Actor construction, failure, delivery,
;; restart, generation advance and shutdown all use the real final runtime.
(let* ((now 1000)
       (definition (starlangruntime:make-native-actor-definition
                    "worker"
                    (lambda (message state runtime)
                      (declare (ignore state runtime))
                      (if (eq message :crash) (error "demonstration crash") :ok))
                    :restart-policy :permanent :mailbox-capacity 2)))
  (starsupervisor:with-supervisor
      (root (starsupervisor:make-supervisor-spec "backoff" (list definition)
                                                :max-restarts 2 :period-ms 10000 :backoff-ms 250)
            :clock (lambda () now))
    (starsupervisor:supervisor-tell root "worker" :crash)
    (assert (eq :waiting (starsupervisor:run-supervisor root)))
    (assert (= 1250 (starsupervisor:next-restart-at root)))
    (format t "Waiting for host tick at ~Dms; no sleeping worker.~%"
            (starsupervisor:next-restart-at root))
    (setf now 1250)
    (starsupervisor:run-supervisor root)
    (starsupervisor:supervisor-tell root "worker" :ok)
    (assert (eq :drained (starsupervisor:drain-supervisor root)))
    (assert (null (starsupervisor:next-restart-at root)))
    (format t "~S~%" (starsupervisor:supervisor-snapshot root))))
