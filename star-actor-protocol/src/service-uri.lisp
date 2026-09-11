(in-package :staractorprotocol)

;;;; Legacy star://domain:address:actor-name compatibility input.
;;;;
;;;; Normative sources: STAR-SERVER-041 ("Relationship to Legacy
;;;; STAR-LANG-004") and the STAR-LANG-004 amendment ("Legacy StarLang URI
;;;; Compatibility").  Rules enforced here:
;;;;   * the legacy tuple is parseable ONLY through this explicit
;;;;     compatibility API; parse-star-uri rejects it;
;;;;   * there is no automatic mapping from the old tuple to a canonical
;;;;     identity: the legacy domain is never reused as a canonical
;;;;     authority and no legacy.<domain> authority is invented;
;;;;   * migration requires an explicit canonical target URI or an
;;;;     explicit migration map supplied by the caller, and normalizes
;;;;     immediately into the canonical RFC representation;
;;;;   * new code never emits the legacy tuple format.

(define-condition invalid-star-service-uri-error
    (star-actor-protocol-error)
  ())

(defun fail-invalid-star-service-uri (control &rest arguments)
  (error 'invalid-star-service-uri-error
         :message (apply #'format nil control arguments)))

(defstruct (star-service-uri
            (:constructor %make-star-service-uri
                (domain address actor-name)))
  (domain "" :type string)
  (address "" :type string)
  (actor-name "" :type string))

(defun valid-star-service-token-character-p (character)
  (or (char<= #\a character #\z)
      (char<= #\0 character #\9)
      (member character '(#\- #\_ #\.) :test #'char=)))

(defun valid-star-service-token-p (value)
  (and (stringp value)
       (plusp (length value))
       (every #'valid-star-service-token-character-p value)))

(defun validate-star-service-token (value label)
  (unless (valid-star-service-token-p value)
    (fail-invalid-star-service-uri
     "STAR service URI ~A must be non-empty lowercase ASCII using only letters, digits, '.', '_', or '-': ~S."
     label
     value))
  value)

(defun make-star-service-uri (domain address actor-name)
  (%make-star-service-uri
   (validate-star-service-token domain "domain")
   (validate-star-service-token address "address")
   (validate-star-service-token actor-name "actor name")))

(defun star-service-uri-string (uri)
  "Re-serialize a parsed legacy tuple.  Compatibility output only; new
code must never emit this format as canonical identity."
  (unless (star-service-uri-p uri)
    (fail-invalid-star-service-uri
     "Expected a STAR service URI object, received ~S."
     uri))
  (format nil "star://~A:~A:~A"
          (star-service-uri-domain uri)
          (star-service-uri-address uri)
          (star-service-uri-actor-name uri)))

(defun star-service-uri-target-p (value)
  (and (stringp value)
       (<= 7 (length value))
       (string= "star://" value :end2 7)))

(defun parse-star-service-uri (value)
  "Parse the legacy star://domain:address:actor-name tuple.  This is
compatibility input parsing only; the result is not a canonical STAR
URI and cannot become one without an explicit migration target."
  (unless (star-service-uri-target-p value)
    (fail-invalid-star-service-uri
     "STAR service URI must begin with star://, received ~S."
     value))
  (let* ((body (subseq value 7))
         (first-separator (position #\: body))
         (second-separator
           (and first-separator
                (position #\: body :start (1+ first-separator))))
         (third-separator
           (and second-separator
                (position #\: body :start (1+ second-separator)))))
    (unless (and first-separator second-separator (null third-separator))
      (fail-invalid-star-service-uri
       "STAR service URI must have exactly domain:address:actor-name after star://, received ~S."
       value))
    (make-star-service-uri
     (subseq body 0 first-separator)
     (subseq body (1+ first-separator) second-separator)
     (subseq body (1+ second-separator)))))

(defun ensure-star-service-uri (value)
  (cond
    ((star-service-uri-p value) value)
    ((stringp value) (parse-star-service-uri value))
    (t
     (fail-invalid-star-service-uri
      "Expected STAR service URI string or object, received ~S."
      value))))

(defun canonical-star-service-uri-for-actor (actor-name value)
  "Legacy tuple name-consistency check: the tuple actor name must match
the actor contract.  Compatibility input only."
  (let ((uri (ensure-star-service-uri value)))
    (unless (string= actor-name (star-service-uri-actor-name uri))
      (fail-invalid-star-service-uri
       "STAR service URI actor name ~A does not match actor contract ~A."
       (star-service-uri-actor-name uri)
       actor-name))
    (star-service-uri-string uri)))

(defun legacy-star-actor-uri-p (value)
  "True when VALUE is a legacy star://domain:address:actor-name string.
  Canonical RFC URIs are never legacy tuple input."
  (and (stringp value)
       (star-service-uri-target-p value)
       (not (null (ignore-errors (parse-star-service-uri value))))
       ;; A canonical RFC URI also starts with star:// and contains
       ;; colons only where the canonical profile forbids them; the
       ;; tuple parser accepts it only when it has exactly two colons
       ;; and no slash, which no canonical URI satisfies.
       (null (position #\/ (subseq value 7)))))

(defun star-canonical-migration-target (target)
  (unless (canonical-star-uri-p target)
    (fail-invalid-star-uri
     "legacy STAR migration target must already be a canonical STAR URI: ~S"
     target))
  target)

(defun migrate-legacy-star-uri (legacy &key to map)
  "Migrate a legacy star://domain:address:actor-name input to a canonical
STAR identity.  The destination is always explicit: pass :TO with an
already-canonical STAR URI, or :MAP with an alist whose keys are legacy
tuple strings and whose values are already-canonical STAR URIs.  There is
intentionally no automatic domain-to-authority rewrite (STAR-SERVER-041).
Returns the canonical target string, normalizing immediately into the
canonical representation; signals invalid-star-uri otherwise."
  (let ((tuple (etypecase legacy
                (star-service-uri legacy)
                (string (parse-star-service-uri legacy)))))
    (cond
      (to (star-canonical-migration-target to))
      (map
       (let ((entry (assoc (star-service-uri-string tuple)
                           map :test #'string=)))
         (unless entry
           (fail-invalid-star-uri
            "no explicit migration map entry for legacy STAR actor URI ~S"
            (star-service-uri-string tuple)))
         (star-canonical-migration-target (cdr entry))))
      (t
       (fail-invalid-star-uri
        "migrating legacy STAR actor URI ~S requires an explicit :TO canonical target or an explicit :MAP migration map"
        (star-service-uri-string tuple))))))