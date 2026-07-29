(defpackage :starlease-tests
  (:use :cl :fiveam)
  (:import-from :starlease)
  (:export))
(in-package :starlease-tests)

(def-suite starlease-tests
  :description "Placeholder test suite for star-lease.")

(in-suite starlease-tests)

(test placeholder
  "The star-lease system loads and exposes no surface yet."
  (is (eq t t)))
