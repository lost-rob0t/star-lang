(in-package :stargithub)

(defun json-array-list (value)
  (etypecase value
    (list value)
    (vector (coerce value 'list))))

(defun target-option-p (document option)
  (let ((options (target-data-field document "options" #())))
    (and (json-array-p options)
         (find option (json-array-list options) :test #'string=))))

(defun split-tsv (line expected)
  (let ((fields (uiop:split-string line :separator '(#\Tab))))
    (unless (= expected (length fields))
      (fail-github 'github-enumeration-error
                   "GitHub API row had ~D fields, expected ~D."
                   (length fields) expected))
    fields))

(defun parse-github-user-line (line)
  (destructuring-bind (login id html-url avatar-url account-type)
      (split-tsv line 5)
    (list :login login
          :id id
          :html-url html-url
          :avatar-url avatar-url
          :account-type account-type)))

(defun parse-github-contributor-line (line)
  (destructuring-bind
      (login id html-url avatar-url account-type contributions)
      (split-tsv line 6)
    (list :login login
          :id id
          :html-url html-url
          :avatar-url avatar-url
          :account-type account-type
          :contributions (parse-integer contributions))))

(defun parse-github-repository-line (line)
  (destructuring-bind (id name full-name html-url)
      (split-tsv line 4)
    (list :id id
          :name name
          :full-name full-name
          :html-url html-url)))

(defun require-github-credential ()
  (unless (nonempty-string-p (uiop:getenv "STARINTEL_GITHUB_TOKEN"))
    (fail-github 'github-enumeration-error
                 "STARINTEL_GITHUB_TOKEN is not set."))
  (unless (nonempty-string-p (uiop:getenv "GH_TOKEN"))
    (fail-github 'github-enumeration-error
                 "GH_TOKEN is not set for the GitHub CLI backend.")))

(defun github-api-lines (endpoint jq)
  (require-github-credential)
  (handler-case
      (split-lines
       (uiop:run-program
        (list "gh" "api" "--paginate" endpoint "--jq" jq)
        :output :string
        :error-output :string))
    (error (condition)
      (fail-github 'github-enumeration-error
                   "GitHub API request ~A failed: ~A"
                   endpoint condition))))

(defun github-cli-repositories (organization)
  (mapcar
   #'parse-github-repository-line
   (github-api-lines
    (format nil "/orgs/~A/repos?type=public&per_page=100" organization)
    ".[] | [(.id|tostring), .name, .full_name, .html_url] | @tsv")))

(defun github-cli-contributors (repository)
  (mapcar
   #'parse-github-contributor-line
   (github-api-lines
    (format nil "/repos/~A/contributors?per_page=100&anon=0" repository)
    ".[] | [.login, (.id|tostring), .html_url, (.avatar_url // \"\"), .type, (.contributions|tostring)] | @tsv")))

(defun github-cli-stargazers (repository)
  (mapcar
   #'parse-github-user-line
   (github-api-lines
    (format nil "/repos/~A/stargazers?per_page=100" repository)
    ".[] | [.login, (.id|tostring), .html_url, (.avatar_url // \"\"), .type] | @tsv")))

(defun github-cli-followers (login)
  (mapcar
   #'parse-github-user-line
   (github-api-lines
    (format nil "/users/~A/followers?per_page=100" login)
    ".[] | [.login, (.id|tostring), .html_url, (.avatar_url // \"\"), .type] | @tsv")))

(defun github-cli-following (login)
  (mapcar
   #'parse-github-user-line
   (github-api-lines
    (format nil "/users/~A/following?per_page=100" login)
    ".[] | [.login, (.id|tostring), .html_url, (.avatar_url // \"\"), .type] | @tsv")))

(defun canonical-object-from-alist (entries)
  (starcanonicaljson:make-json-object entries))

(defun canonical-array-from-list (values)
  (starcanonicaljson:make-json-array values))

(defun github-identifier (scheme value)
  (canonical-object
   "scheme" scheme
   "value" value
   "issuer" "GitHub"
   "canonical" starcanonicaljson:+json-true+))

(defun github-source (source-id url)
  (canonical-object
   "source_id" source-id
   "kind" "api"
   "name" "GitHub REST API"
   "url" url
   "access_method" "gh api"))

(defun common-document-fields
    (id dataset dtype timestamp sources target-id run-id method data)
  (canonical-object
   "_id" id
   "dataset" dataset
   "dtype" dtype
   "schema_version" "0.9.0"
   "version" 1
   "date_added" timestamp
   "date_updated" timestamp
   "sources" sources
   "evidence" (canonical-array)
   "provenance"
   (canonical-object
    "collector" "star-github"
    "actor" "github"
    "run_id" run-id
    "method" method)
   "lineage"
   (canonical-object
    "source_document_ids" (canonical-array target-id))
   "data" data))

(defun github-organization-id (organization)
  (format nil "github-org-~A" organization))

(defun github-repository-id (repository)
  (format nil "github-repo-~A" (getf repository :id)))

(defun github-user-id (user)
  (format nil "github-user-~A" (getf user :id)))

(defun github-relation-id (predicate subject-id object-id)
  (format nil "github-rel-~A-~A-~A" predicate subject-id object-id))

(defun organization-document
    (target-document organization timestamp run-id)
  (let* ((dataset (object-value target-document "dataset" "github"))
         (target-id (object-value target-document "_id" ""))
         (id (github-organization-id organization))
         (url (format nil "https://github.com/~A" organization)))
    (values
     id
     (common-document-fields
      id dataset "org" timestamp
      (canonical-array
       (github-source
        (format nil "github:organization:~A" organization)
        (format nil "https://api.github.com/orgs/~A" organization)))
      target-id run-id "github-organization"
      (canonical-object
       "name" organization
       "website" url
       "external_ids"
       (canonical-array
        (github-identifier "github-organization-login" organization)))))))

(defun repository-document
    (target-document repository organization timestamp run-id)
  (let* ((dataset (object-value target-document "dataset" "github"))
         (target-id (object-value target-document "_id" ""))
         (id (github-repository-id repository)))
    (values
     id
     (common-document-fields
      id dataset "product" timestamp
      (canonical-array
       (github-source
        (format nil "github:repository:~A" (getf repository :id))
        (format nil "https://api.github.com/repos/~A"
                (getf repository :full-name))))
      target-id run-id "github-organization-repositories"
      (canonical-object
       "name" (getf repository :full-name)
       "display_name" (getf repository :name)
       "product_type" "source_code_repository"
       "website" (getf repository :html-url)
       "manufacturer_id" (github-organization-id organization)
       "external_ids"
       (canonical-array
        (github-identifier "github-repository-id" (getf repository :id))))))))

(defun user-misc (user followers-count following-count)
  (let ((entries
          (list
           (cons "account_type" (getf user :account-type))
           (cons "github_id" (getf user :id)))))
    (when followers-count
      (push (cons "followers_count" followers-count) entries))
    (when following-count
      (push (cons "following_count" following-count) entries))
    (canonical-array
     (canonical-object-from-alist (nreverse entries)))))

(defun graph-user-document
    (target-document user timestamp run-id source-id source-url
     &key followers-count following-count)
  (let* ((dataset (object-value target-document "dataset" "github"))
         (target-id (object-value target-document "_id" ""))
         (id (github-user-id user)))
    (values
     id
     (common-document-fields
      id dataset "user" timestamp
      (canonical-array (github-source source-id source-url))
      target-id run-id "github-user-discovery"
      (canonical-object
       "name" (getf user :login)
       "username" (getf user :login)
       "platform" "github"
       "url" (getf user :html-url)
       "image_url" (getf user :avatar-url)
       "external_ids"
       (canonical-array
        (github-identifier "github-user-id" (getf user :id)))
       "misc" (user-misc user followers-count following-count))))))

(defun graph-relation-document
    (target-document predicate subject-id object-id timestamp run-id
     source-id source-url relation-type &optional qualifiers)
  (let* ((dataset (object-value target-document "dataset" "github"))
         (target-id (object-value target-document "_id" ""))
         (id (github-relation-id predicate subject-id object-id)))
    (values
     id
     (common-document-fields
      id dataset "relation" timestamp
      (canonical-array (github-source source-id source-url))
      target-id run-id relation-type
      (canonical-object
       "subject" subject-id
       "predicate" predicate
       "object" object-id
       "directed" starcanonicaljson:+json-true+
       "relation_type" relation-type
       "qualifiers" (or qualifiers (canonical-object)))))))
