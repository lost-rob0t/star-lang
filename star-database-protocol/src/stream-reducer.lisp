(in-package :stardatabaseprotocol)

(defparameter +database-stream-page-type+
  "org.starintel/database@1/db-stream-page")

(defstruct (database-stream-state
            (:constructor make-database-stream-state
                (&key checkpoint (committed-items 0))))
  "Committed state for one portable database subscription."
  checkpoint
  (committed-items 0 :type integer))

(defun database-stream-checkpoint= (left right)
  "Compare opaque checkpoints only for exact equality."
  (cond
    ((and (null left) (null right)) t)
    ((and (stringp left) (stringp right)) (string= left right))
    (t nil)))

(defun database-stream-item-change-id (item)
  "Return the stable change id from a normalized stream item."
  (cond
    ((and (listp item)
          (or (null item) (keywordp (first item))))
     (or (getf item :change-id)
         (getf item :changeid)))
    ((listp item)
     (let ((entry
             (or (assoc "changeId" item :test #'equal)
                 (assoc :change-id item :test #'eq)
                 (assoc :changeid item :test #'eq))))
       (and entry (cdr entry))))
    (t nil)))

(defun valid-database-stream-checkpoint-p (checkpoint)
  (or (null checkpoint)
      (and (stringp checkpoint)
           (plusp (length checkpoint)))))

(defun validate-database-stream-page
    (state input-checkpoint output-checkpoint items
     &key (change-id-fn #'database-stream-item-change-id))
  "Validate ordering and replay facts before page effects are committed."
  (unless (database-stream-state-p state)
    (fail-database-contract :invalid-stream-state
                            "Expected DATABASE-STREAM-STATE."))
  (unless (valid-database-stream-checkpoint-p
           (database-stream-state-checkpoint state))
    (fail-database-contract :invalid-stream-checkpoint
                            "Committed stream checkpoint is invalid."))
  (unless (valid-database-stream-checkpoint-p input-checkpoint)
    (fail-database-contract :invalid-stream-checkpoint
                            "Input stream checkpoint is invalid."))
  (unless (database-stream-checkpoint=
           (database-stream-state-checkpoint state)
           input-checkpoint)
    (fail-database-contract :stale-stream-page
                            "Stream page input checkpoint is stale."))
  (unless (and (stringp output-checkpoint)
               (plusp (length output-checkpoint)))
    (fail-database-contract :invalid-stream-checkpoint
                            "Output checkpoint must be a non-empty string."))
  (unless (listp items)
    (fail-database-contract :invalid-stream-items
                            "Stream page items must be a list."))
  (when (and items
             (database-stream-checkpoint=
              input-checkpoint output-checkpoint))
    (fail-database-contract :nonadvancing-stream-page
                            "Non-empty stream page must advance checkpoint."))
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (item items)
      (let ((change-id (funcall change-id-fn item)))
        (unless (and (stringp change-id)
                     (plusp (length change-id)))
          (fail-database-contract :missing-stream-change-id
                                  "Every stream item requires changeId."))
        (when (gethash change-id seen)
          (fail-database-contract :duplicate-stream-change-id
                                  "Stream page repeats changeId ~A."
                                  change-id))
        (setf (gethash change-id seen) t))))
  t)

(defun reduce-database-stream-page
    (state input-checkpoint output-checkpoint items apply-fn
     &key (change-id-fn #'database-stream-item-change-id))
  "Apply a page and advance its checkpoint only after every item succeeds.

APPLY-FN returns :APPLIED, :DUPLICATE, or :RETRY. A retry returns STATE
unchanged; previously applied items may therefore be replayed and must be
recognized by their changeId."
  (check-type apply-fn function)
  (validate-database-stream-page
   state input-checkpoint output-checkpoint items
   :change-id-fn change-id-fn)
  (dolist (item items)
    (case (funcall apply-fn item)
      ((:applied :duplicate))
      (:retry
       (return-from reduce-database-stream-page
         (values state :retry)))
      (otherwise
       (fail-database-contract :invalid-stream-apply-outcome
                               "Unsupported stream apply outcome."))))
  (values
   (make-database-stream-state
    :checkpoint output-checkpoint
    :committed-items
    (+ (database-stream-state-committed-items state)
       (length items)))
   :committed))
