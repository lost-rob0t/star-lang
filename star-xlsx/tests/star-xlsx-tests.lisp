(defpackage :starxlsx-tests
  (:use :cl :fiveam)
  (:import-from :starxlsx)
  (:export))
(in-package :starxlsx-tests)

(def-suite starxlsx-tests
  :description "Placeholder test suite for star-xlsx.")

(in-suite starxlsx-tests)

(test placeholder
  "The star-xlsx system loads and exposes no surface yet."
  (is (eq t t)))
