(in-package :starkb)

(defun memory-record-key (namespace id)
  (list namespace id))

(defun sorted-record-values (table predicate)
  (sort
   (loop for value being the hash-values of table
         when (funcall predicate value)
           collect value)
   #'string< :key #'kb-record-id))

(defun memory-field-equal-p (left right)
  (portable-kb-value-equal-p left right))

(defun make-memory-kb-store (&key (name "memory"))
  "Create the deterministic reference backend for the STAR-KB port.

The memory backend deliberately implements the same cascade and namespace rules
as persistent backends. It is suitable for unit tests and actor fixtures, not as
production durability."
  (let ((entries (make-hash-table :test #'equal))
        (relations (make-hash-table :test #'equal))
        (closed nil))
    (labels
        ((ensure-open ()
           (when closed
             (fail-kb 'kb-backend-error "Memory KB store is closed.")))
         (put-entry (entry)
           (ensure-open)
           (setf (gethash (memory-record-key (kb-record-namespace entry)
                                             (kb-record-id entry))
                          entries)
                 entry)
           entry)
         (fetch-entry (namespace id)
           (ensure-open)
           (gethash (memory-record-key namespace id) entries))
         (delete-entry (namespace id)
           (ensure-open)
           (let ((key (memory-record-key namespace id)))
             (when (gethash key entries)
               (let ((relation-keys nil))
                 (maphash
                  (lambda (relation-key relation)
                    (when (and (string= namespace (kb-record-namespace relation))
                               (or (string= id (kb-relation-source relation))
                                   (string= id (kb-relation-target relation))))
                      (push relation-key relation-keys)))
                  relations)
                 (dolist (relation-key relation-keys)
                   (remhash relation-key relations)))
               (remhash key entries)
               t)))
         (find-kind (namespace kind)
           (ensure-open)
           (sorted-record-values
            entries
            (lambda (entry)
              (and (string= namespace (kb-record-namespace entry))
                   (string= kind (kb-entry-kind entry))))))
         (find-dataset (namespace dataset)
           (ensure-open)
           (sorted-record-values
            entries
            (lambda (entry)
              (and (string= namespace (kb-record-namespace entry))
                   (let ((value (kb-record-dataset entry)))
                     (and value (string= dataset value)))))))
         (find-field (namespace path value)
           (ensure-open)
           (sorted-record-values
            entries
            (lambda (entry)
              (and (string= namespace (kb-record-namespace entry))
                   (let ((pair (assoc path (kb-entry-fields entry)
                                      :test #'string=)))
                     (and pair (memory-field-equal-p value (cdr pair))))))))
         (put-relation (relation)
           (ensure-open)
           (let* ((namespace (kb-record-namespace relation))
                  (source (kb-relation-source relation))
                  (target (kb-relation-target relation)))
             (unless (gethash (memory-record-key namespace source) entries)
               (fail-kb 'kb-contract-error
                        "KB relation source ~S is not an entry in namespace ~S."
                        source namespace))
             (unless (gethash (memory-record-key namespace target) entries)
               (fail-kb 'kb-contract-error
                        "KB relation target ~S is not an entry in namespace ~S."
                        target namespace))
             (setf (gethash (memory-record-key namespace
                                               (kb-record-id relation))
                            relations)
                   relation)
             relation))
         (fetch-relation (namespace id)
           (ensure-open)
           (gethash (memory-record-key namespace id) relations))
         (delete-relation (namespace id)
           (ensure-open)
           (remhash (memory-record-key namespace id) relations))
         (find-predicate (namespace predicate)
           (ensure-open)
           (sorted-record-values
            relations
            (lambda (relation)
              (and (string= namespace (kb-record-namespace relation))
                   (string= predicate (kb-relation-predicate relation))))))
         (neighbors (namespace id predicate incoming)
           (ensure-open)
           (let ((result nil))
             (dolist (relation
                      (sorted-record-values
                       relations
                       (lambda (relation)
                         (and
                          (string= namespace (kb-record-namespace relation))
                          (or (null predicate)
                              (string= predicate
                                       (kb-relation-predicate relation)))
                          (if incoming
                              (string= id (kb-relation-target relation))
                              (string= id (kb-relation-source relation)))))))
               (let ((neighbor-id (if incoming
                                      (kb-relation-source relation)
                                      (kb-relation-target relation))))
                 (let ((entry (gethash (memory-record-key namespace neighbor-id)
                                       entries)))
                   (when entry
                     (push entry result)))))
             (nreverse result)))
         (close-store ()
           (setf closed t)
           t))
      (make-kb-store
       name
       :put-entry #'put-entry
       :fetch-entry #'fetch-entry
       :delete-entry #'delete-entry
       :find-kind #'find-kind
       :find-dataset #'find-dataset
       :find-field #'find-field
       :put-relation #'put-relation
       :fetch-relation #'fetch-relation
       :delete-relation #'delete-relation
       :find-predicate #'find-predicate
       :neighbors #'neighbors
       :close #'close-store))))
