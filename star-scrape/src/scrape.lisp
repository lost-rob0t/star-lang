(in-package :starscrape)

(define-condition scrape-error (error)
  ((message :initarg :message :reader scrape-error-message))
  (:report
   (lambda (condition stream)
     (write-string (scrape-error-message condition) stream))))

(define-condition html-backend-unavailable-error (scrape-error) ())
(define-condition scrape-extraction-error (scrape-error) ())

(defun fail-scrape (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defstruct (html-adapter
            (:constructor %make-html-adapter
                (&key name parse-fn select-fn text-fn attribute-fn)))
  (name "" :type string)
  parse-fn
  select-fn
  text-fn
  attribute-fn)

(defun make-html-adapter (name &key parse select text attribute)
  (unless (and (stringp name) (> (length name) 0))
    (fail-scrape 'scrape-extraction-error
                 "HTML adapter name must be a non-empty string."))
  (dolist (entry (list (cons "parse" parse)
                       (cons "select" select)
                       (cons "text" text)
                       (cons "attribute" attribute)))
    (unless (functionp (cdr entry))
      (fail-scrape 'scrape-extraction-error
                   "HTML adapter ~A operation must be a function."
                   (car entry))))
  (%make-html-adapter
   :name name
   :parse-fn parse
   :select-fn select
   :text-fn text
   :attribute-fn attribute))

(defstruct (scrape-field
            (:constructor %make-scrape-field
                (&key name selector extractor attribute many-p required-p)))
  name
  (selector "" :type string)
  (extractor :text :type keyword)
  attribute
  (many-p nil :type boolean)
  (required-p nil :type boolean))

(defun make-scrape-field
    (name selector
     &key
       (extractor :text)
       attribute
       many
       required)
  (unless (and (stringp selector) (> (length selector) 0))
    (fail-scrape 'scrape-extraction-error
                 "Scrape selector for ~S must be a non-empty string."
                 name))
  (unless (member extractor '(:text :attribute) :test #'eq)
    (fail-scrape 'scrape-extraction-error
                 "Scrape field ~S has unsupported extractor ~S."
                 name
                 extractor))
  (when (and (eq extractor :attribute)
             (not (and (stringp attribute) (> (length attribute) 0))))
    (fail-scrape 'scrape-extraction-error
                 "Attribute scrape field ~S requires an attribute name."
                 name))
  (%make-scrape-field
   :name name
   :selector selector
   :extractor extractor
   :attribute attribute
   :many-p (not (null many))
   :required-p (not (null required))))

(defstruct (scrape-plan
            (:constructor %make-scrape-plan
                (&key name url fields headers request-options)))
  name
  (url "" :type string)
  fields
  headers
  request-options)

(defun make-scrape-plan (name url fields &key headers request-options)
  (unless (and (stringp url) (> (length url) 0))
    (fail-scrape 'scrape-extraction-error "Scrape URL must be a non-empty string."))
  (unless (and (listp fields) (every #'scrape-field-p fields))
    (fail-scrape 'scrape-extraction-error
                 "Scrape plan fields must be a list of SCRAPE-FIELD values."))
  (%make-scrape-plan
   :name name
   :url url
   :fields fields
   :headers headers
   :request-options request-options))

(defstruct (scrape-result
            (:constructor %make-scrape-result
                (&key plan-name url final-url status fields response-headers)))
  plan-name
  (url "" :type string)
  (final-url "" :type string)
  (status 0 :type (integer 0 999))
  fields
  response-headers)

(defun scrape-result-ref (result name &optional default)
  (let ((entry (assoc name (scrape-result-fields result) :test #'equal)))
    (if entry (cdr entry) default)))

(defun sequence-items (sequence)
  (loop for index below (length sequence)
        collect (elt sequence index)))

(defun extract-node-value (adapter field node)
  (ecase (scrape-field-extractor field)
    (:text
     (funcall (html-adapter-text-fn adapter) node))
    (:attribute
     (funcall (html-adapter-attribute-fn adapter)
              node
              (scrape-field-attribute field)))))

(defun extract-field (adapter root field)
  (let* ((nodes
           (funcall (html-adapter-select-fn adapter)
                    root
                    (scrape-field-selector field)))
         (items (if nodes (sequence-items nodes) '())))
    (when (and (null items) (scrape-field-required-p field))
      (fail-scrape 'scrape-extraction-error
                   "Required scrape field ~S matched no nodes for selector ~S."
                   (scrape-field-name field)
                   (scrape-field-selector field)))
    (if (scrape-field-many-p field)
        (mapcar (lambda (node) (extract-node-value adapter field node)) items)
        (when items
          (extract-node-value adapter field (first items))))))

(defun make-plan-request (plan)
  (apply #'starhttpport:make-http-request
         (scrape-plan-url plan)
         :method :get
         :headers (scrape-plan-headers plan)
         (scrape-plan-request-options plan)))

(defun execute-scrape (http-client html-adapter plan)
  (unless (html-adapter-p html-adapter)
    (fail-scrape 'scrape-extraction-error
                 "Expected an HTML adapter, received ~S."
                 html-adapter))
  (unless (scrape-plan-p plan)
    (fail-scrape 'scrape-extraction-error
                 "Expected a scrape plan, received ~S."
                 plan))
  (let ((response
          (starhttpport:perform-http-request
           http-client
           (make-plan-request plan))))
    (unless (starhttpport:http-response-success-p response)
      (fail-scrape 'scrape-extraction-error
                   "Scrape request for ~A returned HTTP ~D."
                   (scrape-plan-url plan)
                   (starhttpport:http-response-status response)))
    (unless (stringp (starhttpport:http-response-body response))
      (fail-scrape 'scrape-extraction-error
                   "Scrape response body for ~A is not text."
                   (scrape-plan-url plan)))
    (let* ((root
             (funcall (html-adapter-parse-fn html-adapter)
                      (starhttpport:http-response-body response)))
           (fields
             (mapcar
              (lambda (field)
                (cons (scrape-field-name field)
                      (extract-field html-adapter root field)))
              (scrape-plan-fields plan))))
      (%make-scrape-result
       :plan-name (scrape-plan-name plan)
       :url (scrape-plan-url plan)
       :final-url (starhttpport:http-response-final-url response)
       :status (starhttpport:http-response-status response)
       :fields fields
       :response-headers (starhttpport:http-response-headers response)))))

(defun ensure-html-system (system-name)
  (require :asdf)
  (let* ((package (find-package "ASDF"))
         (loader (and package (find-symbol "LOAD-SYSTEM" package))))
    (unless (and loader (fboundp loader))
      (fail-scrape 'html-backend-unavailable-error
                   "ASDF cannot load HTML backend ~A."
                   system-name))
    (handler-case
        (funcall (symbol-function loader) system-name)
      (error (condition)
        (fail-scrape 'html-backend-unavailable-error
                     "Could not load HTML backend ~A: ~A"
                     system-name
                     condition)))))

(defun html-backend-symbol (packages names backend-name)
  (or
   (loop for package-name in packages
         for package = (find-package package-name)
         when package
           do (loop for name in names
                    for symbol = (find-symbol name package)
                    when (and symbol (fboundp symbol))
                      do (return-from html-backend-symbol symbol)))
   (fail-scrape 'html-backend-unavailable-error
                "HTML backend ~A does not expose any of ~S."
                backend-name
                names)))

(defun make-plump-clss-html-adapter ()
  "Create an HTML adapter backed by Plump, CLSS, and lQuery node helpers.
The libraries are loaded only when this adapter is requested. Current CLSS
uses QUERY; older releases used SELECT. Both are supported without making
StarLang reader-dependent on either external package."
  (ensure-html-system "lquery")
  (let* ((parse-symbol
           (html-backend-symbol '("PLUMP" "ORG.SHIRAKUMO.PLUMP")
                                '("PARSE")
                                "Plump"))
         (query-symbol
           (html-backend-symbol '("CLSS" "ORG.SHIRAKUMO.CLSS")
                                '("QUERY" "SELECT")
                                "CLSS"))
         (text-symbol
           (html-backend-symbol '("LQUERY-FUNCS" "ORG.SHIRAKUMO.LQUERY.FUNCS")
                                '("TEXT")
                                "lQuery"))
         (attr-symbol
           (html-backend-symbol '("LQUERY-FUNCS" "ORG.SHIRAKUMO.LQUERY.FUNCS")
                                '("ATTR")
                                "lQuery"))
         (parse-fn (symbol-function parse-symbol))
         (query-fn (symbol-function query-symbol))
         (text-fn (symbol-function text-symbol))
         (attr-fn (symbol-function attr-symbol))
         (current-query-p (string= "QUERY" (symbol-name query-symbol))))
    (make-html-adapter
     "plump-clss"
     :parse parse-fn
     :select
     (if current-query-p
         (lambda (root selector)
           (funcall query-fn root selector))
         (lambda (root selector)
           (funcall query-fn selector root)))
     :text text-fn
     :attribute
     (lambda (node attribute)
       (funcall attr-fn node attribute)))))

(defun scrape-contract-valid-p (contract value)
  (case contract
    (:scrape-plan (scrape-plan-p value))
    (:scrape-result (scrape-result-p value))
    (otherwise nil)))

(defun make-scraper-actor-definition
    (name http-client html-adapter &key service-uri metadata)
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (declare (ignore state runtime))
     (execute-scrape http-client html-adapter message))
   :service-uri service-uri
   :accepts :scrape-plan
   :produces :scrape-result
   :input-validator #'scrape-contract-valid-p
   :output-validator #'scrape-contract-valid-p
   :metadata metadata))

(defun create-scraper-actor
    (runtime name http-client html-adapter &key service-uri metadata)
  (starlangruntime:create-actor
   runtime
   (make-scraper-actor-definition
    name
    http-client
    html-adapter
    :service-uri service-uri
    :metadata metadata)))
