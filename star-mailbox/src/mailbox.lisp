(in-package :starmailbox)

(define-condition star-mailbox-error (error)
  ((message :initarg :message :reader star-mailbox-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-mailbox-error-message condition) stream))))

(define-condition invalid-mailbox-capacity-error (star-mailbox-error) ())

(defun fail-mailbox (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defstruct (mailbox-delivery
            (:constructor make-mailbox-delivery
                (status depth capacity)))
  (status :accepted :type keyword)
  (depth 0 :type (integer 0 *))
  (capacity 1 :type (integer 1 *)))

(defstruct (mailbox (:constructor %make-mailbox (capacity)))
  (capacity 1 :type (integer 1 *))
  (front '() :type list)
  (rear '() :type list)
  (depth 0 :type (integer 0 *))
  (closed-p nil :type boolean))

(defun make-mailbox (capacity)
  (unless (and (integerp capacity) (> capacity 0))
    (fail-mailbox
     'invalid-mailbox-capacity-error
     "Mailbox capacity must be a positive integer, received ~S."
     capacity))
  (%make-mailbox capacity))

(defun mailbox-empty-p (mailbox)
  (zerop (mailbox-depth mailbox)))

(defun mailbox-full-p (mailbox)
  (>= (mailbox-depth mailbox) (mailbox-capacity mailbox)))

(defun mailbox-delivery-accepted-p (delivery)
  (and (mailbox-delivery-p delivery)
       (eq :accepted (mailbox-delivery-status delivery))))

(defun mailbox-offer (mailbox message)
  "Offer MESSAGE without executing a consumer. Returns a typed delivery result."
  (cond
    ((mailbox-closed-p mailbox)
     (make-mailbox-delivery
      :closed (mailbox-depth mailbox) (mailbox-capacity mailbox)))
    ((mailbox-full-p mailbox)
     (make-mailbox-delivery
      :full (mailbox-depth mailbox) (mailbox-capacity mailbox)))
    (t
     (push message (mailbox-rear mailbox))
     (incf (mailbox-depth mailbox))
     (make-mailbox-delivery
      :accepted (mailbox-depth mailbox) (mailbox-capacity mailbox)))))

(defun ensure-mailbox-front (mailbox)
  (when (and (null (mailbox-front mailbox))
             (mailbox-rear mailbox))
    (setf (mailbox-front mailbox) (nreverse (mailbox-rear mailbox))
          (mailbox-rear mailbox) '())))

(defun mailbox-poll (mailbox)
  "Remove the oldest queued message. The caller is the single mailbox consumer."
  (if (mailbox-empty-p mailbox)
      (values nil nil)
      (progn
        (ensure-mailbox-front mailbox)
        (let ((message (pop (mailbox-front mailbox))))
          (decf (mailbox-depth mailbox))
          (values message t)))))

(defun mailbox-snapshot (mailbox)
  "Return queued messages in FIFO order without mutating the mailbox."
  (append (copy-list (mailbox-front mailbox))
          (nreverse (copy-list (mailbox-rear mailbox)))))

(defun clear-mailbox (mailbox)
  (setf (mailbox-front mailbox) '()
        (mailbox-rear mailbox) '()
        (mailbox-depth mailbox) 0)
  mailbox)

(defun close-mailbox (mailbox &key (discard-p nil))
  (setf (mailbox-closed-p mailbox) t)
  (when discard-p
    (clear-mailbox mailbox))
  mailbox)