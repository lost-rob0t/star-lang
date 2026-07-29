(defpackage :starhttpport-tests
  (:use :cl :fiveam)
  (:import-from :starhttpport)
  (:export))
(in-package :starhttpport-tests)

(def-suite starhttpport-tests
  :description "Placeholder test suite for star-http-port.")

(in-suite starhttpport-tests)

(test placeholder
  "The star-http-port system loads and exposes no surface yet."
  (is (eq t t)))
