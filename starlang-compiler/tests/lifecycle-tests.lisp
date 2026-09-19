;;;; Document lifecycle DSL tests: closed .star lowering, deterministic
;;;; rejections of unreachable/ambiguous/unsafe transitions, deterministic
;;;; manifest and transition-table emission, versioned replay, and the
;;;; committed fixtures consumed by the server lifecycle executor (LATER
;;;; slice starintel-server#240).

(defpackage :starlang-lifecycle-tests
  (:use :cl :fiveam)
  (:export #:run-tests
           #:manifest-fixture-json
           #:compiled-fixture-manifest))

(in-package :starlang-lifecycle-tests)

(def-suite starlang-lifecycle-tests
  :description "Document lifecycle DSL: lowering, validation, deterministic emission.")

(in-suite starlang-lifecycle-tests)

(defun fixture-path (name)
  (asdf:system-relative-pathname :starlang-compiler
                                 (format nil "../fixtures/lifecycle/~A" name)))

(defparameter *valid-lifecycle-source*
  "(spec-library \"org.starintel/lifecycle-fixtures@1\" (:version \"1.0.0\")
  (document person (:persistence persistent)
    (name string :required)
    (age integer :optional))
  (lifecycle person-lifecycle
    (:applies org.starintel/person@1
     :version 2
     :initial draft
     :states (draft active archived redacted deleted)
     :retention (evidence (years 7))
     :storage (tier warm replication regional)
     :ttl (days 90)
     :indexing (mode full-text)
     :encryption (class sealed)
     :hold (legal \"litigation-2026\")
     :events (submitted archived redacted tombstoned)
     :transitions (
       (:from draft :on submitted :to active
        :guard submit-guard :emit submitted)
       (:from active :on archived :to archived
        :action archive :emit archived)
       (:from archived :on redacted :to redacted :action redact)
       (:from redacted :on tombstoned :to deleted
        :action tombstone :supersedes org.starintel/person@0)))))")

(defun compile-source (source)
  (starlangcompiler:compile-spec-library
   (starlangcompiler:read-star-syntax source)))

(defun lifecycle-declaration (source)
  (let ((declarations
          (getf (compile-source source) :declarations)))
    (find :lifecycle declarations :key (lambda (item) (getf item :kind)))))

(defun data-only-p (value)
  (typecase value
    ((or null boolean string integer keyword symbol) t)
    (cons (and (data-only-p (car value)) (data-only-p (cdr value))))
    (t nil)))

(test lifecycle-declaration-lowers-to-closed-data-ir
  "A valid .star lifecycle lowers to data-only IR through the closed parser."
  (let ((lifecycle (lifecycle-declaration *valid-lifecycle-source*)))
    (is-true lifecycle)
    (is (equal "person-lifecycle" (getf lifecycle :name)))
    (is (equal "org.starintel/lifecycle-fixtures@1/person-lifecycle"
               (getf lifecycle :qualified-name)))
    (is (equal "org.starintel/person@1" (getf lifecycle :applies)))
    (is (eql 2 (getf lifecycle :version)))
    (is (equal "draft" (getf lifecycle :initial)))
    (is (equal '("draft" "active" "archived" "redacted" "deleted")
               (getf lifecycle :states)))
    (is (equal '(:evidence-days 2555) (getf lifecycle :retention)))
    (is (equal '(:tier :warm :replication :regional)
               (getf lifecycle :storage)))
    (is (eql 90 (getf lifecycle :ttl-days)))
    (is (equal '(:mode :full-text) (getf lifecycle :indexing)))
    (is (equal '(:class :sealed) (getf lifecycle :encryption)))
    (is (equal '(:class :legal :reason "litigation-2026")
               (getf lifecycle :hold)))
    (is (equal '("submitted" "archived" "redacted" "tombstoned")
               (getf lifecycle :events)))
    (is (equal
         '((:from "draft" :on "submitted" :to "active"
            :guard "submit-guard" :action :keep :emit "submitted")
           (:from "active" :on "archived" :to "archived"
            :action :archive :emit "archived")
           (:from "archived" :on "redacted" :to "redacted" :action :redact)
           (:from "redacted" :on "tombstoned" :to "deleted"
            :action :tombstone :supersedes "org.starintel/person@0"))
         (getf lifecycle :transitions)))
    (is-true (data-only-p lifecycle))))

(defun rejected-lifecycle (source)
  "Compile SOURCE and return the lifecycle compiler error, failing the test
when the source is wrongly accepted."
  (handler-case
      (progn (compile-source source)
             (error "Lifecycle source was accepted but must be rejected: ~A"
                    source))
    (starlangcompiler:invalid-declaration-error (condition)
      condition)))

(defun rejection-message (condition)
  (starlangcompiler:star-lang-core-error-message condition))

(defun with-transitions (transitions)
  (format nil "(spec-library \"org.starintel/lifecycle-fixtures@1\" (:version \"1.0.0\")
  (lifecycle person-lifecycle
    (:applies org.starintel/person@1
     :version 1
     :initial draft
     :states (draft active deleted)
     :events (submitted tombstoned destroyed)
     :transitions (~A))))"
          transitions))

(test lifecycle-rejects-unreachable-state
  "A declared state with no incoming transition is rejected."
  (let ((condition
          (rejected-lifecycle
           (with-transitions
            "(:from draft :on submitted :to active)"))))
    (is (search "unreachable" (rejection-message condition))
        "Rejection must name the unreachable state.")))

(test lifecycle-rejects-ambiguous-transition
  "Two transitions sharing the same (from, event) pair are rejected."
  (let ((condition
          (rejected-lifecycle
           (with-transitions
            "(:from draft :on submitted :to active)
             (:from draft :on submitted :to deleted)"))))
    (is (search "ambiguous" (rejection-message condition))
        "Rejection must name the ambiguity.")))

(test lifecycle-rejects-unsafe-destroy-under-evidence-retention
  "Provenance-erasing destroy is rejected while evidence retention applies."
  (let ((condition
          (rejected-lifecycle
           "(spec-library \"org.starintel/lifecycle-fixtures@1\" (:version \"1.0.0\")
  (lifecycle person-lifecycle
    (:applies org.starintel/person@1
     :version 1
     :initial draft
     :states (draft active deleted)
     :retention (evidence (years 7))
     :events (submitted destroyed)
     :transitions (
       (:from draft :on submitted :to active)
       (:from active :on destroyed :to deleted :action destroy)))))")))
    (is (search "unsafe" (rejection-message condition))
        "Rejection must name the unsafe transition.")))

(test lifecycle-rejects-unsafe-destroy-under-legal-hold
  "Provenance-erasing destroy is rejected while a legal hold applies."
  (let ((condition
          (rejected-lifecycle
           "(spec-library \"org.starintel/lifecycle-fixtures@1\" (:version \"1.0.0\")
  (lifecycle person-lifecycle
    (:applies org.starintel/person@1
     :version 1
     :initial draft
     :states (draft active deleted)
     :hold (legal \"litigation-2026\")
     :events (submitted destroyed)
     :transitions (
       (:from draft :on submitted :to active)
       (:from active :on destroyed :to deleted :action destroy)))))")))
    (is (search "unsafe" (rejection-message condition))
        "Rejection must name the unsafe transition.")))

(test lifecycle-allows-destroy-without-retention-or-hold
  "Destroy is a legal closed action when no evidence retention or hold applies."
  (let ((lifecycle
          (lifecycle-declaration
           (with-transitions
            "(:from draft :on submitted :to active)
             (:from active :on destroyed :to deleted :action destroy)"))))
    (is-true lifecycle)
    (is (equal :destroy
               (getf (second (getf lifecycle :transitions)) :action)))))

(test lifecycle-rejects-undeclared-target-state
  "A transition targeting an undeclared state is rejected."
  (let ((condition
          (rejected-lifecycle
           (with-transitions
            "(:from draft :on submitted :to vanished)
             (:from vanished :on tombstoned :to deleted)"))))
    (is (search "undeclared" (rejection-message condition))
        "Rejection must name the undeclared state.")))

(test lifecycle-rejects-undeclared-event
  "A transition event outside the declared event vocabulary is rejected."
  (let ((condition
          (rejected-lifecycle
           (with-transitions
            "(:from draft :on unlisted :to active)"))))
    (is (search "event" (rejection-message condition))
        "Rejection must name the undeclared event.")))

(test lifecycle-rejects-invalid-version
  "Lifecycle version must be a positive integer."
  (let ((condition
          (rejected-lifecycle
           "(spec-library \"org.starintel/lifecycle-fixtures@1\" (:version \"1.0.0\")
  (lifecycle person-lifecycle
    (:applies org.starintel/person@1
     :version 0
     :initial draft
     :states (draft)
     :events ()
     :transitions ())))")))
    (is (search "version" (rejection-message condition))
        "Rejection must name the invalid version.")))

(defun manifest-fixture-json (manifest)
  "Single authoritative lifecycle-manifest plist to canonical JSON mapping
used both by the byte-determinism test and by the committed
fixtures/lifecycle/generate-manifest.lisp driver. Key mapping is closed;
absent optional fields are omitted."
  (labels ((keyword-value (value)
             (string-downcase (symbol-name value)))
           (row-json (row)
             (starcanonicaljson:make-json-object
              (remove nil
                      (list (cons "from" (getf row :from))
                            (cons "on" (getf row :on))
                            (cons "to" (getf row :to))
                            (when (getf row :guard)
                              (cons "guard" (getf row :guard)))
                            (cons "action" (keyword-value (getf row :action)))
                            (when (getf row :emit)
                              (cons "emit" (getf row :emit)))
                            (when (getf row :supersedes)
                              (cons "supersedes" (getf row :supersedes)))))))
           (lifecycle-json (lifecycle)
             (starcanonicaljson:make-json-object
              (remove nil
                      (list
                       (cons "name" (getf lifecycle :name))
                       (cons "qualifiedName" (getf lifecycle :qualified-name))
                       (cons "applies" (getf lifecycle :applies))
                       (cons "version" (getf lifecycle :version))
                       (cons "initial" (getf lifecycle :initial))
                       (cons "states"
                             (starcanonicaljson:make-json-array (getf lifecycle :states)))
                       (when (getf lifecycle :retention)
                         (cons "retention"
                               (starcanonicaljson:make-json-object
                                (list (cons "evidenceDays"
                                            (getf (getf lifecycle :retention)
                                                  :evidence-days))))))
                       (when (getf lifecycle :storage)
                         (cons "storage"
                               (starcanonicaljson:make-json-object
                                (list (cons "tier"
                                            (keyword-value
                                             (getf (getf lifecycle :storage) :tier)))
                                      (cons "replication"
                                            (keyword-value
                                             (getf (getf lifecycle :storage)
                                                   :replication)))))))
                       (when (getf lifecycle :ttl-days)
                         (cons "ttlDays" (getf lifecycle :ttl-days)))
                       (when (getf lifecycle :indexing)
                         (cons "indexing"
                               (starcanonicaljson:make-json-object
                                (list (cons "mode"
                                            (keyword-value
                                             (getf (getf lifecycle :indexing)
                                                   :mode)))))))
                       (when (getf lifecycle :encryption)
                         (cons "encryption"
                               (starcanonicaljson:make-json-object
                                (list (cons "class"
                                            (keyword-value
                                             (getf (getf lifecycle :encryption)
                                                   :class)))))))
                       (when (getf lifecycle :hold)
                         (cons "hold"
                               (starcanonicaljson:make-json-object
                                (list (cons "class"
                                            (keyword-value
                                             (getf (getf lifecycle :hold) :class)))
                                      (cons "reason"
                                            (getf (getf lifecycle :hold)
                                                  :reason))))))
                       (cons "events"
                             (starcanonicaljson:make-json-array (getf lifecycle :events)))
                       (cons "transitions"
                             (starcanonicaljson:make-json-array
                              (mapcar #'row-json
                                      (getf lifecycle :transitions)))))))))
    (starcanonicaljson:canonical-json-string
     (starcanonicaljson:make-json-object
      (list (cons "wireVersion" 1)
            (cons "lifecycle" (lifecycle-json (getf manifest :lifecycle))))))))

(defun compiled-fixture-manifest ()
  "Compile the committed fixtures/lifecycle/document-lifecycle.star through
the closed parser and emit its lifecycle manifest."
  (starlangcompiler:emit-lifecycle-manifest
   (find :lifecycle
         (getf (starlangcompiler:load-star-form
                (fixture-path "document-lifecycle.star"))
               :declarations)
         :key (lambda (item) (getf item :kind)))))

(test lifecycle-emits-deterministic-manifest-and-transition-table
  "Manifest and transition table are deterministic and versioned."
  (let* ((first-manifest
           (starlangcompiler:emit-lifecycle-manifest
            (lifecycle-declaration *valid-lifecycle-source*)))
         (second-manifest
           (starlangcompiler:emit-lifecycle-manifest
            (lifecycle-declaration *valid-lifecycle-source*))))
    (is (equal first-manifest second-manifest)
        "Two compilations of the same source must emit equal manifests.")
    (is (eql 1 (getf first-manifest :wire-version)))
    (is (eql 2 (getf (getf first-manifest :lifecycle) :version))
        "The manifest records the declared lifecycle version for replay.")
    (is (equal (getf (getf first-manifest :lifecycle) :transitions)
               (starlangcompiler:lifecycle-transition-table
                (getf first-manifest :lifecycle)))
        "The transition table is exactly the manifest transition rows.")))

(test lifecycle-manifest-json-fixture-is-byte-deterministic
  "The committed manifest JSON fixture matches a fresh compilation byte for byte."
  (let* ((manifest
           (starlangcompiler:emit-lifecycle-manifest
            (lifecycle-declaration *valid-lifecycle-source*)))
         (expected
           (with-open-file (stream (fixture-path "document-lifecycle.manifest.json"))
             (read-line stream nil nil t)))
         (actual (manifest-fixture-json manifest)))
    (is (string= expected actual)
        "Compiled manifest JSON must equal the committed fixture bytes.")))

(test lifecycle-fixture-compiles-through-closed-parser
  "The committed .star lifecycle fixture compiles to the expected lifecycle."
  (let ((library (starlangcompiler:load-star-form
                  (fixture-path "document-lifecycle.star"))))
    (is-true (find :lifecycle (getf library :declarations)
                   :key (lambda (item) (getf item :kind))))))

(test lifecycle-transition-table-replays-versioned-events
  "The transition table is a total replay function from the initial state."
  (let* ((lifecycle (getf (starlangcompiler:emit-lifecycle-manifest
                           (lifecycle-declaration *valid-lifecycle-source*))
                          :lifecycle))
         (table (starlangcompiler:lifecycle-transition-table lifecycle))
         (initial (getf lifecycle :initial)))
    (labels ((successor (state event)
               (let ((row (find-if (lambda (row)
                                     (and (equal (getf row :from) state)
                                          (equal (getf row :on) event)))
                                   table)))
                 (when row (getf row :to)))))
      (is (equal "active" (successor initial "submitted")))
      (is (equal "archived" (successor "active" "archived")))
      (is (equal "redacted" (successor "archived" "redacted")))
      (is (equal "deleted" (successor "redacted" "tombstoned")))
      (is (null (successor "deleted" "tombstoned"))
          "Terminal states have no successors; replay is table-total."))))

(defun run-tests ()
  (unless (run! 'starlang-lifecycle-tests)
    (error "starlang-lifecycle-tests failed."))
  t)
