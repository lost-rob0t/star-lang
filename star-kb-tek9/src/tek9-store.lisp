(in-package :starkbtek9)

(defconstant +records-database-name+ "star-kb/records")
(defconstant +index-entry-kind+ "star-kb.entry-kind")
(defconstant +index-entry-dataset+ "star-kb.entry-dataset")
(defconstant +index-entry-field+ "star-kb.entry-field")
(defconstant +index-relation-predicate+ "star-kb.relation-predicate")
(defconstant +index-relation-dataset+ "star-kb.relation-dataset")
(defconstant +schema-marker-key+ "star-kb/schema-version")
(defconstant +schema-version+ 1)

(defun component-key (value)
  (format nil "~D:~A" (length value) value))

(defun composite-key (&rest values)
  (with-output-to-string (stream)
    (dolist (value values)
      (write-string (component-key value) stream))))

(defun record-key (record-type namespace id)
  (composite-key (string-downcase (symbol-name record-type)) namespace id))

(defun entry-document-key (namespace id)
  (record-key :entry namespace id))

(defun relation-document-key (namespace id)
  (record-key :relation namespace id))

(defun encode-portable-index-value (value)
  "Encode portable StarLang VALUE into an unambiguous deterministic string.

This is an equality-index encoding, not a wire format. Type tags and length
prefixes prevent collisions without depending on the Common Lisp printer."
  (labels ((emit (item stream)
             (cond
               ((null item)
                (write-string "n" stream))
               ((eq item t)
                (write-string "t" stream))
               ((integerp item)
                (format stream "i~D;" item))
               ((stringp item)
                (format stream "s~D:" (length item))
                (write-string item stream))
               ((symbolp item)
                (let ((name (staractorprotocol:portable-wire-identifier-string item)))
                  (format stream "y~D:" (length name))
                  (write-string name stream)))
               ((consp item)
                (write-string "c" stream)
                (let ((left (encode-portable-index-value (car item)))
                      (right (encode-portable-index-value (cdr item))))
                  (format stream "~D:" (length left))
                  (write-string left stream)
                  (format stream "~D:" (length right))
                  (write-string right stream)))
               ((vectorp item)
                (format stream "v~D:" (length item))
                (dotimes (index (length item))
                  (let ((encoded
                          (encode-portable-index-value (aref item index))))
                    (format stream "~D:" (length encoded))
                    (write-string encoded stream))))
               (t
                (error "Unsupported portable index value ~S." (type-of item))))))
    (with-output-to-string (stream)
      (emit value stream))))

(defun entry-kind-index-key (entry)
  (composite-key (star-kb:kb-record-namespace entry)
                 (star-kb:kb-entry-kind entry)))

(defun entry-dataset-index-key (entry)
  (let ((dataset (star-kb:kb-record-dataset entry)))
    (and dataset
         (composite-key (star-kb:kb-record-namespace entry) dataset))))

(defun entry-field-index-keys (entry)
  (loop for (path . value) in (star-kb:kb-entry-fields entry)
        collect (composite-key
                 (star-kb:kb-record-namespace entry)
                 path
                 (encode-portable-index-value value))))

(defun relation-predicate-index-key (relation)
  (composite-key (star-kb:kb-record-namespace relation)
                 (star-kb:kb-relation-predicate relation)))

(defun relation-dataset-index-key (relation)
  (let ((dataset (star-kb:kb-record-dataset relation)))
    (and dataset
         (composite-key (star-kb:kb-record-namespace relation) dataset))))

(defun record-value (document)
  (tek9:doc-value document))

(defun register-kb-indexes (database)
  (tek9:register-index
   database +index-entry-kind+
   (lambda (document)
     (let ((value (record-value document)))
       (and (star-kb:kb-entry-p value)
            (entry-kind-index-key value))))
   :database-name +records-database-name+)
  (tek9:register-index
   database +index-entry-dataset+
   (lambda (document)
     (let ((value (record-value document)))
       (and (star-kb:kb-entry-p value)
            (entry-dataset-index-key value))))
   :database-name +records-database-name+)
  (tek9:register-index
   database +index-entry-field+
   (lambda (document)
     (let ((value (record-value document)))
       (and (star-kb:kb-entry-p value)
            (entry-field-index-keys value))))
   :database-name +records-database-name+
   :multi-valued t)
  (tek9:register-index
   database +index-relation-predicate+
   (lambda (document)
     (let ((value (record-value document)))
       (and (star-kb:kb-relation-p value)
            (relation-predicate-index-key value))))
   :database-name +records-database-name+)
  (tek9:register-index
   database +index-relation-dataset+
   (lambda (document)
     (let ((value (record-value document)))
       (and (star-kb:kb-relation-p value)
            (relation-dataset-index-key value))))
   :database-name +records-database-name+)
  database)

(defun ensure-index-schema (database)
  "Rebuild indexes exactly when the STAR-KB index schema version changes.

Tek9 index extractor functions are process-local configuration, while index
B+trees are durable. The marker lets a new adapter version migrate old records
without rebuilding all indexes on every process start."
  (let ((marker
          (tek9:fetch* database +schema-marker-key+
                       :database-name +records-database-name+)))
    (unless (eql (getf marker :star-kb-schema-version) +schema-version+)
      (tek9:with-write-transaction
          (database :database-names (list +records-database-name+))
        (dolist (index (list +index-entry-kind+
                             +index-entry-dataset+
                             +index-entry-field+
                             +index-relation-predicate+
                             +index-relation-dataset+))
          (tek9:rebuild-index database index))
        (tek9:put
         database
         (tek9:new-document
          :id +schema-marker-key+
          :value (list :star-kb-schema-version +schema-version+))
         :database-name +records-database-name+))))
  database)

