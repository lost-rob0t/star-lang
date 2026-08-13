(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "transport-port-prototype.lisp" *load-truename*))
(load (merge-pathnames "rabbitmq-transport-binding-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun rabbitmq-test-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun rabbitmq-test-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun rabbitmq-test-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun test-rabbitmq-endpoint-parsing ()
  (let ((binding (parse-rabbitmq-endpoint "rabbitmq:star.fec.ingest")))
    (rabbitmq-test-assert-equal
     "star.fec.ingest" (rabbitmq-binding-queue binding) "queue")
    (rabbitmq-test-assert-equal
     "" (rabbitmq-binding-exchange binding) "default exchange")
    (rabbitmq-test-assert-equal
     "star.fec.ingest" (rabbitmq-binding-routing-key binding) "routing key"))
  (dolist (endpoint '("amqp:star.fec.ingest" "rabbitmq:" "rabbitmq:bad queue"))
    (rabbitmq-test-assert-true
     (rabbitmq-test-signaled-p
      'rabbitmq-binding-error
      (lambda () (parse-rabbitmq-endpoint endpoint)))
     (format nil "reject endpoint ~S" endpoint))))

(defun make-recording-rabbitmq-driver (events inbound &key (publish-result t))
  (make-rabbitmq-driver
   :consume
   (lambda (queue)
     (setf (car events) (append (car events) (list (list :consume queue))))
     (let ((next (pop (car inbound))))
       (if next
           (values (getf next :envelope)
                   (getf next :tag)
                   (getf next :redelivery-count))
           (values nil nil nil))))
   :publish
   (lambda (exchange routing-key envelope)
     (setf (car events)
           (append (car events)
                   (list (list :publish exchange routing-key envelope))))
     publish-result)
   :ack
   (lambda (tag)
     (setf (car events) (append (car events) (list (list :ack tag))))
     t)
   :requeue
   (lambda (tag)
     (setf (car events) (append (car events) (list (list :requeue tag))))
     t)
   :schedule
   (lambda (exchange routing-key envelope delay-ms)
     (setf (car events)
           (append (car events)
                   (list (list :schedule exchange routing-key envelope delay-ms))))
     t)
   :reject
   (lambda (tag reason)
     (setf (car events)
           (append (car events) (list (list :reject tag reason))))
     t)
   :now (lambda () 1234)))

(defun test-rabbitmq-port-settlement-semantics ()
  (let* ((events (list '()))
         (command '(:kind :command :message-id "rmq-1" :attempt 1))
         (inbound
           (list (list (list :envelope command
                             :tag 42
                             :redelivery-count 1))))
         (driver (make-recording-rabbitmq-driver events inbound))
         (port (bind-rabbitmq-transport-port
                driver "rabbitmq:star.fec.ingest"))
         (delivery (transport-receive port)))
    (rabbitmq-test-assert-equal 42
                               (transport-delivery-tag delivery)
                               "delivery tag")
    (rabbitmq-test-assert-equal 1
                               (transport-delivery-redelivery-count delivery)
                               "redelivery count")
    (rabbitmq-test-assert-equal 1234 (transport-now port) "driver clock")

    (transport-publish port '(:kind :ack :message-id "ack-1"))
    (transport-ack port delivery)
    (rabbitmq-test-assert-equal
     '((:consume "star.fec.ingest")
       (:publish "" "star.fec.ingest" (:kind :ack :message-id "ack-1"))
       (:ack 42))
     (car events)
     "receive publish ack operations")))

(defun test-rabbitmq-native-requeue ()
  (let* ((events (list '()))
         (command '(:kind :command :message-id "rmq-native" :attempt 1))
         (inbound
           (list (list (list :envelope command
                             :tag 77
                             :redelivery-count 0))))
         (driver (make-recording-rabbitmq-driver events inbound))
         (port (bind-rabbitmq-transport-port driver "rabbitmq:q"))
         (delivery (transport-receive port)))
    (setf (car events) '())
    (transport-requeue port delivery command 0)
    (rabbitmq-test-assert-equal
     '((:requeue 77))
     (car events)
     "unchanged zero-delay delivery uses broker requeue")))

(defun test-rabbitmq-retry-republishes-before-ack ()
  (let* ((events (list '()))
         (command '(:kind :command :message-id "rmq-retry" :attempt 1))
         (replacement '(:kind :command :message-id "rmq-retry-2" :attempt 2))
         (inbound
           (list (list (list :envelope command
                             :tag 88
                             :redelivery-count 0))))
         (driver (make-recording-rabbitmq-driver events inbound))
         (port (bind-rabbitmq-transport-port driver "rabbitmq:q"))
         (delivery (transport-receive port)))
    (setf (car events) '())
    (transport-requeue port delivery replacement 2500)
    (rabbitmq-test-assert-equal
     '((:schedule "" "q"
                  (:kind :command :message-id "rmq-retry-2" :attempt 2)
                  2500)
       (:ack 88))
     (car events)
     "replacement retry is confirmed before original ack")))

(defun test-rabbitmq-reject ()
  (let* ((events (list '()))
         (command '(:kind :command :message-id "rmq-poison" :attempt 1))
         (inbound
           (list (list (list :envelope command
                             :tag 99
                             :redelivery-count 0))))
         (driver (make-recording-rabbitmq-driver events inbound))
         (port (bind-rabbitmq-transport-port driver "rabbitmq:q"))
         (delivery (transport-receive port)))
    (setf (car events) '())
    (transport-reject port delivery "bad envelope")
    (rabbitmq-test-assert-equal
     '((:reject 99 "bad envelope"))
     (car events)
     "poison delivery reject")))

(defun test-rabbitmq-publish-must-confirm ()
  (let* ((events (list '()))
         (inbound (list '()))
         (driver
           (make-recording-rabbitmq-driver
            events inbound :publish-result nil))
         (port (bind-rabbitmq-transport-port driver "rabbitmq:q")))
    (rabbitmq-test-assert-true
     (rabbitmq-test-signaled-p
      'rabbitmq-binding-error
      (lambda ()
        (transport-publish port '(:kind :ack :message-id "unconfirmed"))))
     "unconfirmed publish is a transport failure")))

(defun run-rabbitmq-transport-binding-tests ()
  (test-rabbitmq-endpoint-parsing)
  (test-rabbitmq-port-settlement-semantics)
  (test-rabbitmq-native-requeue)
  (test-rabbitmq-retry-republishes-before-ack)
  (test-rabbitmq-reject)
  (test-rabbitmq-publish-must-confirm)
  (format t "Star-Lang RabbitMQ transport binding tests passed.~%")
  t)

(unless (run-rabbitmq-transport-binding-tests)
  (error "Star-Lang RabbitMQ transport binding tests failed."))
