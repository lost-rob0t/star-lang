;;;; Final semantic validation for compiled specification libraries.

(in-package #:star-lang.compiler.core)

(defun local-qualified-name-p (library qualified-name)
  (let ((prefix (format nil "~A/" (getf library :name))))
    (and (stringp qualified-name)
         (<= (length prefix) (length qualified-name))
         (string= prefix qualified-name :end2 (length prefix)))))

(defun semantic-declaration-table (library)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (declaration (getf library :declarations))
      (setf (gethash (getf declaration :qualified-name) table) declaration))
    table))

(defun local-declaration (library table qualified-name context)
  (when (local-qualified-name-p library qualified-name)
    (or (gethash qualified-name table)
        (fail 'invalid-type-error
              "~A references missing local declaration ~A."
              context qualified-name))))

(defun require-local-kind (library table qualified-name expected-kind context)
  (let ((declaration (local-declaration library table qualified-name context)))
    (when (and declaration (not (eq (getf declaration :kind) expected-kind)))
      (fail 'invalid-type-error
            "~A requires a ~A, but ~A is a ~A."
            context expected-kind qualified-name (getf declaration :kind)))
    declaration))

(defun document-parent (library table document)
  (let ((extends (getf document :extends)))
    (and extends
         (require-local-kind
          library table extends :document
          (format nil "Document ~A :extends" (getf document :qualified-name))))))

(defun validate-document-inheritance (library table)
  (let ((states (make-hash-table :test #'equal)))
    (labels ((visit (document path)
               (let* ((name (getf document :qualified-name))
                      (state (gethash name states)))
                 (cond
                   ((eq state :done))
                   ((eq state :visiting)
                    (fail 'invalid-declaration-error
                          "Document inheritance cycle: ~{~A~^ -> ~} -> ~A."
                          (reverse path) name))
                   (t
                    (setf (gethash name states) :visiting)
                    (let ((parent (document-parent library table document)))
                      (when parent
                        (visit parent (cons name path))))
                    (setf (gethash name states) :done))))))
      (dolist (document (declarations-of-kind library :document))
        (visit document '())))))

(defun ancestor-field-names (library table document)
  (let ((names '())
        (parent (document-parent library table document)))
    (loop while parent
          do (dolist (field (getf parent :fields))
               (pushnew (getf field :name) names :test #'string=))
             (setf parent (document-parent library table parent)))
    names))

(defun validate-additive-document-fields (library table)
  (dolist (document (declarations-of-kind library :document))
    (let ((ancestor-fields (ancestor-field-names library table document)))
      (dolist (field (getf document :fields))
        (when (member (getf field :name) ancestor-fields :test #'string=)
          (fail 'invalid-field-error
                "Document ~A redefines inherited field ~A; extensions are additive."
                (getf document :qualified-name)
                (getf field :name)))))))

(defun validate-predicate-endpoints (library table)
  (dolist (predicate (declarations-of-kind library :predicate))
    (require-local-kind
     library table (getf predicate :source) :document
     (format nil "Predicate ~A source" (getf predicate :qualified-name)))
    (require-local-kind
     library table (getf predicate :destination) :document
     (format nil "Predicate ~A destination" (getf predicate :qualified-name)))))

(defun validate-library-semantics (library)
  "Validate cross-declaration invariants of normalized specification IR."
  (unless (and (listp library)
               (eql (getf library :ir-version) +normalized-ir-version+)
               (string= (or (getf library :ir-schema) "") +normalized-ir-schema+)
               (eq (getf library :kind) :spec-library))
    (fail 'invalid-library-error
          "Semantic validation requires normalized specification-library IR."))
  (let ((table (semantic-declaration-table library)))
    (validate-document-inheritance library table)
    (validate-additive-document-fields library table)
    (validate-predicate-endpoints library table))
  library)

(defun compile-core-library (source)
  "Compile SOURCE when needed, then apply final semantic validation."
  (validate-library-semantics
   (if (and (listp source)
            (eql (getf source :ir-version) +normalized-ir-version+)
            (string= (or (getf source :ir-schema) "") +normalized-ir-schema+)
            (eq (getf source :kind) :spec-library))
       source
       (compile-spec-library source))))

(defun actor-contract-declaration (library table type context allowed-kinds)
  (let ((declaration (local-declaration library table type context)))
    (when (and declaration
               (not (member (getf declaration :kind) allowed-kinds :test #'eq)))
      (fail 'invalid-actor-error
            "~A references ~A, whose kind ~A is not allowed."
            context type (getf declaration :kind)))
    declaration))

(defun validate-actor-contract (library actor)
  "Validate an actor's local accepts/produces types against LIBRARY."
  (let ((table (semantic-declaration-table library))
        (actor-name (getf actor :name)))
    (dolist (type (getf actor :accepts))
      (when (stringp type)
        (actor-contract-declaration
         library table type
         (format nil "Actor ~A accepts" actor-name)
         '(:message))))
    (dolist (type (getf actor :produces))
      (when (stringp type)
        (actor-contract-declaration
         library table type
         (format nil "Actor ~A produces" actor-name)
         '(:message :document)))))
  actor)

(defun emit-core-manifest (library actors)
  "Emit the portable manifest only after final semantic checks pass."
  (validate-library-semantics library)
  (dolist (actor actors)
    (validate-actor-contract library actor))
  (emit-portable-manifest library actors))

(export '(compile-core-library
          emit-core-manifest
          validate-library-semantics
          validate-actor-contract))
