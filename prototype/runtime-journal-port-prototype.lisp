(in-package #:star-lang.core-surface.prototype)

(export '(make-file-runtime-journal-port
          make-memory-runtime-journal-port
          make-runtime-journal-port
          runtime-journal-append
          runtime-journal-port-p
          runtime-journal-replay))

;; Preserve the historical prototype condition surface for standalone scripts,
;; but keep all journal behavior in final star-journal.
(define-condition runtime-journal-error (star-lang-core-error) ())

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARJOURNAL")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-journal/star-journal.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-journal)))

(defun call-final-journal (thunk)
  (handler-case
      (funcall thunk)
    (starjournal:star-journal-error (condition)
      (fail 'runtime-journal-error "~A" condition))))

(defun runtime-journal-port-p (value)
  (starjournal:runtime-journal-port-p value))

(defun make-runtime-journal-port (&rest arguments)
  (call-final-journal
   (lambda ()
     (apply #'starjournal:make-runtime-journal-port arguments))))

(defun runtime-journal-append (port event)
  (call-final-journal
   (lambda ()
     (starjournal:runtime-journal-append port event))))

(defun runtime-journal-replay (port)
  (call-final-journal
   (lambda ()
     (starjournal:runtime-journal-replay port))))

(defun make-memory-runtime-journal-port ()
  (call-final-journal
   #'starjournal:make-memory-runtime-journal-port))

(defun make-file-runtime-journal-port (pathname)
  (call-final-journal
   (lambda ()
     (starjournal:make-file-runtime-journal-port pathname))))
