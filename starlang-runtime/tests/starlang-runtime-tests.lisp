(defpackage :starlangruntime-tests
  (:use :cl :fiveam)
  (:import-from :starlangruntime)
  (:export))
(in-package :starlangruntime-tests)

(def-suite starlangruntime-tests
  :description "Placeholder test suite for starlang-runtime.")

(in-suite starlangruntime-tests)

(test placeholder
  "The starlang-runtime system loads and exposes no surface yet."
  (is (eq t t)))
