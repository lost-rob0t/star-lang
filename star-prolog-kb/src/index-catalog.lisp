(in-package :starprologkb)

(defparameter +index-catalog-db+ "star/kb-indexes")

(defun %index-spec-catalog-value (spec)
  (list :name (kb-index-spec-name spec)
        :source (kb-index-spec-source spec)
        :selectors (copy-tree (kb-index-spec-selectors spec))
        :kind (kb-index-spec-kind spec)))

(defun %catalog-value-index-spec (value)
  (unless (and (listp value)
               (stringp (getf value :name))
               (stringp (getf value :source))
               (listp (getf value :selectors)))
    (error 'prolog-kb-schema-error
           :message (format nil "Invalid persisted KB index definition ~S." value)))
  (let ((kind (%normalize-kind (or (getf value :kind) :auto))))
    (make-kb-index-spec
     :name (getf value :name)
     :source (getf value :source)
     :selectors (copy-tree (getf value :selectors))
     :kind kind
     :unique-p (eq kind :unique)
     :multi-valued-p (not (eq kind :unique))
     :automatic-p nil)))

(defun %ensure-index-catalog-db (database)
  ;; Open before any explicit transaction; Tek9/LMDB does not permit a new DBI
  ;; to be created from inside an already-active transaction.
  (%tek9-call "DATABASE-DB" database +index-catalog-db+)
  database)

(defun %persist-runtime-index-spec (kb spec)
  (let ((database (starintel-kb-database kb)))
    (%ensure-index-catalog-db database)
    (%tek9-call
     "CALL-WITH-TRANSACTION"
     database
     (lambda ()
       (%tek9-call "PUT*"
                   database
                   (%index-spec-catalog-value spec)
                   :id (kb-index-spec-name spec)
                   :database-name +index-catalog-db+))
     :write
     :database-names (list +index-catalog-db+)))
  spec)

(defun %persisted-runtime-index-specs (kb)
  (let ((database (starintel-kb-database kb))
        (values '()))
    (%ensure-index-catalog-db database)
    (%tek9-call
     "MAP-DATABASE"
     database
     :database-name +index-catalog-db+
     :map-fn
     (lambda (id document)
       (declare (ignore id))
       (push (%catalog-value-index-spec
              (%tek9-call "DOC-VALUE" document))
             values)))
    (sort values #'string< :key #'kb-index-spec-name)))

(defun %register-rehydrated-index (kb spec)
  (let* ((resolved
           (resolve-index-spec
            (starintel-kb-spec-ir kb)
            (copy-kb-index-spec spec)))
         (database (starintel-kb-database kb)))
    (%tek9-call "REGISTER-INDEX"
                database
                (kb-index-spec-name resolved)
                (%make-index-extractor resolved (starintel-kb-spec-ir kb))
                :key-type :string
                :unique (kb-index-spec-unique-p resolved)
                :multi-valued (kb-index-spec-multi-valued-p resolved))
    (setf (starintel-kb-indexes kb)
          (append (starintel-kb-indexes kb) (list resolved)))
    resolved))

(defun %rehydrate-runtime-indexes (kb)
  "Re-register durable runtime index definitions after Tek9 opens.

StarLang-declared indexes win if a runtime catalog entry with the same name is
still present, allowing a formerly dynamic index to be promoted into source."
  (dolist (spec (%persisted-runtime-index-specs kb) kb)
    (unless (%find-index-spec kb (kb-index-spec-name spec))
      (%register-rehydrated-index kb spec))))

;; Capture the underlying storage functions once. DEFVAR deliberately keeps the
;; first binding when this file is reloaded interactively, avoiding wrapper-on-
;; wrapper recursion during Lisp image development.
(defvar *open-starintel-kb-without-index-catalog*
  (symbol-function 'open-starintel-kb))

(defvar *define-index-without-index-catalog*
  (symbol-function 'define-index))

(defun open-starintel-kb (program spec-ir
                          &key
                            (path #P"./starintel-prolog-kb/")
                            max-dbs
                            (graph-name +default-graph-name+)
                            rebuild-indexes)
  "Open the Tek9 KB and rehydrate runtime-defined indexes from its catalog."
  ;; The underlying opener intentionally skips rebuild here. Rehydrate first so
  ;; :REBUILD-INDEXES rebuilds source-declared and runtime-catalog indexes once,
  ;; under one consistent definition set.
  (let ((kb
          (funcall *open-starintel-kb-without-index-catalog*
                   program spec-ir
                   :path path
                   :max-dbs max-dbs
                   :graph-name graph-name
                   :rebuild-indexes nil)))
    (handler-case
        (progn
          (%rehydrate-runtime-indexes kb)
          (when rebuild-indexes
            (dolist (spec (starintel-kb-indexes kb))
              (%tek9-call "REBUILD-INDEX-FAST"
                          (starintel-kb-database kb)
                          (kb-index-spec-name spec))))
          kb)
      (error (condition)
        (ignore-errors (close-starintel-kb kb))
        (error condition)))))

(defun %forget-process-index (kb spec)
  (ignore-errors
    (%tek9-call "UNREGISTER-INDEX"
                (starintel-kb-database kb)
                (kb-index-spec-name spec)))
  (setf (starintel-kb-indexes kb)
        (remove (kb-index-spec-name spec)
                (starintel-kb-indexes kb)
                :test #'string=
                :key #'kb-index-spec-name))
  kb)

(defun define-index (kb name &key source fields (kind :auto) (rebuild t))
  "Define, build, and durably catalog a new Tek9 index.

The definition is written only after registration/rebuild succeeds. On the next
OPEN-STARINTEL-KB it is re-registered against the same durable Tek9 index DB.
If catalog persistence fails, process-local registration is rolled back and the
operation fails closed."
  (let ((spec
          (funcall *define-index-without-index-catalog*
                   kb name
                   :source source
                   :fields fields
                   :kind kind
                   :rebuild rebuild)))
    (handler-case
        (progn
          (%persist-runtime-index-spec kb spec)
          spec)
      (error (condition)
        (%forget-process-index kb spec)
        (error condition)))))
