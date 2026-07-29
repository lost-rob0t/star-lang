(defpackage :starjournal-tests
  (:use :cl :fiveam)
  (:import-from :starjournal)
  (:export))
(in-package :starjournal-tests)

(def-suite starjournal-tests
  :description "Placeholder test suite for star-journal.")

(in-suite starjournal-tests)

(test placeholder
  "The star-journal system loads and exposes no surface yet."
  (is (eq t t)))
