(in-package :starsentocompat-integration-tests)

(defun spawn-probe (port system)
  (runtime-spawn
   port system (unique-actor-name "probe")
   (lambda (message)
     (case message
       (:events (sento-reply (reverse act:*state*)))
       (otherwise (push (second message) act:*state*))))
   :state nil))

(defun spawn-echo (port system)
  (runtime-spawn
   port system (unique-actor-name "echo")
   (lambda (message)
     (unless (eq message :no-reply)
       (sento-reply message)))))

(defun spawn-coordinator (port system probe)
  (runtime-spawn
   port system (unique-actor-name "coordinator")
   (lambda (message)
     (if (and (consp message) (eq (first message) :forward))
         (runtime-tell port (second message) (third message) act:*self*)
         (runtime-tell port probe (list :observed message) act:*self*)))))

(defun spawn-counter (port system concurrent-entry-p)
  (let ((handler-active-p nil))
    (runtime-spawn
     port system (unique-actor-name "counter")
     (lambda (message)
       (case message
         (:increment
          (when handler-active-p
            (setf (car concurrent-entry-p) t))
          (setf handler-active-p t)
          (unwind-protect
               (progn
                 ;; Widen the receive body without relying on time for success.
                 (loop repeat 100 do (sqrt 144.0d0))
                 (incf act:*state*))
            (setf handler-active-p nil)))
         (:count
          (sento-reply
           (list :count act:*state*
                 :concurrent-entry (car concurrent-entry-p))))))
     :state 0)))

(test real-multi-actor-topology-and-lifecycle
  (with-real-actor-system (system)
    (let* ((port (make-sento-runtime-port))
           (probe (spawn-probe port system))
           (echo (spawn-echo port system))
           (coordinator (spawn-coordinator port system probe)))
      (is (eq echo (first (runtime-resolve port system (act-cell:name echo)))))
      (is (sento-actor-live-p system echo))

      ;; coordinator -> echo -> coordinator -> probe, entirely by actor messages.
      (runtime-tell port coordinator (list :forward echo '(:echo :mailbox)))
      (is (equal '((:echo :mailbox))
                 (await-probe-events port probe 1)))

      ;; Ordinary request/reply is asynchronous internally and awaited only here,
      ;; outside an actor receive handler.
      (is (equal '(:echo :ask)
                 (ask-result port echo '(:echo :ask)
                             :operation "echo ask/reply")))

      (runtime-stop port system echo :wait t)
      (is (not (sento-actor-live-p system echo)))
      (is (null (runtime-resolve port system (act-cell:name echo))))

      ;; Exercise shutdown through the runtime port; suppress fixture teardown
      ;; only after the blocking shutdown and leak assertion succeed.
      (runtime-shutdown port system :wait t)
      (is (null (sento-all-actors system)))
      (setf system nil))))

(test duplicate-name-and-ask-failure-are-mapped
  (with-real-actor-system (system)
    (let* ((port (make-sento-runtime-port))
           (name (unique-actor-name "duplicate"))
           (actor (runtime-spawn port system name #'identity)))
      (declare (ignore actor))
      (signals star-sento-compat-error
        (runtime-spawn port system name #'identity))
      (let ((silent (runtime-spawn port system
                                   (unique-actor-name "silent")
                                   (lambda (message)
                                     (declare (ignore message))))))
        (let ((future (runtime-ask port silent :no-reply :timeout 0.05)))
          (signals sento-ask-failure-error
            (await-future future :timeout 1.0
                         :operation "mapped ask timeout")))))))

(test one-actor-receive-path-is-serialized-under-concurrent-submission
  (with-real-actor-system (system)
    (let* ((port (make-sento-runtime-port))
           (concurrent-entry-p (list nil))
           (counter (spawn-counter port system concurrent-entry-p))
           (producer-count 4)
           (messages-per-producer 250)
           (threads
             (loop repeat producer-count
                   collect
                   (make-thread
                    (lambda ()
                      (loop repeat messages-per-producer
                            do (runtime-tell port counter :increment)))))))
      (mapc #'join-thread threads)
      (let ((result (ask-result port counter :count
                                :operation "serialized counter result")))
        (is (= (* producer-count messages-per-producer)
               (getf result :count)))
        (is (null (getf result :concurrent-entry)))))))

(test fixture-shuts-down-after-body-failure
  (let ((destroyed-p nil))
    (handler-case
        (with-real-actor-system (system)
          (runtime-spawn
           (make-sento-runtime-port)
           system
           (unique-actor-name "teardown")
           #'identity
           :destroy (lambda (actor)
                      (declare (ignore actor))
                      (setf destroyed-p t)))
          (error "deliberate fixture body failure"))
      (error () nil))
    (is destroyed-p)))
