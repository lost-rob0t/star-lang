(defpackage :starsentocompat-tests
  (:use :cl :fiveam)
  (:import-from :starsentocompat)
  (:export))
(in-package :starsentocompat-tests)

(def-suite starsentocompat-tests
  :description "Placeholder test suite for star-sento-compat.")

(in-suite starsentocompat-tests)

(test placeholder
  "The star-sento-compat system loads and exposes no surface yet."
  (is (eq t t)))
