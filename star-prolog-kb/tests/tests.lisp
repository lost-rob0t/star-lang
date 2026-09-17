(defpackage :starprologkb-tests
  (:use :cl)
  (:export #:run-tests))

(in-package :starprologkb-tests)

(defvar *checks* 0)

(defun check (condition control &rest arguments)
  (incf *checks*)
  (unless condition
    (error (apply #'format nil control arguments))))

(defun sample-spec-ir ()
  (starlangcompiler:compile-spec-library
   (starlangcompiler:read-star-syntax
    "(spec-library \"test/core@1\"
       (:version \"1.0.0\")
       (document document
         (:persistence persistent)
         (id string :required)
         (dtype string :required)
         (dataset string :required)
         (tags (list string) :optional))
       (document user
         (:extends document :persistence persistent)
         (username string :required)
         (profile map :optional)))"
    :source-id "test-spec")))

(defun sample-program ()
  (starprologkb:compile-prolog-kb-source
   "(prolog-kb \"test/prolog-kb@1\"
      (:version \"1.0.0\"
       :runtime tek9
       :persistence persistent
       :protocol \"star.logic.prolog/1\")
      (schema core
        (:source \"test/core@1\" :version \"1.0.0\"))
      (index userByProvider
        (:source user
         :fields (username (profile provider))
         :kind auto))
      (prolog reachability
        (:source \"test/reachability\" :kind rules)
        \"reachable(A,B) :- star_relation(_,A,_,B).\"))"
   :source-id "test-kb"))

(defun test-grammar ()
  (let* ((program (sample-program))
         (block (first (starprologkb:prolog-kb-program-prolog-blocks program)))
         (index (first (starprologkb:prolog-kb-program-indexes program))))
    (check (string= "test/prolog-kb@1"
                    (starprologkb:prolog-kb-program-name program))
           "wrong program name")
    (check (eq :tek9 (starprologkb:prolog-kb-program-runtime program))
           "runtime was not tek9")
    (check (equal '(("username") ("profile" "provider"))
                  (starprologkb:kb-index-spec-selectors index))
           "nested index selector grammar changed")
    (check (string=
            "reachable(A,B) :- star_relation(_,A,_,B)."
            (starprologkb:prolog-source-block-text block))
           "raw Prolog text was not preserved")))

(defun test-all-fields-have-indexes ()
  (let* ((spec (sample-spec-ir))
         (indexes (starprologkb:make-auto-index-specs spec))
         (names (mapcar #'starprologkb:kb-index-spec-name indexes)))
    (dolist (name '("field/id"
                    "field/dtype"
                    "field/dataset"
                    "field/tags"
                    "field/username"
                    "field/profile"))
      (check (member name names :test #'string=)
             "missing automatic field index ~A" name))
    (let ((user-fields (starprologkb:effective-document-fields spec "user")))
      (check (find "id" user-fields :test #'string=
                   :key (lambda (field) (getf field :name)))
             "user did not inherit id field")
      (check (find "username" user-fields :test #'string=
                   :key (lambda (field) (getf field :name)))
             "user own field disappeared"))))

(defun test-index-resolution-and-extraction ()
  (let* ((spec (sample-spec-ir))
         (program (sample-program))
         (indexes (starprologkb:resolve-index-specs program spec))
         (tags (find "field/tags" indexes :test #'string=
                     :key #'starprologkb:kb-index-spec-name))
         (custom (find "userByProvider" indexes :test #'string=
                       :key #'starprologkb:kb-index-spec-name))
         (document
           '("id" "u-1"
             "dtype" "user"
             "dataset" "demo"
             "tags" ("alpha" "beta")
             "username" "alice"
             "profile" ("provider" "example"))))
    (check tags "tags index not resolved")
    (check custom "custom index not resolved")
    (check (= 2 (length (starprologkb::%index-values tags spec document)))
           "list field did not emit one posting per element")
    (check (= 1 (length (starprologkb::%index-values custom spec document)))
           "compound custom index did not emit one key")))

(defun tek9-available-p ()
  (or (find-package :tek9)
      (ignore-errors (asdf:find-system "tek9" nil))))

(defun test-tek9-integration-when-available ()
  (unless (tek9-available-p)
    (format t "~&star-prolog-kb: Tek9 not present; integration smoke skipped.~%")
    (return-from test-tek9-integration-when-available t))
  (let* ((root (merge-pathnames
                (format nil "star-prolog-kb-~D/" (get-universal-time))
                (uiop:temporary-directory)))
         (spec (sample-spec-ir))
         (program (sample-program))
         (kb nil))
    (unwind-protect
         (progn
           (setf kb (starprologkb:open-starintel-kb program spec :path root))
           (starprologkb:put-starintel-document
            kb
            '("id" "u-1"
              "dtype" "user"
              "dataset" "demo"
              "tags" ("alpha" "beta")
              "username" "alice"
              "profile" ("provider" "example")))
           (check (= 1 (length (starprologkb:query-field kb "username" "alice")))
                  "Tek9 automatic field index returned wrong count")
           (check (= 1 (length (starprologkb:query-field kb "tags" "beta")))
                  "Tek9 list-field index did not expand values")
           (check (= 1 (length (starprologkb:query-index
                                kb "userByProvider" "alice" "example")))
                  "StarLang-declared compound/path index returned wrong count")
           (starprologkb:define-index
            kb "byDataset" :source "document" :fields '("dataset"))
           (check (= 1 (length (starprologkb:query-index kb "byDataset" "demo")))
                  "runtime-defined Tek9 index returned wrong count")
           (check (search "reachable(A,B)" (starprologkb:prolog-snapshot-string kb))
                  "raw Prolog block missing from snapshot")

           ;; Runtime index definitions are durable KB catalog state, not Lisp
           ;; image state. Reopen the same LMDB environment and prove rehydrate.
           (starprologkb:close-starintel-kb kb)
           (setf kb nil)
           (setf kb (starprologkb:open-starintel-kb program spec :path root))
           (check (find "byDataset"
                        (starprologkb:list-indexes kb)
                        :test #'string=
                        :key #'starprologkb:kb-index-spec-name)
                  "runtime-defined index was not rehydrated after restart")
           (check (= 1 (length (starprologkb:query-index kb "byDataset" "demo")))
                  "rehydrated runtime index lost durable postings"))
      (when kb
        (ignore-errors (starprologkb:close-starintel-kb kb)))
      (when (probe-file root)
        (ignore-errors
          (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))))

(defun run-tests ()
  (setf *checks* 0)
  (test-grammar)
  (test-all-fields-have-indexes)
  (test-index-resolution-and-extraction)
  (test-tek9-integration-when-available)
  (format t "~&star-prolog-kb: ~D checks passed.~%" *checks*)
  t)
