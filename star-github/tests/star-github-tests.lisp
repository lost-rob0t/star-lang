(defpackage :stargithub-tests
  (:use :cl)
  (:import-from :starlangruntime #:make-runtime #:invoke-actor)
  (:import-from :starartifact #:create-json-file-writer-actor)
  (:import-from :stargithub
                #:github-run-result-status
                #:github-run-result-run-id
                #:github-run-result-documents-written
                #:create-github-actor)
  (:export #:run-tests))

(in-package :stargithub-tests)

(defun check (truth message)
  (unless truth (error message)))

(defun make-target ()
  (let ((document (make-hash-table :test #'equal)))
    (setf (gethash "_id" document) "github-example"
          (gethash "dataset" document) "example"
          (gethash "dtype" document) "target"
          (gethash "version" document) "0.8.0"
          (gethash "actor" document) "github"
          (gethash "target" document) "example-org"
          (gethash "delay" document) 86400
          (gethash "recurring" document) t
          (gethash "options" document) nil)
    document))

(defun fixture-members (organization)
  (declare (ignore organization))
  (list (list :login "alice"
              :id "101"
              :html-url "https://example.invalid/alice"
              :avatar-url ""
              :account-type "User")))

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
                  (user-file (merge-pathnames "documents-user/github-user-101.json" root))
                  (run-file (merge-pathnames
                             (format nil "target-runs/~A.json"
                                     (github-run-result-run-id result))
                             root)))
             (check (eq :completed (github-run-result-status result))
                    "GitHub actor did not complete")
             (check (= 1 (github-run-result-documents-written result))
                    "GitHub actor wrote the wrong number of documents")
             (check (probe-file user-file) "user JSON was not persisted")
             (check (probe-file run-file) "target-run JSON was not persisted")))
      (when (probe-file root)
        (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))
  (format t "~&star-github tests passed~%")
  t)
