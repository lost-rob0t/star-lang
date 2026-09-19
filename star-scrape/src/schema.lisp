;;;; Scraper schema contract compilation (star-lang#137).
;;;;
;;;; The versioned .star vocabulary (fixtures/star-scrape-core.star) is the
;;;; schema authority: every bound, enum, and field contract lives there and
;;;; enters only through the closed StarLang parser. This module loads that
;;;; vocabulary into a portable manifest, validates a scraper policy
;;;; (constructed by Lisp consumers as plain data, never eval) against it
;;;; with the generic portable-wire validator, applies the closed scraper
;;;; policy gate for rules the type vocabulary cannot express, and emits a
;;;; deterministic data-only scraper manifest that serializes to canonical
;;;; JSON.

(in-package :starscrape.schema)

(defparameter +scraper-manifest-schema+ "org.starscrape/scraper-manifest@1")
(defconstant +scraper-manifest-wire-version+ 1)
(defparameter +scraper-policy-type-name+ "scraper-policy")

(define-condition scraper-schema-error (error)
  ((message :initarg :message :reader scraper-schema-error-message))
  (:report
   (lambda (condition stream)
     (write-string (scraper-schema-error-message condition) stream))))

(define-condition scraper-policy-error (scraper-schema-error) ())

(defun fail-schema (control &rest arguments)
  (error 'scraper-schema-error
         :message (apply #'format nil control arguments)))

(defun fail-policy (control &rest arguments)
  (error 'scraper-policy-error
         :message (apply #'format nil control arguments)))

(defun load-scraper-vocabulary (pathname &key expected-name)
  "Load the scraper vocabulary .star file through the closed StarLang
pipeline (read, expand, validate, compile) and return its portable
manifest as the first value and the compiled spec-library IR as the
second. EXPECTED-NAME, when given, must equal the spec-library name."
  (let ((ir (starlangcompiler:load-star-form pathname)))
    (unless (and (listp ir) (eq (getf ir :kind) :spec-library))
      (fail-schema
       "Scraper vocabulary must compile to a spec-library, received ~S."
       (type-of ir)))
    (when (and expected-name (not (string= (getf ir :name) expected-name)))
      (fail-schema
       "Scraper vocabulary library is ~A, expected ~A."
       (getf ir :name) expected-name))
    (values (starlangcompiler:emit-portable-manifest ir nil) ir)))

(defun scraper-policy-type-name (vocabulary)
  (let ((library (getf vocabulary :library)))
    (unless (and (listp library) (stringp (getf library :name)))
      (fail-schema "Scraper vocabulary manifest lacks a library identity."))
    (format nil "~A/~A" (getf library :name) +scraper-policy-type-name+)))

(defun compile-scraper-manifest (vocabulary policy)
  "Validate POLICY (plain Lisp data; keyword plists, lists, strings,
integers, booleans) against the portable VOCABULARY manifest and emit
the deterministic data-only scraper manifest. The generic portable-wire
validator enforces every vocabulary contract (types, required fields,
unknown-field rejection, enum membership, scalar bounds); the closed
policy gate then enforces the domain rules the vocabulary cannot
express. Both must pass before the manifest exists."
  (unless (and (listp vocabulary) (listp (getf vocabulary :types)))
    (fail-schema
     "Scraper manifest compilation requires a portable vocabulary manifest."))
  (let ((type-name (scraper-policy-type-name vocabulary)))
    (unless (staractorprotocol:portable-manifest-type-contract
             vocabulary type-name)
      (fail-schema "Scraper vocabulary does not declare ~A." type-name))
    (staractorprotocol:validate-portable-wire-value
     vocabulary type-name policy "Scraper policy"))
  (validate-scraper-policy-gate policy)
  (list :manifest-schema +scraper-manifest-schema+
        :wire-version +scraper-manifest-wire-version+
        :vocabulary vocabulary
        :policy policy))

(defun scraper-manifest-json (manifest)
  "Serialize a scraper manifest to canonical JSON (RFC 8785-style
sorted keys, lower camelCase field keys)."
  (starcanonicaljson:canonical-manifest-json manifest))

;;;; Closed scraper policy gate.
;;;;
;;;; The generic wire validator does not interpret scalar :pattern
;;;; constraints, so every security-critical string shape is re-checked
;;;; here against the same contract the vocabulary declares.

(defun policy-plist-p (value)
  (staractorprotocol:portable-keyword-plist-p value))

(defun policy-area (policy key context)
  (let ((value (getf policy key)))
    (unless (policy-plist-p value)
      (fail-policy "~A policy area must be an object." context))
    value))

(defun validate-scraper-policy-gate (policy)
  (validate-request-policy-gate (policy-area policy :request "Request"))
  (validate-extraction-gate (policy-area policy :extraction "Extraction"))
  (validate-mapping-gate (getf policy :mapping))
  (validate-pagination-gate (policy-area policy :pagination "Pagination"))
  (validate-robots-gate (policy-area policy :robots "Robots"))
  (validate-provenance-gate (policy-area policy :provenance "Provenance"))
  policy)

(defun ascii-alphanumeric-p (character)
  (and (<= 0 (char-code character) 127)
       (alphanumericp character)))

(defun non-control-string-p (value limit)
  (and (stringp value)
       (plusp (length value))
       (<= (length value) limit)
       (notany (lambda (character) (<= (char-code character) 31)) value)))

(defun validated-text (value limit context)
  (unless (non-control-string-p value limit)
    (fail-policy
     "~A must be a non-empty string of at most ~D characters without ~
      control characters."
     context limit))
  value)

(defun validate-selector (value context)
  (validated-text value 256 context))

(defun validate-identifier (value context)
  (unless
      (and (stringp value)
           (plusp (length value))
           (<= (length value) 128)
           (ascii-alphanumeric-p (char value 0))
           (every
            (lambda (character)
              (or (ascii-alphanumeric-p character)
                  (member character '(#\. #\_ #\-))))
            value))
    (fail-policy "~A must be a bounded identifier." context))
  value)

(defun validate-extracted-field-name (value context)
  (unless
      (and (stringp value)
           (plusp (length value))
           (<= (length value) 64)
           (let ((first (char value 0)))
             (and (<= (char-code first) 127)
                  (char<= #\a first)
                  (char<= first #\z)))
           (every #'ascii-alphanumeric-p value))
    (fail-policy
     "~A must use lower camelCase (initial lowercase ASCII letter, ASCII ~
      alphanumerics)."
     context))
  value)

(defun validate-document-type (value)
  (unless
      (and (stringp value)
           (plusp (length value))
           (<= (length value) 64)
           (let ((first (char value 0)))
             (and (<= (char-code first) 127)
                  (char<= #\a first)
                  (char<= first #\z)))
           (every
            (lambda (character)
              (or (ascii-alphanumeric-p character)
                  (char= character #\-)))
            value))
    (fail-policy
     "Document mapping documentType must be a lowercase ASCII identifier."))
  value)

(defun validate-allowed-origin (origin)
  (unless (and (stringp origin) (>= (length origin) 9))
    (fail-policy "Allowed origin must be a string."))
  (unless (string= origin "https://" :end1 8 :end2 8)
    (fail-policy
     "Allowed origin ~S must use the https scheme." origin))
  (let* ((authority (subseq origin 8))
         (terminator
           (position-if
            (lambda (character)
              (member character '(#\/ #\? #\# #\@)))
            authority)))
    (when terminator
      (fail-policy
       "Allowed origin ~S must be a bare scheme and authority with no ~
        path, query, fragment, or userinfo."
       origin))
    (validate-origin-authority authority origin))
  origin)

(defun validate-origin-authority (authority origin)
  (let ((host authority)
        (port nil))
    (let ((colon (position #\: authority)))
      (when colon
        (setf host (subseq authority 0 colon)
              port (subseq authority (1+ colon)))
        (unless
            (and (plusp (length port))
                 (<= (length port) 5)
                 (every #'digit-char-p port))
          (fail-policy "Allowed origin ~S has an invalid port." origin))))
    ;; Hostname rules double as an SSRF guard: bare IP literals (for
    ;; example loopback or link-local metadata addresses) carry no
    ;; alphabetic character and are rejected.
    (unless
        (and (plusp (length host))
             (<= (length host) 253)
             (position-if #'alpha-char-p host)
             (find #\. host)
             (not (char= (char host 0) #\.))
             (not (char= (char host (1- (length host))) #\.))
             (not (search ".." host))
             (every
              (lambda (character)
                (or (ascii-alphanumeric-p character)
                    (member character '(#\. #\-))))
              host))
      (fail-policy
       "Allowed origin ~S must use a public hostname, not an address ~
        literal or bare name."
       origin))))

(defun validate-media-token (token)
  (and (plusp (length token))
       (<= (length token) 127)
       (every
        (lambda (character)
          (or (ascii-alphanumeric-p character)
              (member character
                      '(#\$ #\! #\# #\& #\^ #\_ #\. #\+ #\-))))
        token)))

(defun validate-content-type (value)
  (unless (and (stringp value) (<= 3 (length value) 255))
    (fail-policy "Allowed content type must be a bounded string."))
  (when (find-if
         (lambda (character)
           (member character '(#\; #\space #\tab #\newline #\return)))
         value)
    (fail-policy
     "Allowed content type ~S must not carry parameters or whitespace."
     value))
  (let ((slash (position #\/ value)))
    (unless (and slash (plusp slash) (< (1+ slash) (length value)))
      (fail-policy "Allowed content type ~S must be type/subtype." value))
    (unless
        (and (validate-media-token (subseq value 0 slash))
             (validate-media-token (subseq value (1+ slash))))
      (fail-policy
       "Allowed content type ~S has invalid type or subtype tokens."
       value)))
  value)

(defun validate-request-policy-gate (request)
  ;; SSRF posture is deny-by-default; the vocabulary enum carries allow
  ;; for forward compatibility but the gate only ever accepts forbid.
  (unless (eq (getf request :private-network) :forbid)
    (fail-policy
     "SSRF protection: request policy privateNetwork must be forbid."))
  (let ((origins (getf request :allowed-origins)))
    (unless (and (listp origins) origins)
      (fail-policy
       "Request policy must allow at least one origin."))
    (dolist (origin origins)
      (validate-allowed-origin origin)))
  (let ((content-types (getf request :allowed-content-types)))
    (unless (and (listp content-types) content-types)
      (fail-policy
       "Request policy must declare at least one allowed content type."))
    (dolist (entry content-types)
      (validate-content-type entry)))
  request)

(defun validate-transform-list (transform)
  (when transform
    (unless (and (listp transform) transform)
      (fail-policy "Extraction field transform must be a non-empty list when declared.")))
  transform)

(defun validate-extraction-gate (extraction)
  (let ((fields (getf extraction :fields)))
    (unless (and (listp fields) fields)
      (fail-policy "Extraction plan must declare at least one field."))
    (dolist (field fields)
      (unless (policy-plist-p field)
        (fail-policy "Extraction field must be an object."))
      (validate-extracted-field-name
       (getf field :name) "Extraction field name")
      (validate-selector (getf field :selector) "Extraction field selector")
      (when (eq (getf field :kind) :attribute)
        (validate-selector
         (getf field :attribute)
         "Attribute extraction field attribute name"))
      (validate-transform-list (getf field :transform))))
  extraction)

(defun validate-mapping-gate (mappings)
  (unless (and (listp mappings) mappings)
    (fail-policy "Document mapping must declare at least one mapping."))
  (dolist (mapping mappings)
    (unless (policy-plist-p mapping)
      (fail-policy "Document mapping must be an object."))
    (validate-document-type (getf mapping :document-type))
    (let ((fields (getf mapping :fields)))
      (unless (and (listp fields) fields)
        (fail-policy "Document mapping must map at least one field."))
      (dolist (entry fields)
        (unless (policy-plist-p entry)
          (fail-policy "Field mapping must be an object."))
        (validate-extracted-field-name
         (getf entry :source) "Field mapping source")
        (validate-extracted-field-name
         (getf entry :target) "Field mapping target"))))
  mappings)

(defun validate-pagination-gate (pagination)
  ;; Pagination kind was already constrained to the vocabulary enum, so
  ;; the gate cross-checks selector and parameter presence only.
  (let ((kind (getf pagination :kind))
        (next-selector (getf pagination :next-selector))
        (page-parameter (getf pagination :page-parameter)))
    (ecase kind
      (:none
       (when (or next-selector page-parameter)
         (fail-policy
          "Pagination kind none must not declare selectors or parameters.")))
      (:next-link
       (unless next-selector
         (fail-policy "Pagination kind next-link requires nextSelector."))
       (validate-selector next-selector "Pagination nextSelector"))
      (:page-param
       (unless page-parameter
         (fail-policy
          "Pagination kind page-param requires pageParameter."))
       (validate-identifier
        page-parameter "Pagination pageParameter"))))
  pagination)

(defun validate-robots-gate (robots)
  (validated-text (getf robots :user-agent) 128 "Robots policy userAgent")
  robots)

(defun validate-provenance-gate (provenance)
  (validated-text (getf provenance :collector) 256 "Provenance collector")
  (let ((version (getf provenance :collector-version)))
    (when version
      (validate-identifier version "Provenance collectorVersion")))
  (let ((license (getf provenance :source-license)))
    (when license
      (validated-text license 256 "Provenance sourceLicense")))
  (let ((method (getf provenance :collection-method)))
    (when method
      (validate-identifier method "Provenance collectionMethod")))
  provenance)
