(in-package :stardatabaseprotocol)

(defparameter +database-read-capability+ "databaseRead")
(defparameter +database-write-capability+ "databaseWrite")
(defparameter +database-transaction-capability+ "databaseTransaction")
(defparameter +database-subscribe-capability+ "databaseSubscribe")
(defparameter +database-admin-capability+ "databaseAdmin")

(defparameter +database-read-request-type+
  "org.starintel/database@1/db-read-request")
(defparameter +database-write-request-type+
  "org.starintel/database@1/db-write-request")
(defparameter +database-transaction-request-type+
  "org.starintel/database@1/db-transaction-request")
(defparameter +database-subscribe-request-type+
  "org.starintel/database@1/db-subscribe-request")
(defparameter +database-result-type+
  "org.starintel/database@1/db-result")
(defparameter +database-write-result-type+
  "org.starintel/database@1/db-write-result")
(defparameter +database-error-type+
  "org.starintel/database@1/db-error")

(define-condition database-contract-error (error)
  ((code :initarg :code :reader database-contract-error-code)
   (message :initarg :message :reader database-contract-error-message))
  (:report
   (lambda (condition stream)
     (write-string (database-contract-error-message condition) stream))))

(defun fail-database-contract (code control &rest arguments)
  (error 'database-contract-error
         :code code
         :message (apply #'format nil control arguments)))

(defun database-access-capability (access)
  "Return the canonical actor capability required for ACCESS."
  (ecase access
    ((:read :logic) +database-read-capability+)
    (:write +database-write-capability+)
    (:transaction +database-transaction-capability+)
    (:subscribe +database-subscribe-capability+)
    (:admin +database-admin-capability+)))

(defun database-message-access (message-type)
  "Return the database access class implied by a canonical request type."
  (cond
    ((string= message-type +database-read-request-type+) :read)
    ((string= message-type +database-write-request-type+) :write)
    ((string= message-type +database-transaction-request-type+) :transaction)
    ((string= message-type +database-subscribe-request-type+) :subscribe)
    (t nil)))

(defun actor-capabilities (actor)
  (unless (and (listp actor)
               (eq (getf actor :kind) :actor))
    (fail-database-contract
     :invalid-actor
     "Expected compiled StarLang actor IR."))
  (let ((capabilities (getf actor :capabilities)))
    (unless (and (listp capabilities)
                 (every #'stringp capabilities))
      (fail-database-contract
       :invalid-capabilities
       "Actor capabilities must be a list of strings."))
    capabilities))

(defun database-actor-capability-p (actor access)
  "True when ACTOR explicitly carries the capability required for ACCESS."
  (not
   (null
    (member (database-access-capability access)
            (actor-capabilities actor)
            :test #'string=))))

(defun validate-database-actor-access (actor access)
  "Require ACTOR to carry exactly the authority needed for ACCESS.

This function never infers write authority from read authority or vice versa."
  (let ((required (database-access-capability access)))
    (unless (database-actor-capability-p actor access)
      (fail-database-contract
       :missing-capability
       "Actor ~A lacks required database capability ~A."
       (or (getf actor :name) "<unnamed>")
       required))
    t))

(defun database-read-only-actor-p (actor)
  "True when ACTOR can read/subscribe but has no mutation/admin authority."
  (let ((capabilities (actor-capabilities actor)))
    (and
     (member +database-read-capability+ capabilities :test #'string=)
     (not
      (intersection
       capabilities
       (list +database-write-capability+
             +database-transaction-capability+
             +database-admin-capability+)
       :test #'string=)))))
