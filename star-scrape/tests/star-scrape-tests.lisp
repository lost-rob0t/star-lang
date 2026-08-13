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

(defun run-tests ()
  (test-execute-scrape)
  (test-required-field-failure)
  (test-http-failure)
  (test-scraper-actor)
  (format t "~&star-scrape tests passed~%")
  t)
