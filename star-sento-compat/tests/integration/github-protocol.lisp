(in-package :starsentocompat-integration-tests)

(defparameter +github-api-base-url+ "https://api.github.com")
(defparameter +github-api-version+ "2026-03-10")
(defparameter +github-user-agent+ "StarLang-real-actor-system-test")
(defparameter +github-components+ '(:profile :repositories :social :stars :gists))
(defparameter +github-result-kinds+
  '(:github-profile-result
    :github-repositories-result
    :github-social-result
    :github-stars-result
    :github-gists-result))

(defstruct github-rate-limit
  limit
  remaining
  used
  reset
  resource
  retry-after)

(defstruct github-pagination-summary
  (pages 0 :type (integer 0 *))
  (items 0 :type (integer 0 *))
  (status :complete :type keyword)
  bounded-reason
  next-url)

(defstruct github-component-failure
  kind
  status
  message
  retry-after
  rate-limit)

(defstruct github-user-profile
  login
  id
  node-id
  avatar-url
  html-url
  name
  company
  blog
  location
  email
  bio
  public-repos
  public-gists
  followers
  following
  created-at
  updated-at
  account-type)

(defstruct github-user-summary
  login
  id
  node-id
  avatar-url
  html-url
  account-type
  site-admin)

(defstruct github-repository-summary
  id
  node-id
  name
  full-name
  owner-login
  html-url
  description
  fork-p
  archived-p
  disabled-p
  visibility
  default-branch
  language
  size
  stars
  forks
  watchers
  open-issues
  created-at
  pushed-at
  updated-at
  topics)

(defstruct github-gist-file-summary
  filename
  type
  language
  size
  truncated-p)

(defstruct github-gist-summary
  id
  node-id
  html-url
  description
  public-p
  created-at
  updated-at
  owner-login
  files
  comments)

(defstruct github-component-result
  component
  (status :failed :type keyword)
  data
  (request-count 0 :type (integer 0 *))
  pagination
  failure
  rate-limit)

(defstruct github-user-snapshot
  job-id
  username
  status
  profile
  repositories
  social
  stars
  gists
  started-at
  completed-at
  completed-components
  failed-components)

(defstruct github-job-state
  job-id
  username
  reply-to
  started-at
  (results (make-hash-table :test #'eq))
  completion-order)

(defun github-terminal-status-p (status)
  (member status '(:complete :bounded :failed) :test #'eq))

(defun github-result-kind-for-component (component)
  (ecase component
    (:profile :github-profile-result)
    (:repositories :github-repositories-result)
    (:social :github-social-result)
    (:stars :github-stars-result)
    (:gists :github-gists-result)))

(defun github-component-for-result-kind (kind)
  (ecase kind
    (:github-profile-result :profile)
    (:github-repositories-result :repositories)
    (:github-social-result :social)
    (:github-stars-result :stars)
    (:github-gists-result :gists)))

(defun github-snapshot-component (snapshot component)
  (ecase component
    (:profile (github-user-snapshot-profile snapshot))
    (:repositories (github-user-snapshot-repositories snapshot))
    (:social (github-user-snapshot-social snapshot))
    (:stars (github-user-snapshot-stars snapshot))
    (:gists (github-user-snapshot-gists snapshot))))

(defun github-aggregate-status (results)
  (let ((statuses
          (mapcar (lambda (component)
                    (github-component-result-status
                     (gethash component results)))
                  +github-components+)))
    (cond
      ((every (lambda (status) (eq status :complete)) statuses)
       :complete)
      ((every (lambda (status) (eq status :failed)) statuses)
       :failed)
      (t
       :partial))))

(defun github-results-complete-p (results)
  (every (lambda (component)
           (let ((result (gethash component results)))
             (and result
                  (github-terminal-status-p
                   (github-component-result-status result)))))
         +github-components+))
