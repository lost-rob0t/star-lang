(in-package :stargithub)

(defun merge-github-user (index user)
  (setf (gethash (getf user :id) index) user)
  user)

(defun set-github-user-counts (counts user followers following)
  (setf (gethash (getf user :id) counts)
        (list :followers followers :following following)))

(defun github-user-count (counts user key)
  (getf (gethash (getf user :id) counts) key))

(defun persist-graph-relation
    (runtime writer target-document predicate subject-id object-id
     timestamp run-id source-id source-url relation-type
     &optional qualifiers)
  (multiple-value-bind (id document)
      (graph-relation-document
       target-document predicate subject-id object-id timestamp run-id
       source-id source-url relation-type qualifiers)
    (persist-json-document runtime writer "documents-relation" id document)
    1))

(defun persist-github-users
    (runtime writer target-document user-index user-counts timestamp run-id)
  (let ((written 0))
    (maphash
     (lambda (github-id user)
       (declare (ignore github-id))
       (multiple-value-bind (id document)
           (graph-user-document
            target-document user timestamp run-id
            (format nil "github:user:~A" (getf user :id))
            (format nil "https://api.github.com/users/~A" (getf user :login))
            :followers-count (github-user-count user-counts user :followers)
            :following-count (github-user-count user-counts user :following))
         (persist-json-document runtime writer "documents-user" id document)
         (incf written)))
     user-index)
    written))

