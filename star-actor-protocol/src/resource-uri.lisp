;;;; Canonical hierarchical STAR resource URIs (issue #72 slice 1).
;;;;
;;;; One reusable value model for RFC 3986 hierarchical STAR URIs:
;;;;
;;;;   star://<authority>/<resource-kind>/<resource-path>
;;;;
;;;; with reviewed resource kinds (currently actor and service). The legacy
;;;; tuple form star://domain:address:actor-name remains compatibility input
;;;; only: this model never parses it as a resource URI and never emits it.

(in-package :staractorprotocol)

(define-condition invalid-star-resource-uri-error
    (star-actor-protocol-error)
  ())

(define-condition star-resource-kind-error
    (invalid-star-resource-uri-error)
  ())

(define-condition legacy-star-resource-uri-error
    (invalid-star-resource-uri-error)
  ())

(defun fail-invalid-star-resource-uri (control &rest arguments)
  (error 'invalid-star-resource-uri-error
         :message (apply #'format nil control arguments)))

(defun fail-star-resource-kind (control &rest arguments)
  (error 'star-resource-kind-error
         :message (apply #'format nil control arguments)))

(defun fail-legacy-star-resource-uri (control &rest arguments)
  (error 'legacy-star-resource-uri-error
         :message (apply #'format nil control arguments)))

(defstruct (star-resource-uri
            (:constructor %make-star-resource-uri
                (authority resource-kind resource-path path-segments)))
  (authority "" :type string)
  (resource-kind :actor :type keyword)
  (resource-path "" :type string)
  (path-segments '() :type list))

(defparameter *star-resource-kinds* '(:actor :service))

(defun star-resource-kind-name (kind)
  (ecase kind
    (:actor "actor")
    (:service "service")))

(defun valid-star-resource-uri-authority-character-p (character)
  (or (char<= #\a character #\z)
      (char<= #\0 character #\9)
      (member character '(#\- #\.) :test #'char=)))

(defun hierarchical-star-uri-p (value)
  "True when VALUE is a star:// URI string using the hierarchical form.
The legacy tuple form (no slash-delimited path) is not hierarchical."
  (and (stringp value)
       (<= 10 (length value))
       (string= "star://" value :end2 7)
       (position #\/ value :start 7)))

(defun parse-star-resource-authority (value)
  (unless (plusp (length value))
    (fail-invalid-star-resource-uri
     "STAR resource URI authority must be non-empty."))
  (dotimes (index (length value))
    (let ((character (char value index)))
      (unless (valid-star-resource-uri-authority-character-p character)
        (fail-invalid-star-resource-uri
         "STAR resource URI authority ~S must be a lowercase RFC 3986 \
reg-name without userinfo or transport port."
         value))))
  value)

(defun star-resource-kind-from-string (value)
  (cond
    ((string= value "actor") :actor)
    ((string= value "service") :service)
    ((find-if #'upper-case-p value)
     (fail-star-resource-kind
      "STAR resource kind ~S must be lowercase." value))
    (t
     (fail-star-resource-kind
      "STAR resource kind ~S is not a reviewed resource kind." value))))

(defun hex-digit-p (character)
  (or (digit-char-p character 16)))

(defun unreserved-character-p (character)
  (or (char<= #\a character #\z)
      (char<= #\A character #\Z)
      (char<= #\0 character #\9)
      (member character '(#\- #\_ #\. #\~) :test #'char=)))

(defun normalize-percent-escape (value start)
  "Return (VALUES decoded-string consumed) for the percent escape at START,
normalizing case: unreserved characters decode, everything else keeps an
uppercase hexadecimal escape."
  (let* ((first (char value (+ start 1)))
         (second (char value (+ start 2))))
    (unless (and (hex-digit-p first) (hex-digit-p second))
      (fail-invalid-star-resource-uri
       "STAR resource URI contains an invalid percent escape in ~S." value))
    (let* ((code (parse-integer value :start (+ start 1) :end (+ start 3)
                                     :radix 16 :junk-allowed nil))
           (character (code-char code)))
      (unless character
        (fail-invalid-star-resource-uri
         "STAR resource URI percent escape ~A encodes no character." value))
      (if (unreserved-character-p character)
          (values (string character) 3)
          (values (format nil "%~:@(~2,'0X~)" code) 3)))))

(defun normalize-resource-path-segment (value context)
  (unless (plusp (length value))
    (fail-invalid-star-resource-uri
     "STAR resource URI ~A segments must be non-empty." context))
  (with-output-to-string (output)
    (let ((index 0)
          (length (length value)))
      (loop while (< index length)
            do (let ((character (char value index)))
                 (cond
                   ((char= character #\%)
                    (unless (<= (+ index 3) length)
                      (fail-invalid-star-resource-uri
                       "STAR resource URI ~A has a truncated percent escape."
                       context))
                    (multiple-value-bind (text consumed)
                        (normalize-percent-escape value index)
                      (write-string text output)
                      (incf index consumed)))
                   ((char= character #\/)
                    (fail-invalid-star-resource-uri
                     "STAR resource URI ~A contains a nested slash." context))
                   ((member character '(#\? #\#) :test #'char=)
                    (fail-invalid-star-resource-uri
                     "STAR resource URI ~A contains a reserved delimiter."
                     context))
                   (t
                    (write-char character output)
                    (incf index 1))))))))

(defun star-resource-kind-string-or-fail (value)
  (unless (stringp value)
    (fail-invalid-star-resource-uri
     "STAR resource URI resource kind must be a string, received ~S." value))
  (star-resource-kind-from-string value))

(defun parse-star-resource-path (value)
  (unless (and (stringp value) (plusp (length value)))
    (fail-invalid-star-resource-uri
     "STAR resource URI requires a non-empty resource path."))
  (when (char= (char value (1- (length value))) #\/)
    (fail-invalid-star-resource-uri
     "STAR resource URI resource path must not end with a slash."))
  (let* ((raw-segments (split-sequence-on-slash value))
         (segments (mapcar
                    (lambda (segment)
                      (normalize-resource-path-segment segment "resource path"))
                    raw-segments)))
    (dolist (segment raw-segments)
      (when (zerop (length segment))
        (fail-invalid-star-resource-uri
         "STAR resource URI resource path has an empty segment."))
      (when (or (string= segment ".") (string= segment ".."))
        (fail-invalid-star-resource-uri
         "STAR resource URI resource path contains a dot segment.")))
    (values segments
            (reduce (lambda (left right)
                      (concatenate 'string left "/" right))
                    segments))))

(defun split-sequence-on-slash (value)
  (loop with start = 0
        for index = (position #\/ value :start start)
        if index
          collect (subseq value start index)
          and do (setf start (1+ index))
        else
          collect (subseq value start (length value))
          and do (loop-finish)))

(defun parse-star-resource-uri (value)
  "Parse and canonicalize one hierarchical STAR resource URI string."
  (unless (and (stringp value)
               (<= 10 (length value))
               (string= "star://" value :end2 7))
    (fail-invalid-star-resource-uri
     "STAR resource URI must begin with the lowercase scheme star://, \
received ~S."
     (and (stringp value) value)))
  (let* ((body (subseq value 7))
         (slash (position #\/ body)))
    (unless slash
      (if (find #\: body)
          (fail-legacy-star-resource-uri
           "STAR URI ~S uses the legacy tuple form; it is compatibility \
input only and is not a hierarchical resource URI."
           value)
          (fail-invalid-star-resource-uri
           "STAR resource URI requires star://<authority>/<path>, received \
~S."
           value)))
    (let* ((authority (parse-star-resource-authority
                       (subseq body 0 slash)))
           (path (subseq body (1+ slash)))
           (kind-slash (position #\/ path)))
      (unless kind-slash
        (fail-star-resource-kind
         "STAR resource URI requires a reviewed resource kind segment, \
received ~S."
         value))
      (let ((resource-kind
              (star-resource-kind-string-or-fail
               (subseq path 0 kind-slash)))
            (resource-path (subseq path (1+ kind-slash))))
        (multiple-value-bind (segments normalized-path)
            (parse-star-resource-path resource-path)
          (%make-star-resource-uri
           authority
           resource-kind
           normalized-path
           segments))))))

(defun star-resource-uri-string (uri)
  "Serialize one resource URI in canonical hierarchical form."
  (unless (star-resource-uri-p uri)
    (fail-invalid-star-resource-uri
     "Expected a STAR resource URI object, received ~S." uri))
  (format nil "star://~A/~A/~A"
          (star-resource-uri-authority uri)
          (star-resource-kind-name (star-resource-uri-resource-kind uri))
          (star-resource-uri-resource-path uri)))

(defun ensure-star-resource-uri (value)
  (cond
    ((star-resource-uri-p value) value)
    ((stringp value) (parse-star-resource-uri value))
    (t
     (fail-invalid-star-resource-uri
      "Expected a STAR resource URI string or object, received ~S." value))))

(defun canonical-star-resource-uri-for-actor (actor-name value)
  "Canonicalize VALUE and require that its last resource path segment is
ACTOR-NAME, mirroring the legacy actor-name binding contract."
  (let ((uri (ensure-star-resource-uri value)))
    (unless (string= actor-name
                     (first (last (star-resource-uri-path-segments uri))))
      (fail-invalid-star-resource-uri
       "STAR resource URI ~A does not bind actor contract ~A."
       (star-resource-uri-string uri)
       actor-name))
    (star-resource-uri-string uri)))
