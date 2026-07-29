(defpackage :starlangcompiler-tests
  (:use :cl :fiveam)
  (:import-from :starlangcompiler)
  (:export))
(in-package :starlangcompiler-tests)

(def-suite starlangcompiler-tests
  :description "Placeholder test suite for starlang-compiler.")

(in-suite starlangcompiler-tests)

(test placeholder
  "The starlang-compiler system loads and exposes no surface yet."
  (is (eq t t)))