(defun safe-github-enumeration (label function argument)
  (handler-case
      (values (funcall function argument) t)
    (github-enumeration-error (condition)
      (format *error-output*
              "~&github graph warning [~A ~A]: ~A~%"
              label argument condition)
      (values '() nil))))

(defun collect-member-graph
    (runtime writer target-document organization members
     user-index timestamp run-id)
  (let ((written 0))
    (dolist (github-user members)
      (merge-github-user user-index github-user)
      (incf written
            (persist-graph-relation
             runtime writer target-document
             "member-of"
             (github-user-id github-user)
             (github-organization-id organization)
             timestamp run-id
             (format nil "github:org-members:~A" organization)
             (format nil "https://api.github.com/orgs/~A/members" organization)
             "github-public-org-member")))
    written))

(defun collect-repository-contributors
    (runtime writer target-document repository user-index timestamp run-id
     contributors-enumerator)
  (let ((written 0))
    (multiple-value-bind (contributors complete-p)
        (safe-github-enumeration
         "contributors" contributors-enumerator (getf repository :full-name))
      (declare (ignore complete-p))
      (dolist (contributor contributors)
        (merge-github-user user-index contributor)
        (incf written
              (persist-graph-relation
               runtime writer target-document
               "contributed-to"
               (github-user-id contributor)
               (github-repository-id repository)
               timestamp run-id
               (format nil "github:contributors:~A" (getf repository :id))
               (format nil "https://api.github.com/repos/~A/contributors"
                       (getf repository :full-name))
               "github-repository-contributor"
               (canonical-object
                "contributions" (getf contributor :contributions))))))
    written))

(defun collect-repository-stargazer-identities
    (runtime writer target-document repository user-index timestamp run-id
     stargazers-enumerator)
  (let ((written 0))
    (multiple-value-bind (stargazers complete-p)
        (safe-github-enumeration
         "stargazers" stargazers-enumerator (getf repository :full-name))
      (declare (ignore complete-p))
      (dolist (stargazer stargazers)
        (merge-github-user user-index stargazer)
        (incf written
              (persist-graph-relation
               runtime writer target-document
               "stars"
               (github-user-id stargazer)
               (github-repository-id repository)
               timestamp run-id
               (format nil "github:stargazers:~A" (getf repository :id))
               (format nil "https://api.github.com/repos/~A/stargazers"
                       (getf repository :full-name))
               "github-repository-stargazer"))))
    written))

(defun collect-repository-graph
    (runtime writer target-document organization repositories
     user-index timestamp run-id contributors-enumerator stargazers-enumerator)
  (let ((written 0))
    (dolist (repository repositories)
      (multiple-value-bind (id document)
          (repository-document
           target-document repository organization timestamp run-id)
        (persist-json-document runtime writer "documents-product" id document)
        (incf written))

      (when (target-option-p target-document "enumerate-contributors")
        (incf written
              (collect-repository-contributors
               runtime writer target-document repository user-index
               timestamp run-id contributors-enumerator)))

      ;; GitHub restricted public stargazer identities in July 2026.
      ;; enumerate-stargazers records the count from repository metadata.
      ;; This separate option is only useful for repositories where the token
      ;; is an admin/collaborator and GitHub permits the identity endpoint.
      (when (target-option-p target-document
                             "enumerate-stargazer-identities")
        (incf written
              (collect-repository-stargazer-identities
               runtime writer target-document repository user-index
               timestamp run-id stargazers-enumerator))))
    written))

(defun collect-member-social-graph
    (runtime writer target-document members user-index user-counts
     timestamp run-id followers-enumerator following-enumerator)
  (let ((written 0)
        (collect-followers
          (target-option-p target-document "enumerate-followers"))
        (collect-following
          (target-option-p target-document "enumerate-following")))
    (dolist (github-user members)
      (multiple-value-bind (followers followers-complete-p)
          (if collect-followers
              (safe-github-enumeration
               "followers" followers-enumerator (getf github-user :login))
              (values '() nil))
        (multiple-value-bind (following following-complete-p)
            (if collect-following
                (safe-github-enumeration
                 "following" following-enumerator (getf github-user :login))
                (values '() nil))
          (set-github-user-counts
           user-counts github-user
           (and collect-followers followers-complete-p (length followers))
           (and collect-following following-complete-p (length following)))

          (dolist (follower followers)
            (merge-github-user user-index follower)
            (incf written
                  (persist-graph-relation
                   runtime writer target-document
                   "follows"
                   (github-user-id follower)
                   (github-user-id github-user)
                   timestamp run-id
                   (format nil "github:followers:~A" (getf github-user :id))
                   (format nil "https://api.github.com/users/~A/followers"
                           (getf github-user :login))
                   "github-user-follower")))

          (dolist (followed following)
            (merge-github-user user-index followed)
            (incf written
                  (persist-graph-relation
                   runtime writer target-document
                   "follows"
                   (github-user-id github-user)
                   (github-user-id followed)
                   timestamp run-id
                   (format nil "github:following:~A" (getf github-user :id))
                   (format nil "https://api.github.com/users/~A/following"
                           (getf github-user :login))
                   "github-user-following"))))))
    written))

(defun repositories-required-p (target-document)
  (or (target-option-p target-document "enumerate-repositories")
      (target-option-p target-document "enumerate-contributors")
      (target-option-p target-document "enumerate-stargazers")
      (target-option-p target-document "enumerate-stargazer-identities")))

(defun run-github-target
    (runtime writer target-document
     &key
       (enumerator #'github-cli-enumerator)
       (repository-enumerator #'github-cli-repositories)
       (contributors-enumerator #'github-cli-contributors)
       (stargazers-enumerator #'github-cli-stargazers)
       (followers-enumerator #'github-cli-followers)
       (following-enumerator #'github-cli-following))
  (validate-github-target-document target-document)
  (let* ((started-at (unix-time))
         (timestamp (rfc3339-now))
         (target-id (object-value target-document "_id" ""))
         (organization (target-data-field target-document "target" nil))
         (run-id (format nil "github-run-~A-~D" organization started-at))
         (user-index (make-hash-table :test #'equal))
         (user-counts (make-hash-table :test #'equal))
         (written 0))
    (handler-case
        (let ((members
                (if (target-option-p target-document "enumerate-members")
                    (funcall enumerator organization)
                    '()))
              (repositories
                (if (repositories-required-p target-document)
                    (funcall repository-enumerator organization)
                    '())))
          (multiple-value-bind (id document)
              (organization-document
               target-document organization timestamp run-id)
            (persist-json-document runtime writer "documents-org" id document)
            (incf written))

          (incf written
                (collect-member-graph
                 runtime writer target-document organization members
                 user-index timestamp run-id))

          (incf written
                (collect-repository-graph
                 runtime writer target-document organization repositories
                 user-index timestamp run-id
                 contributors-enumerator stargazers-enumerator))

          (incf written
                (collect-member-social-graph
                 runtime writer target-document members
                 user-index user-counts timestamp run-id
                 followers-enumerator following-enumerator))

          (incf written
                (persist-github-users
                 runtime writer target-document user-index user-counts
                 timestamp run-id))

          (%make-github-run-result
           :status :completed
           :run-id run-id
           :target-id target-id
           :documents-written written
           :error nil))
      (github-enumeration-error (condition)
        (%make-github-run-result
         :status :failed
         :run-id run-id
         :target-id target-id
         :documents-written written
         :error (princ-to-string condition))))))

(defun make-github-actor-definition
    (name writer
     &key
       (enumerator #'github-cli-enumerator)
       (repository-enumerator #'github-cli-repositories)
       (contributors-enumerator #'github-cli-contributors)
       (stargazers-enumerator #'github-cli-stargazers)
       (followers-enumerator #'github-cli-followers)
       (following-enumerator #'github-cli-following)
       service-uri metadata)
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (declare (ignore state))
     (run-github-target
      runtime writer message
      :enumerator enumerator
      :repository-enumerator repository-enumerator
      :contributors-enumerator contributors-enumerator
      :stargazers-enumerator stargazers-enumerator
      :followers-enumerator followers-enumerator
      :following-enumerator following-enumerator))
   :service-uri service-uri
   :accepts :starintel-target
   :produces :github-run-result
   :input-validator #'github-contract-valid-p
   :output-validator #'github-contract-valid-p
   :metadata metadata))

(defun create-github-actor
    (runtime name writer
     &key
       (enumerator #'github-cli-enumerator)
       (repository-enumerator #'github-cli-repositories)
       (contributors-enumerator #'github-cli-contributors)
       (stargazers-enumerator #'github-cli-stargazers)
       (followers-enumerator #'github-cli-followers)
       (following-enumerator #'github-cli-following)
       service-uri metadata)
  (starlangruntime:create-actor
   runtime
   (make-github-actor-definition
    name writer
    :enumerator enumerator
    :repository-enumerator repository-enumerator
    :contributors-enumerator contributors-enumerator
    :stargazers-enumerator stargazers-enumerator
    :followers-enumerator followers-enumerator
    :following-enumerator following-enumerator
    :service-uri service-uri
    :metadata metadata)))
