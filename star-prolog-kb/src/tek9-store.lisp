(in-package :starprologkb)

(defparameter +prolog-source-db+ "star/prolog-source")
(defparameter +default-graph-name+ "starintel")

(defstruct (starintel-kb (:constructor %make-starintel-kb))
  program
  spec-ir
  database
  indexes
  (graph-name +default-graph-name+))

(defun %ensure-tek9 ()
  "Load the external Tek9 ASDF system on first storage use."
  (or (find-package :tek9)
      (handler-case
          (progn
            (asdf:load-system "tek9")
            (or (find-package :tek9)
                (error "ASDF loaded tek9 without defining package TEK9.")))
        (error (condition)
          (error 'tek9-unavailable-error
                 :message
                 (format nil
                         "The star-prolog-kb storage boundary requires the tek9 ASDF system: ~A"
                         condition))))))

(defun %tek9-symbol (name)
  (let* ((package (%ensure-tek9))
         (symbol (find-symbol (string-upcase name) package)))
    (unless symbol
      (error 'tek9-unavailable-error
             :message (format nil "Installed Tek9 lacks symbol ~A." name)))
    symbol))

(defun %tek9-call (name &rest arguments)
  (let ((symbol (%tek9-symbol name)))
    (unless (fboundp symbol)
      (error 'tek9-unavailable-error
             :message (format nil "Tek9 symbol ~A is not callable." name)))
    (apply (symbol-function symbol) arguments)))

