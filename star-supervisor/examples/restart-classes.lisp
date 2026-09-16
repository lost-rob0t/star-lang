(require :asdf)
(asdf:load-system "star-supervisor")

;; Every row runs a fresh real runtime and delivers a real mailbox message.
(dolist (policy '(:permanent :transient :temporary))
  (dolist (reason '(:normal :crash))
    (let ((definition
            (starlangruntime:make-native-actor-definition
             "worker"
             (lambda (message state runtime)
               (declare (ignore state))
               (ecase message
                 (:normal (starlangruntime:stop-actor runtime "worker") :normal)
                 (:crash (error "demonstration crash"))))
             :restart-policy policy)))
      (starsupervisor:with-supervisor
          (root (starsupervisor:make-supervisor-spec "restart-classes" (list definition)))
        (starsupervisor:supervisor-tell root "worker" reason)
        (starsupervisor:run-supervisor root)
        (let* ((child (first (getf (starsupervisor:supervisor-snapshot root) :children)))
               (expected (if (or (eq policy :permanent)
                                 (and (eq policy :transient) (eq reason :crash))) 1 0)))
          (assert (= expected (getf child :restarts)))
          (format t "~S + ~S -> ~S, restarts=~D~%"
                  policy reason (getf child :status) (getf child :restarts)))))))
