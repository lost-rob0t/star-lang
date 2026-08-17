(in-package :starsentocompat-integration-tests)

(define-condition github-component-timeout (error)
  ((component :initarg :component :reader github-timeout-component))
  (:report
   (lambda (condition stream)
     (format stream "Timed out waiting for controlled HTTP component ~S."
             (github-timeout-component condition)))))

(defstruct github-http-capability
  client
  token
  (connect-timeout 5 :type (integer 1 *))
  (read-timeout 10 :type (integer 1 *))
  (max-redirects 2 :type (integer 0 *))
  (max-pages 2 :type (integer 1 *))
  (max-items 200 :type (integer 1 *)))

(defstruct github-page-collection
  (status :failed :type keyword)
  data
  (request-count 0 :type (integer 0 *))
  pagination
  failure
  rate-limit)

(defun make-github-capability
    (client &key token (connect-timeout 5) (read-timeout 10)
                 (max-redirects 2) (max-pages 2) (max-items 200))
  (check-type client starhttpport:http-client)
  (when token
    (unless (and (stringp token) (> (length token) 0))
      (error "GitHub token must be NIL or a non-empty string.")))
  (make-github-http-capability
   :client client :token token :connect-timeout connect-timeout
   :read-timeout read-timeout :max-redirects max-redirects
   :max-pages max-pages :max-items max-items))

