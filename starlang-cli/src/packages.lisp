;;;; Final starlang-cli package: the installed starlang command surface.
;;;; This system is a leaf over final systems only; it must never load
;;;; starlang-prototype or anything under prototype/ at runtime.

(defpackage :star-lang.cli
  (:use :cl)
  (:export
   #:cli-version
   #:run-cli
   #:usage
   #:compile-program-manifest
   #:run-actor-program))
