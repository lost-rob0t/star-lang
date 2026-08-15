(defpackage :starmailbox-tests
  (:use :cl :fiveam)
  (:import-from :starmailbox
                #:invalid-mailbox-capacity-error
                #:make-mailbox
                #:mailbox-capacity
                #:mailbox-depth
                #:mailbox-closed-p
                #:mailbox-empty-p
                #:mailbox-full-p
                #:mailbox-offer
                #:mailbox-poll
                #:mailbox-snapshot
                #:close-mailbox
                #:mailbox-delivery-status)
  (:export))

(in-package :starmailbox-tests)

(def-suite starmailbox-tests
  :description "Bounded FIFO StarLang mailbox semantics.")

(in-suite starmailbox-tests)

(test capacity-must-be-positive
  (signals invalid-mailbox-capacity-error (make-mailbox 0))
  (signals invalid-mailbox-capacity-error (make-mailbox -1)))

(test offer-is-bounded-and-does-not-consume
  (let ((mailbox (make-mailbox 2)))
    (is (= 2 (mailbox-capacity mailbox)))
    (is (eq :accepted
            (mailbox-delivery-status (mailbox-offer mailbox :first))))
    (is (eq :accepted
            (mailbox-delivery-status (mailbox-offer mailbox :second))))
    (is (= 2 (mailbox-depth mailbox)))
    (is (mailbox-full-p mailbox))
    (is (eq :full
            (mailbox-delivery-status (mailbox-offer mailbox :third))))
    (is (equal '(:first :second) (mailbox-snapshot mailbox)))
    (is (= 2 (mailbox-depth mailbox)))))

(test poll-is-fifo
  (let ((mailbox (make-mailbox 3)))
    (dolist (message '(:first :second :third))
      (mailbox-offer mailbox message))
    (multiple-value-bind (message present-p) (mailbox-poll mailbox)
      (is present-p)
      (is (eq :first message)))
    (multiple-value-bind (message present-p) (mailbox-poll mailbox)
      (is present-p)
      (is (eq :second message)))
    (multiple-value-bind (message present-p) (mailbox-poll mailbox)
      (is present-p)
      (is (eq :third message)))
    (is (mailbox-empty-p mailbox))))

(test close-rejects-new-messages
  (let ((mailbox (make-mailbox 2)))
    (mailbox-offer mailbox :queued)
    (close-mailbox mailbox :discard-p t)
    (is (mailbox-closed-p mailbox))
    (is (mailbox-empty-p mailbox))
    (is (eq :closed
            (mailbox-delivery-status (mailbox-offer mailbox :late))))))