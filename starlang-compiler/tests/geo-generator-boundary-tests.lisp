;;;; Immutable 0.10.1 geography: portable semantics vs generated JSON Schema.
;;;; Snapshot these known omissions; do not duplicate a spatial execution engine.

(defpackage #:starlang-geo-generator-boundary-tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:starlang-geo-generator-boundary-tests)

(def-suite starlang-geo-generator-boundary-tests
  :description "Geo/mission source, portable-validator, and generator debt inventory.")
(in-suite starlang-geo-generator-boundary-tests)

(defparameter +geo-library+ "org.starintel/core@1")
(defparameter +broad-decimal-pattern+ "^[+-]?[0-9]+(?:\\.[0-9]+)?$")

(defun geo-source-manifest ()
  (let* ((source-file
           (asdf:system-relative-pathname
            :starlang-compiler "../specs/starintel/0.10.1/core.star"))
         (library
           (starlangcompiler:compile-spec-library
            (starlangcompiler:read-star-syntax
             (uiop:read-file-string source-file)
             :source-id (namestring source-file)))))
    (starlangcompiler:emit-portable-manifest library nil)))

(defun geo-boundary-goldens ()
  (let* ((fixture-file
           (asdf:system-relative-pathname
            :starlang-compiler
            "tests/fixtures/geo-generator-boundaries-0101.json"))
         (yason:*parse-json-arrays-as-vectors* t))
    (yason:parse (uiop:read-file-string fixture-file))))

(defun geo-portable-scalar (manifest name)
  (find (format nil "~A/~A" +geo-library+ name)
        (getf manifest :types)
        :key (lambda (entry) (getf entry :name))
        :test #'string=))

(defun geo-wire-value-valid-p (manifest name value)
  (handler-case
      (progn
        (staractorprotocol:validate-portable-wire-value
         manifest (format nil "~A/~A" +geo-library+ name) value)
        t)
    (staractorprotocol:invalid-wire-envelope-error () nil)))

(test geo-frozen-scalar-goldens-cover-portable-numeric-bounds
  "Real StarLang source and portable validation enforce 12 decimal cases."
  (let* ((goldens (geo-boundary-goldens))
         (manifest (geo-source-manifest))
         (authority (gethash "authority" goldens))
         (rules (gethash "scalarRules" goldens))
         (samples (gethash "scalarCases" goldens))
         (schema (yason:parse (starlangcompiler:generate-json-schema manifest)))
         (definitions (gethash "$defs" schema)))
    (is (string= +geo-library+ (gethash "library" authority)))
    (is (string= "0.10.1" (gethash "version" authority)))
    (is (equal (getf (getf manifest :library) :name) +geo-library+))
    (is (string= "0.10.1" (getf (getf manifest :library) :version)))
    (is (= 4 (length rules)))
    (loop for rule across rules
          for name = (gethash "name" rule)
          for scalar = (geo-portable-scalar manifest name)
          do (is (consp scalar))
             (when scalar
               (is (string= "decimal" (getf scalar :base)))
               (is (= (gethash "scale" rule) (getf scalar :scale)))
               (is (= (gethash "minimum" rule) (getf scalar :minimum)))
               (multiple-value-bind (maximum present-p)
                   (gethash "maximum" rule)
                 (if present-p
                     (is (= maximum (getf scalar :maximum)))
                     (is (null (getf scalar :maximum)))))))
    (is (= 12 (length samples)))
    (loop for sample across samples
          for name = (gethash "scalar" sample)
          for value = (gethash "value" sample)
          for outcome = (gethash "outcome" sample)
          for valid-p = (geo-wire-value-valid-p manifest name value)
          do (is (member name '("latitude" "longitude" "distance-meters"
                                "confidence-score") :test #'string=))
             (is (string= outcome (if valid-p "accept" "reject"))))
    ;; The legacy generated schema still exposes these as broad decimal strings.
    ;; This proves a known omission, NOT equivalent JSON Schema validation.
    (dolist (definition '("Latitude" "Longitude" "DistanceMeters" "ConfidenceScore"))
      (let ((scalar (gethash definition definitions)))
        (is (string= "string" (gethash "type" scalar)))
        (is (string= +broad-decimal-pattern+ (gethash "pattern" scalar)))
        (is (null (gethash "minimum" scalar)))
        (is (null (gethash "maximum" scalar)))))))

(test geo-frozen-structural-gaps-are-recorded-not-invented
  "Avoid claiming bbox, discriminator, query responses or evidence links exist."
  (let* ((goldens (geo-boundary-goldens))
         (manifest (geo-source-manifest))
         (schema (yason:parse (starlangcompiler:generate-json-schema manifest)))
         (defs (gethash "$defs" schema))
         (geo-props (gethash "properties" (gethash "Geo" defs)))
         (point-props (gethash "properties" (gethash "GeoPoint" defs)))
         (target-props (gethash "properties" (gethash "MissionTarget" defs)))
         (bbox (gethash "boundingBox" geo-props))
         (geometry (gethash "geometryType" point-props))
         (accuracy (gethash "accuracyMeters" geo-props))
         (spatial (find (format nil "~A/query-spatial" +geo-library+)
                        (getf manifest :messages)
                        :key (lambda (entry) (getf entry :name))
                        :test #'string=)))
    (is (= 6 (length (gethash "knownSchemaGaps" goldens))))
    (is (string= "array" (gethash "type" bbox)))
    (is (null (gethash "minItems" bbox)))
    (is (null (gethash "maxItems" bbox)))
    (is (string= "#/$defs/GeoGeometryType" (gethash "$ref" geometry)))
    (is (member "polygon" (coerce (gethash "enum" (gethash "GeoGeometryType" defs))
                                   'list) :test #'string=))
    (is (string= "string" (gethash "type" accuracy)))
    (is (null (gethash "minimum" accuracy)))
    (is (consp spatial))
    (is (find "dataset" (getf spatial :fields)
              :key (lambda (entry) (getf entry :name)) :test #'string=))
    (is (find "mode" (getf spatial :fields)
              :key (lambda (entry) (getf entry :name)) :test #'string=))
    (is (null (find (format nil "~A/query-spatial-result" +geo-library+)
                    (getf manifest :messages)
                    :key (lambda (entry) (getf entry :name)) :test #'string=)))
    (is (string= "#/$defs/StarReference"
                 (gethash "$ref" (gethash "location" target-props))))
    (is (null (gethash "locationEvidence" target-props)))))

(defun run-tests ()
  (unless (run! 'starlang-geo-generator-boundary-tests)
    (error "StarIntel frozen geo generator boundary tests failed.")))
