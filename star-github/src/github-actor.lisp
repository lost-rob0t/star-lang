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

(defun target-field (document key &optional default)
  (let ((direct (object-value document key :missing)))
    (if (eq direct :missing)
        (let ((data (object-value document "data" nil)))
          (object-value data key default))
        direct)))

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
       (string= "target" (or (target-field document "dtype" "") ""))
       (string-equal "github" (or (target-field document "actor" "") ""))
       (github-org-slug-p (target-field document "target" nil))))

(defun validate-github-target-document (document)
  (unless (hash-table-p document)
    (fail-github 'github-target-validation-error
                 "GitHub actor requires a StarIntel JSON document object."))
  (unless (string= "target" (or (target-field document "dtype" "") ""))
    (fail-github 'github-target-validation-error
                 "GitHub actor requires dtype=target."))
  (unless (string-equal "github" (or (target-field document "actor" "") ""))
    (fail-github 'github-target-validation-error
                 "Target actor must be github."))
  (unless (nonempty-string-p
           (or (target-field document "_id" nil)
               (target-field document "id" nil)))
    (fail-github 'github-target-validation-error
                 "Target document requires _id or id."))
  (unless (github-org-slug-p (target-field document "target" nil))
    (fail-github 'github-target-validation-error
                 "GitHub target must be an organization slug."))
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

(defun member-document (target-document member timestamp)
  (let* ((dataset (or (target-field target-document "dataset" nil) "github"))
         (login (getf member :login))
         (github-id (getf member :id))
         (document-id (format nil "github-user-~A" github-id)))
    (values
     document-id
     (canonical-object
      "_id" document-id
      "dataset" dataset
      "dtype" "user"
      "sources" (canonical-array "github:org-members")
      "version" "0.8.0"
      "dateAdded" timestamp
      "dateUpdated" timestamp
      "url" (getf member :html-url)
      "name" login
      "platform" "github"
      "bio" ""
      "misc"
      (canonical-array
       (canonical-object
        "githubId" github-id
        "avatarUrl" (canonical-null-if-empty (getf member :avatar-url))
        "accountType" (getf member :account-type))))))))

(defun target-run-document
    (target-document run-id status started-at completed-at documents-written error)
  (let ((target-id
          (or (target-field target-document "_id" nil)
              (target-field target-document "id" nil)))
        (dataset (or (target-field target-document "dataset" nil) "github"))
        (target (target-field target-document "target" "")))
    (canonical-object
     "_id" run-id
     "dataset" dataset
     "dtype" "target-run"
     "sources" (canonical-array "star-github")
     "version" "0.8.0"
     "dateAdded" started-at
     "dateUpdated" completed-at
     "targetId" target-id
     "actor" "github"
     "target" target
     "status" status
     "startedAt" started-at
     "completedAt" completed-at
     "documentsWritten" documents-written
     "error" (if error error starcanonicaljson:+json-null+))))

(defun persist-json-document (runtime writer collection id document)
  (starlangruntime:invoke-actor
   runtime
   writer
   (starartifact:make-json-file-write collection id document)))

(defun run-github-target
    (runtime writer target-document &key (enumerator #'github-cli-enumerator))
  (validate-github-target-document target-document)
  (let* ((started-at (unix-time))
         (target-id
           (or (target-field target-document "_id" nil)
               (target-field target-document "id" nil)))
         (organization (target-field target-document "target" nil))
         (run-id (format nil "github-run-~A-~D" organization started-at)))
    (handler-case
        (let ((members (funcall enumerator organization))
              (written 0))
          (dolist (member members)
            (multiple-value-bind (document-id document)
                (member-document target-document member started-at)
              (persist-json-document
               runtime writer "documents-user" document-id document)
              (incf written)))
          (let ((completed-at (unix-time)))
            (persist-json-document
             runtime writer "target-runs" run-id
             (target-run-document
              target-document run-id "completed" started-at completed-at written nil))
            (%make-github-run-result
             :status :completed
             :run-id run-id
             :target-id target-id
             :documents-written written
             :error nil)))
      (github-enumeration-error (condition)
        (let* ((completed-at (unix-time))
               (message (princ-to-string condition)))
          (persist-json-document
           runtime writer "target-runs" run-id
           (target-run-document
            target-document run-id "failed" started-at completed-at 0 message))
          (%make-github-run-result
           :status :failed
           :run-id run-id
           :target-id target-id
           :documents-written 0
           :error message))))))

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
