(defpackage :starmailbox
  (:use :cl)
  (:nicknames :star-mailbox)
  (:export
   #:star-mailbox-error
   #:invalid-mailbox-capacity-error
   #:mailbox
   #:mailbox-p
   #:make-mailbox
   #:mailbox-capacity
   #:mailbox-depth
   #:mailbox-closed-p
   #:mailbox-empty-p
   #:mailbox-full-p
   #:mailbox-offer
   #:mailbox-poll
   #:mailbox-snapshot
   #:clear-mailbox
   #:close-mailbox
   #:mailbox-delivery
   #:mailbox-delivery-p
   #:mailbox-delivery-status
   #:mailbox-delivery-depth
   #:mailbox-delivery-capacity
   #:mailbox-delivery-accepted-p))