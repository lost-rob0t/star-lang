(defpackage :starsupervisor-tests
  (:use :cl :fiveam)
  (:import-from :starsupervisor)
  (:export))
(in-package :starsupervisor-tests)

(def-suite starsupervisor-tests
  :description "Placeholder test suite for star-supervisor.")

(in-suite starsupervisor-tests)

(test placeholder
  "The star-supervisor system loads and exposes no surface yet."
  (is (eq t t)))
