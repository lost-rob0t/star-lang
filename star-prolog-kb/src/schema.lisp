(in-package :starprologkb)

(defun document-declarations (spec-ir)
  "Return document declarations from compiled StarLang specification IR."
  (remove-if-not (lambda (declaration)
                   (eq (getf declaration :kind) :document))
                 (copy-list (getf spec-ir :declarations))))

(defun %document-table (spec-ir)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (document (document-declarations spec-ir) table)
      (setf (gethash (getf document :name) table) document
            (gethash (getf document :qualified-name) table) document))))

(defun %find-document (table name)
  (or (gethash name table)
      (gethash (string-downcase name) table)
      (loop for document being the hash-values of table
            when (or (string-equal name (getf document :name))
                     (string-equal name (getf document :qualified-name)))
              return document)))

(defun %merge-fields (parent own)
  (let ((result (copy-list parent)))
    (dolist (field own result)
      (let ((existing
              (position (getf field :name) result
                        :test #'string=
                        :key (lambda (candidate) (getf candidate :name)))))
        (if existing
            (setf (nth existing result) field)
            (setf result (append result (list field))))))))

(defun effective-document-fields (spec-ir document-name)
  "Return DOCUMENT-NAME fields after resolving local StarLang inheritance."
  (let ((table (%document-table spec-ir))
        (memo (make-hash-table :test #'equal)))
    (labels ((resolve (document trail)
               (let ((qualified (getf document :qualified-name)))
                 (or (gethash qualified memo)
                     (progn
                       (when (member qualified trail :test #'string=)
                         (error 'prolog-kb-schema-error
                                :message
                                (format nil "Document inheritance cycle at ~A."
                                        qualified)))
                       (let* ((parent-name (getf document :extends))
                              (parent
                                (and (stringp parent-name)
                                     (%find-document table parent-name)))
                              (parent-fields
                                (if parent
                                    (resolve parent (cons qualified trail))
                                    nil))
                              (effective
                                (%merge-fields parent-fields
                                               (getf document :fields))))
                         (setf (gethash qualified memo) effective)
                         effective))))))
      (let ((document (%find-document table document-name)))
        (unless document
          (error 'prolog-kb-schema-error
                 :message (format nil "Unknown StarLang document type ~A."
                                  document-name)))
        (copy-tree (resolve document nil))))))

(defun field-index-name (field-name)
  "Canonical Tek9 index name for one StarIntel field."
  (format nil "field/~A" field-name))

(defun %field-type-list-p (type)
  (and (consp type) (eq (first type) :list)))

(defun %schema-field-table (spec-ir)
  "Map every effective field name to all schema occurrences defining it."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (document (document-declarations spec-ir) table)
      (dolist (field (effective-document-fields
                      spec-ir (getf document :qualified-name)))
        (pushnew field (gethash (getf field :name) table)
                 :test #'equal)))))

(defun make-auto-index-specs (spec-ir)
  "Create one global Tek9 secondary index for every effective StarLang field.

Scalar fields emit one posting; list fields emit one posting per element. The
index name is field/FIELD. The id field is unique; all other field indexes are
non-unique and use DUPSORT postings."
  (let ((fields (%schema-field-table spec-ir))
        (result '()))
    (maphash
     (lambda (name occurrences)
       (declare (ignore occurrences))
       (push (make-kb-index-spec
              :name (field-index-name name)
              :source nil
              :selectors (list (list name))
              :kind (if (string= name "id") :unique :multi)
              :unique-p (string= name "id")
              ;; Tek9 permits one extractor to return a list of postings. Keep
              ;; automatic indexes multi-valued so scalar and list fields share
              ;; one durable representation.
              :multi-valued-p (not (string= name "id"))
              :automatic-p t)
             result))
     fields)
    (sort result #'string< :key #'kb-index-spec-name)))

(defun %field-by-name (fields name)
  (find name fields :test #'string= :key (lambda (field) (getf field :name))))

(defun %source-document (spec-ir source)
  (%find-document (%document-table spec-ir) source))

(defun %selector-root-field (fields selector)
  (%field-by-name fields (first selector)))

(defun resolve-index-spec (spec-ir spec)
  "Validate one user index against SPEC-IR and finalize Tek9 index flags."
  (unless (kb-index-spec-p spec)
    (error 'prolog-kb-schema-error
           :message (format nil "Expected KB-INDEX-SPEC, got ~S." spec)))
  (when (kb-index-spec-automatic-p spec)
    (return-from resolve-index-spec spec))
  (let* ((source (kb-index-spec-source spec))
         (document (%source-document spec-ir source)))
    (unless document
      (error 'prolog-kb-schema-error
             :message (format nil "Index ~A names unknown document type ~A."
                              (kb-index-spec-name spec) source)))
    (let ((fields
            (effective-document-fields spec-ir (getf document :qualified-name))))
      (dolist (selector (kb-index-spec-selectors spec))
        (let ((root (%selector-root-field fields selector)))
          (unless root
            (error 'prolog-kb-schema-error
                   :message
                   (format nil "Index ~A selects unknown field ~A on ~A."
                           (kb-index-spec-name spec)
                           (first selector)
                           source)))
          (when (and (eq (kb-index-spec-kind spec) :unique)
                     (%field-type-list-p (getf root :type)))
            (error 'prolog-kb-schema-error
                   :message
                   (format nil
                           "Unique index ~A cannot directly select list field ~A."
                           (kb-index-spec-name spec)
                           (first selector)))))))
    (setf (kb-index-spec-unique-p spec)
          (eq (kb-index-spec-kind spec) :unique)
          (kb-index-spec-multi-valued-p spec)
          (not (eq (kb-index-spec-kind spec) :unique)))
    spec))

(defun resolve-index-specs (program spec-ir)
  "Return automatic field indexes plus checked StarLang-declared indexes."
  (let* ((automatic (make-auto-index-specs spec-ir))
         (custom (mapcar (lambda (spec)
                           (resolve-index-spec spec-ir (copy-kb-index-spec spec)))
                         (prolog-kb-program-indexes program)))
         (all (append automatic custom))
         (seen (make-hash-table :test #'equal)))
    (dolist (spec all)
      (let ((name (kb-index-spec-name spec)))
        (when (gethash name seen)
          (error 'prolog-kb-schema-error
                 :message (format nil "Duplicate Tek9 index name ~A." name)))
        (setf (gethash name seen) t)))
    all))

(defun %validate-schema-reference (program spec-ir)
  (let ((reference (prolog-kb-program-schema program)))
    (unless (equal (kb-schema-ref-source reference) (getf spec-ir :name))
      (error 'prolog-kb-schema-error
             :message
             (format nil "KB expects schema ~A, compiled schema is ~A."
                     (kb-schema-ref-source reference)
                     (getf spec-ir :name))))
    (unless (equal (kb-schema-ref-version reference) (getf spec-ir :version))
      (error 'prolog-kb-schema-error
             :message
             (format nil "KB expects schema version ~A, compiled schema is ~A."
                     (kb-schema-ref-version reference)
                     (getf spec-ir :version))))
    (let ((expected (kb-schema-ref-digest reference))
          (actual (getf spec-ir :digest)))
      (when (and expected actual (not (string= expected actual)))
        (error 'prolog-kb-schema-error
               :message "KB schema digest does not match compiled StarLang schema.")))
    t))

(defun required-tek9-max-dbs (indexes)
  "Return a safe LMDB named-DB budget for INDEXES plus graph and KB metadata."
  ;; Tek9 graph/v2 currently owns ten named DBs. Add main, Prolog source, and
  ;; headroom for future graph/catalog metadata. The minimum preserves Tek9's
  ;; default behavior for small schemas.
  (max 64 (+ 24 (length indexes))))