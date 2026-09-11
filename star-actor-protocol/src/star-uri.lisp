(in-package :staractorprotocol)

;;;; Shared RFC 3986 STAR URI model (canonical identity authority).
;;;; Normative sources:
;;;;   - STAR-SERVER-041 "RFC 3986 STAR URI Authority Routing Extension"
;;;;     (roam/design/star-server/STAR-SERVER-041-star-uri-authority-routing-protocol.org)
;;;;   - STAR-LANG-004 amendment "STAR Service URI Discovery and Dispatch"
;;;;     (roam/design/star-lang/STAR-LANG-004-star-service-uri-discovery.org)
;;;;   - starintel-server source/star-uri.lisp (reviewed reference projection;
;;;;     its replacement marker designates this shared StarLang library).
;;;;
;;;; Grammar (STAR-SERVER-041 v1):
;;;;
;;;;   star-uri       = "star://" authority "/" resource-kind [ "/" resource-path ]
;;;;   authority      = reg-name
;;;;   resource-kind  = segment
;;;;   resource-path  = segment *( "/" segment )
;;;;
;;;; The legacy star://domain:address:actor-name tuple is compatibility
;;;; input only and lives behind the explicit legacy API in
;;;; service-uri.lisp; parse-star-uri rejects it.  This file implements the
;;;; one canonical URI model for StarLang; no second parser may be created.

(define-condition star-actor-protocol-error (error)
  ((message
    :initarg :message
    :reader star-actor-protocol-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-actor-protocol-error-message condition) stream))))

(define-condition invalid-star-uri (star-actor-protocol-error) ())

