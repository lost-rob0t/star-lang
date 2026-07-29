(defpackage :staradaptersdk-tests
  (:use :cl :fiveam)
  (:import-from :staradaptersdk)
  (:export))
(in-package :staradaptersdk-tests)

(def-suite staradaptersdk-tests
  :description "Placeholder test suite for star-adapter-sdk.")

(in-suite staradaptersdk-tests)

(test placeholder
  "The star-adapter-sdk system loads and exposes no surface yet."
  (is (eq t t)))
