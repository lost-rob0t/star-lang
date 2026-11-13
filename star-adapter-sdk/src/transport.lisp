;;;; Transport port contract for inbound and outbound adapter ports.
;;;;
;;;; Migrated from prototype/transport-port-prototype.lisp; the prototype
;;;; file is now a forwarding shell plus prototype-owned test doubles. A
;;;; transport port moves wire envelopes across a process boundary while
;;;; keeping delivery settlement (acknowledge, requeue, reject) explicit.
;;;; The contract is runtime-neutral data plus function operations only.

(in-package :staradaptersdk)

(define-condition transport-port-error (error)
  ((message :initarg :message :reader transport-port-error-message))
  (:report
   (lambda (condition stream)
     (write-string (transport-port-error-message condition) stream))))

(defun fail-transport (control &rest arguments)
  (error 'transport-port-error
         :message (apply #'format nil control arguments)))

(defstruct (transport-delivery (:constructor %make-transport-delivery))
  tag
  envelope
  (redelivery-count 0)
  (visible-at 0))

(defun make-transport-delivery (&key tag envelope (redelivery-count 0)
                                  (visible-at 0))
  "%MAKE-TRANSPORT-DELIVERY under its portable name. Delivery tags carry the
concrete transport's identity (string, integer, or keyword) and are opaque
to the port contract."
  (%make-transport-delivery
   :tag tag :envelope envelope
   :redelivery-count redelivery-count :visible-at visible-at))

(defstruct (transport-port (:constructor %make-transport-port))
  name
  receive-fn
  publish-fn
  ack-fn
  requeue-fn
  reject-fn
  now-fn)

(defun make-transport-port (&key name receive publish ack requeue reject now)
  "Build a transport port from explicit operations. Every operation must be
a function: the port is a contract, never a concrete socket or connection."
  (dolist (entry (list (cons "receive" receive)
                       (cons "publish" publish)
                       (cons "ack" ack)
                       (cons "requeue" requeue)
                       (cons "reject" reject)
                       (cons "now" now)))
    (unless (functionp (cdr entry))
      (fail-transport
       "Transport port ~A operation must be a function."
       (car entry))))
  (%make-transport-port
   :name (or name "transport")
   :receive-fn receive
   :publish-fn publish
   :ack-fn ack
   :requeue-fn requeue
   :reject-fn reject
   :now-fn now))

(defun transport-receive (port)
  (unless (transport-port-p port)
    (fail-transport "Expected a transport port, received ~S." port))
  (funcall (transport-port-receive-fn port)))

(defun transport-publish (port envelope)
  (unless (transport-port-p port)
    (fail-transport "Expected a transport port, received ~S." port))
  (funcall (transport-port-publish-fn port) envelope))

(defun transport-ack (port delivery)
  (funcall (transport-port-ack-fn port) delivery))

(defun transport-requeue (port delivery replacement-envelope delay-ms)
  (funcall (transport-port-requeue-fn port)
           delivery replacement-envelope delay-ms))

(defun transport-reject (port delivery reason)
  (funcall (transport-port-reject-fn port) delivery reason))

(defun transport-now (port)
  (funcall (transport-port-now-fn port)))
