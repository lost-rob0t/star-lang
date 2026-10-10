;;;; Version 2 pure mapping contract. The .star source owns wire structure.
(in-package :starscrape.schema)

(defun scraper-vocabulary-version (vocabulary)
  (let ((name (getf (getf vocabulary :library) :name))
        (version (getf (getf vocabulary :library) :version)))
    (cond ((equal name "org.starscrape/scraper@1") 1)
          ((and (equal name "org.starscrape/scraper@2") (equal version "2.0.0")) 2)
          (t (fail-schema "Unsupported scraper vocabulary identity ~S." name)))))

(defun validate-v2-value (vocabulary type value)
  (unless (= 2 (scraper-vocabulary-version vocabulary))
    (fail-schema "Pure mapping requires org.starscrape/scraper@2."))
  (staractorprotocol:validate-portable-wire-value
   vocabulary (format nil "org.starscrape/scraper@2/~A" type) value "Mapping contract"))

(defun nonempty-unique-names (entries key context &key (allow-empty nil))
  (unless (and (listp entries) (or allow-empty entries))
    (fail-policy "~A must be a non-empty list." context))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry entries)
      (let ((name (getf entry key)))
        (validate-identifier name context)
        (when (gethash name seen)
          (fail-policy "Duplicate ~A ~S." context name))
        (setf (gethash name seen) t))))
  entries)

