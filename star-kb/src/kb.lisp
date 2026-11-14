(in-package :starkb)

(define-condition kb-error (error)
  ((message :initarg :message :reader kb-error-message))
  (:report
   (lambda (condition stream)
     (write-string (kb-error-message condition) stream))))

(define-condition kb-contract-error (kb-error) ())

(define-condition kb-backend-error (kb-error)
  ((operation :initarg :operation :initform :unknown
              :reader kb-backend-error-operation)
   (backend :initarg :backend :initform "unknown"
            :reader kb-backend-error-backend)))

(defun fail-kb (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun fail-kb-backend (store operation condition)
  (error 'kb-backend-error
         :message (format nil "KB backend ~A failed during ~A: ~A"
                          (kb-store-name store) operation condition)
         :operation operation
         :backend (kb-store-name store)))

(defun nonempty-string (value context)
  (unless (and (stringp value) (> (length value) 0))
    (fail-kb 'kb-contract-error "~A must be a non-empty string." context))
  value)

(defun optional-string (value context)
  (when value
    (nonempty-string value context))
  value)

(defun snapshot-kb-value (value context)
  (handler-case
      (staractorprotocol:snapshot-portable-wire-value value)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail-kb 'kb-contract-error
               "~A contains a non-portable StarLang value: ~A"
               context condition))))

(defun proper-list-p (value)
  (loop with slow = value
        with fast = value
        do (cond
             ((null fast) (return t))
             ((atom fast) (return nil))
             ((null (cdr fast)) (return t))
             ((atom (cdr fast)) (return nil))
             (t
              (setf slow (cdr slow)
                    fast (cddr fast))
              (when (eq slow fast)
                (return nil))))))

(defun validate-fields (fields)
  (unless (or (null fields)
              (and (proper-list-p fields)
                   (every (lambda (entry)
                            (and (consp entry)
                                 (stringp (car entry))
                                 (> (length (car entry)) 0)))
                          fields)))
    (fail-kb 'kb-contract-error
             "KB entry fields must be a string-keyed alist of canonical field paths."))
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (entry fields)
      (when (gethash (car entry) seen)
        (fail-kb 'kb-contract-error
                 "KB entry contains duplicate canonical field path ~S."
                 (car entry)))
      (setf (gethash (car entry) seen) t)))
  fields)

(defun make-kb-entry (id
                      &key
                        (namespace "default")
                        (kind "document")
                        dataset
                        fields
                        metadata
                        provenance)
  "Construct an owned portable symbolic-catalog entry.

FIELDS is a flat string-keyed alist. Keys are canonical schema field/path names;
StarLang never rewrites their spelling. Values may be any bounded portable wire
value accepted by STAR-ACTOR-PROTOCOL."
  (nonempty-string id "KB entry id")
  (nonempty-string namespace "KB entry namespace")
  (nonempty-string kind "KB entry kind")
  (optional-string dataset "KB entry dataset")
  (let ((owned-fields (snapshot-kb-value fields "KB entry fields"))
        (owned-metadata (snapshot-kb-value metadata "KB entry metadata"))
        (owned-provenance (snapshot-kb-value provenance "KB entry provenance")))
    (validate-fields owned-fields)
    (list :record-type :entry
          :id (copy-seq id)
          :namespace (copy-seq namespace)
          :kind (copy-seq kind)
          :dataset (and dataset (copy-seq dataset))
          :fields owned-fields
          :metadata owned-metadata
          :provenance owned-provenance)))

(defun make-kb-relation (id source predicate target
                         &key
                           (namespace "default")
                           dataset
                           metadata
                           provenance)
  "Construct an owned portable relation record.

A concrete backend may materialize this both as an indexed catalog record and a
graph edge. The record remains authoritative for metadata/provenance that does
not belong in the edge hot path."
  (nonempty-string id "KB relation id")
  (nonempty-string source "KB relation source")
  (nonempty-string predicate "KB relation predicate")
  (nonempty-string target "KB relation target")
  (nonempty-string namespace "KB relation namespace")
  (optional-string dataset "KB relation dataset")
  (list :record-type :relation
        :id (copy-seq id)
        :namespace (copy-seq namespace)
        :source (copy-seq source)
        :predicate (copy-seq predicate)
        :target (copy-seq target)
        :dataset (and dataset (copy-seq dataset))
        :metadata (snapshot-kb-value metadata "KB relation metadata")
        :provenance (snapshot-kb-value provenance "KB relation provenance")))

(defun plist-record-p (record type required-string-keys)
  (and (proper-list-p record)
       (evenp (length record))
       (eq (getf record :record-type) type)
       (every (lambda (key)
                (let ((value (getf record key)))
                  (and (stringp value) (> (length value) 0))))
              required-string-keys)))

