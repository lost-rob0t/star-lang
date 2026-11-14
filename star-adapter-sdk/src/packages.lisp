(defpackage :staradaptersdk
  (:use :cl)
  (:nicknames :star-adapter-sdk)
  (:export
   #:transport-port-error
   #:transport-port
   #:transport-port-p
   #:transport-port-name
   #:make-transport-port
   #:transport-receive
   #:transport-publish
   #:transport-ack
   #:transport-requeue
   #:transport-reject
   #:transport-now
   #:transport-delivery
   #:transport-delivery-p
   #:transport-delivery-tag
   #:transport-delivery-envelope
   #:transport-delivery-redelivery-count
   #:make-transport-delivery))
