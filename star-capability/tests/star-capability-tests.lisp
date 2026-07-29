(defpackage :starcapability-tests
  (:use :cl :fiveam)
  (:import-from :starcapability)
  (:export))
(in-package :starcapability-tests)

(def-suite starcapability-tests
  :description "Placeholder test suite for star-capability.")

(in-suite starcapability-tests)

(test placeholder
  "The star-capability system loads and exposes no surface yet."
  (is (eq t t)))
