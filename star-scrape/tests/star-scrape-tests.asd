(defsystem "star-scrape-tests"
  :description "Unit tests for star-scrape"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-scrape" "yason")
  :serial t
  :components
  ((:file "star-scrape-tests")
   (:file "mapping-schema-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starscrape-tests :run-tests)
    (uiop:symbol-call :starscrape-tests :test-v2-mapping-contract)))

