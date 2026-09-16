(defpackage :staractorprotocol-snapshot-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-wire-envelope-error
                #:snapshot-portable-wire-value)
  (:export #:run-tests))

(in-package :staractorprotocol-snapshot-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun test-snapshot-owns-mutable-wire-values ()
  (let* ((string (copy-seq "alpha"))
         (vector (vector (copy-seq "first") (copy-seq "second")))
         (source (list :name string :items vector))
         (snapshot (snapshot-portable-wire-value source)))
    (setf (char string 0) #\X
          (char (aref vector 0) 0) #\X
          (aref vector 1) "replacement")
    (check (string= "alpha" (getf snapshot :name))
           "Snapshot retained caller-owned string data.")
    (check (equalp #("first" "second") (getf snapshot :items))
           "Snapshot retained caller-owned vector data.")
    (setf (char (getf snapshot :name) 0) #\Y
          (char (aref (getf snapshot :items) 0) 0) #\Y)
    (check (char= #\X (char string 0))
           "Mutating snapshot changed caller-owned string.")
    (check (char= #\X (char (aref vector 0) 0))
           "Mutating snapshot changed caller-owned vector element.")))

(defun test-snapshot-accepts-shared-acyclic-values-by-value ()
  (let* ((shared (list (copy-seq "shared")))
         (source (list shared shared))
         (snapshot (snapshot-portable-wire-value source)))
    (check (equal source snapshot)
           "Shared acyclic portable value changed semantic content.")
    (check (not (eq (first snapshot) (second snapshot)))
           "Shared input was retained as a mutable shared output alias.")))

(defun test-snapshot-rejects-cycles ()
  (let ((cycle (list "cycle")))
    (setf (cdr cycle) cycle)
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (snapshot-portable-wire-value cycle)))
     "Portable snapshot accepted a circular cons value."))
  (let ((cycle (make-array 1)))
    (setf (aref cycle 0) cycle)
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (snapshot-portable-wire-value cycle)))
     "Portable snapshot accepted a circular vector value.")))

(defun test-snapshot-enforces-resource-bounds ()
  (check
   (signals-p 'invalid-wire-envelope-error
              (lambda ()
                (snapshot-portable-wire-value
                 '((("too-deep")))
                 :max-depth 2)))
   "Portable snapshot accepted a value beyond max-depth.")
  (check
   (signals-p 'invalid-wire-envelope-error
              (lambda ()
                (snapshot-portable-wire-value
                 '(one two three)
                 :max-nodes 2)))
   "Portable snapshot accepted a value beyond max-nodes.")
  (check
   (signals-p 'invalid-wire-envelope-error
              (lambda ()
                (snapshot-portable-wire-value
                 "four"
                 :max-string-length 3)))
   "Portable snapshot accepted a string beyond max-string-length.")
  (check
   (signals-p 'invalid-wire-envelope-error
              (lambda ()
                (snapshot-portable-wire-value
                 #(1 2)
                 :max-vector-length 1)))
   "Portable snapshot accepted a vector beyond max-vector-length."))

(defun test-snapshot-rejects-unsupported-host-values ()
  (check
   (signals-p 'invalid-wire-envelope-error
              (lambda ()
                (snapshot-portable-wire-value (make-hash-table))))
   "Portable snapshot accepted a host hash table.")
  (check
   (signals-p 'invalid-wire-envelope-error
              (lambda ()
                (snapshot-portable-wire-value nil :max-nodes 0)))
   "Portable snapshot accepted an invalid resource limit."))

(defun run-tests ()
  (test-snapshot-owns-mutable-wire-values)
  (test-snapshot-accepts-shared-acyclic-values-by-value)
  (test-snapshot-rejects-cycles)
  (test-snapshot-enforces-resource-bounds)
  (test-snapshot-rejects-unsupported-host-values)
  (format t "~&star-actor-protocol portable snapshot tests passed~%")
  t)
