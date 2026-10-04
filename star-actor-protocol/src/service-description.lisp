(in-package :staractorprotocol)

;; Descriptions are projections of the existing runtime directory/manifest.
;; They are not membership, authentication, lease or partition authority.
(defun service-description-fields (value allowed context)
  (ensure-lifecycle-plist value context)
  (let ((seen nil))
    (loop for (key ignored) on value by #'cddr
          do (unless (and (member key allowed) (not (member key seen)))
               (fail-invalid-wire-envelope "~A has unknown/duplicate field ~S."
                                           context key))
             (push key seen)))
  value)

(defun service-description-strings (value context &key required)
  (unless (and (listp value) (or value (not required))
               (every (lambda (item) (and (stringp item) (< 0 (length item) 257)))
                      value)
               (= (length value) (length (remove-duplicates value :test #'equal))))
    (fail-invalid-wire-envelope "~A requires unique bounded strings." context))
  value)

(defun validate-actor-service-description (description)
  "Validate a bounded, transport-neutral projection. Does not enroll a service."
  (service-description-fields
   description '(:actor-ref :profiles :operations :capabilities :readiness
                 :max-in-flight :max-message-bytes :delivery-classes :scope)
   "actor service description")
  (let ((reference (getf description :actor-ref)))
    (unless (star-actor-reference-p reference)
      (fail-invalid-wire-envelope "Service description requires an ActorRef."))
    ;; Reconstruct to validate mutable DEFSTRUCT fields too.
    (make-star-actor-reference
     :domain-id (star-actor-reference-domain-id reference)
     :logical-path (star-actor-reference-logical-path reference)
     :node-id (star-actor-reference-node-id reference)
     :generation (star-actor-reference-generation reference)
     :protocol-revision (star-actor-reference-protocol-revision reference)
     :capability-set-hash (star-actor-reference-capability-set-hash reference)))
  (dolist (key '(:profiles :operations :capabilities))
    (service-description-strings (getf description key) key
                                 :required (not (eq key :capabilities))))
  (unless (member +actor2actor-semantic-profile+
                  (getf description :profiles) :test #'equal)
    (fail-invalid-wire-envelope "Service must advertise star.actor2actor/1."))
  (unless (member (getf description :readiness) '(:ready :draining :unavailable))
    (fail-invalid-wire-envelope "Invalid service readiness."))
  (dolist (key '(:max-in-flight :max-message-bytes))
    (lifecycle-positive-integer (getf description key) key))
  (let ((classes (getf description :delivery-classes)))
    (unless (and (listp classes) classes
                 (every (lambda (item) (member item '(:volatile :durable))) classes)
                 (= (length classes) (length (remove-duplicates classes))))
      (fail-invalid-wire-envelope "Invalid delivery class set.")))
  (let ((scope (getf description :scope)))
    (service-description-fields scope '(:database-id :dataset-id) "service scope")
    (loop for (key value) on scope by #'cddr
          do (lifecycle-required-nonempty-string value key)))
  t)

(defun actor-service-enrollment-decision
    (description current-reference &key authorized-p lease-valid-p)
  "Pure precondition check for the EXISTING runtime directory owner.
The owner supplies verified authorization and lease observations and performs
its own atomic compare-and-register. This function does not mint authority."
  (validate-actor-service-description description)
  (cond
    ((not (eq authorized-p t)) :unauthorized)
    ((not (eq lease-valid-p t)) :expired)
    ((null current-reference) :register)
    ((not (star-actor-reference-same-logical-actor-p
           (getf description :actor-ref) current-reference)) :identity-mismatch)
    ((< (star-actor-reference-generation (getf description :actor-ref))
        (star-actor-reference-generation current-reference)) :stale-generation)
    ((= (star-actor-reference-generation (getf description :actor-ref))
        (star-actor-reference-generation current-reference))
     (if (and (= (star-actor-reference-protocol-revision
                  (getf description :actor-ref))
                 (star-actor-reference-protocol-revision current-reference))
              (equal (star-actor-reference-capability-set-hash
                      (getf description :actor-ref))
                     (star-actor-reference-capability-set-hash current-reference)))
         :refresh :generation-conflict))
    (t :replace)))

(defun actor-service-admission-decision
    (description operation &key authorized-p lease-valid-p
                             (in-flight 0) message-bytes (delivery-class :volatile))
  "Return a side-effect-free decision. Counters/checks must be serialized by owner."
  (validate-actor-service-description description)
  (unless (and (integerp in-flight) (>= in-flight 0))
    (fail-invalid-wire-envelope "In-flight count must be non-negative."))
  (lifecycle-positive-integer message-bytes "message bytes")
  (cond
    ((not (eq authorized-p t)) :unauthorized)
    ((not (eq lease-valid-p t)) :expired)
    ((not (eq (getf description :readiness) :ready)) :unavailable)
    ((not (member operation (getf description :operations) :test #'equal))
     :operation-unavailable)
    ((not (member delivery-class (getf description :delivery-classes)))
     :delivery-unavailable)
    ((> message-bytes (getf description :max-message-bytes)) :message-too-large)
    ((>= in-flight (getf description :max-in-flight)) :overloaded)
    (t :admit)))

(defun validate-correlated-lifecycle-outcome (request outcome)
  "Validate response identity against the original request, before settlement."
  (validate-lifecycle-envelope request)
  (validate-lifecycle-envelope outcome)
  (unless (and (eq (getf request :kind) :command)
               (member (getf outcome :kind) '(:reply :ack :error))
               (equal (getf request :correlation-id) (getf outcome :correlation-id))
               (equal (getf request :message-id) (getf outcome :causation-id))
               (equal (getf request :actor) (getf outcome :actor))
               (equal (getf request :dataset) (getf outcome :dataset)))
    (fail-invalid-wire-envelope "Outcome does not address the original command."))
  t)

(defun actor2actor-completion-decision
    (request outcome expected-reference observed-reference
     &key terminal-p deadline-expired-p cancel-won-p expected-attempt observed-attempt)
  "Guard before the runtime's serialized first-terminal-wins transition.
Deadline/cancel flags describe authoritative arbitration, not wire assertions.
Generation is actor incarnation, not a Target lease or partition owner fence."
  (validate-correlated-lifecycle-outcome request outcome)
  (lifecycle-positive-integer expected-attempt "expected attempt")
  (lifecycle-positive-integer observed-attempt "observed attempt")
  (cond
    ((or (not (star-actor-reference-same-logical-actor-p
               expected-reference observed-reference))
         (/= (star-actor-reference-generation expected-reference)
             (star-actor-reference-generation observed-reference))) :stale-generation)
    ((/= expected-attempt observed-attempt) :stale-attempt)
    (terminal-p :already-terminal)
    (cancel-won-p :cancelled)
    (deadline-expired-p :deadline-exceeded)
    (t :accept)))

(defun validate-domain-service-definition (definition)
  "Validate local domain composition; ownership stays with the runtime directory."
  (service-description-fields
   definition '(:domain-id :services :max-services :max-in-flight)
   "domain service definition")
  (validate-star-service-token (getf definition :domain-id) "domain")
  (dolist (key '(:max-services :max-in-flight))
    (lifecycle-positive-integer (getf definition key) key))
  (let ((services (getf definition :services)) (seen nil))
    (unless (and (listp services)
                 (<= (length services) (getf definition :max-services)))
      (fail-invalid-wire-envelope "Domain service count exceeds its bound."))
    (dolist (service services)
      (validate-actor-service-description service)
      (let* ((ref (getf service :actor-ref))
             (uri (star-actor-reference-service-uri ref)))
        (unless (string= (getf definition :domain-id)
                         (star-actor-reference-domain-id ref))
          (fail-invalid-wire-envelope "Service belongs to another domain."))
        (when (member uri seen :test #'equal)
          (fail-invalid-wire-envelope "Duplicate logical service in domain."))
        (push uri seen))))
  t)
