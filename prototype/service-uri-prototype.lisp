(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARACTORPROTOCOL")
    (require :asdf)
    ;; Do not reader-reference ASDF:LOAD-SYSTEM here.  This file is also loaded
    ;; directly by regression scripts started with plain `sbcl --script`, where
    ;; the ASDF package does not exist until REQUIRE has executed.
    (funcall (symbol-function (find-symbol "LOAD-SYSTEM" "ASDF"))
             "star-actor-protocol")))

(in-package #:star-lang.core-surface.prototype)

(export '(invalid-star-service-uri-error
          star-service-not-found-error
          star-service-unavailable-error
          star-service-uri
          star-service-uri-p
          star-service-uri-domain
          star-service-uri-address
          star-service-uri-actor-name
          make-star-service-uri
          parse-star-service-uri
          star-service-uri-string
          star-service-uri-target-p
          ensure-star-service-uri
          canonical-star-service-uri-for-actor))

;; Source-aware compatibility conditions remain compiler-side.  The portable
;; parser lives in STAR-ACTOR-PROTOCOL and signals its protocol-local condition;
;; these wrappers translate that failure through FAIL so current syntax/span and
;; import-origin context remain attached for legacy compiler callers.
(define-condition invalid-star-service-uri-error (star-lang-core-error) ())
(define-condition star-service-not-found-error (star-lang-core-error) ())
(define-condition star-service-unavailable-error (star-lang-core-error) ())

(deftype star-service-uri ()
  'staractorprotocol:star-service-uri)

(defun call-with-star-service-uri-compatibility (thunk)
  (handler-case
      (funcall thunk)
    (staractorprotocol:invalid-star-service-uri-error (condition)
      (fail 'invalid-star-service-uri-error "~A" condition))))

(defun star-service-uri-p (value)
  (staractorprotocol:star-service-uri-p value))

(defun star-service-uri-domain (uri)
  (staractorprotocol:star-service-uri-domain uri))

(defun star-service-uri-address (uri)
  (staractorprotocol:star-service-uri-address uri))

(defun star-service-uri-actor-name (uri)
  (staractorprotocol:star-service-uri-actor-name uri))

(defun make-star-service-uri (domain address actor-name)
  (call-with-star-service-uri-compatibility
   (lambda ()
     (staractorprotocol:make-star-service-uri domain address actor-name))))

(defun star-service-uri-string (uri)
  (call-with-star-service-uri-compatibility
   (lambda ()
     (staractorprotocol:star-service-uri-string uri))))

(defun star-service-uri-target-p (value)
  (staractorprotocol:star-service-uri-target-p value))

(defun parse-star-service-uri (value)
  (call-with-star-service-uri-compatibility
   (lambda ()
     (staractorprotocol:parse-star-service-uri value))))

(defun ensure-star-service-uri (value)
  (call-with-star-service-uri-compatibility
   (lambda ()
     (staractorprotocol:ensure-star-service-uri value))))

(defun canonical-star-service-uri-for-actor (actor-name value)
  (call-with-star-service-uri-compatibility
   (lambda ()
     (staractorprotocol:canonical-star-service-uri-for-actor actor-name value))))
