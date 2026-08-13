(in-package #:star-lang.core-surface.prototype)

(export '(bind-rabbitmq-transport-port
          make-rabbitmq-driver
          parse-rabbitmq-endpoint
          rabbitmq-binding-exchange
          rabbitmq-binding-queue
          rabbitmq-binding-routing-key
          rabbitmq-driver-p
          rabbitmq-endpoint-p))

(define-condition rabbitmq-binding-error (transport-port-error) ())

(defstruct (rabbitmq-binding
            (:constructor %make-rabbitmq-binding))
  queue
  (exchange "")
  routing-key)

(defstruct (rabbitmq-driver
            (:constructor %make-rabbitmq-driver))
  consume-fn
  publish-fn
  ack-fn
  requeue-fn
  schedule-fn
  reject-fn
  now-fn)

(defun rabbitmq-endpoint-p (value)
  (and (stringp value)
       (> (length value) 9)
       (string= "rabbitmq:" value :end2 9)))

(defun rabbitmq-token-valid-p (value)
  (and (stringp value)
       (> (length value) 0)
       (notany (lambda (character)
                 (member character '(#\Space #\Tab #\Newline #\Return)))
               value)))

(defun parse-rabbitmq-endpoint (endpoint)
  (unless (rabbitmq-endpoint-p endpoint)
    (fail 'rabbitmq-binding-error
          "RabbitMQ endpoint must use rabbitmq:<queue>, received ~S."
          endpoint))
  (let ((queue (subseq endpoint 9)))
    (unless (rabbitmq-token-valid-p queue)
      (fail 'rabbitmq-binding-error
            "RabbitMQ endpoint queue must be a non-empty token."))
    (%make-rabbitmq-binding
     :queue queue
     :exchange ""
     :routing-key queue)))

(defun make-rabbitmq-driver (&key consume publish ack requeue schedule reject now)
  (dolist (entry (list (cons "consume" consume)
                       (cons "publish" publish)
                       (cons "ack" ack)
                       (cons "requeue" requeue)
                       (cons "schedule" schedule)
                       (cons "reject" reject)
                       (cons "now" now)))
    (unless (functionp (cdr entry))
      (fail 'rabbitmq-binding-error
            "RabbitMQ driver ~A operation must be a function."
            (car entry))))
  (%make-rabbitmq-driver
   :consume-fn consume
   :publish-fn publish
   :ack-fn ack
   :requeue-fn requeue
   :schedule-fn schedule
   :reject-fn reject
   :now-fn now))

(defun rabbitmq-confirmed-p (value operation)
  (unless value
    (fail 'rabbitmq-binding-error
          "RabbitMQ ~A was not confirmed by the broker driver."
          operation))
  value)

(defun rabbitmq-delivery-from-driver (binding driver)
  (multiple-value-bind (envelope delivery-tag redelivery-count)
      (funcall (rabbitmq-driver-consume-fn driver)
               (rabbitmq-binding-queue binding))
    (when envelope
      (unless delivery-tag
        (fail 'rabbitmq-binding-error
              "RabbitMQ consume returned an envelope without a delivery tag."))
      (unless (and (integerp redelivery-count) (>= redelivery-count 0))
        (fail 'rabbitmq-binding-error
              "RabbitMQ redelivery count must be a nonnegative integer."))
      (%make-transport-delivery
       :tag delivery-tag
       :envelope (copy-tree envelope)
       :redelivery-count redelivery-count
       :visible-at 0))))

(defun rabbitmq-publish-through-driver (binding driver envelope)
  (rabbitmq-confirmed-p
   (funcall (rabbitmq-driver-publish-fn driver)
            (rabbitmq-binding-exchange binding)
            (rabbitmq-binding-routing-key binding)
            (copy-tree envelope))
   "publish"))

(defun rabbitmq-ack-through-driver (driver delivery)
  (rabbitmq-confirmed-p
   (funcall (rabbitmq-driver-ack-fn driver)
            (transport-delivery-tag delivery))
   "acknowledgement"))

(defun rabbitmq-native-requeue-p (delivery replacement-envelope delay-ms)
  (and (zerop delay-ms)
       (equal replacement-envelope
              (transport-delivery-envelope delivery))))

(defun rabbitmq-requeue-through-driver
    (binding driver delivery replacement-envelope delay-ms)
  (unless (and (integerp delay-ms) (>= delay-ms 0))
    (fail 'rabbitmq-binding-error
          "RabbitMQ retry delay must be a nonnegative integer."))
  (if (rabbitmq-native-requeue-p delivery replacement-envelope delay-ms)
      (rabbitmq-confirmed-p
       (funcall (rabbitmq-driver-requeue-fn driver)
                (transport-delivery-tag delivery))
       "broker requeue")
      (progn
        ;; Application retries carry a new StarLang envelope/attempt. RabbitMQ
        ;; basic.nack cannot replace a message body or delay it, so the driver
        ;; must confirm the replacement publication before the original
        ;; delivery is acknowledged.
        (rabbitmq-confirmed-p
         (funcall (rabbitmq-driver-schedule-fn driver)
                  (rabbitmq-binding-exchange binding)
                  (rabbitmq-binding-routing-key binding)
                  (copy-tree replacement-envelope)
                  delay-ms)
         "scheduled retry publish")
        (rabbitmq-ack-through-driver driver delivery))))

(defun rabbitmq-reject-through-driver (driver delivery reason)
  (rabbitmq-confirmed-p
   (funcall (rabbitmq-driver-reject-fn driver)
            (transport-delivery-tag delivery)
            reason)
   "rejection"))

(defun bind-rabbitmq-transport-port (driver endpoint)
  (unless (rabbitmq-driver-p driver)
    (fail 'rabbitmq-binding-error
          "RabbitMQ transport binding requires a RabbitMQ driver."))
  (let ((binding (parse-rabbitmq-endpoint endpoint)))
    (make-transport-port
     :name (format nil "rabbitmq:~A" (rabbitmq-binding-queue binding))
     :receive (lambda ()
                (rabbitmq-delivery-from-driver binding driver))
     :publish (lambda (envelope)
                (rabbitmq-publish-through-driver binding driver envelope))
     :ack (lambda (delivery)
            (rabbitmq-ack-through-driver driver delivery))
     :requeue (lambda (delivery replacement-envelope delay-ms)
                (rabbitmq-requeue-through-driver
                 binding driver delivery replacement-envelope delay-ms))
     :reject (lambda (delivery reason)
               (rabbitmq-reject-through-driver driver delivery reason))
     :now (lambda ()
            (funcall (rabbitmq-driver-now-fn driver))))))