(defun github-username-valid-p (username)
  (and (stringp username) (> (length username) 0)
       (every (lambda (character)
                (or (alphanumericp character) (char= character #\-)))
              username)))

(defun require-github-username (username)
  (unless (github-username-valid-p username)
    (error "GitHub username must contain only letters, digits, and hyphens: ~S" username))
  username)

(defun github-request-headers (capability)
  (append `(("Accept" . "application/vnd.github+json")
            ("X-GitHub-Api-Version" . ,+github-api-version+)
            ("User-Agent" . ,+github-user-agent+))
          (when (github-http-capability-token capability)
            (list (cons "Authorization"
                        (format nil "Bearer ~A"
                                (github-http-capability-token capability)))))))

(defun github-request (capability url)
  (perform-http-request
   (github-http-capability-client capability)
   (make-http-request url :method :get
                      :headers (github-request-headers capability)
                      :connect-timeout (github-http-capability-connect-timeout capability)
                      :read-timeout (github-http-capability-read-timeout capability)
                      :max-redirects (github-http-capability-max-redirects capability))))

(defun github-header-name= (left right)
  (and left right
       (string-equal (etypecase left (string left) (symbol (symbol-name left)))
                     (etypecase right (string right) (symbol (symbol-name right))))))

(defun github-header-value (headers name)
  (cond
    ((hash-table-p headers)
     (loop for key being the hash-keys of headers using (hash-value value)
           when (github-header-name= key name) return value))
    ((and (listp headers) (or (null headers) (consp (first headers))))
     (cdr (find name headers :key #'car :test #'github-header-name=)))
    ((listp headers)
     (loop for (key value) on headers by #'cddr
           when (github-header-name= key name) return value))
    (t nil)))

(defun github-safe-parse-integer (value)
  (when value
    (handler-case (parse-integer (princ-to-string value) :junk-allowed nil)
      (error () nil))))

(defun github-rate-limit-from-response (response)
  (let ((headers (http-response-headers response)))
    (make-github-rate-limit
     :limit (github-safe-parse-integer (github-header-value headers "x-ratelimit-limit"))
     :remaining (github-safe-parse-integer (github-header-value headers "x-ratelimit-remaining"))
     :used (github-safe-parse-integer (github-header-value headers "x-ratelimit-used"))
     :reset (github-safe-parse-integer (github-header-value headers "x-ratelimit-reset"))
     :resource (github-header-value headers "x-ratelimit-resource")
     :retry-after (github-safe-parse-integer (github-header-value headers "retry-after")))))

(defun github-rate-limited-response-p (response rate-limit)
  (let ((status (http-response-status response)))
    (or (= status 429)
        (and (= status 403)
             (or (eql 0 (github-rate-limit-remaining rate-limit))
                 (github-rate-limit-retry-after rate-limit))))))

(defun github-http-failure (response)
  (let* ((status (http-response-status response))
         (rate-limit (github-rate-limit-from-response response)))
    (cond
      ((github-rate-limited-response-p response rate-limit)
       (make-github-component-failure :kind :github-rate-limited :status status
                                      :message "GitHub REST API rate limit reached."
                                      :retry-after (github-rate-limit-retry-after rate-limit)
                                      :rate-limit rate-limit))
      ((= status 404)
       (make-github-component-failure :kind :github-user-not-found :status status
                                      :message "GitHub user resource was not found."
                                      :rate-limit rate-limit))
      ((not (<= 200 status 299))
       (make-github-component-failure :kind :github-http-error :status status
                                      :message (format nil "GitHub REST request returned HTTP ~D." status)
                                      :rate-limit rate-limit))
      (t nil))))

(defun github-json-value (object key)
  (when (hash-table-p object)
    (multiple-value-bind (value present-p) (gethash key object)
      (when present-p (if (eq value :null) nil value)))))

(defun github-decode-json (response)
  (handler-case
      (yason:parse (http-response-body response) :object-as :hash-table :json-nulls-as-keyword t)
    (error (condition)
      (values nil
              (make-github-component-failure
               :kind :github-json-invalid :status (http-response-status response)
               :message (format nil "GitHub JSON could not be parsed: ~A" condition)
               :rate-limit (github-rate-limit-from-response response))))))

(defun normalize-github-user-summary (object)
  (unless (hash-table-p object) (error "GitHub user summary is not an object: ~S" object))
  (make-github-user-summary
   :login (github-json-value object "login") :id (github-json-value object "id")
   :node-id (github-json-value object "node_id") :avatar-url (github-json-value object "avatar_url")
   :html-url (github-json-value object "html_url") :account-type (github-json-value object "type")
   :site-admin (github-json-value object "site_admin")))

(defun normalize-github-repository (object)
  (unless (hash-table-p object) (error "GitHub repository summary is not an object: ~S" object))
  (let ((owner (github-json-value object "owner")))
    (make-github-repository-summary
     :id (github-json-value object "id") :node-id (github-json-value object "node_id")
     :name (github-json-value object "name") :full-name (github-json-value object "full_name")
     :owner-login (and (hash-table-p owner) (github-json-value owner "login"))
     :html-url (github-json-value object "html_url") :description (github-json-value object "description")
     :fork-p (github-json-value object "fork") :archived-p (github-json-value object "archived")
     :disabled-p (github-json-value object "disabled") :visibility (github-json-value object "visibility")
     :default-branch (github-json-value object "default_branch") :language (github-json-value object "language")
     :size (github-json-value object "size") :stars (github-json-value object "stargazers_count")
     :forks (github-json-value object "forks_count") :watchers (github-json-value object "watchers_count")
     :open-issues (github-json-value object "open_issues_count") :created-at (github-json-value object "created_at")
     :pushed-at (github-json-value object "pushed_at") :updated-at (github-json-value object "updated_at")
     :topics (github-json-value object "topics"))))

(defun normalize-github-profile (object)
  (unless (hash-table-p object) (error "GitHub user profile is not an object: ~S" object))
  (make-github-user-profile
   :login (github-json-value object "login") :id (github-json-value object "id")
   :node-id (github-json-value object "node_id") :avatar-url (github-json-value object "avatar_url")
   :html-url (github-json-value object "html_url") :name (github-json-value object "name")
   :company (github-json-value object "company") :blog (github-json-value object "blog")
   :location (github-json-value object "location") :email (github-json-value object "email")
   :bio (github-json-value object "bio") :public-repos (github-json-value object "public_repos")
   :public-gists (github-json-value object "public_gists") :followers (github-json-value object "followers")
   :following (github-json-value object "following") :created-at (github-json-value object "created_at")
   :updated-at (github-json-value object "updated_at") :account-type (github-json-value object "type")))

(defun normalize-github-gist-files (files)
  (when (hash-table-p files)
    (sort (loop for key being the hash-keys of files using (hash-value value)
                when (hash-table-p value)
                  collect (make-github-gist-file-summary
                           :filename (or (github-json-value value "filename") key)
                           :type (github-json-value value "type")
                           :language (github-json-value value "language")
                           :size (github-json-value value "size")
                           :truncated-p (github-json-value value "truncated")))
          #'string< :key (lambda (file) (or (github-gist-file-summary-filename file) "")))))

(defun normalize-github-gist (object)
  (unless (hash-table-p object) (error "GitHub Gist summary is not an object: ~S" object))
  (let ((owner (github-json-value object "owner")))
    (make-github-gist-summary
     :id (github-json-value object "id") :node-id (github-json-value object "node_id")
     :html-url (github-json-value object "html_url") :description (github-json-value object "description")
     :public-p (github-json-value object "public") :created-at (github-json-value object "created_at")
     :updated-at (github-json-value object "updated_at")
     :owner-login (and (hash-table-p owner) (github-json-value owner "login"))
     :files (normalize-github-gist-files (github-json-value object "files"))
     :comments (github-json-value object "comments"))))

(defun github-split-string (string separator)
  (loop with start = 0
        for position = (position separator string :start start)
        collect (subseq string start position)
        while position do (setf start (1+ position))))

(defun github-link-next-url (headers)
  (let ((link (github-header-value headers "link")))
    (when link
      (loop for part in (github-split-string (princ-to-string link) #\,)
            when (search "rel=\"next\"" part :test #'char-equal)
              do (let ((left (position #\< part)) (right (position #\> part)))
                   (when (and left right (< left right))
                     (return (subseq part (1+ left) right))))))))

(defun github-page-collection (capability initial-url normalizer)
  (let ((url initial-url) (pages 0) (items 0) (values '()) (last-rate-limit nil))
    (loop
      (incf pages)
      (let ((response
              (handler-case (github-request capability url)
                (http-port-error (condition)
                  (return (make-github-page-collection
                           :status :failed :data (nreverse values) :request-count pages
                           :pagination (make-github-pagination-summary :pages pages :items items :status :failed :next-url url)
                           :failure (make-github-component-failure :kind :github-http-error :message (princ-to-string condition))))))))
        (setf last-rate-limit (github-rate-limit-from-response response))
        (let ((failure (github-http-failure response)))
          (when failure
            (return (make-github-page-collection
                     :status :failed :data (nreverse values) :request-count pages
                     :pagination (make-github-pagination-summary :pages pages :items items :status :failed :next-url url)
                     :failure failure :rate-limit last-rate-limit))))
        (multiple-value-bind (decoded json-failure) (github-decode-json response)
          (when json-failure
            (return (make-github-page-collection
                     :status :failed :data (nreverse values) :request-count pages
                     :pagination (make-github-pagination-summary :pages pages :items items :status :failed :next-url url)
                     :failure json-failure :rate-limit last-rate-limit)))
          (unless (listp decoded)
            (return (make-github-page-collection
                     :status :failed :data (nreverse values) :request-count pages
                     :pagination (make-github-pagination-summary :pages pages :items items :status :failed :next-url url)
                     :failure (make-github-component-failure :kind :github-response-invalid
                                                             :status (http-response-status response)
                                                             :message "GitHub collection response was not a JSON array."
                                                             :rate-limit last-rate-limit)
                     :rate-limit last-rate-limit)))
          (handler-case
              (let* ((normalized (mapcar normalizer decoded))
                     (remaining (- (github-http-capability-max-items capability) items))
                     (accepted-count (min remaining (length normalized))))
                (setf values (nconc (nreverse (subseq normalized 0 accepted-count)) values))
                (incf items accepted-count)
                (let ((next-url (github-link-next-url (http-response-headers response))))
                  (cond
                    ((< accepted-count (length normalized))
                     (return (make-github-page-collection
                              :status :bounded :data (nreverse values) :request-count pages
                              :pagination (make-github-pagination-summary :pages pages :items items :status :bounded
                                                                          :bounded-reason :max-items :next-url next-url)
                              :rate-limit last-rate-limit)))
                    ((and next-url (>= pages (github-http-capability-max-pages capability)))
                     (return (make-github-page-collection
                              :status :bounded :data (nreverse values) :request-count pages
                              :pagination (make-github-pagination-summary :pages pages :items items :status :bounded
                                                                          :bounded-reason :max-pages :next-url next-url)
                              :rate-limit last-rate-limit)))
                    ((and next-url (>= items (github-http-capability-max-items capability)))
                     (return (make-github-page-collection
                              :status :bounded :data (nreverse values) :request-count pages
                              :pagination (make-github-pagination-summary :pages pages :items items :status :bounded
                                                                          :bounded-reason :max-items :next-url next-url)
                              :rate-limit last-rate-limit)))
                    (next-url (setf url next-url))
                    (t (return (make-github-page-collection
                                :status :complete :data (nreverse values) :request-count pages
                                :pagination (make-github-pagination-summary :pages pages :items items :status :complete)
                                :rate-limit last-rate-limit))))))
            (error (condition)
              (return (make-github-page-collection
                       :status :failed :data (nreverse values) :request-count pages
                       :pagination (make-github-pagination-summary :pages pages :items items :status :failed :next-url url)
                       :failure (make-github-component-failure
                                 :kind :github-response-invalid :status (http-response-status response)
                                 :message (format nil "GitHub response normalization failed: ~A" condition)
                                 :rate-limit last-rate-limit)
                       :rate-limit last-rate-limit)))))))))

(defun github-component-from-page (component page)
  (make-github-component-result
   :component component :status (github-page-collection-status page)
   :data (github-page-collection-data page) :request-count (github-page-collection-request-count page)
   :pagination (github-page-collection-pagination page) :failure (github-page-collection-failure page)
   :rate-limit (github-page-collection-rate-limit page)))

(defun github-fetch-profile (capability username)
  (require-github-username username)
  (let ((response
          (handler-case
              (github-request capability (format nil "~A/users/~A" +github-api-base-url+ username))
            (http-port-error (condition)
              (return-from github-fetch-profile
                (make-github-component-result
                 :component :profile :status :failed :request-count 1
                 :failure (make-github-component-failure :kind :github-http-error :message (princ-to-string condition))))))))
    (let ((rate-limit (github-rate-limit-from-response response))
          (failure (github-http-failure response)))
      (when failure
        (return-from github-fetch-profile
          (make-github-component-result :component :profile :status :failed :request-count 1
                                        :failure failure :rate-limit rate-limit)))
      (multiple-value-bind (decoded json-failure) (github-decode-json response)
        (when json-failure
          (return-from github-fetch-profile
            (make-github-component-result :component :profile :status :failed :request-count 1
                                          :failure json-failure :rate-limit rate-limit)))
        (handler-case
            (make-github-component-result :component :profile :status :complete :request-count 1
                                          :data (normalize-github-profile decoded) :rate-limit rate-limit)
          (error (condition)
            (make-github-component-result
             :component :profile :status :failed :request-count 1
             :failure (make-github-component-failure
                       :kind :github-response-invalid :status (http-response-status response)
                       :message (format nil "GitHub profile normalization failed: ~A" condition)
                       :rate-limit rate-limit)
             :rate-limit rate-limit)))))))

(defun github-user-repositories-url (username)
  (format nil "~A/users/~A/repos?type=owner&per_page=100" +github-api-base-url+ (require-github-username username)))
(defun github-user-followers-url (username)
  (format nil "~A/users/~A/followers?per_page=100" +github-api-base-url+ (require-github-username username)))
(defun github-user-following-url (username)
  (format nil "~A/users/~A/following?per_page=100" +github-api-base-url+ (require-github-username username)))
(defun github-user-stars-url (username)
  (format nil "~A/users/~A/starred?per_page=100" +github-api-base-url+ (require-github-username username)))
(defun github-user-gists-url (username)
  (format nil "~A/users/~A/gists?per_page=100" +github-api-base-url+ (require-github-username username)))

(defun github-fetch-repositories (capability username)
  (github-component-from-page :repositories
                              (github-page-collection capability (github-user-repositories-url username)
                                                      #'normalize-github-repository)))
(defun github-fetch-stars (capability username)
  (github-component-from-page :stars
                              (github-page-collection capability (github-user-stars-url username)
                                                      #'normalize-github-repository)))
(defun github-fetch-gists (capability username)
  (github-component-from-page :gists
                              (github-page-collection capability (github-user-gists-url username)
                                                      #'normalize-github-gist)))

(defun github-social-status (followers following)
  (cond ((or (eq (github-page-collection-status followers) :failed)
             (eq (github-page-collection-status following) :failed)) :failed)
        ((or (eq (github-page-collection-status followers) :bounded)
             (eq (github-page-collection-status following) :bounded)) :bounded)
        (t :complete)))

(defun github-fetch-social (capability username)
  (let ((followers (github-page-collection capability (github-user-followers-url username)
                                           #'normalize-github-user-summary))
        (following (github-page-collection capability (github-user-following-url username)
                                           #'normalize-github-user-summary)))
    (make-github-component-result
     :component :social :status (github-social-status followers following)
     :data (list :followers (github-page-collection-data followers)
                 :following (github-page-collection-data following))
     :request-count (+ (github-page-collection-request-count followers)
                       (github-page-collection-request-count following))
     :pagination (list :followers (github-page-collection-pagination followers)
                       :following (github-page-collection-pagination following))
     :failure (remove nil (list (github-page-collection-failure followers)
                                (github-page-collection-failure following)))
     :rate-limit (or (github-page-collection-rate-limit following)
                     (github-page-collection-rate-limit followers)))))
