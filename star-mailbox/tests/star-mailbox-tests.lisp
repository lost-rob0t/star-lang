(defpackage :starmailbox-tests
  (:use :cl :fiveam)
  (:import-from :starmailbox)
  (:export))
(in-package :starmailbox-tests)

(def-suite starmailbox-tests
  :description "Placeholder test suite for star-mailbox.")

(in-suite starmailbox-tests)

(test placeholder
  "The star-mailbox system loads and exposes no surface yet."
  (is (eq t t)))