(defun sort-records (records)
  (sort (copy-list records) #'string< :key #'star-kb:kb-record-id))

(defun select-index-records (database index key)
  (sort-records (tek9:select-index database index key)))

(defun make-tek9-kb-store (database &key close-database-p (name "tek9"))
  "Wrap an already-open Tek9 DATABASE as a STAR-KB store.

When CLOSE-DATABASE-P is true, STAR-KB:KB-CLOSE owns and closes DATABASE.
Indexes are process-local Tek9 configuration and are registered every time the
adapter is constructed; the underlying LMDB index contents remain durable."
  (unless (tek9:db-is-open-p database)
    (error "Tek9 database must be open before creating a KB store."))
  (register-kb-indexes database)
  (ensure-index-schema database)
  (labels
      ((put-entry (entry)
         (let ((namespace (star-kb:kb-record-namespace entry))
               (id (star-kb:kb-record-id entry)))
           (tek9:with-write-transaction
               (database :database-names (list +records-database-name+))
             (tek9:put
              database
              (tek9:new-document :id (entry-document-key namespace id)
                                 :value entry)
              :database-name +records-database-name+)
             (tek9:put-node
              database
              (make-instance 'tek9:node :id id :props entry)
              :database-name namespace))
           entry))
       (fetch-entry (namespace id)
         (tek9:fetch* database (entry-document-key namespace id)
                      :database-name +records-database-name+))
       (delete-entry (namespace id)
         (tek9:with-write-transaction
             (database :database-names (list +records-database-name+))
           (let ((entry (fetch-entry namespace id)))
             (when entry
               ;; Tek9 DELETE-NODE cascades graph edges. Mirror that cascade in
               ;; the indexed relation records inside the same LMDB txn.
               (let ((edge-ids
                       (remove-duplicates
                        (append
                         (tek9:fetch-node-edge-ids
                          database id :database-name namespace)
                         (tek9:fetch-node-edge-ids
                          database id :database-name namespace :incoming t))
                        :test #'string=)))
                 (dolist (edge-id edge-ids)
                   (tek9:delete-document
                    database (relation-document-key namespace edge-id)
                    :database-name +records-database-name+)))
               (tek9:delete-node database id :database-name namespace)
               (tek9:delete-document
                database (entry-document-key namespace id)
                :database-name +records-database-name+)
               t))))
       (find-kind (namespace kind)
         (select-index-records
          database +index-entry-kind+ (composite-key namespace kind)))
       (find-dataset (namespace dataset)
         (select-index-records
          database +index-entry-dataset+ (composite-key namespace dataset)))
       (find-field (namespace path value)
         (select-index-records
          database +index-entry-field+
          (composite-key namespace path (encode-portable-index-value value))))
       (put-relation (relation)
         (let ((namespace (star-kb:kb-record-namespace relation))
               (id (star-kb:kb-record-id relation)))
           (tek9:with-write-transaction
               (database :database-names (list +records-database-name+))
             ;; Write both projections in one LMDB transaction. If Tek9 rejects
             ;; a missing endpoint, the record/index mutation rolls back too.
             (tek9:put
              database
              (tek9:new-document :id (relation-document-key namespace id)
                                 :value relation)
              :database-name +records-database-name+)
             (tek9:put-edge
              database
              (make-instance 'tek9:edge
                             :id id
                             :source (star-kb:kb-relation-source relation)
                             :predicate (star-kb:kb-relation-predicate relation)
                             :target (star-kb:kb-relation-target relation))
              :database-name namespace))
           relation))
       (fetch-relation (namespace id)
         (tek9:fetch* database (relation-document-key namespace id)
                      :database-name +records-database-name+))
       (delete-relation (namespace id)
         (tek9:with-write-transaction
             (database :database-names (list +records-database-name+))
           (let ((relation (fetch-relation namespace id)))
             (when relation
               (tek9:delete-edge
                database
                (make-instance 'tek9:edge
                               :id id
                               :source (star-kb:kb-relation-source relation)
                               :predicate (star-kb:kb-relation-predicate relation)
                               :target (star-kb:kb-relation-target relation))
                :database-name namespace)
               (tek9:delete-document
                database (relation-document-key namespace id)
                :database-name +records-database-name+)
               t))))
       (find-predicate (namespace predicate)
         (select-index-records
          database +index-relation-predicate+
          (composite-key namespace predicate)))
       (neighbors (namespace id predicate incoming)
         (mapcar #'tek9:node-props
                 (tek9:fetch-node-neighbors
                  database id
                  :database-name namespace
                  :predicate predicate
                  :incoming incoming)))
       (close-store ()
         (when close-database-p
           (tek9:close-database database))
         t))
    (star-kb:make-kb-store
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
     :close #'close-store)))

(defun open-tek9-kb-store (path
                           &key
                             (name "star-kb")
                             (max-size (* 16 1024 1024 1024))
                             (max-dbs 64)
                             (max-readers 126)
                             (durability :full))
  "Open a durable Tek9-backed STAR-KB store rooted at PATH.

The returned store owns the Tek9 environment and closes it via
STAR-KB:KB-CLOSE."
  (let* ((database
           (tek9:new-database
            name
            :path (uiop:ensure-directory-pathname path)
            :max-size max-size
            :max-dbs max-dbs
            :max-readers max-readers
            :durability durability
            :index-definitions nil))
         (opened (tek9:open-database database)))
    (handler-case
        (make-tek9-kb-store opened :close-database-p t :name name)
      (error (condition)
        (tek9:close-database opened)
        (error condition)))))
