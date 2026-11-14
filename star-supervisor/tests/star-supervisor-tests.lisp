(defpackage :starsupervisor-tests
  (:use :cl :fiveam))
(in-package :starsupervisor-tests)

(def-suite supervisor-suite
  :description "Deterministic final runtime + real mailboxes; no fake actor operations.")
(in-suite supervisor-suite)

(defun worker (name &key (restart :permanent) (capacity 4) initial-state)
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (case message
       (:crash (error "intentional fixture failure"))
       (:normal (starlangruntime:stop-actor runtime name) (values :normal state))
       (otherwise (values :ok (1+ (or state 0))))))
   :restart-policy restart :mailbox-capacity capacity :initial-state initial-state))

(defun spec (&rest definitions)
  (starsupervisor:make-supervisor-spec "test-root" definitions))

(defun child-state (supervisor name)
  (find name (getf (starsupervisor:supervisor-snapshot supervisor) :children)
        :key (lambda (state) (getf state :name)) :test #'string=))

(defun crash (supervisor name)
  (starsupervisor:supervisor-tell supervisor name :crash)
  (starsupervisor:supervisor-step supervisor))

(test invalid-specifications
  (dolist (strategy '(:one-for-all :rest-for-one :unknown))
    (signals starsupervisor:invalid-supervisor-spec
      (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :strategy strategy)))
  (dolist (limit '(-1 1.5 "three"))
    (signals starsupervisor:invalid-supervisor-spec
      (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :max-restarts limit)))
  (signals starsupervisor:invalid-supervisor-spec
    (starsupervisor:make-supervisor-spec "root" nil))
  (signals starsupervisor:invalid-supervisor-spec
    (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :period-ms 0))
  (signals starsupervisor:invalid-supervisor-spec
    (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :backoff-ms -1))
  (signals starsupervisor:invalid-supervisor-spec (spec (worker "a") (worker "a")))
  (signals starsupervisor:invalid-supervisor-spec (spec (worker "a" :restart :unknown)))
  (signals starsupervisor:invalid-supervisor-spec
    (spec (starlangruntime:make-external-actor-definition "a" "star://local:localhost:a"))))

(test real-runtime-and-mailbox-bound
  (starsupervisor:with-supervisor (supervisor (spec (worker "a" :capacity 1)))
    (is (starlangruntime:runtime-p (starsupervisor:supervisor-runtime supervisor)))
    (is (= 1 (starlangruntime:runtime-actor-count (starsupervisor:supervisor-runtime supervisor))))
    (is (eq :accepted (starlangruntime:delivery-result-status
                      (starsupervisor:supervisor-tell supervisor "a" :ok))))
    (is (= 0 (starlangruntime:actor-instance-invocation-count
              (starlangruntime:find-actor (starsupervisor:supervisor-runtime supervisor) "a"))))
    (is (eq :mailbox-full (starlangruntime:delivery-result-status
                          (starsupervisor:supervisor-tell supervisor "a" :ok))))
    (starsupervisor:supervisor-step supervisor)
    (is (= 0 (getf (child-state supervisor "a") :mailbox-depth)))))

(test permanent-crash-generation-and-sibling-isolation
  (starsupervisor:with-supervisor (supervisor (spec (worker "a") (worker "b")))
    (let ((old-reference (starsupervisor:child-reference supervisor "a")))
      (starsupervisor:supervisor-tell supervisor "a" :crash)
      (starsupervisor:supervisor-tell supervisor "b" :ok)
      (multiple-value-bind (progress results) (starsupervisor:supervisor-step supervisor)
        (is (not (null progress)))
        (is (equal '(:failed :completed) (mapcar #'starlangruntime:dispatch-result-status results))))
      (is (= 1 (getf (child-state supervisor "a") :generation)))
      (is (= 1 (getf (child-state supervisor "a") :restarts)))
      (is (= 0 (getf (child-state supervisor "b") :generation)))
      (is (= 1 (starlangruntime:actor-instance-data
                (starlangruntime:find-actor (starsupervisor:supervisor-runtime supervisor) "b"))))
      (signals starlangruntime:actor-stale-reference-error
        (starsupervisor:supervisor-tell supervisor old-reference :ok))
      (is (eq :accepted (starlangruntime:delivery-result-status
                        (starsupervisor:supervisor-tell supervisor
                          (starsupervisor:child-reference supervisor "a") :ok)))))))

(test normal-exit-restart-matrix
  (dolist (policy '(:permanent :transient :temporary))
    (starsupervisor:with-supervisor (supervisor (spec (worker "a" :restart policy)))
      ;; The actor really stops itself while handling a mailbox message.
      (starsupervisor:supervisor-tell supervisor "a" :normal)
      (starsupervisor:supervisor-step supervisor)
      (is (eq :normal (getf (child-state supervisor "a") :last-exit)))
      (is (= (if (eq policy :permanent) 1 0)
             (getf (child-state supervisor "a") :restarts))))))

(test abnormal-exit-restart-matrix
  (dolist (policy '(:permanent :transient :temporary))
    (starsupervisor:with-supervisor (supervisor (spec (worker "a" :restart policy)))
      (crash supervisor "a")
      (is (eq :failure (getf (child-state supervisor "a") :last-exit)))
      (is (= (if (eq policy :temporary) 0 1)
             (getf (child-state supervisor "a") :restarts))))))

(test shared-restart-budget-and-terminal-shutdown
  (starsupervisor:with-supervisor
      (supervisor (starsupervisor:make-supervisor-spec "root" (list (worker "a") (worker "b"))
                                                    :max-restarts 2)
                  :clock (constantly 0))
    (crash supervisor "a")
    (crash supervisor "b")
    (crash supervisor "a")
    (is (eq :failed (starsupervisor:supervisor-status supervisor)))
    (is (eq :restart-intensity-exceeded
            (getf (starsupervisor:supervisor-snapshot supervisor) :reason)))
    (is (eq :stopped (starlangruntime:runtime-status (starsupervisor:supervisor-runtime supervisor))))
    (dolist (name '("a" "b"))
      (is (eq :stopped (getf (child-state supervisor name) :status)))
      (is (not (starlangruntime:actor-running-p
                (starlangruntime:find-actor (starsupervisor:supervisor-runtime supervisor) name))))
      (is (= 0 (getf (child-state supervisor name) :mailbox-depth))))
    (is (eq :failed (starsupervisor:stop-supervisor supervisor)))
    (signals starsupervisor:supervisor-stopped-error
      (starsupervisor:supervisor-tell supervisor "a" :ok))))

(test zero-restart-budget
  (starsupervisor:with-supervisor
      (supervisor (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :max-restarts 0))
    (crash supervisor "a")
    (is (eq :failed (starsupervisor:supervisor-status supervisor)))
    (is (= 0 (getf (child-state supervisor "a") :restarts)))))

(test half-open-window-boundary
  (let ((now 0))
    (starsupervisor:with-supervisor
        (supervisor (starsupervisor:make-supervisor-spec "root" (list (worker "a"))
                                                      :max-restarts 1 :period-ms 10)
                    :clock (lambda () now))
      (crash supervisor "a")
      (setf now 10)
      (crash supervisor "a")
      (is (eq :running (starsupervisor:supervisor-status supervisor)))
      (is (= 2 (getf (child-state supervisor "a") :restarts))))))

(test inside-window-still-counts
  (let ((now 0))
    (starsupervisor:with-supervisor
        (supervisor (starsupervisor:make-supervisor-spec "root" (list (worker "a"))
                                                      :max-restarts 1 :period-ms 10)
                    :clock (lambda () now))
      (crash supervisor "a")
      (setf now 9)
      (crash supervisor "a")
      (is (eq :failed (starsupervisor:supervisor-status supervisor))))))

(test backoff-is-a-deadline-not-a-sleep
  (let ((now 100))
    (starsupervisor:with-supervisor
        (supervisor (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :backoff-ms 5)
                    :clock (lambda () now))
      (crash supervisor "a")
      (is (= 105 (starsupervisor:next-restart-at supervisor)))
      (is (eq :waiting (starsupervisor:run-supervisor supervisor)))
      (setf now 104)
      (starsupervisor:supervisor-step supervisor)
      (is (= 0 (getf (child-state supervisor "a") :generation)))
      (setf now 105)
      (starsupervisor:supervisor-step supervisor)
      (is (= 1 (getf (child-state supervisor "a") :generation)))
      (is (null (starsupervisor:next-restart-at supervisor))))))

(test operator-stop-cancels-pending-restart
  (let ((now 0))
    (starsupervisor:with-supervisor
        (supervisor (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :backoff-ms 5)
                    :clock (lambda () now))
      (crash supervisor "a")
      (starsupervisor:stop-child supervisor "a")
      (setf now 20)
      (starsupervisor:run-supervisor supervisor)
      (is (= 0 (getf (child-state supervisor "a") :generation)))
      (is (eq :stopped (getf (child-state supervisor "a") :status))))))

(test restart-keeps-committed-state-and-discards-queued-work
  (starsupervisor:with-supervisor (supervisor (spec (worker "a")))
    (starsupervisor:supervisor-tell supervisor "a" :ok)
    (starsupervisor:supervisor-step supervisor)
    (starsupervisor:supervisor-tell supervisor "a" :crash)
    (starsupervisor:supervisor-tell supervisor "a" :ok)
    (starsupervisor:supervisor-step supervisor)
    (is (= 0 (getf (child-state supervisor "a") :mailbox-depth)))
    (is (= 1 (starlangruntime:actor-instance-data
              (starlangruntime:find-actor (starsupervisor:supervisor-runtime supervisor) "a"))))))

(test drain-handles-existing-work-without-restart
  (starsupervisor:with-supervisor (supervisor (spec (worker "a") (worker "b")))
    (starsupervisor:supervisor-tell supervisor "a" :crash)
    (starsupervisor:supervisor-tell supervisor "b" :ok)
    (is (eq :drained (starsupervisor:drain-supervisor supervisor)))
    (is (= 0 (getf (child-state supervisor "a") :restarts)))
    (is (= 1 (starlangruntime:actor-instance-data
              (starlangruntime:find-actor (starsupervisor:supervisor-runtime supervisor) "b"))))
    (signals starsupervisor:supervisor-stopped-error
      (starsupervisor:supervisor-tell supervisor "b" :ok))))

(test drain-fences-producer-and-cancels-backoff
  (let ((root nil))
    (starsupervisor:with-supervisor
        (supervisor
         (spec (starlangruntime:make-native-actor-definition
                "producer"
                (lambda (message state runtime)
                  (declare (ignore message state runtime))
                  (signals starsupervisor:supervisor-stopped-error
                    (starsupervisor:supervisor-tell root "producer" :again))
                  :ok))))
      (setf root supervisor)
      (starsupervisor:supervisor-tell supervisor "producer" :ok)
      (is (eq :drained (starsupervisor:drain-supervisor supervisor)))))
  (starsupervisor:with-supervisor
      (supervisor (starsupervisor:make-supervisor-spec "root" (list (worker "a")) :backoff-ms 5)
                  :clock (constantly 0))
    (crash supervisor "a")
    (is (eq :drained (starsupervisor:drain-supervisor supervisor)))
    (is (null (starsupervisor:next-restart-at supervisor)))))

(test drain-limit-stops-a-self-feeding-actor
  (starsupervisor:with-supervisor
      (supervisor
       (spec (starlangruntime:make-native-actor-definition
              "producer"
              (lambda (message state runtime)
                (declare (ignore state))
                ;; Raw intra-runtime sends remain possible; the drain cap matters.
                (starlangruntime:tell runtime "producer" message)
                :ok))))
    (starsupervisor:supervisor-tell supervisor "producer" :again)
    (is (eq :drain-limit (starsupervisor:drain-supervisor supervisor :max-steps 3)))
    (is (= 0 (getf (child-state supervisor "producer") :mailbox-depth)))
    (is (eq :stopped (starsupervisor:supervisor-status supervisor)))))

(test startup-failure-is-surfaced
  (let ((started nil))
    (signals error
      (starsupervisor:start-supervisor
       (spec (starlangruntime:make-native-actor-definition
              "first"
              (lambda (&rest arguments) (declare (ignore arguments)) :ok)
              :initial-state (lambda () (setf started t)))
             (starlangruntime:make-native-actor-definition
              "second"
              (lambda (&rest arguments) (declare (ignore arguments)) :ok)
              :initial-state (lambda () (error "startup failed"))))))
    (is (not (null started)))))

(test monotonic-clock-and-unwind-cleanup
  (let ((now 10) (captured nil))
    (signals starsupervisor:supervisor-clock-error
      (starsupervisor:with-supervisor (supervisor (spec (worker "a")) :clock (lambda () now))
        (setf captured supervisor now 9)
        (starsupervisor:supervisor-step supervisor)))
    (is (eq :stopped (starsupervisor:supervisor-status captured)))
    (is (eq :stopped (starlangruntime:runtime-status (starsupervisor:supervisor-runtime captured))))))

(test multiple-supervisors-and-defensive-snapshot
  (starsupervisor:with-supervisor (first (spec (worker "a")))
    (starsupervisor:with-supervisor (second (spec (worker "a")))
      (is (not (eq (starsupervisor:supervisor-runtime first) (starsupervisor:supervisor-runtime second))))
      (let ((snapshot (starsupervisor:supervisor-snapshot first)))
        (setf (char (getf snapshot :name) 0) #\X)
        (setf (char (getf (first (getf snapshot :children)) :name) 0) #\Z))
      (is (string= "test-root" (getf (starsupervisor:supervisor-snapshot first) :name)))
      (crash first "a")
      (is (= 0 (getf (child-state second "a") :generation)))
      (starsupervisor:stop-supervisor first)
      (is (eq :running (starsupervisor:supervisor-status second))))))

(test actual-actor-to-actor-mailbox-hop
  (starsupervisor:with-supervisor
      (supervisor
       (spec (starlangruntime:make-native-actor-definition
              "relay"
              (lambda (message state runtime)
                (declare (ignore state))
                (starlangruntime:tell runtime "sink" message)
                :forwarded))
             (worker "sink")))
    (starsupervisor:supervisor-tell supervisor "relay" :ok)
    (multiple-value-bind (progress results) (starsupervisor:supervisor-step supervisor)
      (is (not (null progress)))
      (is (= 2 (length results))))
    (is (= 1 (starlangruntime:actor-instance-data
              (starlangruntime:find-actor (starsupervisor:supervisor-runtime supervisor) "sink"))))))

(test exact-round-budget-completion-is-not-a-limit
  (starsupervisor:with-supervisor (supervisor (spec (worker "a")))
    (starsupervisor:supervisor-tell supervisor "a" :ok)
    (is (eq :idle (starsupervisor:run-supervisor supervisor :max-steps 1)))
    (starsupervisor:supervisor-tell supervisor "a" :ok)
    (is (eq :drained (starsupervisor:drain-supervisor supervisor :max-steps 1)))))