(defun fail-invalid-star-uri (control &rest arguments)
  (error 'invalid-star-uri
         :message (apply #'format nil control arguments)))

;;;; Reviewed global resource-kind registry (STAR-SERVER-041).  Adding a
;;;; kind requires a reviewed protocol registry change.
(defparameter +star-uri-resource-kinds+
  '("actor" "service" "document" "target" "dataset" "relation" "job")
  "The reviewed global STAR resource-kind registry from STAR-SERVER-041.")

;;;; Immutable value model recommended by STAR-SERVER-041: authority plus
;;;; hierarchical path segments, with resource-kind/resource-path views.
;;;; There are deliberately no domain/address/actor-name fields, and the
;;;; struct setters are not exported.
(defstruct (star-uri
            (:constructor %make-star-uri (authority path-segments))
            (:predicate star-uri-p)
            (:copier nil))
  (authority "" :type string :read-only t)
  (path-segments '() :type list :read-only t))

(defun star-uri-resource-kind (uri)
  "First path segment: the reviewed STAR resource class."
  (car (star-uri-path-segments uri)))

(defun star-uri-resource-path (uri)
  "Ordered segments following the resource kind.  Segments are in
canonical serialization form; percent escapes that must remain are
uppercase."
  (cdr (star-uri-path-segments uri)))

;;;; RFC 3986 character profiles.

(defun star-unreserved-character-p (character)
  (or (char<= #\a character #\z)
      (char<= #\A character #\Z)
      (char<= #\0 character #\9)
      (find character "-._~" :test #'char=)))

(defun star-sub-delimiter-character-p (character)
  (find character "!$&'()*+,;=" :test #'char=))

(defun star-pchar-character-p (character)
  "RFC 3986 pchar profile minus pct-encoded, which is handled explicitly."
  (or (star-unreserved-character-p character)
      (star-sub-delimiter-character-p character)
      (char= character #\:)
      (char= character #\@)))

(defun star-hex-digit-character-p (character)
  (or (char<= #\0 character #\9)
      (char<= #\a character #\f)
      (char<= #\A character #\F)))

(defun star-dot-segment-p (segment)
  (or (string= segment ".") (string= segment "..")))

;;;; Percent-escape handling (canonicalization rules 6 and 7).

(defun star-percent-escape-code (text index)
  "Return (values code end-index) for the %HH escape starting at INDEX,
signaling invalid-star-uri when the escape is malformed."
  (let* ((length (length text))
         (high (and (< (1+ index) length) (char text (1+ index))))
         (low (and (< (+ index 2) length) (char text (+ index 2)))))
    (unless (and high low
                 (char= (char text index) #\%)
                 (star-hex-digit-character-p high)
                 (star-hex-digit-character-p low))
      (fail-invalid-star-uri
       "malformed percent escape in ~S at offset ~D" text index))
    (values
     (+ (* 16 (digit-char-p high 16)) (digit-char-p low 16))
     (+ index 3))))

(defun star-normalized-escape (text index)
  "Return (values normalized-string next-index) for the escape at INDEX.
Percent-encoded unreserved characters normalize to their unreserved
representation; everything else re-serializes with uppercase hex digits."
  (multiple-value-bind (code end)
      (star-percent-escape-code text index)
    (values
     (if (and (< code 128)
              (star-unreserved-character-p (code-char code)))
         (string (code-char code))
         (format nil "%~2,'0X" code))
     end)))

;;;; Authority: RFC 3986 reg-name profile, canonical lowercase.  Userinfo
;;;; and transport ports are forbidden in canonical STAR identity.

(defun star-normalize-authority (text)
  (when (zerop (length text))
    (fail-invalid-star-uri "authority is required"))
  (let ((out (make-string-output-stream))
        (index 0)
        (length (length text)))
    (loop while (< index length)
          for character = (char text index)
          do (cond
               ((char= character #\@)
                (fail-invalid-star-uri
                 "userinfo is forbidden in STAR authority"))
               ((char= character #\:)
                (fail-invalid-star-uri
                 "transport ports are forbidden in canonical STAR authority"))
               ((char= character #\%)
                (multiple-value-bind (escape next)
                    (star-normalized-escape text index)
                  ;; Authority is case-insensitive: decoded unreserved
                  ;; literals fold to lowercase alongside literal characters.
                  (write-string
                   (if (= 1 (length escape))
                       (string (char-downcase (char escape 0)))
                       escape)
                   out)
                  (setf index next)))
               ((or (star-unreserved-character-p character)
                    (star-sub-delimiter-character-p character))
                (write-char (char-downcase character) out)
                (incf index))
               (t
                (fail-invalid-star-uri
                 "character ~S is outside the RFC 3986 reg-name profile for a STAR authority"
                 character))))
    (get-output-stream-string out)))

;;;; Path segments: RFC 3986 pchar plus percent-encoding rules.  Dot
;;;; segments are rejected before percent normalization and again after it.

(defun star-split-path (path-text)
  "Split the canonical path text (which starts with '/') into raw segments."
  (let ((segments '())
        (start 1)
        (length (length path-text)))
    (loop
      (let ((slash (position #\/ path-text :start start)))
        (cond
          (slash
           (push (subseq path-text start slash) segments)
           (setf start (1+ slash)))
          (t
           (push (subseq path-text start) segments)
           (return)))))
    (nreverse segments)))

(defun star-normalize-path-segment (segment original)
  "Validate and canonicalize one raw path segment.  Dot segments are
rejected before and after percent normalization, so %2E and %2E%2E can
never normalize into accepted dot segments.  Resource-path case is
preserved."
  (when (zerop (length segment))
    (fail-invalid-star-uri "empty path segment in ~S" original))
  (when (star-dot-segment-p segment)
    (fail-invalid-star-uri
     "dot path segment ~S is forbidden in ~S" segment original))
  (let ((out (make-string-output-stream))
        (index 0)
        (length (length segment)))
    (loop while (< index length)
          for character = (char segment index)
          do (cond
               ((char= character #\%)
                (multiple-value-bind (escape next)
                    (star-normalized-escape segment index)
                  (write-string escape out)
                  (setf index next)))
               ((star-pchar-character-p character)
                (write-char character out)
                (incf index))
               (t
                (fail-invalid-star-uri
                 "character ~S is not an RFC 3986 pchar in path segment ~S of ~S"
                 character segment original))))
    (let ((normalized (get-output-stream-string out)))
      (when (star-dot-segment-p normalized)
        (fail-invalid-star-uri
         "path segment ~S normalizes to forbidden dot segment ~S in ~S"
         segment normalized original))
      normalized)))

;;;; Parsing, serialization, and canonicalization.

(defun star-uri-text-p (value)
  "True when VALUE is textual star:// input: a canonical STAR URI, a
canonicalizable variant, or legacy tuple input.  It does not assert
validity."
  (and (stringp value)
       (>= (length value) 7)
       (string-equal "star://" value :end1 7 :end2 7)))

(defun parse-star-uri (value)
  "Parse VALUE into a canonical star-uri value, applying the
STAR-SERVER-041 v1 canonicalization rules.  Signals invalid-star-uri for
any input outside the profile, including the legacy tuple form."
  (unless (stringp value)
    (fail-invalid-star-uri
     "STAR URI must be a string, received ~S" value))
  (unless (plusp (length value))
    (fail-invalid-star-uri "STAR URI must be a non-empty string"))
  (unless (star-uri-text-p value)
    (fail-invalid-star-uri "STAR URIs use the star:// scheme: ~S" value))
  (let* ((body (subseq value 7))
         (path-start (position #\/ body))
         (authority-text (if path-start (subseq body 0 path-start) body))
         (path-text (if path-start (subseq body path-start) ""))
         (authority (star-normalize-authority authority-text)))
    (when (zerop (length path-text))
      (fail-invalid-star-uri
       "resource kind is required: star://<authority>/<resource-kind>[/<resource-path>]: ~S"
       value))
    (let ((segments
            (mapcar (lambda (segment)
                      (star-normalize-path-segment segment value))
                    (star-split-path path-text))))
      (unless (member (car segments) +star-uri-resource-kinds+
                      :test #'string=)
        (fail-invalid-star-uri
         "unknown STAR resource kind ~S; reviewed kinds are ~{~A~^, ~}"
         (car segments) +star-uri-resource-kinds+))
      (%make-star-uri authority segments))))

(defun serialize-star-uri (uri)
  "Serialize a star-uri value in canonical v1 form."
  (unless (star-uri-p uri)
    (fail-invalid-star-uri "expected a star-uri value, received ~S" uri))
  (format nil "star://~A/~{~A~^/~}"
          (star-uri-authority uri)
          (star-uri-path-segments uri)))

(defun star-uri-string (uri)
  "Serialize a star-uri value in canonical v1 form (STAR-LANG-004 API
name; identical to serialize-star-uri)."
  (serialize-star-uri uri))

(defun canonicalize-star-uri (value)
  "Return the canonical v1 serialization of VALUE."
  (serialize-star-uri (parse-star-uri value)))

(defun canonical-star-uri-p (value)
  "True when VALUE is a string that is already the exact canonical v1
serialization of a valid STAR URI.  This deliberately differs from
valid-star-uri-p, which accepts any canonicalizable input."
  (and (stringp value)
       (plusp (length value))
       (string= value (ignore-errors (canonicalize-star-uri value)))))

(defun valid-star-uri-p (value)
  "True when VALUE parses under the canonical STAR v1 profile, even if it
still requires canonicalization before it is canonical."
  (and (stringp value)
       (not (null (ignore-errors (parse-star-uri value))))))

(defun actor-star-uri-p (value)
  "True when VALUE (a star-uri value or a string) addresses an actor
resource with a non-empty actor resource path."
  (let ((uri (etypecase value
               (star-uri value)
               (string (ignore-errors (parse-star-uri value))))))
    (and (star-uri-p uri)
         (string= "actor" (star-uri-resource-kind uri))
         (star-uri-resource-path uri))))

(defun ensure-star-uri (value)
  "Coerce VALUE (a star-uri value or a star:// string) to a star-uri
value, signaling invalid-star-uri for anything else."
  (etypecase value
    (star-uri value)
    (string (parse-star-uri value))))

;;;; StarLang actor identity contract: a declared actor URI must be a
;;;; canonical actor URI whose terminal resource-path segment names the
;;;; actor.  Multi-segment actor paths stay valid without assigning
;;;; fixed domain semantics to the leading segments (STAR-LANG-004).

(defun canonical-star-actor-uri-for-actor (actor-name value)
  "Canonicalize a canonical-model actor URI for ACTOR-NAME: the resource
kind must be actor, the actor resource path must be non-empty, and its
terminal segment must equal the actor contract name.  Returns the
canonical serialization; signals invalid-star-uri otherwise."
  (let ((uri (ensure-star-uri value)))
    (unless (string= "actor" (star-uri-resource-kind uri))
      (fail-invalid-star-uri
       "STAR actor identity requires the actor resource kind, received ~S"
       value))
    (let ((resource-path (star-uri-resource-path uri)))
      (unless resource-path
        (fail-invalid-star-uri
         "STAR actor identity requires a non-empty actor resource path: ~S"
         value))
      (unless (string= actor-name (car (last resource-path)))
        (fail-invalid-star-uri
         "STAR actor URI terminal path segment ~A does not match actor contract ~A."
         (car (last resource-path))
         actor-name)))
    (serialize-star-uri uri)))