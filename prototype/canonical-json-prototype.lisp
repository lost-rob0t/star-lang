(in-package #:star-lang.core-surface.prototype)

(export '(canonical-envelope-json
          canonical-manifest-json
          validate-wire-value))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARACTORPROTOCOL")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-actor-protocol/star-actor-protocol.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-actor-protocol))
  (unless (find-package "STARCANONICALJSON")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-canonical-json/star-canonical-json.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-canonical-json)))

(defun call-final-canonical-json (thunk)
  (handler-case
      (funcall thunk)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail 'invalid-envelope-error "~A" condition))
    (starcanonicaljson:invalid-canonical-json-error (condition)
      (fail 'invalid-envelope-error "~A" condition))))

(defun canonical-json-string (value)
  (call-final-canonical-json
   (lambda ()
     (starcanonicaljson:canonical-json-string value))))

(defun canonical-manifest-json (manifest)
  (call-final-canonical-json
   (lambda ()
     (starcanonicaljson:canonical-manifest-json manifest))))

(defun canonical-envelope-json (manifest envelope)
  (call-final-canonical-json
   (lambda ()
     (starcanonicaljson:canonical-envelope-json manifest envelope))))

(defun validate-wire-value
    (manifest type value &optional (context "wire value"))
  (handler-case
      (staractorprotocol:validate-portable-wire-value
       manifest type value context)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail 'invalid-envelope-error "~A" condition)))
  t)

;; Compatibility helpers still used by prototype binding/domain code. Their
;; implementation authority is final star-actor-protocol.
(defun manifest-type-contract (manifest qualified-name)
  (staractorprotocol:portable-manifest-type-contract
   manifest qualified-name))

(defun payload-entry (payload field-name)
  (staractorprotocol:portable-payload-entry payload field-name))
