(defpackage :starartifact-tests
  (:use :cl :fiveam)
  (:import-from :starcanonicaljson
                #:make-json-object)
  (:import-from :starlangruntime
                #:make-runtime
                #:invoke-actor
                #:resolve-actor)
  (:import-from :starartifact
                #:invalid-json-file-record-error
                #:make-json-file-write
                #:json-file-result-status
                #:json-file-result-path
                #:create-json-file-writer-actor)
  (:export))

(in-package :starartifact-tests)

(def-suite starartifact-tests
  :description "Tests for StarLang artifact output adapters.")

(in-suite starartifact-tests)

(defun make-test-root ()
  (merge-pathnames
   (format nil "star-artifact-test-~A/" (symbol-name (gensym "RUN-")))
   (uiop:temporary-directory)))

(defun delete-test-root (root)
  (when (probe-file root)
    (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))

(defun fixture-document (&optional (source "github"))
  (make-json-object
   `(("source" . ,source)
     ("login" . "ada"))))

(test json-file-writer-actor-writes-canonical-files
  "The native actor writes one deterministic canonical JSON file per record."
  (let ((root (make-test-root)))
    (unwind-protect
         (let* ((runtime (make-runtime))
                (actor
                  (create-json-file-writer-actor
                   runtime
                   "json-file-writer"
                   root
                   :service-uri "star://artifact:localhost:json-file-writer"
                   :metadata '(:purpose :test)))
                (write
                  (make-json-file-write
                   "github-members"
                   "ada"
                   (fixture-document)))
                (result (invoke-actor runtime actor write))
                (path (json-file-result-path result)))
           (is (eq actor (resolve-actor runtime "json-file-writer")))
           (is (eq :written (json-file-result-status result)))
           (is (probe-file path))
           (is
            (string=
             (format nil "{\"login\":\"ada\",\"source\":\"github\"}~%")
             (uiop:read-file-string path :external-format :utf-8))))
      (delete-test-root root))))

(test json-file-writer-actor-is-idempotent
  "Rewriting the same canonical document reports UNCHANGED instead of churning the file."
  (let ((root (make-test-root)))
    (unwind-protect
         (let* ((runtime (make-runtime))
                (actor (create-json-file-writer-actor runtime "json-file-writer" root))
                (write
                  (make-json-file-write
                   "github-members"
                   "ada"
                   (fixture-document)))
                (first (invoke-actor runtime actor write))
                (second (invoke-actor runtime actor write)))
           (is (eq :written (json-file-result-status first)))
           (is (eq :unchanged (json-file-result-status second))))
      (delete-test-root root))))

(test json-file-writer-actor-replaces-changed-records
  "A record with the same collection/id replaces its previous JSON document."
  (let ((root (make-test-root)))
    (unwind-protect
         (let* ((runtime (make-runtime))
                (actor (create-json-file-writer-actor runtime "json-file-writer" root))
                (first
                  (make-json-file-write
                   "github-members"
                   "ada"
                   (fixture-document "github")))
                (second
                  (make-json-file-write
                   "github-members"
                   "ada"
                   (fixture-document "github-api"))))
           (invoke-actor runtime actor first)
           (let* ((result (invoke-actor runtime actor second))
                  (path (json-file-result-path result)))
             (is (eq :written (json-file-result-status result)))
             (is
              (string=
               (format nil "{\"login\":\"ada\",\"source\":\"github-api\"}~%")
               (uiop:read-file-string path :external-format :utf-8)))))
      (delete-test-root root))))

(test json-file-writer-rejects-path-traversal
  "Collection and id are path segments, not an escape hatch out of the configured root."
  (signals invalid-json-file-record-error
    (make-json-file-write "../outside" "ada" (fixture-document)))
  (signals invalid-json-file-record-error
    (make-json-file-write "github-members" ".." (fixture-document)))
  (signals invalid-json-file-record-error
    (make-json-file-write "github/members" "ada" (fixture-document))))
