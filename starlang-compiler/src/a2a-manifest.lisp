;;;; A2A v1 projection for compiled StarLang external actors.
;;;;
;;;; The compiler owns portable actor semantics. Deployment owns concrete
;;;; public URLs and credentials. This layer therefore projects a validated
;;;; actor IR plus an explicit host-supplied interface URL into JSON-shaped
;;;; wire data without resolving environment variables or embedding secrets.

(in-package #:star-lang.compiler.core)

(defparameter +a2a-actor-protocol+ "a2a-v1")
(defparameter +a2a-wire-version+ "1.0")

(defun a2a-actor-p (actor)
  "Return true when ACTOR is a compiled external A2A actor."
  (and (listp actor)
       (eq (getf actor :kind) :actor)
       (eq (getf actor :runtime) :external)
       (string= (or (getf actor :protocol) "") +a2a-actor-protocol+)))

(defun loopback-http-url-p (url)
  (or (uiop:string-prefix-p "http://localhost" url)
      (uiop:string-prefix-p "http://127.0.0.1" url)
      (uiop:string-prefix-p "http://[::1]" url)))

(defun valid-a2a-interface-url-p (url)
  "A2A production cards require HTTPS; literal loopback HTTP is allowed for local tests."
  (and (stringp url)
       (> (length url) 0)
       (or (uiop:string-prefix-p "https://" url)
           (loopback-http-url-p url))))

(defun require-a2a-actor (actor)
  (unless (a2a-actor-p actor)
    (fail 'invalid-actor-error
          "A2A projection requires an external actor using protocol a2a-v1."))
  actor)

(defun require-a2a-interface-url (url)
  (unless (valid-a2a-interface-url-p url)
    (fail 'invalid-actor-error
          "A2A interface URL must use HTTPS, or HTTP on literal loopback for local tests."))
  url)

(defun a2a-default-description (actor)
  (format nil "StarLang actor ~A exposed through A2A v1."
          (getf actor :name)))

(defun a2a-skill-from-contract (actor contract)
  (let ((capabilities (copy-list (getf actor :capabilities))))
    `(("id" . ,contract)
      ("name" . ,contract)
      ("description" . ,(format nil "Dispatch ~A to StarLang actor ~A."
                                 contract (getf actor :name)))
      ("tags" . ,(append '("star-lang" "starintel") capabilities))
      ("inputModes" . ("application/json"))
      ("outputModes" . ("application/json")))))

(defun a2a-default-skills (actor)
  (mapcar (lambda (contract)
            (a2a-skill-from-contract actor contract))
          (getf actor :accepts)))

(defun validate-a2a-skills (skills)
  "Require a non-empty list of JSON-shaped skill alists with stable ids."
  (unless (and (listp skills) skills)
    (fail 'invalid-actor-error "A2A Agent Card requires at least one skill."))
  (let ((ids '()))
    (dolist (skill skills)
      (unless (listp skill)
        (fail 'invalid-actor-error "A2A skills must be string-keyed alists."))
      (let ((id (cdr (assoc "id" skill :test #'string=))))
        (unless (and (stringp id) (> (length id) 0))
          (fail 'invalid-actor-error "A2A skill id must be a non-empty string."))
        (when (member id ids :test #'string=)
          (fail 'invalid-actor-error "A2A skill ids must be unique; duplicate ~S." id))
        (push id ids))))
  skills)

(defun emit-a2a-agent-card (actor interface-url
                             &key
                               (version "1.0.0")
                               description
                               skills
                               (streaming t))
  "Project compiled ACTOR to A2A v1 Agent Card wire data.

INTERFACE-URL is supplied by the deployment host and is never inferred from the
actor's endpoint placeholder. Returned data is an alist with exact A2A JSON field
names so language-neutral JSON encoders can serialize it without key rewriting."
  (require-a2a-actor actor)
  (require-a2a-interface-url interface-url)
  (unless (and (stringp version) (> (length version) 0))
    (fail 'invalid-actor-error "A2A agent version must be a non-empty string."))
  (let* ((effective-skills (validate-a2a-skills
                            (or skills (a2a-default-skills actor))))
         (capabilities (if streaming '(("streaming" . t)) '())))
    `(("name" . ,(getf actor :name))
      ("description" . ,(or description (a2a-default-description actor)))
      ("supportedInterfaces" .
       (( ("url" . ,interface-url)
          ("protocolBinding" . "JSONRPC")
          ("protocolVersion" . ,+a2a-wire-version+) )))
      ("version" . ,version)
      ("capabilities" . ,capabilities)
      ("defaultInputModes" . ("application/json"))
      ("defaultOutputModes" . ("application/json"))
      ("skills" . ,effective-skills))))
