(in-package :stargithub)

(define-condition github-target-error (error)
  ((message :initarg :message :reader github-target-error-message))
  (:report
   (lambda (condition stream)
     (write-string (github-target-error-message condition) stream))))

(define-condition github-target-validation-error (github-target-error) ())
(define-condition github-enumeration-error (github-target-error) ())

(defun fail-github (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defstruct (github-run-result
            (:constructor %make-github-run-result
                (&key status run-id target-id documents-written error)))
  (status :completed :type keyword)
  (run-id "" :type string)
  (target-id "" :type string)
  (documents-written 0 :type (integer 0 *))
  error)

(defun unix-time ()
  (- (get-universal-time) 2208988800))

(defun rfc3339-now ()
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil
            "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour minute second)))

(defun nonempty-string-p (value)
  (and (stringp value) (> (length value) 0)))

(defun github-org-slug-p (value)
  (and (nonempty-string-p value)
       (<= (length value) 39)
       (alphanumericp (char value 0))
       (alphanumericp (char value (1- (length value))))
       (every (lambda (character)
                (or (alphanumericp character)
                    (char= character #\-)))
              value)))

(defun object-value (object key &optional default)
  (if (hash-table-p object)
      (gethash key object default)
      default))

(defun object-has-key-p (object key)
  (and (hash-table-p object)
       (nth-value 1 (gethash key object))))

(defun json-array-p (value)
  (or (listp value) (vectorp value)))

(defun target-data (document)
  (object-value document "data" nil))

(defun target-data-field (document key &optional default)
  (object-value (target-data document) key default))

(defun candidate-target-actor (document)
  (or (target-data-field document "actor" nil)
      (object-value document "actor" nil)))

(defun read-starintel-json-document (pathname)
  (handler-case
      (with-open-file (stream pathname :direction :input :external-format :utf-8)
        (let ((document (yason:parse stream)))
          (unless (hash-table-p document)
            (fail-github 'github-target-validation-error
                         "StarIntel target file ~A must contain one JSON object."
                         pathname))
          document))
    (github-target-error (condition)
      (error condition))
    (error (condition)
      (fail-github 'github-target-validation-error
                   "Could not parse StarIntel target file ~A: ~A"
                   pathname condition))))

(defun github-target-document-p (document)
  (and (hash-table-p document)
       (string= "target" (or (object-value document "dtype" "") ""))
       (string-equal "github" (or (candidate-target-actor document) ""))))

(defun validate-required-v090-envelope (document)
  (unless (nonempty-string-p (object-value document "_id" nil))
    (fail-github 'github-target-validation-error
                 "StarIntel 0.9 target requires non-empty _id."))
  (unless (nonempty-string-p (object-value document "dataset" nil))
    (fail-github 'github-target-validation-error
                 "StarIntel 0.9 target requires non-empty dataset."))
  (unless (string= "target" (or (object-value document "dtype" "") ""))
    (fail-github 'github-target-validation-error
                 "StarIntel 0.9 GitHub actor requires dtype=target."))
  (unless (string= "0.9.0" (or (object-value document "schema_version" "") ""))
    (fail-github 'github-target-validation-error
                 "StarIntel GitHub target must use schema_version 0.9.0."))
  (let ((version (object-value document "version" nil)))
    (unless (and (integerp version) (>= version 1))
      (fail-github 'github-target-validation-error
                   "StarIntel 0.9 target requires integer version >= 1.")))
  (dolist (field '("date_added" "date_updated"))
    (unless (nonempty-string-p (object-value document field nil))
      (fail-github 'github-target-validation-error
                   "StarIntel 0.9 target requires ~A." field)))
  (dolist (field '("sources" "evidence"))
    (unless (and (object-has-key-p document field)
                 (json-array-p (object-value document field nil)))
      (fail-github 'github-target-validation-error
                   "StarIntel 0.9 target requires array field ~A." field)))
  (unless (hash-table-p (target-data document))
    (fail-github 'github-target-validation-error
                 "StarIntel 0.9 target requires a data object."))
  document)

(defun validate-github-target-document (document)
  (unless (hash-table-p document)
    (fail-github 'github-target-validation-error
                 "GitHub actor requires a StarIntel JSON document object."))
  (validate-required-v090-envelope document)
  (unless (string-equal "github"
                        (or (target-data-field document "actor" "") ""))
    (fail-github 'github-target-validation-error
                 "StarIntel 0.9 target data.actor must be github."))
  (unless (github-org-slug-p (target-data-field document "target" nil))
    (fail-github 'github-target-validation-error
                 "StarIntel 0.9 target data.target must be a GitHub organization slug."))
  (when (object-has-key-p (target-data document) "options")
    (unless (json-array-p (target-data-field document "options" nil))
      (fail-github 'github-target-validation-error
                   "StarIntel 0.9 target data.options must be an array.")))
  document)

(defun split-lines (text)
  (remove-if (lambda (line) (zerop (length line)))
             (uiop:split-string text :separator '(#\Newline #\Return))))

(defun parse-member-line (line)
  (let ((fields (uiop:split-string line :separator '(#\Tab))))
    (unless (= 5 (length fields))
      (fail-github 'github-enumeration-error
                   "GitHub member row had ~D fields, expected 5."
                   (length fields)))
    (destructuring-bind (login id html-url avatar-url account-type) fields
      (list :login login
            :id id
            :html-url html-url
            :avatar-url avatar-url
            :account-type account-type))))

(defun github-cli-enumerator (organization)
  "Enumerate public organization members with the authenticated GitHub CLI.
STARINTEL_GITHUB_TOKEN is the actor credential. GH_TOKEN is consumed by gh and
is set to the same repository secret by the workflow."
  (let ((token (uiop:getenv "STARINTEL_GITHUB_TOKEN")))
    (unless (nonempty-string-p token)
      (fail-github 'github-enumeration-error
                   "STARINTEL_GITHUB_TOKEN is not set.")))
  (unless (nonempty-string-p (uiop:getenv "GH_TOKEN"))
    (fail-github 'github-enumeration-error
                 "GH_TOKEN is not set for the GitHub CLI backend."))
  (handler-case
      (let* ((endpoint (format nil "/orgs/~A/members?per_page=100" organization))
             (output
               (uiop:run-program
                (list "gh" "api" "--paginate" endpoint
                      "--jq"
                      ".[] | [.login, (.id|tostring), .html_url, (.avatar_url // \"\"), .type] | @tsv")
                :output :string
                :error-output :string)))
        (mapcar #'parse-member-line (split-lines output)))
    (error (condition)
      (fail-github 'github-enumeration-error
                   "GitHub enumeration for ~A failed: ~A"
                   organization condition))))

(defun canonical-object (&rest pairs)
  (starcanonicaljson:make-json-object
   (loop for (key value) on pairs by #'cddr
         collect (cons key value))))

(defun canonical-array (&rest values)
  (starcanonicaljson:make-json-array values))

(defun canonical-null-if-empty (value)
  (if (nonempty-string-p value)
      value
      starcanonicaljson:+json-null+))

(defun github-source (organization)
  (canonical-object
   "source_id" (format nil "github:org-members:~A" organization)
   "kind" "api"
   "name" "GitHub REST API"
   "url" (format nil "https://api.github.com/orgs/~A/members" organization)
   "access_method" "gh api"))

(defun member-document (target-document member timestamp run-id)
  (let* ((dataset (object-value target-document "dataset" "github"))
         (target-id (object-value target-document "_id" ""))
         (organization (target-data-field target-document "target" ""))
         (login (getf member :login))
         (github-id (getf member :id))
         (document-id (format nil "github-user-~A" github-id)))
    (values
     document-id
     (canonical-object
      "_id" document-id
      "dataset" dataset
      "dtype" "user"
      "schema_version" "0.9.0"
      "version" 1
      "date_added" timestamp
      "date_updated" timestamp
      "sources" (canonical-array (github-source organization))
      "evidence" (canonical-array)
      "provenance"
      (canonical-object
       "collector" "star-github"
       "actor" "github"
       "run_id" run-id
       "method" "github-org-members")
      "lineage"
      (canonical-object
       "source_document_ids" (canonical-array target-id))
      "data"
      (canonical-object
       "url" (getf member :html-url)
       "username" login
       "name" login
       "platform" "github"
       "bio" ""
       "misc"
       (canonical-array
        (canonical-object
         "github_id" github-id
         "avatar_url" (canonical-null-if-empty (getf member :avatar-url))
         "account_type" (getf member :account-type))))))))

(defun persist-json-document (runtime writer collection id document)
  (starlangruntime:invoke-actor
   runtime
   writer
   (starartifact:make-json-file-write collection id document)))

(defun run-github-target
    (runtime writer target-document &key (enumerator #'github-cli-enumerator))
  (validate-github-target-document target-document)
  (let* ((started-at (unix-time))
         (timestamp (rfc3339-now))
         (target-id (object-value target-document "_id" ""))
         (organization (target-data-field target-document "target" nil))
         (run-id (format nil "github-run-~A-~D" organization started-at)))
    (handler-case
        (let ((members (funcall enumerator organization))
              (written 0))
          (dolist (member members)
            (multiple-value-bind (document-id document)
                (member-document target-document member timestamp run-id)
              (persist-json-document
               runtime writer "documents-user" document-id document)
              (incf written)))
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
         :documents-written 0
         :error (princ-to-string condition))))))

(defun github-contract-valid-p (contract value)
  (case contract
    (:starintel-target (hash-table-p value))
    (:github-run-result (github-run-result-p value))
    (otherwise nil)))

(defun make-github-actor-definition
    (name writer &key (enumerator #'github-cli-enumerator) service-uri metadata)
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (declare (ignore state))
     (run-github-target runtime writer message :enumerator enumerator))
   :service-uri service-uri
   :accepts :starintel-target
   :produces :github-run-result
   :input-validator #'github-contract-valid-p
   :output-validator #'github-contract-valid-p
   :metadata metadata))

(defun create-github-actor
    (runtime name writer &key (enumerator #'github-cli-enumerator) service-uri metadata)
  (starlangruntime:create-actor
   runtime
   (make-github-actor-definition
    name writer
    :enumerator enumerator
    :service-uri service-uri
    :metadata metadata)))
