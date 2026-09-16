;;;; Regression coverage for actor capability declarations.

(defpackage :starlang-actor-capabilities-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-actor-capabilities-tests)

(def-suite starlang-actor-capabilities-tests
  :description "Final actor capability validation and portable projection.")

(in-suite starlang-actor-capabilities-tests)

(defun actor-source-with-capabilities (capabilities)
  (format nil
          "(actor probe
             (:runtime native
              :handler handle-probe
              :accepts ()
              :produces ()
              :restart temporary
              :mailbox (bounded 1)~A))"
          (if capabilities
              (format nil " :capabilities ~A" capabilities)
              "")))

(defun capture-invalid-actor (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (star-lang.compiler.core:invalid-actor-error (condition)
      condition)))

(defun minimal-test-library ()
  (list :kind :spec-library
        :name "org.starintel/core@1"
        :version "1.0.0"
        :digest "sha256:actor-capabilities-test"
        :imports '()
        :declarations '()))

(test malformed-source-capability-values-fail-closed
  "Explicit capabilities must be a list of identifier syntax, never a scalar or keyword/list value."
  (loop for value in '("network"
                       "\"network\""
                       "42"
                       "t"
                       "((network))"
                       "(:runtime)"
                       "(\"network\")")
        for condition =
          (capture-invalid-actor
           (lambda ()
             (starlangcompiler:compile-actor-source
              (actor-source-with-capabilities value))))
        do (is (typep condition 'star-lang.compiler.core:invalid-actor-error))
           (is (star-lang.compiler.core:star-lang-core-error-span condition))
           (is (eq :lower
                   (star-lang.compiler.core:star-lang-core-error-phase condition)))))

(test trusted-host-capability-shape-fails-closed
  "The trusted host entry point rejects malformed shapes instead of normalizing them to no requirements."
  (dolist (capabilities '(network (:runtime) ((network)) 42 t))
    (signals star-lang.compiler.core:invalid-actor-error
      (star-lang.compiler.core:compile-actor
       `(actor probe
          (:runtime native
           :handler handle-probe
           :accepts ()
           :produces ()
           :restart temporary
           :mailbox (bounded 1)
           :capabilities ,capabilities)))))

(test omitted-empty-and-valid-capabilities-remain-distinct-at-validation
  "Omission and explicit empty are valid; valid identifiers are preserved in order."
  (let ((omitted
          (starlangcompiler:compile-actor-source
           (actor-source-with-capabilities nil)))
        (empty
          (starlangcompiler:compile-actor-source
           (actor-source-with-capabilities "()")))
        (one
          (starlangcompiler:compile-actor-source
           (actor-source-with-capabilities "(network)")))
        (many
          (starlangcompiler:compile-actor-source
           (actor-source-with-capabilities "(network write-dataset emit-documents)"))))
    (is (equal '() (getf omitted :capabilities)))
    (is (equal '() (getf empty :capabilities)))
    (is (equal '("network") (getf one :capabilities)))
    (is (equal '("network" "write-dataset" "emit-documents")
               (getf many :capabilities)))))

(test trusted-host-valid-capabilities-remain-compatible
  "Trusted host forms retain the historical symbol/string identifier representation."
  (let ((actor
          (star-lang.compiler.core:compile-actor
           '(actor probe
             (:runtime native
              :handler handle-probe
              :accepts ()
              :produces ()
              :restart temporary
              :mailbox (bounded 1)
              :capabilities (network "emit-documents"))))))
    (is (equal '("network" "emit-documents")
               (getf actor :capabilities)))))

(test valid-capabilities-survive-portable-and-canonical-manifest-projection
  "Validated capability identifiers survive portable actor and canonical JSON emission exactly."
  (let* ((actor
           (starlangcompiler:compile-actor-source
            (actor-source-with-capabilities
             "(network write-dataset emit-documents)")))
         (portable (starlangcompiler:portable-actor actor))
         (manifest
           (starlangcompiler:emit-portable-manifest
            (minimal-test-library) (list actor)))
         (json (starcanonicaljson:canonical-manifest-json manifest)))
    (is (equal '("network" "write-dataset" "emit-documents")
               (getf portable :capabilities)))
    (is (equal '("network" "write-dataset" "emit-documents")
               (getf (first (getf manifest :actors)) :capabilities)))
    (is (search "\"capabilities\":[\"network\",\"write-dataset\",\"emit-documents\"]"
                json))))

(defun run-tests ()
  (unless (run! 'starlang-actor-capabilities-tests)
    (error "starlang actor capability tests failed.")))