(defun %tek9-instance (class-name &rest initargs)
  (apply #'make-instance (%tek9-symbol class-name) initargs))

(defun %key-name (key)
  (cond
    ((stringp key) key)
    ((symbolp key) (symbol-name key))
    (t (princ-to-string key))))

(defun %normalized-field-key (key)
  (with-output-to-string (stream)
    (loop for character across (string-downcase (%key-name key))
          unless (find character "-_" :test #'char=)
            do (write-char character stream))))

(defun %field-key-p (left right)
  (string= (%normalized-field-key left)
           (%normalized-field-key right)))

(defun %plist-object-p (value)
  (and (consp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (or (stringp (first tail))
                        (symbolp (first tail))))))

(defun %alist-object-p (value)
  (and (consp value)
       (every (lambda (entry)
                (and (consp entry)
                     (or (stringp (car entry))
                         (symbolp (car entry)))))
              value)))

(defun %jsown-object-p (value)
  (and (consp value) (eq (first value) :obj)))

(defun %lookup-field (object field)
  "Return VALUE,PRESENT-P for FIELD across StarIntel's common map shapes."
  (cond
    ((starcanonicaljson:json-object-p object)
     (let ((entry
             (find field (starcanonicaljson:json-object-entries object)
                   :test #'%field-key-p :key #'car)))
       (if entry (values (cdr entry) t) (values nil nil))))
    ((hash-table-p object)
     (let ((found nil)
           (result nil))
       (maphash (lambda (key value)
                  (when (and (not found) (%field-key-p key field))
                    (setf found t result value)))
                object)
       (values result found)))
    ((%jsown-object-p object)
     (let ((entry (find field (rest object) :test #'%field-key-p :key #'car)))
       (if entry (values (cdr entry) t) (values nil nil))))
    ((%plist-object-p object)
     (loop for (key value) on object by #'cddr
           when (%field-key-p key field)
             do (return (values value t))
           finally (return (values nil nil))))
    ((%alist-object-p object)
     (let ((entry (find field object :test #'%field-key-p :key #'car)))
       (if entry
           (values (if (and (consp entry)
                            (consp (cdr entry))
                            (null (cddr entry)))
                       (second entry)
                       (cdr entry))
                   t)
           (values nil nil))))
    (t
     (values nil nil))))

(defun %object-entries (object)
  (cond
    ((starcanonicaljson:json-object-p object)
     (copy-list (starcanonicaljson:json-object-entries object)))
    ((hash-table-p object)
     (let ((entries '()))
       (maphash (lambda (key value) (push (cons key value) entries)) object)
       entries))
    ((%jsown-object-p object) (copy-list (rest object)))
    ((%plist-object-p object)
     (loop for (key value) on object by #'cddr collect (cons key value)))
    ((%alist-object-p object)
     (mapcar (lambda (entry)
               (cons (car entry)
                     (if (and (consp (cdr entry)) (null (cddr entry)))
                         (second entry)
                         (cdr entry))))
             object))
    (t nil)))

(defun %json-array-values (value)
  (and (starcanonicaljson:json-array-p value)
       (starcanonicaljson:json-array-values value)))

(defun %canonical-form (value)
  "Convert VALUE to a deterministic, type-tagged equality key form."
  (cond
    ((eq value starcanonicaljson:+json-true+) '(:boolean t))
    ((eq value starcanonicaljson:+json-false+) '(:boolean nil))
    ((eq value starcanonicaljson:+json-null+) '(:null))
    ((null value) '(:null))
    ((eq value t) '(:boolean t))
    ((stringp value) (list :string value))
    ((integerp value) (list :integer value))
    ((rationalp value) (list :ratio (numerator value) (denominator value)))
    ((floatp value)
     (list :float
           (with-standard-io-syntax
             (let ((*print-readably* t))
               (write-to-string value)))))
    ((symbolp value) (list :symbol (string-downcase (symbol-name value))))
    ((starcanonicaljson:json-array-p value)
     (cons :array (mapcar #'%canonical-form (%json-array-values value))))
    ((or (starcanonicaljson:json-object-p value)
         (hash-table-p value)
         (%jsown-object-p value)
         (%plist-object-p value)
         (%alist-object-p value))
     (list :object
           (sort
            (mapcar (lambda (entry)
                      (cons (%normalized-field-key (car entry))
                            (%canonical-form (cdr entry))))
                    (%object-entries value))
            #'string< :key #'car)))
    ((listp value)
     (cons :list (mapcar #'%canonical-form value)))
    ((vectorp value)
     (cons :vector
           (loop for item across value collect (%canonical-form item))))
    (t
     (list :printed
           (with-standard-io-syntax
             (let ((*print-readably* nil))
               (prin1-to-string value)))))))

(defun %index-key-string (value)
  (with-standard-io-syntax
    (let ((*print-readably* t)
          (*print-pretty* nil))
      (prin1-to-string (%canonical-form value)))))

(defun %compound-key (values)
  "Length-prefix encoded tuple of deterministic component keys."
  (with-output-to-string (stream)
    (dolist (value values)
      (let ((encoded (%index-key-string value)))
        (format stream "~D:~A" (length encoded) encoded)))))

(defun %document-dtype (value)
  (multiple-value-bind (dtype present) (%lookup-field value "dtype")
    (and present (stringp dtype) dtype)))

(defun %document-by-dtype (spec-ir dtype)
  (and dtype (%find-document (%document-table spec-ir) dtype)))

(defun %document-subtype-p (spec-ir actual expected)
  (let ((table (%document-table spec-ir))
        (expected-document (%find-document (%document-table spec-ir) expected)))
    (when expected-document
      (loop with current = actual
            while current
            do (when (or (string= (getf current :name)
                                  (getf expected-document :name))
                         (string= (getf current :qualified-name)
                                  (getf expected-document :qualified-name)))
                 (return t))
               (let ((parent (getf current :extends)))
                 (setf current (and (stringp parent)
                                    (%find-document table parent))))
            finally (return nil)))))

(defun %source-matches-p (spec-ir value source)
  (if (null source)
      t
      (let* ((dtype (%document-dtype value))
             (actual (%document-by-dtype spec-ir dtype)))
        (or (and actual (%document-subtype-p spec-ir actual source))
            (and dtype (string-equal dtype source))))))

(defun %field-type-for-value (spec-ir value field-name &optional source)
  (let* ((document
           (or (%document-by-dtype spec-ir (%document-dtype value))
               (and source (%source-document spec-ir source)))))
    (when document
      (let ((field (%field-by-name
                    (effective-document-fields
                     spec-ir (getf document :qualified-name))
                    field-name)))
        (and field (getf field :type))))))

(defun %list-value-p (type value)
  (or (%field-type-list-p type)
      (starcanonicaljson:json-array-p value)))

(defun %walk-selector-tail (value tail)
  (if (null tail)
      (list value)
      (let ((component (first tail))
            (rest (rest tail)))
        (cond
          ((starcanonicaljson:json-array-p value)
           (mapcan (lambda (item) (%walk-selector-tail item tail))
                   (%json-array-values value)))
          ((and (listp value)
                (not (%plist-object-p value))
                (not (%alist-object-p value))
                (not (%jsown-object-p value)))
           (mapcan (lambda (item) (%walk-selector-tail item tail)) value))
          (t
           (multiple-value-bind (next present) (%lookup-field value component)
             (if present
                 (%walk-selector-tail next rest)
                 nil)))))))

(defun %selector-values (spec-ir value selector &optional source)
  (multiple-value-bind (root present) (%lookup-field value (first selector))
    (unless present
      (return-from %selector-values nil))
    (let ((type (%field-type-for-value spec-ir value (first selector) source)))
      (cond
        ((rest selector)
         (if (%list-value-p type root)
             (let ((items (or (%json-array-values root) root)))
               (mapcan (lambda (item)
                         (%walk-selector-tail item (rest selector)))
                       items))
             (%walk-selector-tail root (rest selector))))
        ((%list-value-p type root)
         (copy-list (or (%json-array-values root) root)))
        (t
         (list root))))))

(defun %cartesian-product (lists)
  (labels ((extend (remaining prefix)
             (if (null remaining)
                 (list (nreverse prefix))
                 (mapcan (lambda (value)
                           (extend (rest remaining) (cons value prefix)))
                         (first remaining)))))
    (if (some #'null lists)
        nil
        (extend lists nil))))

(defun %index-values (spec spec-ir value)
  (unless (%source-matches-p spec-ir value (kb-index-spec-source spec))
    (return-from %index-values nil))
  (let* ((selector-values
           (mapcar (lambda (selector)
                     (%selector-values spec-ir value selector
                                       (kb-index-spec-source spec)))
                   (kb-index-spec-selectors spec)))
         (tuples (%cartesian-product selector-values))
         (keys
           (remove-duplicates
            (mapcar (lambda (tuple)
                      (if (= (length tuple) 1)
                          (%index-key-string (first tuple))
                          (%compound-key tuple)))
                    tuples)
            :test #'string=)))
    (if (kb-index-spec-multi-valued-p spec)
        keys
        (cond
          ((null keys) nil)
          ((null (rest keys)) (first keys))
          (t
           (error 'prolog-kb-schema-error
                  :message
                  (format nil
                          "Unique index ~A produced multiple keys for one document."
                          (kb-index-spec-name spec))))))))

(defun %make-index-extractor (spec spec-ir)
  (lambda (tek9-document)
    (let ((value (%tek9-call "DOC-VALUE" tek9-document)))
      (%index-values spec spec-ir value))))

(defun %make-index-definition (spec spec-ir)
  (%tek9-call "NEW-INDEX-DEFINITION"
              (kb-index-spec-name spec)
              (%make-index-extractor spec spec-ir)
              :key-type :string
              :unique (kb-index-spec-unique-p spec)
              :multi-valued (kb-index-spec-multi-valued-p spec)))

(defun %persist-prolog-blocks (database program)
  ;; Pre-open the DBI before the explicit transaction so LMDB never sees a
  ;; first-use GET-DB from inside a transaction.
  (%tek9-call "DATABASE-DB" database +prolog-source-db+)
  (%tek9-call
   "CALL-WITH-TRANSACTION"
   database
   (lambda ()
     (dolist (block (prolog-kb-program-prolog-blocks program))
       (%tek9-call
        "PUT*" database
        (list :name (prolog-source-block-name block)
              :source (prolog-source-block-source block)
              :kind (prolog-source-block-kind block)
              :text (prolog-source-block-text block))
        :id (prolog-source-block-name block)
        :database-name +prolog-source-db+)))
   :write
   :database-names (list +prolog-source-db+)))

(defun open-starintel-kb (program spec-ir
                          &key
                            (path #P"./starintel-prolog-kb/")
                            max-dbs
                            (graph-name +default-graph-name+)
                            rebuild-indexes)
  "Open a Tek9-backed StarIntel knowledge base described by PROGRAM and SPEC-IR."
  (unless (prolog-kb-program-p program)
    (error 'prolog-kb-schema-error
           :message "PROGRAM must be compiled Prolog-KB StarLang IR."))
  (%validate-schema-reference program spec-ir)
  (%ensure-tek9)
  (let* ((indexes (resolve-index-specs program spec-ir))
         (required-max-dbs (required-tek9-max-dbs indexes))
         (effective-max-dbs (or max-dbs required-max-dbs)))
    (when (< effective-max-dbs required-max-dbs)
      (error 'prolog-kb-schema-error
             :message
             (format nil "Tek9 max-dbs ~D is too small; schema requires at least ~D."
                     effective-max-dbs required-max-dbs)))
    (let* ((definitions
             (mapcar (lambda (spec) (%make-index-definition spec spec-ir))
                     indexes))
           (database
             (%tek9-call
              "NEW-DATABASE"
              (prolog-kb-program-name program)
              :path (uiop:ensure-directory-pathname path)
              :max-dbs effective-max-dbs
              :index-definitions definitions)))
      (handler-case
          (progn
            (%tek9-call "OPEN-DATABASE" database)
            (let ((kb (%make-starintel-kb
                       :program program
                       :spec-ir spec-ir
                       :database database
                       :indexes indexes
                       :graph-name graph-name)))
              (%persist-prolog-blocks database program)
              (when rebuild-indexes
                (dolist (spec indexes)
                  (%tek9-call "REBUILD-INDEX-FAST"
                              database (kb-index-spec-name spec))))
              kb))
        (error (condition)
          (ignore-errors (%tek9-call "CLOSE-DATABASE" database))
          (error condition))))))

(defun close-starintel-kb (kb)
  (when (and (starintel-kb-p kb) (starintel-kb-database kb))
    (%tek9-call "CLOSE-DATABASE" (starintel-kb-database kb)))
  kb)

(defun %required-string-field (value field)
  (multiple-value-bind (field-value present) (%lookup-field value field)
    (unless (and present (stringp field-value) (plusp (length field-value)))
      (error 'prolog-kb-schema-error
             :message
             (format nil "StarIntel document requires non-empty string field ~A."
                     field)))
    field-value))

(defun %reference-id (value)
  (cond
    ((stringp value) value)
    (t
     (or (multiple-value-bind (id present) (%lookup-field value "id")
           (and present (stringp id) id))
         (multiple-value-bind (id present) (%lookup-field value "documentId")
           (and present (stringp id) id))
         (multiple-value-bind (id present) (%lookup-field value "ref")
           (and present (stringp id) id))
         (error 'prolog-kb-schema-error
                :message (format nil "Cannot resolve reference id from ~S." value))))))

(defun %relation-document-p (value)
  (let ((dtype (%document-dtype value)))
    (and dtype
         (or (string-equal dtype "relation")
             (let ((slash (position #\/ dtype :from-end t)))
               (and slash
                    (string-equal (subseq dtype (1+ slash)) "relation")))))))

(defun %relation-edge (value id)
  (when (%relation-document-p value)
    (multiple-value-bind (source source-p) (%lookup-field value "source")
      (multiple-value-bind (destination destination-p)
          (%lookup-field value "destination")
        (multiple-value-bind (predicate predicate-p)
            (%lookup-field value "predicate")
          (unless (and source-p destination-p predicate-p)
            (error 'prolog-kb-schema-error
                   :message "Relation document requires source, predicate, and destination."))
          (%tek9-instance
           "EDGE"
           :id id
           :source (%reference-id source)
           :predicate (princ-to-string predicate)
           :target (%reference-id destination)))))))

(defun %put-starintel-document-in-transaction (kb value)
  (let* ((database (starintel-kb-database kb))
         (id (%required-string-field value "id"))
         (existing (%tek9-call "FETCH*" database id))
         (new-edge (%relation-edge value id)))
    (%tek9-call "PUT*" database value :id id)
    (%tek9-call "PUT-NODE"
                database
                (%tek9-instance "NODE" :id id :props value)
                :database-name (starintel-kb-graph-name kb))
    (when (and existing (%relation-document-p existing) (null new-edge))
      (let ((old-edge (%tek9-call "FETCH-EDGE" database id
                                  :database-name (starintel-kb-graph-name kb))))
        (when old-edge
          (%tek9-call "DELETE-EDGE" database old-edge
                      :database-name (starintel-kb-graph-name kb)))))
    (when new-edge
      (%tek9-call "PUT-EDGE" database new-edge
                  :database-name (starintel-kb-graph-name kb)))
    value))

(defun put-starintel-document (kb value)
  "Atomically persist VALUE as a Tek9 document, graph node, and relation edge."
  (%tek9-call
   "CALL-WITH-TRANSACTION"
   (starintel-kb-database kb)
   (lambda () (%put-starintel-document-in-transaction kb value))
   :write))

(defun put-starintel-documents (kb values)
  "Atomically persist VALUES as one Tek9 transaction."
  (%tek9-call
   "CALL-WITH-TRANSACTION"
   (starintel-kb-database kb)
   (lambda ()
     (mapcar (lambda (value) (%put-starintel-document-in-transaction kb value))
             values))
   :write))

(defun fetch-starintel-document (kb id)
  (%tek9-call "FETCH*" (starintel-kb-database kb) id))

(defun delete-starintel-document (kb id)
  "Delete a StarIntel document, its relation edge (if any), and graph node."
  (let ((database (starintel-kb-database kb)))
    (%tek9-call
     "CALL-WITH-TRANSACTION"
     database
     (lambda ()
       (let ((value (%tek9-call "FETCH*" database id)))
         (when value
           (when (%relation-document-p value)
             (let ((edge (%tek9-call "FETCH-EDGE" database id
                                     :database-name
                                     (starintel-kb-graph-name kb))))
               (when edge
                 (%tek9-call "DELETE-EDGE" database edge
                             :database-name
                             (starintel-kb-graph-name kb)))))
           (%tek9-call "DELETE-NODE" database id
                       :database-name (starintel-kb-graph-name kb))
           (%tek9-call "DELETE-DOCUMENT" database id))))
     :write)))

(defun %find-index-spec (kb name)
  (find name (starintel-kb-indexes kb)
        :test #'string= :key #'kb-index-spec-name))

(defun %unwrap-index-results (documents)
  (mapcar (lambda (document) (%tek9-call "DOC-VALUE" document)) documents))

(defun query-index (kb name &rest values)
  "Query NAME by one value per declared selector and return StarIntel values."
  (let ((spec (%find-index-spec kb name)))
    (unless spec
      (error 'prolog-kb-schema-error
             :message (format nil "Unknown KB index ~A." name)))
    (unless (= (length values) (length (kb-index-spec-selectors spec)))
      (error 'prolog-kb-schema-error
             :message
             (format nil "Index ~A expects ~D query values, received ~D."
                     name
                     (length (kb-index-spec-selectors spec))
                     (length values))))
    (let ((key (if (= (length values) 1)
                   (%index-key-string (first values))
                   (%compound-key values))))
      (%unwrap-index-results
       (%tek9-call "INDEX-FETCH" (starintel-kb-database kb) name key)))))

(defun query-field (kb field value)
  "Query the automatic field/FIELD Tek9 index."
  (query-index kb (field-index-name field) value))

(defun %normalize-selector-input (field)
  (cond
    ((stringp field) (list field))
    ((and (listp field) (every #'stringp field) field) (copy-list field))
    (t
     (error 'prolog-kb-schema-error
            :message (format nil "Invalid index selector ~S." field)))))

(defun %normalize-kind (kind)
  (let ((normalized
          (cond
            ((keywordp kind) kind)
            ((symbolp kind) (intern (string-upcase (symbol-name kind)) :keyword))
            ((stringp kind) (intern (string-upcase kind) :keyword))
            (t nil))))
    (unless (member normalized '(:auto :multi :unique) :test #'eq)
      (error 'prolog-kb-schema-error
             :message "Index kind must be AUTO, MULTI, or UNIQUE."))
    normalized))

(defun define-index (kb name &key source fields (kind :auto) (rebuild t))
  "Define and register a new Tek9 index after the KB has opened.

FIELDS is a list whose entries are field names or nested path lists. New index
DBIs consume the headroom reserved by OPEN-STARINTEL-KB."
  (unless (and (stringp name) (plusp (length name)))
    (error 'prolog-kb-schema-error :message "Index name must be a non-empty string."))
  (unless (and (stringp source) (plusp (length source)))
    (error 'prolog-kb-schema-error :message "Index source must name a document type."))
  (unless (and (listp fields) fields)
    (error 'prolog-kb-schema-error :message "Index fields must be a non-empty list."))
  (when (%find-index-spec kb name)
    (error 'prolog-kb-schema-error
           :message (format nil "KB index ~A already exists." name)))
  (let* ((normalized-kind (%normalize-kind kind))
         (spec
           (resolve-index-spec
            (starintel-kb-spec-ir kb)
            (make-kb-index-spec
             :name name
             :source source
             :selectors (mapcar #'%normalize-selector-input fields)
             :kind normalized-kind
             :unique-p (eq normalized-kind :unique)
             :multi-valued-p (not (eq normalized-kind :unique))
             :automatic-p nil)))
         (database (starintel-kb-database kb)))
    (%tek9-call "REGISTER-INDEX"
                database
                name
                (%make-index-extractor spec (starintel-kb-spec-ir kb))
                :key-type :string
                :unique (kb-index-spec-unique-p spec)
                :multi-valued (kb-index-spec-multi-valued-p spec))
    (when rebuild
      (%tek9-call "REBUILD-INDEX-FAST" database name))
    (setf (starintel-kb-indexes kb)
          (append (starintel-kb-indexes kb) (list spec)))
    spec))

(defun list-indexes (kb)
  (copy-list (starintel-kb-indexes kb)))