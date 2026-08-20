(defpackage :stargithub-tests
  (:use :cl)
  (:import-from :starlangruntime #:make-runtime #:invoke-actor)
  (:import-from :starartifact #:create-json-file-writer-actor)
  (:import-from :stargithub
                #:github-target-validation-error
                #:github-run-result-status
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
          (gethash "options" data)
          #("enumerate-members"
            "enumerate-repositories"
            "enumerate-contributors"
            "enumerate-stargazers"
            "enumerate-followers"
            "enumerate-following"))
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

(defun fixture-user (login id)
  (list :login login
        :id id
        :html-url (format nil "https://example.invalid/~A" login)
        :avatar-url (format nil "https://example.invalid/~A.png" login)
        :account-type "User"))

(defun fixture-members (organization)
  (declare (ignore organization))
  (list (fixture-user "alice" "101")))

(defun fixture-repositories (organization)
  (declare (ignore organization))
  (list (list :id "201"
              :name "repo"
              :full-name "example-org/repo"
              :html-url "https://example.invalid/example-org/repo")))

(defun fixture-contributors (repository)
  (declare (ignore repository))
  (list (append (fixture-user "bob" "102")
                (list :contributions 7))))

(defun fixture-stargazers (repository)
  (declare (ignore repository))
  (list (fixture-user "carol" "103")))

(defun fixture-followers (login)
  (declare (ignore login))
  (list (fixture-user "dave" "104")))

(defun fixture-following (login)
  (declare (ignore login))
  (list (fixture-user "erin" "105")))

(defun parse-json-file (pathname)
  (with-open-file (stream pathname :direction :input :external-format :utf-8)
    (yason:parse stream)))

(defun first-json-item (value)
  (if (vectorp value)
      (aref value 0)
      (first value)))

(defun check-v090-document (document dtype)
  (check (string= "0.9.0" (gethash "schema_version" document))
         "document is not StarIntel 0.9")
  (check (= 1 (gethash "version" document))
         "document version is not integer 1")
  (check (string= dtype (gethash "dtype" document))
         "document dtype is incorrect")
  (check (nth-value 1 (gethash "sources" document))
         "document is missing sources")
  (check (nth-value 1 (gethash "evidence" document))
         "document is missing evidence")
  (check (hash-table-p (gethash "data" document))
         "document is missing data object"))

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
           (create-github-actor
            runtime "github" "json-files"
            :enumerator #'fixture-members
            :repository-enumerator #'fixture-repositories
            :contributors-enumerator #'fixture-contributors
            :stargazers-enumerator #'fixture-stargazers
            :followers-enumerator #'fixture-followers
            :following-enumerator #'fixture-following)

           (let* ((result (invoke-actor runtime "github" (make-target)))
                  (org-file
                    (merge-pathnames "documents-org/github-org-example-org.json" root))
                  (repo-file
                    (merge-pathnames "documents-product/github-repo-201.json" root))
                  (alice-file
                    (merge-pathnames "documents-user/github-user-101.json" root))
                  (member-relation
                    (merge-pathnames
                     "documents-relation/github-rel-member-of-github-user-101-github-org-example-org.json"
                     root))
                  (contributor-relation
                    (merge-pathnames
                     "documents-relation/github-rel-contributed-to-github-user-102-github-repo-201.json"
                     root))
                  (star-relation
                    (merge-pathnames
                     "documents-relation/github-rel-stars-github-user-103-github-repo-201.json"
                     root))
                  (follower-relation
                    (merge-pathnames
                     "documents-relation/github-rel-follows-github-user-104-github-user-101.json"
                     root))
                  (following-relation
                    (merge-pathnames
                     "documents-relation/github-rel-follows-github-user-101-github-user-105.json"
                     root)))

             (check (eq :completed (github-run-result-status result))
                    "GitHub graph actor did not complete")
             (check (= 12 (github-run-result-documents-written result))
                    "GitHub graph actor wrote the wrong number of documents")

             (dolist (pathname
                      (list org-file repo-file alice-file
                            member-relation contributor-relation star-relation
                            follower-relation following-relation))
               (check (probe-file pathname)
                      (format nil "expected graph file missing: ~A" pathname)))

             (check-v090-document (parse-json-file org-file) "org")
             (check-v090-document (parse-json-file repo-file) "product")

             (let* ((alice (parse-json-file alice-file))
                    (data (gethash "data" alice))
                    (misc (first-json-item (gethash "misc" data))))
               (check-v090-document alice "user")
               (check (string= "alice" (gethash "username" data))
                      "user data.username is missing")
               (check (string= "github" (gethash "platform" data))
                      "user data.platform is missing")
               (check (= 1 (gethash "followers_count" misc))
                      "followers_count was not recorded in v0.9 data.misc")
               (check (= 1 (gethash "following_count" misc))
                      "following_count was not recorded in v0.9 data.misc"))

             (dolist (pathname
                      (list member-relation contributor-relation star-relation
                            follower-relation following-relation))
               (check-v090-document (parse-json-file pathname) "relation"))

             (let* ((follower (parse-json-file follower-relation))
                    (data (gethash "data" follower)))
               (check (string= "follows" (gethash "predicate" data))
                      "follower edge does not use canonical relation data")
               (check (string= "github-user-104" (gethash "subject" data))
                      "follower relation subject is incorrect")
               (check (string= "github-user-101" (gethash "object" data))
                      "follower relation object is incorrect"))

             (check (null (directory (merge-pathnames "target-runs/*.json" root)))
                    "actor must not invent target-run documents"))

           (check (legacy-target-rejected-p runtime)
                  "legacy flat 0.8 target unexpectedly passed strict v0.9 validation"))
      (when (probe-file root)
        (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))
  (format t "~&star-github graph tests passed~%")
  t)