(defun named-entry (name entries context)
  (or (find name entries :key (lambda (entry) (getf entry :name)) :test #'equal)
      (fail-policy "Unknown ~A binding ~S." context name)))

(defun validate-json-field-path (path)
  ;; Closed traversal syntax, never a host-language expression or JSONPath evaluator.
  (unless (and (plusp (length path)) (char= (char path 0) #\$))
    (fail-policy "JSON field path must start with $."))
  (let ((index 1) (size (length path)))
    (labels ((identifier-start-p (c)
               (or (and (<= (char-code c) 127) (alpha-char-p c)) (char= c #\_)))
             (identifier-part-p (c)
               (or (identifier-start-p c) (and (char<= #\0 c) (char<= c #\9)))))
      (loop while (< index size) do
        (case (char path index)
          (#\.
           (incf index)
           (unless (and (< index size) (identifier-start-p (char path index)))
             (fail-policy "JSON field path contains an invalid property."))
           (loop while (and (< index size) (identifier-part-p (char path index)))
                 do (incf index)))
          (#\[
           (incf index)
           (let ((start index))
             (loop while (and (< index size) (find (char path index) "0123456789"))
                   do (incf index))
             (unless (and (> index start) (< index size) (char= (char path index) #\]))
               (fail-policy "JSON field path requires a nonnegative array index.")))
           (incf index))
          (otherwise (fail-policy "JSON field path contains unsupported syntax."))))))
  path)

(defun validate-mapping-selector (entry format &key field)
  (let ((kind (getf entry :selector-kind)) (selector (getf entry :selector)))
    (validate-selector selector "Mapping selector")
    (when (find (code-char 127) selector)
      (fail-policy "Mapping selector cannot contain control characters."))
    (if (eq format :json)
        (progn
          (unless (eq kind :json-path)
            (fail-policy "JSON input requires json-path selectors."))
          (validate-json-field-path selector)
          (when (and field (not (eq (getf entry :kind) :value)))
            (fail-policy "JSON field extraction requires kind value.")))
        (progn
          (unless (member kind '(:css :xpath))
            (fail-policy "HTML input requires css or xpath selectors."))
          (when (and field (eq (getf entry :kind) :value))
            (fail-policy "HTML field extraction cannot use kind value."))
          ;; Relative XPath is required for fields so row matching cannot
          ;; silently bind another row. Runtimes must enforce subtree membership.
          (when (and field (eq kind :xpath)
                     (not (char= (char selector 0) #\.)))
            (fail-policy "Row-scoped XPath fields must begin with dot."))))
    (when field
      (if (eq (getf entry :kind) :attribute)
          (progn
            (validate-selector (getf entry :attribute) "Extraction attribute")
            (when (find (code-char 127) (getf entry :attribute))
              (fail-policy "Extraction attribute cannot contain control characters.")))
          (when (getf entry :attribute)
            (fail-policy "Only attribute extractors may declare attribute.")))
      (when (and (member :transform entry) (null (getf entry :transform)))
        (fail-policy "Declared transform list must be non-empty."))
      (validate-transform-list (getf entry :transform)))))

(defun canonical-mapping-vocabulary ()
  ;; Reuse the canonical .star compiler, not a copied dtype/field registry.
  (load-scraper-vocabulary
   (merge-pathnames "../specs/starintel/0.10.1/core.star"
                    (asdf:system-source-directory :star-scrape))
   :expected-name "org.starintel/core@1"))

(defun canonical-document-contract (canonical name)
  (let ((contract (staractorprotocol:portable-manifest-type-contract
                   canonical (format nil "org.starintel/core@1/~A" name))))
    (unless (and contract (eq (getf contract :kind) :document))
      (fail-policy "Unknown canonical StarIntel document type ~S." name))
    contract))

(defun canonical-document-fields (canonical contract)
  (append (getf contract :fields)
          (when (getf contract :extends)
            (canonical-document-fields
             canonical
             (staractorprotocol:portable-manifest-type-contract
              canonical (getf contract :extends))))))

(defun canonical-subtype-p (canonical contract expected)
  (or (equal (getf contract :name) expected)
      (and (getf contract :extends)
           (canonical-subtype-p
            canonical (staractorprotocol:portable-manifest-type-contract
                       canonical (getf contract :extends)) expected))))

(defun validate-mapping-plan-gate (plan)
  (let* ((scopes (getf plan :scopes)) (documents (getf plan :documents))
         (relations (getf plan :relations))
         (canonical (canonical-mapping-vocabulary)))
    (nonempty-unique-names scopes :name "row scope")
    (nonempty-unique-names documents :name "document mapping")
    (nonempty-unique-names relations :name "relation mapping" :allow-empty t)
    (dolist (scope scopes)
      (validate-mapping-selector scope (getf plan :input-format))
      (nonempty-unique-names (getf scope :fields) :name "extraction field")
      (dolist (field (getf scope :fields))
        (validate-extracted-field-name (getf field :name) "Extraction field name")
        (validate-mapping-selector field (getf plan :input-format) :field t)))
    (dolist (document documents)
      (let* ((scope (named-entry (getf document :scope) scopes "row scope"))
             (fields (getf scope :fields))
             (keys (getf document :natural-key))
             (contract (canonical-document-contract canonical (getf document :document-type)))
             (canonical-fields (canonical-document-fields canonical contract)))
        (unless (and keys (= (length keys) (length (remove-duplicates keys :test #'equal))))
          (fail-policy "Natural key must contain distinct extracted field names."))
        (dolist (key keys)
          (let ((field (named-entry key fields "natural key")))
            (unless (and (eq (getf field :required) t) (not (eq (getf field :many) t)))
              (fail-policy "Natural key fields must be required scalar extractions."))))
        (nonempty-unique-names (getf document :fields) :target "mapped target field")
        (dolist (mapping (getf document :fields))
          (named-entry (getf mapping :source) fields "extracted field")
          (validate-extracted-field-name (getf mapping :target) "Mapped target field")
          (unless (find (getf mapping :target) canonical-fields
                        :key (lambda (f) (getf f :name)) :test #'equal)
            (fail-policy "Unknown canonical field ~S for ~S."
                         (getf mapping :target) (getf document :document-type)))
          (when (member (getf mapping :target) '("id" "dataset" "dtype" "schemaVersion") :test #'equal)
            (fail-policy "Canonical identity/envelope fields are supplied by the mapper.")))))
    (dolist (relation relations)
      (when (find (getf relation :name) documents :key (lambda (d) (getf d :name)) :test #'equal)
        (fail-policy "Document and relation names must be distinct."))
      (named-entry (getf relation :scope) scopes "relation row scope")
      (let ((predicate (find (format nil "org.starintel/core@1/~A" (getf relation :predicate))
                             (getf canonical :predicates)
                             :key (lambda (p) (getf p :name)) :test #'equal)))
        (unless predicate (fail-policy "Unknown canonical relation predicate."))
        (dolist (binding '((:source-document . :source) (:destination-document . :destination)))
          (let ((document (named-entry (getf relation (car binding)) documents "relation document")))
            (unless (equal (getf relation :scope) (getf document :scope))
              (fail-policy "Relation endpoints must bind emitted documents in the same row scope."))
            (unless (canonical-subtype-p canonical
                                        (canonical-document-contract canonical (getf document :document-type))
                                        (getf predicate (cdr binding)))
              (fail-policy "Relation endpoint type does not satisfy canonical predicate.")))))))
  plan)

(defun compile-mapping-manifest (vocabulary mapping-plan)
  "Compile pure offline mapping independently of acquisition or credentials."
  (validate-v2-value vocabulary "mapping-plan" mapping-plan)
  (validate-mapping-plan-gate mapping-plan)
  (list :manifest-schema "org.starscrape/mapping-manifest@2"
        :wire-version 2 :vocabulary vocabulary :mapping-plan mapping-plan))

(defun validate-scraper-v2-policy-gate (policy)
  (let* ((request (policy-area policy :request "Request"))
         (auth-ref (getf request :auth-ref)))
    (validate-request-policy-gate request)
    (when auth-ref
      (unless (and (stringp auth-ref) (> (length auth-ref) 11)
                   (string= "secret-ref:" auth-ref :end2 11))
        (fail-policy "Authentication must be an opaque secret-ref reference, never a literal."))
      (validate-identifier (subseq auth-ref 11) "Authentication reference")))
  (validate-mapping-plan-gate (getf policy :mapping-plan))
  (let* ((parser (if (eq (getf (getf policy :mapping-plan) :input-format) :json)
                     :parse-json :parse-html))
         (expected (list :net-https-fetch parser :rate-limit-scheduler
                         :crawl-budget :starintel-documents))
         (actual (getf policy :capabilities)))
    (unless (and (= (length actual) (length expected))
                 (every (lambda (capability) (member capability actual)) expected))
      (fail-policy "V2 acquisition requires exactly its network, format parser, rate, budget and document capabilities.")))
  (validate-pagination-gate (policy-area policy :pagination "Pagination"))
  (validate-robots-gate (policy-area policy :robots "Robots"))
  (validate-provenance-gate (policy-area policy :provenance "Provenance"))
  policy)

(defun scraper-v2-manifest-json (manifest)
  ;; Reuse the canonical typed wire codec so false and empty arrays retain
  ;; their types. The generic vocabulary codec intentionally omits NIL
  ;; metadata and is therefore unsuitable for policy payloads.
  (let* ((vocabulary (getf manifest :vocabulary))
         (pure-p (equal (getf manifest :manifest-schema)
                        "org.starscrape/mapping-manifest@2"))
         (key (if pure-p :mapping-plan :policy))
         (type (if pure-p "mapping-plan" "scraper-policy")))
    (unless (or pure-p (equal (getf manifest :manifest-schema)
                             "org.starscrape/scraper-manifest@2"))
      (fail-schema "Unsupported v2 manifest envelope."))
    (validate-v2-value vocabulary type (getf manifest key))
    (starcanonicaljson:canonical-json-string
     (starcanonicaljson:make-json-object
      (list
       (cons "manifestSchema" (getf manifest :manifest-schema))
       (cons "wireVersion" 2)
       (cons "vocabulary"
             (starcanonicaljson::starlang-manifest-json-object vocabulary vocabulary))
       (cons (if pure-p "mappingPlan" "policy")
             (starcanonicaljson::starlang-wire-json-value-for-type
              vocabulary (format nil "org.starscrape/scraper@2/~A" type)
              (getf manifest key) "Scraper v2 payload")))))))
