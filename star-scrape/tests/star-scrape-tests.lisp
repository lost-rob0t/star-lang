(defpackage :starscrape-tests
  (:use :cl)
  (:import-from :starhttpport
                #:make-http-client
                #:make-http-response)
  (:import-from :starlangruntime
                #:make-runtime
                #:invoke-actor
                #:resolve-actor)
  (:import-from :starscrape
                #:scrape-extraction-error
                #:make-html-adapter
                #:make-scrape-field
                #:make-scrape-plan
                #:execute-scrape
                #:scrape-result-status
                #:scrape-result-final-url
                #:scrape-result-ref
                #:create-scraper-actor)
  (:import-from :starscrape.schema
                #:+scraper-manifest-schema+
                #:scraper-schema-error
                #:scraper-policy-error
                #:load-scraper-vocabulary
                #:compile-scraper-manifest
                #:scraper-manifest-json)
  (:import-from :starlangcompiler
                #:compile-spec-library
                #:read-star-syntax
                #:invalid-declaration-error
                #:invalid-field-error
                #:star-lang-core-error)
  (:import-from :staractorprotocol
                #:invalid-wire-envelope-error)
  (:import-from :starcanonicaljson
                #:canonical-json-string
                #:make-json-object
                #:make-json-array)
  (:export #:run-tests))

(in-package :starscrape-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun fixture-node (text &rest attributes)
  (list :text text
        :attributes
        (loop for (name value) on attributes by #'cddr
              collect (cons name value))))

(defun fixture-attribute (node attribute)
  (cdr (assoc attribute (getf node :attributes) :test #'string=)))

(defun make-fixture-html-adapter ()
  (make-html-adapter
   "fixture-dom"
   :parse
   (lambda (html)
     (declare (ignore html))
     (list
      (cons "title"
            (list (fixture-node "StarLang scraper")))
      (cons "a.result"
            (list (fixture-node "Alpha" "href" "/alpha")
                  (fixture-node "Beta" "href" "/beta")))))
   :select
   (lambda (root selector)
     (cdr (assoc selector root :test #'string=)))
   :text
   (lambda (node)
     (getf node :text))
   :attribute #'fixture-attribute))

(defun make-fixture-http-client (&key (status 200))
  (make-http-client
   "fixture-http"
   (lambda (request)
     (make-http-response
      :body "<html>fixture</html>"
      :status status
      :headers '(("content-type" . "text/html; charset=utf-8"))
      :final-url (starhttpport:http-request-url request)))))

(defun make-fixture-plan ()
  (make-scrape-plan
   :search-page
   "https://example.test/search"
   (list
    (make-scrape-field :title "title" :required t)
    (make-scrape-field :links
                       "a.result"
                       :extractor :attribute
                       :attribute "href"
                       :many t))
   :headers '(("user-agent" . "StarLang-Scrape-Test"))
   :request-options '(:connect-timeout 2 :read-timeout 4 :max-redirects 1)))

(defun test-execute-scrape ()
  (let ((result
          (execute-scrape
           (make-fixture-http-client)
           (make-fixture-html-adapter)
           (make-fixture-plan))))
    (check (= 200 (scrape-result-status result))
           "Scrape result did not preserve HTTP status.")
    (check (string= "https://example.test/search"
                    (scrape-result-final-url result))
           "Scrape result did not preserve final URL.")
    (check (string= "StarLang scraper" (scrape-result-ref result :title))
           "Text field extraction failed.")
    (check (equal '("/alpha" "/beta") (scrape-result-ref result :links))
           "Multi-value attribute extraction failed.")))

(defun test-required-field-failure ()
  (let ((adapter
          (make-html-adapter
           "empty"
           :parse (lambda (html) (declare (ignore html)) nil)
           :select (lambda (root selector)
                     (declare (ignore root selector))
                     nil)
           :text (lambda (node) (declare (ignore node)) nil)
           :attribute (lambda (node attribute)
                        (declare (ignore node attribute))
                        nil))))
    (check
     (signals-p 'scrape-extraction-error
                (lambda ()
                  (execute-scrape
                   (make-fixture-http-client)
                   adapter
                   (make-scrape-plan
                    :missing
                    "https://example.test/missing"
                    (list (make-scrape-field :required "h1" :required t))))))
     "Missing required scrape field did not fail.")))

(defun test-http-failure ()
  (check
   (signals-p 'scrape-extraction-error
              (lambda ()
                (execute-scrape
                 (make-fixture-http-client :status 503)
                 (make-fixture-html-adapter)
                 (make-fixture-plan))))
   "Non-success HTTP status did not fail the scrape."))

(defun test-scraper-actor ()
  (let* ((runtime (make-runtime))
         (client (make-fixture-http-client))
         (adapter (make-fixture-html-adapter))
         (actor
           (create-scraper-actor
            runtime
            "page-scraper"
            client
            adapter
            :service-uri "star://scrape:localhost:page-scraper"
            :metadata '(:purpose :fixture)))
         (result
           (invoke-actor
            runtime
            "star://scrape:localhost:page-scraper"
            (make-fixture-plan))))
    (check (eq actor (resolve-actor runtime "page-scraper"))
           "Scraper actor was not registered by name.")
    (check (string= "StarLang scraper" (scrape-result-ref result :title))
           "Scraper actor did not execute its scrape plan.")))

;;;; Scraper schema contract tests (star-lang#137).
;;;;
;;;; The .star fixture is the schema authority; the Lisp policy is plain
;;;; data constructed without eval. Generic bounds come from the compiled
;;;; vocabulary; the closed policy gate adds domain rules the generic wire
;;;; validator cannot express.

(defun scraper-fixture-path ()
  (merge-pathnames "../fixtures/star-scrape-core.star"
                   (asdf:system-source-directory :star-scrape)))

(defun fixture-vocabulary-manifest ()
  (load-scraper-vocabulary (scraper-fixture-path)))

(defun example-scraper-policy ()
  (list
   :request
   (list
    :allowed-origins '("https://quotes.example.org")
    :redirect-policy :same-origin
    :max-redirects 3
    :private-network :forbid
    :max-response-bytes 2097152
    :connect-timeout-ms 10000
    :read-timeout-ms 30000
    :allowed-content-types '("text/html" "application/xhtml+xml"))
   :extraction
   (list
    :fields
    (list
     (list :name "quoteText"
           :selector "div.quote span.text"
           :kind :text
           :required t)
     (list :name "quoteAuthor"
           :selector "div.quote small.author"
           :kind :text)
     (list :name "quoteTags"
           :selector "div.quote div.tags a.tag"
           :kind :text
           :many t)
     (list :name "detailLink"
           :selector "div.quote a"
           :kind :attribute
           :attribute "href"
           :transform '(:absolute-url))))
   :mapping
   (list
    (list :document-type "quote"
          :fields
          (list
           (list :source "quoteText" :target "content")
           (list :source "quoteAuthor" :target "author")
           (list :source "detailLink" :target "url"))))
   :pagination
   (list
    :kind :next-link
    :next-selector "li.next a"
    :max-pages 100
    :max-depth 2)
   :rate
   (list
    :requests-per-second 5
    :concurrent-requests 2
    :inter-request-delay-ms 200)
   :retry
   (list
    :max-attempts 3
    :backoff-base-ms 500
    :backoff-max-ms 8000
    :jitter :equal)
   :robots
   (list
    :mode :respect
    :user-agent "StarLangScraper/1.0 (+https://starlang.example.dev/bot)")
   :capabilities
   '(:net-https-fetch :parse-html :rate-limit-scheduler :crawl-budget
     :starintel-documents)
   :provenance
   (list
    :collector "example-scraper"
    :collector-version "1.0.0"
    :source-license "CC-BY-4.0"
    :collection-method "website-crawl")))

(defun plist-field (plist key)
  (getf plist key))

(defun decoded-json-field (decoded &rest keys)
  (let ((value decoded))
    (dolist (key keys value)
      (setf value
            (cond
              ((hash-table-p value) (gethash key value))
              ((and (integerp key)
                    (or (listp value) (vectorp value)))
               (elt value key))
              ((and (listp value) (every #'consp value))
               (cdr (assoc key value :test #'string=)))
              (t nil))))))

(defun json-nodes-from-decoded (value)
  (cond
    ((hash-table-p value)
     (make-json-object
      (loop for key being the hash-keys of value
              using (hash-value item)
            collect (cons key (json-nodes-from-decoded item)))))
    ;; NIL must be tested before LISTP. Arrays are decoded as vectors so
    ;; a decoded NIL is always JSON false (the manifest never emits null).
    ((eq value nil) starcanonicaljson:+json-false+)
    ((eq value t) starcanonicaljson:+json-true+)
    ((stringp value) value)
    ((vectorp value)
     (make-json-array
      (mapcar #'json-nodes-from-decoded (coerce value 'list))))
    ((listp value)
     (make-json-array (mapcar #'json-nodes-from-decoded value)))
    (t value)))

(defun test-scraper-vocabulary-compiles ()
  "The .star vocabulary compiles through the closed pipeline; IR and
portable manifest are deterministic."
  (let* ((ir-1 (starlangcompiler:load-star-form (scraper-fixture-path)))
         (ir-2 (starlangcompiler:load-star-form (scraper-fixture-path)))
         (manifest-1 (fixture-vocabulary-manifest))
         (manifest-2 (fixture-vocabulary-manifest)))
    (check (eq (getf ir-1 :kind) :spec-library)
           "Scraper vocabulary IR is not a spec-library.")
    (check (string= (getf ir-1 :name) "org.starscrape/scraper@1")
           "Scraper vocabulary has the wrong library name.")
    (check (string= (getf ir-1 :version) "1.0.0")
           "Scraper vocabulary has the wrong library version.")
    (check (equal ir-1 ir-2)
           "Scraper vocabulary IR is not deterministic.")
    (check (equal manifest-1 manifest-2)
           "Portable scraper vocabulary manifest is not deterministic.")
    (let ((names (mapcar (lambda (declaration) (getf declaration :name))
                         (getf manifest-1 :types))))
      (dolist (required '("org.starscrape/scraper@1/scraper-policy"
                          "org.starscrape/scraper@1/request-policy"
                          "org.starscrape/scraper@1/pagination-policy"
                          "org.starscrape/scraper@1/extraction-field"
                          "org.starscrape/scraper@1/document-mapping"
                          "org.starscrape/scraper@1/provenance-info"
                          "org.starscrape/scraper@1/retry-backoff"
                          "org.starscrape/scraper@1/robots-policy"
                          "org.starscrape/scraper@1/rate-limits"
                          "org.starscrape/scraper@1/effect-capability"))
        (check (member required names :test #'string=)
               "Scraper vocabulary is missing type ~A." required)))))

(defun test-scraper-manifest-compiles ()
  "The example schema compiles to a portable scraper manifest."
  (let* ((vocabulary (fixture-vocabulary-manifest))
         (policy (example-scraper-policy))
         (manifest (compile-scraper-manifest vocabulary policy)))
    (check (string= (getf manifest :manifest-schema)
                    +scraper-manifest-schema+)
           "Scraper manifest carries the wrong schema identifier.")
    (check (= (getf manifest :wire-version) 1)
           "Scraper manifest carries the wrong wire version.")
    (check (string= (getf (getf (getf manifest :vocabulary) :library) :name)
                    "org.starscrape/scraper@1")
           "Scraper manifest does not pin the vocabulary library.")
    (check (equal (getf manifest :policy) policy)
           "Scraper manifest did not preserve the validated policy.")))

(defun test-scraper-manifest-json-round-trips ()
  "The manifest serializes to canonical JSON; decoding and re-encoding
produces identical bytes without semantic drift."
  (let* ((vocabulary (fixture-vocabulary-manifest))
         (manifest
           (compile-scraper-manifest vocabulary (example-scraper-policy)))
         (json-1 (scraper-manifest-json manifest))
         (json-2 (scraper-manifest-json
                  (compile-scraper-manifest
                   (fixture-vocabulary-manifest)
                   (example-scraper-policy)))))
    (check (string= json-1 json-2)
           "Scraper manifest canonical JSON is not deterministic.")
    (check (null (search "null" json-1))
           "Scraper manifest JSON contains null literals.")
    (let ((root (namestring (asdf:system-source-directory :star-scrape))))
      (check (null (search root json-1))
             "Scraper manifest JSON leaks local source paths."))
    (let ((decoded
            (let ((yason:*parse-json-arrays-as-vectors* t))
              (yason:parse json-1))))
      (check (string= (decoded-json-field decoded "manifestSchema")
                      +scraper-manifest-schema+)
             "Decoded manifest lost its schema identifier.")
      (check (= 3 (decoded-json-field decoded "policy" "request" "maxRedirects"))
             "Decoded manifest lost the maxRedirects bound.")
      (check (string= "https://quotes.example.org"
                      (elt (decoded-json-field
                            decoded "policy" "request" "allowedOrigins")
                           0))
             "Decoded manifest lost the allowed origin.")
      (check (null (decoded-json-field
                    decoded "policy" "extraction" "fields" 0 "transform"))
             "Absent optional fields must stay absent after decoding.")
      (let ((reencoded
              (canonical-json-string
               (json-nodes-from-decoded decoded))))
        (check (string= json-1 reencoded)
               "Canonical JSON round-trip drifted semantically.")))))

(defun test-scraper-manifest-rejects-malformed-policy ()
  "Malformed policies are rejected with structured errors."
  (let ((vocabulary (fixture-vocabulary-manifest)))
    (flet ((must-reject (policy note)
             (check
              (signals-p 'invalid-wire-envelope-error
                         (lambda ()
                           (compile-scraper-manifest vocabulary policy)))
              "Malformed scraper policy was not rejected: ~A." note)))
      (must-reject
       (append '(:bogus-area nil) (example-scraper-policy))
       "unknown top-level area")
      (must-reject
       (remove-from-plist (example-scraper-policy) :pagination)
       "missing pagination area")
      ;; Odd-length plist is not a payload object.
      (must-reject '(:request) "odd-length payload")
      ;; Scalar type violation: integer field carries a string.
      (must-reject
       (replace-policy-area
        (example-scraper-policy) :request :max-redirects "three")
       "string where integer is required")
      ;; Enum violation: unknown extractor kind.
      (must-reject
       (replace-policy-area
        (example-scraper-policy) :extraction :fields
        (list (list :name "broken" :selector "h1" :kind :xpath)))
       "unknown extractor kind"))))

(defun substitute-plist-value (plist key value)
  (let ((copy (copy-list plist)))
    (loop for tail on copy by #'cddr
          when (eq (first tail) key)
            do (setf (second tail) value))
    copy))

(defun remove-from-plist (plist key)
  (loop for (k v) on plist by #'cddr
        unless (eq k key)
          append (list k v)))

(defun replace-policy-area (policy area update-key update-value)
  (substitute-plist-value
   policy
   area
   (substitute-plist-value (plist-field policy area) update-key update-value)))

(defun test-scraper-policy-bounds-enforced ()
  "Vocabulary scalar bounds bound recursion and pagination."
  (let ((vocabulary (fixture-vocabulary-manifest)))
    (flet ((must-reject (area update-key update-value note)
             (check
              (signals-p
               'invalid-wire-envelope-error
               (lambda ()
                 (compile-scraper-manifest
                  vocabulary
                  (replace-policy-area
                   (example-scraper-policy) area update-key update-value))))
              "Bound violation was not rejected: ~A." note)))
      (must-reject :request :max-redirects 6
                   "maxRedirects above vocabulary maximum")
      (must-reject :request :max-redirects -1
                   "negative maxRedirects")
      (must-reject :pagination :max-pages 1001
                   "maxPages above vocabulary maximum")
      (must-reject :pagination :max-depth 9
                   "maxDepth above vocabulary maximum")
      (must-reject :request :max-response-bytes 512
                   "maxResponseBytes below vocabulary minimum")
      (must-reject :retry :max-attempts 11
                   "maxAttempts above vocabulary maximum"))))

(defun test-scraper-forbidden-capabilities-rejected ()
  "Capabilities outside the closed .star allowlist are forbidden."
  (let ((vocabulary (fixture-vocabulary-manifest)))
    (dolist (forbidden '(:net-private-fetch :fs-write :exec-spawn :eval-lisp))
      (check
       (signals-p
        'invalid-wire-envelope-error
        (lambda ()
          (compile-scraper-manifest
           vocabulary
           (append
            (remove-from-plist (example-scraper-policy) :capabilities)
            (list :capabilities (list forbidden))))))
       "Forbidden capability ~S was not rejected." forbidden))))

(defun test-scraper-policy-gate-rules ()
  "Closed domain rules reject policies the type checker alone accepts."
  (let ((vocabulary (fixture-vocabulary-manifest)))
    (flet ((must-reject (policy note)
             (check
              (signals-p 'scraper-policy-error
                         (lambda ()
                           (compile-scraper-manifest vocabulary policy)))
              "Scraper policy gate did not reject ~A." note)))
      ;; SSRF: private-network access must stay forbidden.
      (must-reject
       (replace-policy-area
        (example-scraper-policy) :request :private-network :allow)
       "privateNetwork allow")
      ;; Plaintext origin is type-valid but forbidden by the gate.
      (must-reject
       (replace-policy-area
        (example-scraper-policy) :request :allowed-origins
        '("http://quotes.example.org"))
       "plaintext origin")
      ;; Origin with path or userinfo is not a bare origin.
      (must-reject
       (replace-policy-area
        (example-scraper-policy) :request :allowed-origins
        '("https://quotes.example.org/admin?x=1"))
       "origin with path")
      ;; Empty content-type allowlist.
      (must-reject
       (replace-policy-area
        (example-scraper-policy) :request :allowed-content-types '())
       "empty content types")
      ;; Attribute extractor without an attribute name.
      (must-reject
       (list
        :request (plist-field (example-scraper-policy) :request)
        :extraction
        (list :fields
              (list (list :name "link"
                          :selector "a"
                          :kind :attribute)))
        :mapping (plist-field (example-scraper-policy) :mapping)
        :pagination (plist-field (example-scraper-policy) :pagination)
        :rate (plist-field (example-scraper-policy) :rate)
        :retry (plist-field (example-scraper-policy) :retry)
        :robots (plist-field (example-scraper-policy) :robots)
        :capabilities (plist-field (example-scraper-policy) :capabilities)
        :provenance (plist-field (example-scraper-policy) :provenance))
       "attribute extractor without attribute")
      ;; next-link pagination without a next selector.
      (must-reject
       (substitute-plist-value
        (example-scraper-policy) :pagination
        (list :kind :next-link :max-pages 5 :max-depth 1))
       "next-link without selector")
      ;; page-param pagination without a page parameter.
      (must-reject
       (substitute-plist-value
        (example-scraper-policy) :pagination
        (list :kind :page-param :max-pages 5 :max-depth 1))
       "page-param without parameter")
      ;; none pagination must not declare selectors or parameters.
      (must-reject
       (substitute-plist-value
        (example-scraper-policy) :pagination
        (list :kind :none
              :next-selector "li.next a"
              :max-pages 1
              :max-depth 0))
       "none pagination with selector")
      ;; Empty document mapping list.
      (must-reject
       (substitute-plist-value
        (example-scraper-policy) :mapping '())
       "empty document mapping"))))

(defun test-malformed-scraper-vocabulary-rejected ()
  "Malformed .star vocabulary fails closed at the compiler with
structured diagnostics (star-lang-core-error subclasses)."
  (labels ((compile-source (source)
             (compile-spec-library
              (read-star-syntax source :source-id "malformed-scraper.star"))))
    (check
     (signals-p
      'invalid-declaration-error
      (lambda ()
        (compile-source
         "(spec-library \"org.starscrape/broken@1\" (:version \"1.0.0\")
           (scraper-config broken (:persistence transient)))")))
     "Unknown specification declaration head was not rejected.")
    (check
     (signals-p
      'invalid-field-error
      (lambda ()
        (compile-source
         "(spec-library \"org.starscrape/broken@1\" (:version \"1.0.0\")
           (document broken (:persistence transient)
             (name string)))")))
     "Field without presence marker was not rejected.")
    (check
     (signals-p
      'star-lang-core-error
      (lambda ()
        (compile-source
         "(spec-library \"org.starscrape/broken@1\" (:version \"1.0.0\")
           (document p (:persistence transient)
             (bad_field_name string :required)))")))
     "snake_case field name was not rejected.")
    (check
     (signals-p
      'invalid-declaration-error
      (lambda ()
        (compile-source
         "(spec-library \"org.starscrape/broken@1\" (:version \"1.0.0\")
           (enum capability (net-https-fetch net-https-fetch)))")))
     "Duplicate enum value was not rejected.")
    (check
     (signals-p
      'error
      (lambda ()
        (compile-source
         "(spec-library \"org.starscrape/broken@1\" (:version \"1.0.0\")
           (document p (:persistence transient)
             (bad_field_name string :required)))")))
     "snake_case field name was not rejected.")
    (check
     (signals-p
      'scraper-schema-error
      (lambda ()
        (load-scraper-vocabulary
         (merge-pathnames "../fixtures/star-scrape-core.star"
                          (asdf:system-source-directory :star-scrape))
         :expected-name "org.starscrape/wrong@1")))
     "Wrong vocabulary identity was not rejected.")))

(defun run-tests ()
  (test-execute-scrape)
  (test-required-field-failure)
  (test-http-failure)
  (test-scraper-actor)
  (test-scraper-vocabulary-compiles)
  (test-scraper-manifest-compiles)
  (test-scraper-manifest-json-round-trips)
  (test-scraper-manifest-rejects-malformed-policy)
  (test-scraper-policy-bounds-enforced)
  (test-scraper-forbidden-capabilities-rejected)
  (test-scraper-policy-gate-rules)
  (test-malformed-scraper-vocabulary-rejected)
  (format t "~&star-scrape tests passed~%")
  t)
