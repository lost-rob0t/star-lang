(defpackage :starcanonicaljson-tests
  (:use :cl :fiveam)
  (:import-from :starcanonicaljson)
  (:export))
(in-package :starcanonicaljson-tests)

(def-suite starcanonicaljson-tests
  :description "Placeholder test suite for star-canonical-json.")

(in-suite starcanonicaljson-tests)

(test placeholder
  "The star-canonical-json system loads and exposes no surface yet."
  (is (eq t t)))