(defun kb-entry-p (record)
  (and (plist-record-p record :entry '(:id :namespace :kind))
       (or (null (getf record :dataset))
           (and (stringp (getf record :dataset))
                (> (length (getf record :dataset)) 0)))
       (handler-case
           (progn
             (validate-fields (getf record :fields))
             t)
         (kb-contract-error () nil))))

(defun kb-relation-p (record)
  (and (plist-record-p record :relation
                       '(:id :namespace :source :predicate :target))
       (or (null (getf record :dataset))
           (and (stringp (getf record :dataset))
                (> (length (getf record :dataset)) 0)))))

(defun ensure-entry (record context)
  (unless (kb-entry-p record)
    (fail-kb 'kb-contract-error "~A is not a valid KB entry." context))
  record)

(defun ensure-relation (record context)
  (unless (kb-relation-p record)
    (fail-kb 'kb-contract-error "~A is not a valid KB relation." context))
  record)

(defun kb-record-id (record)
  (getf record :id))

(defun kb-record-namespace (record)
  (getf record :namespace))

(defun kb-record-dataset (record)
  (getf record :dataset))

(defun kb-entry-kind (entry)
  (getf entry :kind))

(defun kb-entry-fields (entry)
  (getf entry :fields))

(defun kb-record-metadata (record)
  (getf record :metadata))

(defun kb-record-provenance (record)
  (getf record :provenance))

(defun kb-relation-source (relation)
  (getf relation :source))

(defun kb-relation-predicate (relation)
  (getf relation :predicate))

(defun kb-relation-target (relation)
  (getf relation :target))

(defun portable-kb-value-equal-p (left right)
  "Structural equality for portable values using StarLang wire symbol semantics."
  (cond
    ((and (null left) (null right)) t)
    ((or (null left) (null right)) nil)
    ((and (eq left t) (eq right t)) t)
    ((or (eq left t) (eq right t)) nil)
    ((and (integerp left) (integerp right)) (= left right))
    ((and (stringp left) (stringp right)) (string= left right))
    ((and (symbolp left) (symbolp right))
     (string= (staractorprotocol:portable-wire-identifier-string left)
              (staractorprotocol:portable-wire-identifier-string right)))
    ((and (consp left) (consp right))
     (and (portable-kb-value-equal-p (car left) (car right))
          (portable-kb-value-equal-p (cdr left) (cdr right))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (portable-kb-value-equal-p
                        (aref left index) (aref right index)))))
    (t nil)))

(defun kb-field-value (entry field-path &optional default)
  (nonempty-string field-path "KB field path")
  (let ((pair (assoc field-path (kb-entry-fields entry) :test #'string=)))
    (if pair (cdr pair) default)))

(defstruct (kb-store
            (:constructor %make-kb-store
                (&key name
                      put-entry-fn fetch-entry-fn delete-entry-fn
                      find-kind-fn find-dataset-fn find-field-fn
                      put-relation-fn fetch-relation-fn delete-relation-fn
                      find-predicate-fn neighbors-fn close-fn)))
  (name "" :type string)
  put-entry-fn
  fetch-entry-fn
  delete-entry-fn
  find-kind-fn
  find-dataset-fn
  find-field-fn
  put-relation-fn
  fetch-relation-fn
  delete-relation-fn
  find-predicate-fn
  neighbors-fn
  close-fn)

(defun make-kb-store (name
                      &key
                        put-entry fetch-entry delete-entry
                        find-kind find-dataset find-field
                        put-relation fetch-relation delete-relation
                        find-predicate neighbors close)
  (nonempty-string name "KB store name")
  (dolist (operation
           (list put-entry fetch-entry delete-entry
                 find-kind find-dataset find-field
                 put-relation fetch-relation delete-relation
                 find-predicate neighbors close))
    (unless (functionp operation)
      (fail-kb 'kb-contract-error
               "Every KB store operation must be a function.")))
  (%make-kb-store
   :name (copy-seq name)
   :put-entry-fn put-entry
   :fetch-entry-fn fetch-entry
   :delete-entry-fn delete-entry
   :find-kind-fn find-kind
   :find-dataset-fn find-dataset
   :find-field-fn find-field
   :put-relation-fn put-relation
   :fetch-relation-fn fetch-relation
   :delete-relation-fn delete-relation
   :find-predicate-fn find-predicate
   :neighbors-fn neighbors
   :close-fn close))

(defun ensure-store (store)
  (unless (kb-store-p store)
    (fail-kb 'kb-contract-error "Expected a KB store, received ~S." store))
  store)

(defun call-kb-backend (store operation accessor &rest arguments)
  (ensure-store store)
  (let ((function (funcall accessor store)))
    (handler-case
        (apply function arguments)
      (kb-error (condition)
        (error condition))
      (error (condition)
        (fail-kb-backend store operation condition)))))

(defun snapshot-result (value context)
  (snapshot-kb-value value context))

(defun snapshot-entry-result (value context)
  (when value
    (let ((owned (snapshot-result value context)))
      (ensure-entry owned context)
      owned)))

(defun snapshot-relation-result (value context)
  (when value
    (let ((owned (snapshot-result value context)))
      (ensure-relation owned context)
      owned)))

(defun snapshot-entry-list (value context)
  (unless (listp value)
    (fail-kb 'kb-backend-error "~A backend result must be a list." context))
  (mapcar (lambda (entry) (snapshot-entry-result entry context)) value))

(defun snapshot-relation-list (value context)
  (unless (listp value)
    (fail-kb 'kb-backend-error "~A backend result must be a list." context))
  (mapcar (lambda (relation) (snapshot-relation-result relation context)) value))

(defun kb-put-entry (store entry)
  (let ((owned (snapshot-result entry "KB put entry")))
    (ensure-entry owned "KB put entry")
    (snapshot-entry-result
     (call-kb-backend store :put-entry #'kb-store-put-entry-fn owned)
     "KB put entry result")))

(defun kb-fetch-entry (store namespace id)
  (nonempty-string namespace "KB fetch namespace")
  (nonempty-string id "KB fetch entry id")
  (snapshot-entry-result
   (call-kb-backend store :fetch-entry #'kb-store-fetch-entry-fn
                    namespace id)
   "KB fetch entry result"))

(defun kb-delete-entry (store namespace id)
  (nonempty-string namespace "KB delete namespace")
  (nonempty-string id "KB delete entry id")
  (not (null
        (call-kb-backend store :delete-entry #'kb-store-delete-entry-fn
                         namespace id))))

(defun kb-find-entries-by-kind (store namespace kind)
  (nonempty-string namespace "KB kind namespace")
  (nonempty-string kind "KB entry kind")
  (snapshot-entry-list
   (call-kb-backend store :find-kind #'kb-store-find-kind-fn
                    namespace kind)
   "KB kind query"))

(defun kb-find-entries-by-dataset (store namespace dataset)
  (nonempty-string namespace "KB dataset namespace")
  (nonempty-string dataset "KB dataset")
  (snapshot-entry-list
   (call-kb-backend store :find-dataset #'kb-store-find-dataset-fn
                    namespace dataset)
   "KB dataset query"))

(defun kb-find-entries-by-field (store namespace field-path value)
  (nonempty-string namespace "KB field namespace")
  (nonempty-string field-path "KB field path")
  (let ((owned (snapshot-result value "KB field query value")))
    (snapshot-entry-list
     (call-kb-backend store :find-field #'kb-store-find-field-fn
                      namespace field-path owned)
     "KB field query")))

(defun kb-put-relation (store relation)
  (let ((owned (snapshot-result relation "KB put relation")))
    (ensure-relation owned "KB put relation")
    (snapshot-relation-result
     (call-kb-backend store :put-relation #'kb-store-put-relation-fn
                      owned)
     "KB put relation result")))

(defun kb-fetch-relation (store namespace id)
  (nonempty-string namespace "KB relation namespace")
  (nonempty-string id "KB relation id")
  (snapshot-relation-result
   (call-kb-backend store :fetch-relation #'kb-store-fetch-relation-fn
                    namespace id)
   "KB fetch relation result"))

(defun kb-delete-relation (store namespace id)
  (nonempty-string namespace "KB relation namespace")
  (nonempty-string id "KB relation id")
  (not (null
        (call-kb-backend store :delete-relation
                         #'kb-store-delete-relation-fn
                         namespace id))))

(defun kb-find-relations-by-predicate (store namespace predicate)
  (nonempty-string namespace "KB predicate namespace")
  (nonempty-string predicate "KB relation predicate")
  (snapshot-relation-list
   (call-kb-backend store :find-predicate
                    #'kb-store-find-predicate-fn
                    namespace predicate)
   "KB predicate query"))

(defun kb-neighbors (store namespace id &key predicate incoming)
  (nonempty-string namespace "KB neighbor namespace")
  (nonempty-string id "KB neighbor entry id")
  (when predicate
    (nonempty-string predicate "KB neighbor predicate"))
  (snapshot-entry-list
   (call-kb-backend store :neighbors #'kb-store-neighbors-fn
                    namespace id predicate (not (null incoming)))
   "KB neighbor query"))

(defun kb-close (store)
  (not (null
        (call-kb-backend store :close #'kb-store-close-fn))))
