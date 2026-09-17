(in-package :starlangcompiler)

(defun generate-object-bindings (manifest target)
  "Generate portable stubs for every object visible to MANIFEST.

Every target receives scalars, enums, documents, predicates, messages, actors,
and explicit opaque definitions for referenced external contracts. The
portable manifest is hardened before generation and target identifiers use a
collision-safe deterministic name table."
  (staractorprotocol:validate-portable-manifest manifest)
  (let* ((effective-target (binding-target target))
         (*binding-name-table*
           (binding-make-name-table manifest effective-target)))
    (ecase effective-target
      (:common-lisp (binding-generate-common-lisp manifest))
      (:python (binding-generate-python manifest))
      (:typescript (binding-generate-typescript manifest))
      (:nim (binding-generate-nim manifest))
      (:java (binding-generate-java manifest))
      (:kotlin (binding-generate-kotlin manifest))
      (:go (binding-generate-go manifest))
      (:rust (binding-generate-rust manifest))
      (:elisp (binding-generate-elisp manifest))
      (:prolog (binding-generate-prolog manifest)))))

(defun generate-all-object-bindings (manifest)
  "Return an alist mapping every supported target to generated source."
  (mapcar (lambda (target)
            (cons target (generate-object-bindings manifest target)))
          +object-binding-targets+))
