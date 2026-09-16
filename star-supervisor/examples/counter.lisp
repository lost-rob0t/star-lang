;; From the repository root, with CL_SOURCE_REGISTRY="$PWD//:":
;; sbcl --script star-supervisor/examples/counter.lisp
(require :asdf)
(asdf:load-system "star-supervisor")

(let ((definition
        (starlangruntime:make-native-actor-definition
         "counter"
         (lambda (message count runtime)
           (declare (ignore runtime))
           (ecase message
             (:increment (values (1+ count) (1+ count)))
             (:crash (error "demonstration crash"))))
         :initial-state 0 :restart-policy :permanent :mailbox-capacity 8)))
  (starsupervisor:with-supervisor
      (root (starsupervisor:make-supervisor-spec
             "counter-service" (list definition)
             :strategy :one-for-one :max-restarts 3 :period-ms 10000))
    (let ((old-reference (starsupervisor:child-reference root "counter")))
      (starsupervisor:supervisor-tell root old-reference :increment)
      (starsupervisor:run-supervisor root)
      (starsupervisor:supervisor-tell root old-reference :crash)
      (starsupervisor:run-supervisor root)
      (handler-case
          (progn
            (starsupervisor:supervisor-tell root old-reference :increment)
            (error "BUG: a stale reference was accepted"))
        (starlangruntime:actor-stale-reference-error ()
          (format t "Old generation rejected.~%")))
      (starsupervisor:supervisor-tell root
        (starsupervisor:child-reference root "counter") :increment)
      (starsupervisor:run-supervisor root)
      (let ((actor (starlangruntime:find-actor (starsupervisor:supervisor-runtime root) "counter")))
        (assert (= 1 (starlangruntime:actor-instance-generation actor)))
        (assert (= 2 (starlangruntime:actor-instance-data actor))))
      (format t "~S~%" (starsupervisor:supervisor-snapshot root))
      (assert (eq :drained (starsupervisor:drain-supervisor root))))))
