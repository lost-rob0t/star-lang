(in-package :starprologkb)

(define-condition star-prolog-kb-error (error)
  ((message :initarg :message :reader star-prolog-kb-error-message)
   (span :initarg :span :initform nil :reader %star-prolog-kb-error-span))
  (:report (lambda (condition stream)
             (write-string (star-prolog-kb-error-message condition) stream))))

(define-condition prolog-kb-grammar-error (star-prolog-kb-error) ())
(define-condition prolog-kb-schema-error (star-prolog-kb-error) ())
(define-condition tek9-unavailable-error (star-prolog-kb-error) ())

(defstruct kb-schema-ref
  alias
  source
  version
  digest)

(defstruct kb-index-spec
  name
  source
  selectors
  (kind :auto)
  unique-p
  multi-valued-p
  automatic-p)

(defstruct prolog-source-block
  name
  source
  (kind :rules)
  text
  span)

(defstruct prolog-kb-program
  name
  version
  (runtime :tek9)
  (persistence :persistent)
  (protocol "star.logic.prolog/1")
  schema
  indexes
  prolog-blocks
  source-map)

(defun %grammar-fail (syntax control &rest arguments)
  (error 'prolog-kb-grammar-error
         :message (apply #'format nil control arguments)
         :span (and syntax
                    (star-lang.compiler.core:star-syntax-p syntax)
                    (star-lang.compiler.core:star-syntax-span syntax))))

(defun %syntax-list-p (syntax)
  (star-lang.compiler.core:syntax-list-p syntax))

(defun %elements (syntax)
  (star-lang.compiler.core:syntax-elements syntax))

(defun %datum (syntax)
  (star-lang.compiler.core:star-syntax-to-datum syntax))

(defun %head (syntax)
  (star-lang.compiler.core:syntax-head-name syntax))

(defun %atom-string (syntax context)
  (unless (and (star-lang.compiler.core:star-syntax-p syntax)
               (not (%syntax-list-p syntax)))
    (%grammar-fail syntax "~A must be an atom." context))
  (let ((value (%datum syntax)))
    (unless (stringp value)
      (%grammar-fail syntax "~A must be a string or identifier." context))
    value))

(defun %plist-pairs (syntax context)
  (unless (%syntax-list-p syntax)
    (%grammar-fail syntax "~A options must be a list." context))
  (let ((elements (%elements syntax)))
    (unless (evenp (length elements))
      (%grammar-fail syntax "~A options must contain key/value pairs." context))
    (loop for (key value) on elements by #'cddr
          do (unless (and (star-lang.compiler.core:star-syntax-p key)
                          (eq (star-lang.compiler.core:star-syntax-kind key)
                              :keyword))
               (%grammar-fail key "~A option key must be a StarLang keyword." context))
          collect (cons (%datum key) value))))

(defun %option (pairs key &key required context)
  (let ((entry (assoc key pairs :test #'eq)))
    (cond
      (entry (cdr entry))
      (required
       (%grammar-fail nil "~A requires option ~S." context key))
      (t nil))))

(defun %ensure-known-options (pairs allowed context)
  (dolist (pair pairs)
    (unless (member (car pair) allowed :test #'eq)
      (%grammar-fail (cdr pair)
                     "~A does not support option ~S."
                     context (car pair)))))

(defun %keywordish-name (syntax context)
  (let ((name (string-downcase (%atom-string syntax context))))
    (intern (string-upcase name) :keyword)))

(defun %compile-schema-ref (syntax)
  (unless (and (%syntax-list-p syntax)
               (= (length (%elements syntax)) 3)
               (string= (or (%head syntax) "") "schema"))
    (%grammar-fail syntax
                   "Schema declaration is (schema ALIAS (:source STRING :version STRING [:digest STRING]))."))
  (destructuring-bind (operator alias options) (%elements syntax)
    (declare (ignore operator))
    (let* ((pairs (%plist-pairs options "schema"))
           (source-node (%option pairs :source :required t :context "schema"))
           (version-node (%option pairs :version :required t :context "schema"))
           (digest-node (%option pairs :digest :context "schema")))
      (%ensure-known-options pairs '(:source :version :digest) "schema")
      (let ((source (%atom-string source-node "schema :source"))
            (version (%atom-string version-node "schema :version"))
            (digest (and digest-node (%atom-string digest-node "schema :digest"))))
        (when (and digest
                   (not (and (>= (length digest) 7)
                             (string= "sha256:" digest :end2 7))))
          (%grammar-fail digest-node "Schema digest must use sha256:."))
        (make-kb-schema-ref
         :alias (%atom-string alias "schema alias")
         :source source
         :version version
         :digest digest)))))

(defun %selector (syntax)
  (cond
    ((%syntax-list-p syntax)
     (let ((parts (%elements syntax)))
       (when (null parts)
         (%grammar-fail syntax "Index field path cannot be empty."))
       (mapcar (lambda (part)
                 (%atom-string part "index field path component"))
               parts)))
    (t
     (list (%atom-string syntax "index field")))))

(defun %compile-index (syntax)
  (unless (and (%syntax-list-p syntax)
               (= (length (%elements syntax)) 3)
               (string= (or (%head syntax) "") "index"))
    (%grammar-fail syntax
                   "Index declaration is (index NAME (:source DOCUMENT :fields (FIELD...) [:kind auto|multi|unique]))."))
  (destructuring-bind (operator name options) (%elements syntax)
    (declare (ignore operator))
    (let* ((pairs (%plist-pairs options "index"))
           (source-node (%option pairs :source :required t :context "index"))
           (fields-node (%option pairs :fields :required t :context "index"))
           (kind-node (%option pairs :kind :context "index")))
      (%ensure-known-options pairs '(:source :fields :kind) "index")
      (unless (%syntax-list-p fields-node)
        (%grammar-fail fields-node "Index :fields must be a list."))
      (let* ((selectors (mapcar #'%selector (%elements fields-node)))
             (kind (if kind-node
                       (%keywordish-name kind-node "index :kind")
                       :auto)))
        (when (null selectors)
          (%grammar-fail fields-node "Index :fields cannot be empty."))
        (unless (member kind '(:auto :multi :unique) :test #'eq)
          (%grammar-fail kind-node
                         "Index :kind must be auto, multi, or unique."))
        (make-kb-index-spec
         :name (%atom-string name "index name")
         :source (%atom-string source-node "index :source")
         :selectors selectors
         :kind kind
         :unique-p (eq kind :unique)
         :multi-valued-p (not (eq kind :unique))
         :automatic-p nil)))))

(defun %compile-prolog-block (syntax)
  (unless (and (%syntax-list-p syntax)
               (= (length (%elements syntax)) 4)
               (string= (or (%head syntax) "") "prolog"))
    (%grammar-fail syntax
                   "Prolog declaration is (prolog NAME (:source STRING [:kind source|rules|bootstrap]) RAW-PROLOG-STRING)."))
  (destructuring-bind (operator name options text) (%elements syntax)
    (declare (ignore operator))
    (let* ((pairs (%plist-pairs options "prolog"))
           (source-node (%option pairs :source :required t :context "prolog"))
           (kind-node (%option pairs :kind :context "prolog"))
           (kind (if kind-node
                     (%keywordish-name kind-node "prolog :kind")
                     :rules)))
      (%ensure-known-options pairs '(:source :kind) "prolog")
      (unless (member kind '(:source :rules :bootstrap) :test #'eq)
        (%grammar-fail kind-node
                       "Prolog :kind must be source, rules, or bootstrap."))
      (unless (and (star-lang.compiler.core:star-syntax-p text)
                   (eq (star-lang.compiler.core:star-syntax-kind text) :string))
        (%grammar-fail text "Raw Prolog body must be a StarLang string literal."))
      (make-prolog-source-block
       :name (%atom-string name "prolog block name")
       :source (%atom-string source-node "prolog :source")
       :kind kind
       :text (%datum text)
       :span (star-lang.compiler.core:star-syntax-span text)))))

(defun %compile-top-options (syntax)
  (let* ((pairs (%plist-pairs syntax "prolog-kb"))
         (version-node (%option pairs :version :required t :context "prolog-kb"))
         (runtime-node (%option pairs :runtime :required t :context "prolog-kb"))
         (persistence-node
           (%option pairs :persistence :required t :context "prolog-kb"))
         (protocol-node (%option pairs :protocol :context "prolog-kb")))
    (%ensure-known-options pairs '(:version :runtime :persistence :protocol)
                           "prolog-kb")
    (let ((version (%atom-string version-node "prolog-kb :version"))
          (runtime (%keywordish-name runtime-node "prolog-kb :runtime"))
          (persistence
            (%keywordish-name persistence-node "prolog-kb :persistence"))
          (protocol (if protocol-node
                        (%atom-string protocol-node "prolog-kb :protocol")
                        "star.logic.prolog/1")))
      (unless (eq runtime :tek9)
        (%grammar-fail runtime-node
                       "StarIntel Prolog KB runtime must be tek9."))
      (unless (eq persistence :persistent)
        (%grammar-fail persistence-node
                       "StarIntel Prolog KB persistence must be persistent."))
      (values version runtime persistence protocol))))

(defun %ensure-unique-names (items name-reader kind)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (item items)
      (let ((name (funcall name-reader item)))
        (when (gethash name seen)
          (%grammar-fail nil "Duplicate ~A named ~A." kind name))
        (setf (gethash name seen) t)))))

(defun compile-prolog-kb (syntax)
  "Compile one real StarLang syntax tree using the Prolog-KB extension grammar.

The source is read by the canonical StarLang reader and macro expander. This
package validates only the extension form; it does not introduce another reader."
  (unless (star-lang.compiler.core:star-syntax-p syntax)
    (%grammar-fail nil "COMPILE-PROLOG-KB requires a StarLang syntax object."))
  (let ((expanded (starlangcompiler:expand-star-syntax syntax)))
    (unless (and (%syntax-list-p expanded)
                 (>= (length (%elements expanded)) 3)
                 (string= (or (%head expanded) "") "prolog-kb"))
      (%grammar-fail expanded "Expected one prolog-kb form."))
    (destructuring-bind (operator name options &rest declarations)
        (%elements expanded)
      (declare (ignore operator))
      (unless (eq (star-lang.compiler.core:star-syntax-kind name) :string)
        (%grammar-fail name "Prolog KB name must be a string."))
      (multiple-value-bind (version runtime persistence protocol)
          (%compile-top-options options)
        (let ((schema nil)
              (indexes '())
              (blocks '()))
          (dolist (declaration declarations)
            (let ((head (%head declaration)))
              (cond
                ((string= (or head "") "schema")
                 (when schema
                   (%grammar-fail declaration
                                  "A prolog-kb may declare exactly one schema."))
                 (setf schema (%compile-schema-ref declaration)))
                ((string= (or head "") "index")
                 (push (%compile-index declaration) indexes))
                ((string= (or head "") "prolog")
                 (push (%compile-prolog-block declaration) blocks))
                (t
                 (%grammar-fail declaration
                                "Unknown prolog-kb declaration ~S."
                                (and declaration (%datum declaration)))))))
          (unless schema
            (%grammar-fail expanded "A prolog-kb requires one schema declaration."))
          (setf indexes (nreverse indexes)
                blocks (nreverse blocks))
          (%ensure-unique-names indexes #'kb-index-spec-name "index")
          (%ensure-unique-names blocks #'prolog-source-block-name "Prolog block")
          (make-prolog-kb-program
           :name (%datum name)
           :version version
           :runtime runtime
           :persistence persistence
           :protocol protocol
           :schema schema
           :indexes indexes
           :prolog-blocks blocks
           :source-map
           (star-lang.compiler.core:star-syntax-source-map expanded)))))))

(defun compile-prolog-kb-source (source &key source-id pathname origin limits)
  "Read SOURCE with StarLang's canonical reader, then compile Prolog-KB grammar."
  (compile-prolog-kb
   (starlangcompiler:read-star-syntax
    source
    :source-id (or source-id "<prolog-kb>")
    :pathname pathname
    :origin origin
    :limits limits)))

(defun load-prolog-kb-file (pathname &key limits)
  "Load and compile one .star Prolog-KB file through the canonical StarLang reader."
  (let ((path (truename pathname)))
    (unless (and (pathname-type path)
                 (string-equal (pathname-type path) "star"))
      (error 'prolog-kb-grammar-error
             :message "Prolog KB source must use the .star extension."))
    (compile-prolog-kb-source
     (uiop:read-file-string path)
     :source-id (namestring path)
     :pathname path
     :limits limits)))