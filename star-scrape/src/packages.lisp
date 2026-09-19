(defpackage :starscrape
  (:use :cl)
  (:nicknames :star-scrape)
  (:export
   #:scrape-error
   #:html-backend-unavailable-error
   #:scrape-extraction-error
   #:html-adapter
   #:html-adapter-p
   #:html-adapter-name
   #:make-html-adapter
   #:make-plump-clss-html-adapter
   #:scrape-field
   #:scrape-field-p
   #:scrape-field-name
   #:scrape-field-selector
   #:scrape-field-extractor
   #:scrape-field-attribute
   #:scrape-field-many-p
   #:scrape-field-required-p
   #:make-scrape-field
   #:scrape-plan
   #:scrape-plan-p
   #:scrape-plan-name
   #:scrape-plan-url
   #:scrape-plan-fields
   #:scrape-plan-headers
   #:make-scrape-plan
   #:scrape-result
   #:scrape-result-p
   #:scrape-result-plan-name
   #:scrape-result-url
   #:scrape-result-final-url
   #:scrape-result-status
   #:scrape-result-fields
   #:scrape-result-response-headers
   #:scrape-result-ref
   #:execute-scrape
   #:make-scraper-actor-definition
   #:create-scraper-actor))

(defpackage :starscrape.schema
  (:use :cl)
  (:nicknames #:star-scrape.schema)
  (:export
   #:+scraper-manifest-schema+
   #:+scraper-manifest-wire-version+
   #:scraper-schema-error
   #:scraper-policy-error
   #:load-scraper-vocabulary
   #:compile-scraper-manifest
   #:scraper-manifest-json))
