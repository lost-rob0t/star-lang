(defpackage :starkb-tests
  (:use :cl)
  (:import-from :starkb
                #:kb-contract-error
                #:make-kb-entry
                #:make-kb-relation
                #:kb-record-id
                #:kb-entry-kind
                #:kb-field-value
                #:make-memory-kb-store
                #:kb-put-entry
                #:kb-fetch-entry
                #:kb-delete-entry
                #:kb-find-entries-by-kind
                #:kb-find-entries-by-dataset
                #:kb-find-entries-by-field
                #:kb-put-relation
                #:kb-fetch-relation
                #:kb-find-relations-by-predicate
                #:kb-neighbors
                #:kb-close)
  (:export #:run-tests))

(in-package :starkb-tests)

(defvar *checks* 0)

(defun check (truth control &rest arguments)
  (incf *checks*)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun check-equal (expected actual context)
  (check (equal expected actual)
         "~A: expected ~S, got ~S." context expected actual))

(defun check-signals (condition-type thunk context)
  (incf *checks*)
  (handler-case
      (progn
        (funcall thunk)
        (error "~A: expected ~S." context condition-type))
    (condition (condition)
      (unless (typep condition condition-type)
        (error "~A: expected ~S, got ~S." context condition-type
               (type-of condition))))))

(defun ids (records)
  (mapcar #'kb-record-id records))

(defun seed-store (store namespace)
  (kb-put-entry
   store
   (make-kb-entry "a"
                  :namespace namespace
                  :kind "person"
                  :dataset "people"
                  :fields '(("name" . "Ada") ("age" . 37)
                            ("roles" . #("admin" "analyst")))
                  :metadata '(:rank 1)
                  :provenance '(:source "unit")))
  (kb-put-entry
   store
   (make-kb-entry "b"
                  :namespace namespace
                  :kind "person"
                  :dataset "people"
                  :fields '(("name" . "Bob") ("age" . 41))))
  (kb-put-entry
   store
   (make-kb-entry "c"
                  :namespace namespace
                  :kind "org"
                  :dataset "orgs"
                  :fields '(("name" . "C Corp"))))
  store)

(defun test-portable-owned-entry ()
  (let* ((name (copy-seq "Ada"))
         (fields (list (cons "name" name)))
         (entry (make-kb-entry "a" :kind "person" :fields fields)))
    (setf (char name 0) #\X)
    (check-equal "Ada" (kb-field-value entry "name")
                 "entry owns field snapshot")))

(defun test-invalid-fields ()
  (check-signals
   'kb-contract-error
   (lambda ()
     (make-kb-entry "a" :fields '(("x" . 1) ("x" . 2))))
   "duplicate field path rejected")
  (check-signals
   'kb-contract-error
   (lambda ()
     (make-kb-entry "a" :fields '(("" . 1))))
   "empty field path rejected"))

(defun test-memory-indexes-and-namespaces ()
  (let ((store (make-memory-kb-store)))
    (unwind-protect
         (progn
           (seed-store store "one")
           (seed-store store "two")
           (check-equal '("a" "b")
                        (ids (kb-find-entries-by-kind store "one" "person"))
                        "kind index")
           (check-equal '("a" "b")
                        (ids (kb-find-entries-by-dataset store "one" "people"))
                        "dataset index")
           (check-equal '("a")
                        (ids (kb-find-entries-by-field store "one" "age" 37))
                        "field index")
           (check-equal '("a")
                        (ids (kb-find-entries-by-field
                              store "one" "roles" #("admin" "analyst")))
                        "structured field equality")
           (check-equal "person"
                        (kb-entry-kind (kb-fetch-entry store "two" "a"))
                        "namespace isolated fetch"))
      (kb-close store))))

(defun test-relations-and-traversal ()
  (let ((store (make-memory-kb-store)))
    (unwind-protect
         (progn
           (seed-store store "g")
           (kb-put-relation
            store
            (make-kb-relation "r1" "a" "knows" "b"
                              :namespace "g"
                              :dataset "people"
                              :provenance '(:source "edge")))
           (kb-put-relation
            store
            (make-kb-relation "r2" "c" "employs" "b"
                              :namespace "g"))
           (check-equal '("r1")
                        (ids (kb-find-relations-by-predicate store "g" "knows"))
                        "predicate index")
           (check-equal '("b")
                        (ids (kb-neighbors store "g" "a" :predicate "knows"))
                        "outgoing traversal")
           (check-equal '("a")
                        (ids (kb-neighbors store "g" "b"
                                           :predicate "knows" :incoming t))
                        "incoming traversal")
           (check-equal "r1"
                        (kb-record-id (kb-fetch-relation store "g" "r1"))
                        "relation fetch")
           (check (kb-delete-entry store "g" "a")
                  "entry delete should succeed")
           (check (null (kb-fetch-relation store "g" "r1"))
                  "entry delete cascades relation records")
           (check-equal '("c")
                        (ids (kb-neighbors store "g" "b" :incoming t))
                        "unrelated relation survives cascade"))
      (kb-close store))))

(defun test-relation-endpoints-required ()
  (let ((store (make-memory-kb-store)))
    (unwind-protect
         (check-signals
          'kb-contract-error
          (lambda ()
            (kb-put-relation
             store
             (make-kb-relation "r" "missing" "knows" "also-missing")))
          "relation endpoints must exist")
      (kb-close store))))

(defun run-tests ()
  (setf *checks* 0)
  (test-portable-owned-entry)
  (test-invalid-fields)
  (test-memory-indexes-and-namespaces)
  (test-relations-and-traversal)
  (test-relation-endpoints-required)
  (format t "~&STAR-KB-TESTS: ~D checks passed.~%" *checks*)
  t)
