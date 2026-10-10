(defpackage :starkbtek9-tests
  (:use :cl)
  (:import-from :starkb
                #:make-kb-entry
                #:make-kb-relation
                #:kb-record-id
                #:kb-record-provenance
                #:kb-put-entry
                #:kb-fetch-entry
                #:kb-delete-entry
                #:kb-find-entries-by-kind
                #:kb-find-entries-by-dataset
                #:kb-find-entries-by-field
                #:kb-put-relation
                #:kb-fetch-relation
                #:kb-delete-relation
                #:kb-find-relations-by-predicate
                #:kb-neighbors
                #:kb-close)
  (:import-from :starkbtek9
                #:open-tek9-kb-store)
  (:export #:run-tests))

(in-package :starkbtek9-tests)

(defvar *checks* 0)

(defun check (truth control &rest arguments)
  (incf *checks*)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun check-equal (expected actual context)
  (check (equal expected actual)
         "~A: expected ~S, got ~S." context expected actual))

(defun ids (records)
  (mapcar #'kb-record-id records))

(defun temporary-directory ()
  (let ((path (merge-pathnames
               (format nil "star-kb-tek9-~A/" (gensym))
               (uiop:temporary-directory))))
    (ensure-directories-exist path)
    path))

(defun remove-tree (path)
  (when (probe-file path)
    (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun seed (store namespace)
  (kb-put-entry store
                (make-kb-entry "a" :namespace namespace :kind "person"
                               :dataset "people"
                               :fields '(("name" . "Ada")
                                         ("roles" . #("admin" "analyst")))))
  (kb-put-entry store
                (make-kb-entry "b" :namespace namespace :kind "person"
                               :dataset "people"
                               :fields '(("name" . "Bob"))))
  (kb-put-entry store
                (make-kb-entry "c" :namespace namespace :kind "org"
                               :dataset "orgs"
                               :fields '(("name" . "C Corp"))))
  store)

(defun test-durable-indexes-and-graph ()
  (let ((path (temporary-directory)))
    (unwind-protect
         (progn
           (let ((store (open-tek9-kb-store path :name "test")))
             (seed store "g")
             (seed store "other")
             (check-equal '("a" "b")
                          (ids (kb-find-entries-by-kind store "g" "person"))
                          "Tek9 kind index")
             (check-equal '("a" "b")
                          (ids (kb-find-entries-by-dataset store "g" "people"))
                          "Tek9 dataset index")
             (check-equal '("a")
                          (ids (kb-find-entries-by-field store "g" "name" "Ada"))
                          "Tek9 field index")
             (check-equal '("a")
                          (ids (kb-find-entries-by-field
                                store "g" "roles" #("admin" "analyst")))
                          "Tek9 structured field equality index")
             (kb-put-relation
              store
              (make-kb-relation "r1" "a" "knows" "b"
                                :namespace "g"
                                :dataset "people"
                                :provenance '(:source "fixture")))
             (check-equal '("r1")
                          (ids (kb-find-relations-by-predicate store "g" "knows"))
                          "Tek9 predicate index")
             (check-equal '("b")
                          (ids (kb-neighbors store "g" "a" :predicate "knows"))
                          "Tek9 outgoing graph traversal")
             (check-equal '("a")
                          (ids (kb-neighbors store "g" "b"
                                             :predicate "knows" :incoming t))
                          "Tek9 incoming graph traversal")
             (check-equal '(:source "fixture")
                          (kb-record-provenance
                           (kb-fetch-relation store "g" "r1"))
                          "relation provenance stored outside edge hot path")
             (check-equal nil
                          (kb-neighbors store "other" "a" :predicate "knows")
                          "graph namespaces isolated")
             (kb-close store))
           ;; Reopen: index definitions are process configuration, while index
           ;; data and graph topology must remain durable.
           (let ((store (open-tek9-kb-store path :name "test")))
             (check-equal '("a")
                          (ids (kb-find-entries-by-field store "g" "name" "Ada"))
                          "field index survives reopen")
             (check-equal '("b")
                          (ids (kb-neighbors store "g" "a" :predicate "knows"))
                          "graph survives reopen")
             ;; Replacing the same relation id must move adjacency and indexes
             ;; atomically, exercising Tek9's edge-replacement path.
             (kb-put-relation
              store
              (make-kb-relation "r1" "c" "employs" "b" :namespace "g"))
             (check-equal nil
                          (kb-neighbors store "g" "a" :predicate "knows")
                          "old adjacency removed on relation replacement")
             (check-equal '("b")
                          (ids (kb-neighbors store "g" "c" :predicate "employs"))
                          "new adjacency installed on relation replacement")
             (check-equal nil
                          (kb-find-relations-by-predicate store "g" "knows")
                          "old predicate index removed")
             (check-equal '("r1")
                          (ids (kb-find-relations-by-predicate store "g" "employs"))
                          "new predicate index installed")
             (check (kb-delete-entry store "g" "c")
                    "entry cascade delete succeeds")
             (check (null (kb-fetch-relation store "g" "r1"))
                    "entry cascade removes relation record")
             (check (null (kb-fetch-entry store "g" "c"))
                    "entry cascade removes entry record")
             (kb-close store)))
      (remove-tree path))))

(defun test-relation-failure-rolls-back-record ()
  (let ((path (temporary-directory)))
    (unwind-protect
         (let ((store (open-tek9-kb-store path :name "rollback")))
           (unwind-protect
                (progn
                  (handler-case
                      (kb-put-relation
                       store
                       (make-kb-relation "bad" "missing-a" "knows" "missing-b"
                                         :namespace "g"))
                    (starkb:kb-backend-error () nil))
                  (check (null (kb-fetch-relation store "g" "bad"))
                         "failed graph write rolls back relation document"))
             (kb-close store)))
      (remove-tree path))))

(defun test-explicit-relation-delete ()
  (let ((path (temporary-directory)))
    (unwind-protect
         (let ((store (open-tek9-kb-store path :name "delete")))
           (unwind-protect
                (progn
                  (seed store "g")
                  (kb-put-relation store
                                   (make-kb-relation "r" "a" "knows" "b"
                                                     :namespace "g"))
                  (check (kb-delete-relation store "g" "r")
                         "relation delete succeeds")
                  (check (null (kb-fetch-relation store "g" "r"))
                         "relation record deleted")
                  (check (null (kb-neighbors store "g" "a" :predicate "knows"))
                         "relation adjacency deleted"))
             (kb-close store)))
      (remove-tree path))))

(defun run-tests ()
  (setf *checks* 0)
  (test-durable-indexes-and-graph)
  (test-relation-failure-rolls-back-record)
  (test-explicit-relation-delete)
  (format t "~&STAR-KB-TEK9-TESTS: ~D checks passed.~%" *checks*)
  t)
