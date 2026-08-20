(defpackage :stargithub-tests
  (:use :cl)
  (:import-from :starlangruntime #:make-runtime #:invoke-actor)
  (:import-from :starartifact #:create-json-file-writer-actor)
  (:import-from :stargithub
                #:github-target-validation-error
                #:github-run-result-status
                #:github-run-result-run-id
                #:github-run-result-documents-written
                #:create-github-actor)
  (:export #:run-tests))

(in-package :stargithub-tests)

(defun check (truth message)
  (unless truth (error message)))

(defun make-target ()
  (let ((document (make-hash-table :test #'equal))
        (data (make-hash-table :test #'equal)))
    (setf (gethash "_id" document) "github-example"
          (gethash "dataset" document) "example"
          (gethash "dtype" document) "target"
          (gethash "schema_version" document) "0.9.0"
          (gethash "version" document) 1
          (gethash "date_added" document) "2026-08-20T00:00:00Z"
          (gethash "date_updated" document) "2026-08-20T00:00:00Z"
          (gethash "sources" document) #()
          (gethash "evidence" document) #()
          (gethash "data" document) data)
    (setf (gethash "actor" data) "github"
          (gethash "target" data) "example-org"
          (gethash "target_type" data) "github-organization"
          (gethash "delay" data) 86400
          (gethash "recurring" data) t
          (gethash "options" data) #("enumerate-members"))
    document))

(defun make-legacy-target ()
  (let ((document (make-hash-table :test #'equal)))
    (setf (gethash "_id" document) "github-example"
          (gethash "dataset" document) "example"
          (gethash "dtype" document) "target"
          (gethash "version" document) "0.8.0"
          (gethash "actor" document) "github"
          (gethash "target" document) "example-org"
          (gethash "options" document) #("enumerate-members"))
    document))

(defun fixture-members (organization)
  (declare (ignore organization))
  (list (list :login "alice"
              :id "101"
              :html-url "https://example.invalid/alice"
              :avatar-url ""
              :account-type "User")))

(defun parse-json-file (pathname)
  (with-open-file (stream pathname :direction :input :external-format :utf-8)
    (yason:parse stream)))

(defun legacy-target-rejected-p (runtime)
  (handler-case
      (progn
        (invoke-actor runtime "github" (make-legacy-target))
        nil)
    (github-target-validation-error () t)))

(defun run-tests ()
  (let* ((root (merge-pathnames "star-github-test/" (uiop:temporary-directory)))
         (runtime (make-runtime)))
    (unwind-protect
         (progn
           (when (probe-file root)
             (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))
           (create-json-file-writer-actor runtime "json-files" root)
           (create-github-actor runtime "github" "json-files"
                                :enumerator #'fixture-members)
           (let* ((result (invoke-actor runtime "github" (make-target)))
                  (user-file
                    (merge-pathnames "documents-user/github-user-101.json" root))
                  (document (parse-json-file user-file))
                  (data (gethash "data" document)))
             (check (eq :completed (github-run-result-status result))
                    "GitHub actor did not complete")
             (check (= 1 (github-run-result-documents-written result))
                    "GitHub actor wrote the wrong number of documents")
             (check (probe-file user-file) "user JSON was not persisted")
             (check (string= "0.9.0" (gethash "schema_version" document))
                    "user JSON is not StarIntel 0.9")
             (check (= 1 (gethash "version" document))
                    "user JSON version is not the v0.9 integer revision")
             (check (string= "user" (gethash "dtype" document))
                    "user JSON dtype is incorrect")
             (check (string= "alice" (gethash "username" data))
                    "user JSON data.username is missing")
             (check (string= "github" (gethash "platform" data))
                    "user JSON data.platform is missing")
             (check (null (directory (merge-pathnames "target-runs/*.json" root)))
                    "actor must not invent target-run documents"))
           (check (legacy-target-rejected-p runtime)
                  "legacy flat 0.8 target unexpectedly passed strict v0.9 validation"))
      (when (probe-file root)
        (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))
  (format t "~&star-github tests passed~%")
  t)
