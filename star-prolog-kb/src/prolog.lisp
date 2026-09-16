(in-package :starprologkb)

(defun %write-prolog-string (value stream)
  (write-char #\" stream)
  (loop for character across value
        do (case character
             (#\\ (write-string "\\\\" stream))
             (#\" (write-string "\\\"" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (otherwise (write-char character stream))))
  (write-char #\" stream))

(defun %write-prolog-value (value stream)
  (cond
    ((eq value starcanonicaljson:+json-true+) (write-string "true" stream))
    ((eq value starcanonicaljson:+json-false+) (write-string "false" stream))
    ((eq value starcanonicaljson:+json-null+) (write-string "null" stream))
    ((null value) (write-string "null" stream))
    ((eq value t) (write-string "true" stream))
    ((integerp value) (format stream "~D" value))
    ((stringp value) (%write-prolog-string value stream))
    (t (%write-prolog-string (%index-key-string value) stream))))

(defun %write-prolog-fact (predicate arguments stream)
  (write-string predicate stream)
  (write-char #\( stream)
  (loop for argument in arguments
        for first-p = t then nil
        do (unless first-p (write-string ", " stream))
           (%write-prolog-value argument stream))
  (write-string ")." stream)
  (terpri stream))

(defun %field-list-p-for-value (kb value name field-value)
  (let ((type (%field-type-for-value
               (starintel-kb-spec-ir kb) value name)))
    (%list-value-p type field-value)))

(defun %field-values-for-prolog (kb document field-name field-value)
  (if (%field-list-p-for-value kb document field-name field-value)
      (copy-list (or (%json-array-values field-value) field-value))
      (list field-value)))

(defun %sorted-document-entries (document)
  (sort (copy-list (%object-entries document))
        #'string<
        :key (lambda (entry) (%normalized-field-key (car entry)))))

(defun %write-document-prolog (kb value stream)
  (let ((id (%required-string-field value "id")))
    (multiple-value-bind (dtype dtype-p) (%lookup-field value "dtype")
      (multiple-value-bind (dataset dataset-p) (%lookup-field value "dataset")
        (%write-prolog-fact
         "star_document"
         (list id
               (if dtype-p dtype "")
               (if dataset-p dataset ""))
         stream)))
    (dolist (entry (%sorted-document-entries value))
      (let* ((field-name (%key-name (car entry)))
             (field-value (cdr entry)))
        (dolist (item (%field-values-for-prolog kb value field-name field-value))
          (%write-prolog-fact
           "star_field"
           (list id field-name item)
           stream))))
    (when (%relation-document-p value)
      (multiple-value-bind (source source-p) (%lookup-field value "source")
        (multiple-value-bind (destination destination-p)
            (%lookup-field value "destination")
          (multiple-value-bind (predicate predicate-p)
              (%lookup-field value "predicate")
            (when (and source-p destination-p predicate-p)
              (%write-prolog-fact
               "star_relation"
               (list id
                     (%reference-id source)
                     (princ-to-string predicate)
                     (%reference-id destination))
               stream))))))))

(defun %map-starintel-values (kb function)
  (%tek9-call
   "MAP-DATABASE"
   (starintel-kb-database kb)
   :map-fn
   (lambda (id document)
     (declare (ignore id))
     (funcall function (%tek9-call "DOC-VALUE" document)))))

(defun write-prolog-snapshot (kb stream)
  "Write a deterministic Prolog snapshot of the current Tek9 StarIntel KB.

Generated bridge predicates are intentionally small and stable:
  star_document(Id, DType, Dataset).
  star_field(Id, Field, Value).
  star_relation(RelationId, SourceId, Predicate, DestinationId).

Raw `(prolog ...)` StarLang blocks are appended verbatim after generated facts."
  (write-string ":- dynamic star_document/3." stream)
  (terpri stream)
  (write-string ":- dynamic star_field/3." stream)
  (terpri stream)
  (write-string ":- dynamic star_relation/4." stream)
  (terpri stream)
  (terpri stream)
  (let ((documents '()))
    (%map-starintel-values kb (lambda (value) (push value documents)))
    (dolist (value
             (sort documents #'string<
                   :key (lambda (document)
                          (%required-string-field document "id"))))
      (%write-document-prolog kb value stream)))
  (dolist (block (prolog-kb-program-prolog-blocks
                  (starintel-kb-program kb)))
    (terpri stream)
    (format stream "%% StarLang raw Prolog block: ~A (~(~A~))~%"
            (prolog-source-block-name block)
            (prolog-source-block-kind block))
    (write-string (prolog-source-block-text block) stream)
    (unless (or (zerop (length (prolog-source-block-text block)))
                (char= (char (prolog-source-block-text block)
                             (1- (length (prolog-source-block-text block))))
                       #\Newline))
      (terpri stream)))
  kb)

(defun prolog-snapshot-string (kb)
  (with-output-to-string (stream)
    (write-prolog-snapshot kb stream)))