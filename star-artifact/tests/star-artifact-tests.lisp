(defpackage :starartifact-tests
  (:use :cl :fiveam)
  (:import-from :starartifact)
  (:export))
(in-package :starartifact-tests)

(def-suite starartifact-tests
  :description "Placeholder test suite for star-artifact.")

(in-suite starartifact-tests)

(test placeholder
  "The star-artifact system loads and exposes no surface yet."
  (is (eq t t)))
