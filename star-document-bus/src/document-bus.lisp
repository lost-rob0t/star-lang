(defpackage :star-document-bus
  (:use :cl)
  (:export #:bus-error #:bus-error-code #:make-delivery-observation
           #:observe-delivery #:delivery-commit-knowledge #:delivery-settle-p
           #:delivery-retry-action #:make-change-observer #:observe-change
           #:acknowledge-change #:observer-checkpoint #:close-observer))
(in-package :star-document-bus)
(define-condition bus-error (error)
  ((code :initarg :code :reader bus-error-code)))
(defun fail (code) (error 'bus-error :code code))

(defstruct (delivery-observation (:constructor %delivery-observation))
  command (knowledge :not-established) accepted dispatched receipt published)
(defun make-delivery-observation (command)
  "Observe trusted evidence; this object is NOT a durable inbox or outcome store."
  (setf command (staractorprotocol:snapshot-portable-wire-value command))
  (staractorprotocol:validate-lifecycle-envelope command :validate-payload nil)
  (unless (eq :command (getf command :kind)) (fail :invalid-argument))
  (%delivery-observation :command command))
(defun delivery-commit-knowledge (delivery)
  (delivery-observation-knowledge delivery))
(defun delivery-settle-p (delivery)
  "Transport settlement eligibility requires durable acceptance or a known outcome."
  (or (delivery-observation-accepted delivery)
      (member (delivery-commit-knowledge delivery) '(:committed :not-executed))))
(defun delivery-retry-action (delivery)
  (case (delivery-commit-knowledge delivery)
    (:committed :replay-receipt)
    (:unknown :reconcile-original-key)
    (otherwise :retry-original-key)))
(defun receipt-value-equal-p (left right)
  "Compare owned portable receipt values without folding case or vector identity."
  (cond
    ((and (staractorprotocol:portable-json-number-p left)
          (staractorprotocol:portable-json-number-p right))
     (string= (staractorprotocol:portable-json-number-lexeme left)
              (staractorprotocol:portable-json-number-lexeme right)))
    ((and (stringp left) (stringp right)) (string= left right))
    ((and (consp left) (consp right))
     ;; Snapshot bounds nesting, but proper-list cardinality can be large.
     (loop while (and (consp left) (consp right))
           do (unless (receipt-value-equal-p (car left) (car right))
                (return-from receipt-value-equal-p nil))
              (setf left (cdr left) right (cdr right))
           finally (return (receipt-value-equal-p left right))))
    ((and (vectorp left) (not (stringp left))
          (vectorp right) (not (stringp right)))
     (and (= (length left) (length right))
          (every #'receipt-value-equal-p left right)))
    (t (eql left right))))

(defun observe-delivery (delivery evidence &key receipt)
  "Evidence comes from the trusted service adapter, never untrusted wire flags.
NOT-EXECUTED means an authoritative rejection, not a timeout or broker NACK."
  (case evidence
    ((:broker-confirmed :broker-acked) nil)
    (:dispatched (setf (delivery-observation-dispatched delivery) t))
    (:durably-accepted
     (when (eq :not-executed (delivery-commit-knowledge delivery))
       (fail :conflicting-evidence))
     (setf (delivery-observation-accepted delivery) t))
    (:disconnected
     (unless (member (delivery-commit-knowledge delivery) '(:committed :not-executed))
       ;; A send can reach its peer even without local send-completion evidence.
       (setf (delivery-observation-knowledge delivery) :unknown)))
    (:not-executed
     (when (eq :committed (delivery-commit-knowledge delivery))
       (fail :conflicting-evidence))
     (setf (delivery-observation-knowledge delivery) :not-executed))
    (:committed
     (unless receipt (fail :receipt-required))
     (setf receipt (staractorprotocol:snapshot-portable-wire-value receipt))
     (when (or (eq :not-executed (delivery-commit-knowledge delivery))
               (and (delivery-observation-receipt delivery)
                    (not (receipt-value-equal-p receipt (delivery-observation-receipt delivery)))))
       (fail :conflicting-evidence))
     (setf (delivery-observation-knowledge delivery) :committed
           (delivery-observation-receipt delivery) receipt))
    (:published
     (unless (eq :committed (delivery-commit-knowledge delivery)) (fail :commit-required))
     (setf (delivery-observation-published delivery) t))
    (otherwise (fail :invalid-argument)))
  delivery)

(defstruct (change-observer (:constructor %change-observer))
  scope credit retention checkpoint closed
  (pending nil) (seen nil) (positions nil))
(defun token-p (value) (and (stringp value) (< 0 (length value) 4097)))
(defun make-change-observer (&key scope credit retention)
  "Bounded local delivery observer; opaque tokens must be issued by the service.
SCOPE is a trusted authorization visibility identity, not caller-supplied authority."
  (unless (and (token-p scope) (integerp credit) (<= 1 credit 65536)
               (integerp retention) (<= credit retention 65536))
    (fail :invalid-argument))
  (%change-observer :scope (copy-seq scope) :credit credit :retention retention))
(defun check-observer (observer scope)
  (unless (equal scope (change-observer-scope observer)) (fail :permission-denied))
  (when (change-observer-closed observer) (fail :closed)))
(defun observer-checkpoint (observer)
  (let ((value (change-observer-checkpoint observer))) (and value (copy-seq value))))
(defun observe-change (observer scope event-id partition position checkpoint)
  "Validate local delivery order/credit. Positions are adapter-normalized integers,
not public cursor tokens. Checkpoint is an opaque service-issued partition vector.
The service must authenticate and authorize EACH call before invoking this helper."
  (check-observer observer scope)
  (unless (and (every #'token-p (list event-id partition checkpoint))
               (integerp position) (plusp position))
    (fail :invalid-argument))
  (let* ((entry (list (copy-seq event-id) (copy-seq partition) position (copy-seq checkpoint)))
         (known (assoc event-id (change-observer-seen observer) :test #'equal))
         (last (assoc partition (change-observer-positions observer) :test #'equal)))
    (when known
      (unless (equal (subseq entry 0 3) (subseq known 0 3)) (fail :event-conflict))
      (return-from observe-change :duplicate))
    (when (and last (<= position (cdr last))) (fail :history-lost))
    (when (>= (length (change-observer-pending observer)) (change-observer-credit observer))
      (fail :slow-consumer))
    ;; Bound partition bookkeeping too: a hostile stream cannot grow it forever.
    (when (and (not last) (>= (length (change-observer-positions observer))
                              (change-observer-retention observer)))
      (fail :budget-exceeded))
    (if last (setf (cdr last) position)
        (push (cons (copy-seq partition) position) (change-observer-positions observer)))
    (setf (change-observer-pending observer)
          (append (change-observer-pending observer) (list entry))
          (change-observer-seen observer)
          (append (change-observer-seen observer) (list entry)))
    (when (> (length (change-observer-seen observer)) (change-observer-retention observer))
      (pop (change-observer-seen observer)))
    :deliver))
(defun acknowledge-change (observer scope event-id)
  "Advance only the contiguous application-processed prefix, never broker ACKs."
  (check-observer observer scope)
  (unless (and (token-p event-id) (change-observer-pending observer)
               (equal event-id (caar (change-observer-pending observer))))
    (fail :checkpoint-order))
  (let ((entry (pop (change-observer-pending observer))))
    (setf (change-observer-checkpoint observer) (fourth entry))
    (observer-checkpoint observer)))
(defun close-observer (observer)
  "Close only this observer. Does not cancel a Target or another subscriber."
  (setf (change-observer-closed observer) t
        (change-observer-pending observer) nil
        (change-observer-seen observer) nil
        (change-observer-positions observer) nil)
  (observer-checkpoint observer))
