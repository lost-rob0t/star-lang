(spec-library "org.starscrape/scraper@1"
  (:version "1.0.0")

  ;; Bounded scalars. The bounds below are schema authority: consumers
  ;; must not re-declare them.
  (scalar bounded-identifier
    (:base string
     :pattern "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"))

  (scalar bounded-text
    (:base string
     :pattern "^[^[:cntrl:]]{1,256}$"))

  (scalar user-agent-text
    (:base string
     :pattern "^[^[:cntrl:]]{1,128}$"))

  (scalar allowed-origin
    (:base string
     :pattern "^https://[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?$"))

  (scalar media-type
    (:base string
     :pattern "^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,126}/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,126}$"))

  (scalar selector-expression
    (:base string
     :pattern "^[^[:cntrl:]]{1,256}$"))

  (scalar document-type-name
    (:base string
     :pattern "^[a-z][a-z0-9-]{0,63}$"))

  (scalar extracted-field-name
    (:base string
     :pattern "^[a-z][A-Za-z0-9]{0,63}$"))

  (scalar max-redirects
    (:base integer
     :minimum 0
     :maximum 5))

  (scalar timeout-ms
    (:base integer
     :minimum 1
     :maximum 600000))

  (scalar delay-ms
    (:base integer
     :minimum 0
     :maximum 600000))

  (scalar max-response-bytes
    (:base integer
     :minimum 1024
     :maximum 104857600))

  (scalar crawl-depth
    (:base integer
     :minimum 0
     :maximum 8))

  (scalar max-pages
    (:base integer
     :minimum 1
     :maximum 1000))

  (scalar max-attempts
    (:base integer
     :minimum 1
     :maximum 10))

  (scalar requests-per-second
    (:base integer
     :minimum 1
     :maximum 1000))

  (scalar concurrent-requests
    (:base integer
     :minimum 1
     :maximum 64))

  ;; Closed effect-capability allowlist. Any capability outside this enum
  ;; is forbidden for website scrapers.
  (enum effect-capability
    (net-https-fetch parse-html rate-limit-scheduler crawl-budget
                     starintel-documents))

  (enum extractor-kind
    (text attribute html))

  (enum transform-kind
    (trim lowercase uppercase strip-tags absolute-url decode-entities))

  (enum pagination-kind
    (none next-link page-param))

  ;; SSRF posture is deny-by-default: the policy gate rejects allow.
  (enum private-network-policy
    (forbid allow))

  (enum redirect-policy
    (deny same-origin))

  (enum robots-mode
    (respect ignore))

  (enum backoff-jitter
    (none equal full))

  (document request-policy
    (:persistence transient)
    (allowedOrigins (list allowed-origin) :required)
    (redirectPolicy redirect-policy :required)
    (maxRedirects max-redirects :required)
    (privateNetwork private-network-policy :required)
    (maxResponseBytes max-response-bytes :required)
    (connectTimeoutMs timeout-ms :optional)
    (readTimeoutMs timeout-ms :optional)
    (allowedContentTypes (list media-type) :required))

  (document extraction-field
    (:persistence transient)
    (name extracted-field-name :required)
    (selector selector-expression :required)
    (kind extractor-kind :required)
    (attribute selector-expression :optional)
    (many boolean :optional)
    (required boolean :optional)
    (transform (list transform-kind) :optional))

  (document extraction-plan
    (:persistence transient)
    (fields (list extraction-field) :required))

  (document field-mapping
    (:persistence transient)
    (source extracted-field-name :required)
    (target extracted-field-name :required))

  (document document-mapping
    (:persistence transient)
    (documentType document-type-name :required)
    (fields (list field-mapping) :required))

  (document pagination-policy
    (:persistence transient)
    (kind pagination-kind :required)
    (nextSelector selector-expression :optional)
    (pageParameter bounded-identifier :optional)
    (maxPages max-pages :required)
    (maxDepth crawl-depth :required))

  (document rate-limits
    (:persistence transient)
    (requestsPerSecond requests-per-second :required)
    (concurrentRequests concurrent-requests :required)
    (interRequestDelayMs delay-ms :optional))

  (document retry-backoff
    (:persistence transient)
    (maxAttempts max-attempts :required)
    (backoffBaseMs delay-ms :required)
    (backoffMaxMs delay-ms :optional)
    (jitter backoff-jitter :required))

  (document robots-policy
    (:persistence transient)
    (mode robots-mode :required)
    (userAgent user-agent-text :required))

  (document provenance-info
    (:persistence transient)
    (collector bounded-text :required)
    (collectorVersion bounded-identifier :optional)
    (sourceLicense bounded-text :optional)
    (collectionMethod bounded-text :optional))

  (document scraper-policy
    (:persistence transient)
    (request request-policy :required)
    (extraction extraction-plan :required)
    (mapping (list document-mapping) :required)
    (pagination pagination-policy :required)
    (rate rate-limits :required)
    (retry retry-backoff :required)
    (robots robots-policy :required)
    (capabilities (list effect-capability) :required)
    (provenance provenance-info :required)))
