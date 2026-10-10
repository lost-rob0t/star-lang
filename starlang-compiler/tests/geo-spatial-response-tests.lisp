;;;; SL04 proposal: compile real source, generate output, validate actual wire.
(defpackage #:starlang-geo-spatial-response-tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))
(in-package #:starlang-geo-spatial-response-tests)
(def-suite starlang-geo-spatial-response-tests)
(in-suite starlang-geo-spatial-response-tests)
(defparameter +authority+ "org.starintel/core@1")

(defun sl04-source (path)
  (uiop:read-file-string
   (asdf:system-relative-pathname :starlang-compiler path)))

(defun sl04-manifest ()
  (let* ((source (sl04-source "../specs/starintel/0.10.1/core.star"))
         (fragment (concatenate 'string
                    (sl04-source "../specs/starintel/proposals/query-spatial-result.star.inc")
                    (string (code-char 10))
                    (sl04-source "../specs/starintel/proposals/query-spatial-bbox.star.inc")))
         (needle "(:version \"0.10.1\")")
         (at (search needle source)))
    (unless at (error "Frozen 0.10.1 source header changed."))
    (let* ((bumped (concatenate 'string (subseq source 0 at)
                                "(:version \"0.10.2\")"
                                (subseq source (+ at (length needle)))))
           (end (position (code-char 41) bumped :from-end t)))
      (unless end (error "Missing spec-library closing form."))
      (starlangcompiler:emit-portable-manifest
       (starlangcompiler:compile-spec-library
        (starlangcompiler:read-star-syntax
         (concatenate 'string (subseq bumped 0 end)
                      (string (code-char 10)) fragment
                      (string (code-char 10)) ")")))
       nil))))

(defun sl04-goldens ()
  (let ((yason:*parse-json-arrays-as-vectors* t))
    (yason:parse
     (sl04-source "tests/fixtures/geo-spatial-response-probes-0102.json"))))

(defun sl04-wire (value)
  (cond
    ((eq value 'yason:true) t)
    ((eq value 'yason:false) nil)
    ((hash-table-p value)
     (loop for key being the hash-keys of value using (hash-value entry)
           collect (cons key (sl04-wire entry))))
    ((and (vectorp value) (not (stringp value)))
     (map 'list #'sl04-wire value))
    (t value)))

(test geo-spatial-response-generates-typed-contracts
  (let* ((manifest (sl04-manifest))
         (schema (yason:parse (starlangcompiler:generate-json-schema manifest)))
         (defs (gethash "$defs" schema))
         (match (gethash "SpatialMatch" defs))
         (properties (gethash "properties" match))
         (bindings (starlangcompiler:generate-all-bindings manifest))
         (message (find (format nil "~A/query-spatial-result" +authority+)
                        (getf manifest :messages)
                        :key (lambda (x) (getf x :name)) :test #'string=)))
    (is (string= "0.10.2" (getf (getf manifest :library) :version)))
    (is (consp message))
    (is (member "matches"
                (loop for f in (getf message :fields)
                      when (getf f :required) collect (getf f :name))
                :test #'string=))
    (is (hash-table-p match))
    ;; Check the compiled normalized source, actual JSON Schema, and bindings.
    (let ((contract
            (find (format nil "~A/spatial-match" +authority+)
                  (getf manifest :types)
                  :key (lambda (entry) (getf entry :name))
                  :test #'string=)))
      (is (consp contract))
      (dolist (name '("observedAt" "validFrom" "validUntil"))
        (let ((field (find name (getf contract :fields)
                           :key (lambda (entry) (getf entry :name))
                           :test #'string=))
              (property (gethash name properties)))
          (is (consp field))
          (is (string= (format nil "~A/unix-time" +authority+)
                       (getf field :type)))
          (is (not (getf field :required)))
          (is (string= "#/$defs/UnixTime" (gethash "$ref" property)))
          (is (not (member name (coerce (gethash "required" match) 'list)
                           :test #'string=))))))
    (dolist (name '("observedAt" "validFrom" "validUntil"))
      (is (search name (cdr (assoc :typescript bindings))))
      (is (search name (cdr (assoc :python bindings))))
      (is (search name (cdr (assoc :rust bindings)))))
    (is (string= "#/$defs/StarReference"
                 (gethash "$ref" (gethash "items" (gethash "evidence" properties)))))
    (is (search "export interface QuerySpatialResult"
                (cdr (assoc :typescript bindings))))
    (is (search "QuerySpatialResult = TypedDict"
                (cdr (assoc :python bindings))))
    (is (search "pub struct SpatialMatch"
                (cdr (assoc :rust bindings))))))

(test geo-spatial-response-wire-goldens
  (let* ((manifest (sl04-manifest))
         (goldens (sl04-goldens))
         (cases (gethash "cases" goldens))
         (message (format nil "~A/query-spatial-result" +authority+))
         (accepts 0) (rejects 0))
    (is (= 13 (length cases)))
    (loop for example across cases do
      (let ((payload (sl04-wire (gethash "payload" example))))
        (cond
          ((string= "accept" (gethash "result" example))
           (incf accepts)
           (is (staractorprotocol:validate-portable-message-payload
                manifest message payload)))
          ((string= "reject" (gethash "result" example))
           (incf rejects)
           (signals staractorprotocol:invalid-wire-envelope-error
             (staractorprotocol:validate-portable-message-payload
              manifest message payload)))
          (t (error "Unknown geo spatial fixture outcome.")))))
    (is (= 3 accepts))
    (is (= 10 rejects))))


(defun sl04-bbox-goldens ()
  (let ((yason:*parse-json-arrays-as-vectors* t))
    (yason:parse
     (sl04-source "tests/fixtures/geo-spatial-bbox-probes-0102.json"))))

(test geo-spatial-bbox-generated-shape
  (let* ((manifest (sl04-manifest))
         (schema (yason:parse (starlangcompiler:generate-json-schema manifest)))
         (defs (gethash "$defs" schema))
         (bounds (gethash "SpatialBounds" defs))
         (bounds-properties (gethash "properties" bounds))
         (request (gethash "QuerySpatialBbox" defs))
         (request-properties (gethash "properties" request))
         (bindings (starlangcompiler:generate-all-bindings manifest))
         (message (find (format nil "~A/query-spatial-bbox" +authority+)
                        (getf manifest :messages)
                        :key (lambda (item) (getf item :name))
                        :test #'string=)))
    (is (consp message))
    (is (hash-table-p bounds))
    (is (hash-table-p request))
    (is (string= "#/$defs/SpatialBounds"
                 (gethash "$ref" (gethash "bounds" request-properties))))
    (is (member "bounds"
                (loop for field in (getf message :fields)
                      when (getf field :required)
                      collect (getf field :name))
                :test #'string=))
    (dolist (pair '(("west" "Longitude") ("south" "Latitude")
                    ("east" "Longitude") ("north" "Latitude")))
      (is (string= (format nil "#/$defs/~A" (second pair))
                   (gethash "$ref" (gethash (first pair) bounds-properties))))
      (is (member (first pair) (coerce (gethash "required" bounds) 'list)
                  :test #'string=)))
    (is (search "export interface SpatialBounds"
                (cdr (assoc :typescript bindings))))
    (is (search "SpatialBounds = TypedDict"
                (cdr (assoc :python bindings))))
    (is (search "pub struct SpatialBounds"
                (cdr (assoc :rust bindings))))))

(test geo-spatial-bbox-wire-goldens
  (let* ((manifest (sl04-manifest))
         (goldens (sl04-bbox-goldens))
         (cases (gethash "cases" goldens))
         (message (format nil "~A/query-spatial-bbox" +authority+))
         (accepts 0) (rejects 0))
    (is (= 12 (length cases)))
    (loop for example across cases do
      (let ((payload (sl04-wire (gethash "payload" example))))
        (cond
          ((string= "accept" (gethash "result" example))
           (incf accepts)
           (is (staractorprotocol:validate-portable-message-payload
                manifest message payload)))
          ((string= "reject" (gethash "result" example))
           (incf rejects)
           (signals staractorprotocol:invalid-wire-envelope-error
             (staractorprotocol:validate-portable-message-payload
              manifest message payload)))
          (t (error "Unknown bbox golden outcome.")))))
    (is (= 2 accepts))
    (is (= 10 rejects))))

(defun run-tests ()
  (unless (run! 'starlang-geo-spatial-response-tests)
    (error "SL04 spatial response tests failed.")))
