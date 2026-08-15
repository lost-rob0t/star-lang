(in-package #:star-lang.core-surface.prototype)

(export '(make-runtime-directory-port
          resolve-star-service-uri
          runtime-directory-snapshot))

(define-condition runtime-directory-error (star-lang-core-error) ())

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARLANGRUNTIME")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../starlang-runtime/starlang-runtime.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :starlang-runtime)))

(deftype runtime-directory-port ()
  'starlangruntime:runtime-directory-port)

(defun runtime-directory-port-p (value)
  (starlangruntime:runtime-directory-port-p value))

(defun call-final-runtime-directory (thunk)
  (handler-case
      (funcall thunk)
    (starlangruntime:runtime-directory-service-not-found-error (condition)
      (fail 'star-service-not-found-error "~A" condition))
    (starlangruntime:runtime-directory-service-unavailable-error (condition)
      (fail 'star-service-unavailable-error "~A" condition))
    (starlangruntime:runtime-directory-error (condition)
      (fail 'runtime-directory-error "~A" condition))
    (staractorprotocol:invalid-star-service-uri-error (condition)
      (fail 'invalid-star-service-uri-error "~A" condition))))

(defun make-runtime-directory-port (&rest arguments)
  (call-final-runtime-directory
   (lambda ()
     (apply #'starlangruntime:make-runtime-directory-port arguments))))

(defun runtime-directory-snapshot (port context)
  (call-final-runtime-directory
   (lambda ()
     (starlangruntime:runtime-directory-snapshot port context))))

(defun resolve-star-service-uri (port context uri-value)
  (call-final-runtime-directory
   (lambda ()
     (starlangruntime:resolve-star-service-uri
      port context uri-value))))
