(defpackage :staractorprotocol-tests
  (:use :cl :fiveam)
  (:import-from :staractorprotocol)
  (:export))
(in-package :staractorprotocol-tests)

(def-suite staractorprotocol-tests
  :description "Placeholder test suite for star-actor-protocol.")

(in-suite staractorprotocol-tests)

(test placeholder
  "The star-actor-protocol system loads and exposes no surface yet."
  (is (eq t t)))
