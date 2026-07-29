(defpackage :starprocessport-tests
  (:use :cl :fiveam)
  (:import-from :starprocessport)
  (:export))
(in-package :starprocessport-tests)

(def-suite starprocessport-tests
  :description "Placeholder test suite for star-process-port.")

(in-suite starprocessport-tests)

(test placeholder
  "The star-process-port system loads and exposes no surface yet."
  (is (eq t t)))
