;;;; Permanent proof that semantic/program compilation is final-owned.

(defpackage :starlang-final-authority-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-final-authority-tests)

(def-suite starlang-final-authority-tests
  :description "Final-only StarLang semantic and normalized program IR proof.")

(in-suite starlang-final-authority-tests)

(defparameter +digest-a+
  "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")

(test exact-digest-contract-is-final-owned
  (is (starlangcompiler:full-sha256-digest-p +digest-a+))
  (is (starlangcompiler:full-sha256-digest-p
       "sha256:FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"))
  (dolist (bad '("sha256:a"
                 "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                 "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                 "sha256:gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg"
                 "SHA256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    (is (not (starlangcompiler:full-sha256-digest-p bad)))))

(test compiler-imports-require-full-digests
  (signals star-lang.compiler.core:invalid-library-error
    (starlangcompiler:compile-spec-library
     '(spec-library "test/core@1"
       (:version "1.0.0" :digest "sha256:short")
       (message ping (:fields ()))))))

(test semantic-validation-rejects-inheritance-cycles
  (signals star-lang.compiler.core:invalid-declaration-error
    (starlangcompiler:compile-core-library
     `(spec-library "test/core@1"
       (:version "1.0.0" :digest ,+digest-a+)
       (document parent
         (:persistence persistent :extends child)
         (parentField string :required))
       (document child
         (:persistence persistent :extends parent)
         (childField string :required))))))

(test semantic-validation-rejects-predicate-kind-mismatch
  (signals star-lang.compiler.core:invalid-type-error
    (starlangcompiler:compile-core-library
     `(spec-library "test/core@1"
       (:version "1.0.0" :digest ,+digest-a+)
       (message ping (:fields ()))
       (document person
         (:persistence persistent)
         (name string :required))
       (predicate wrong
         (:source ping :destination person))))))

(defparameter +program-source+
  "((spec-graph
      (:lock-digest \"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
       :libraries
       ((:name \"test/core@1\"
         :version \"1.0.0\"
         :digest \"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"
         :path \"spec-lock/test-core/library.star\"))))
    (actor worker
      (:runtime native
       :accepts ()
       :produces ()
       :handler handle-worker
       :restart temporary
       :mailbox (bounded 8)))
    (dataflow ingest
      (from-dataset \"fixture\")
      (send worker current)
      (collect results)))")

(test program-source-compiles-through-closed-reader
  (let* ((program (starlangcompiler:compile-program-source +program-source+))
         (declarations (getf program :declarations))
         (actor (find :actor declarations :key (lambda (item) (getf item :kind))))
         (flow (find :dataflow declarations :key (lambda (item) (getf item :kind))))
         (send (find :send (getf flow :nodes) :key (lambda (item) (getf item :op)))))
    (is (= 2 (getf program :ir-version)))
    (is (string= "org.star-lang/normalized-ir@2" (getf program :ir-schema)))
    (is (eq :program (getf program :kind)))
    (is (string= "worker" (getf actor :name)))
    (is (eq :native (getf actor :runtime)))
    (is (string= "worker" (getf send :target)))
    (is (listp (getf program :source-map)))))

(test final-program-compiler-does-not-load-prototype
  (starlangcompiler:compile-program-source +program-source+)
  (dolist (package-name '("STAR-LANG.PROTOTYPE"
                          "STAR-LANG.COMPILER-IR.PROTOTYPE"
                          "STAR-LANG.SPEC-DOMAIN.PROTOTYPE"
                          "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
    (is (null (find-package package-name)))))

(test remote-unresolved-spec-path-fails-closed
  (let ((source
          "((spec-graph
              (:lock-digest \"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
               :libraries
               ((:name \"test/core@1\"
                 :version \"1.0.0\"
                 :digest \"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"
                 :path \"https://example.invalid/core.star\")))))"))
    (signals star-lang.compiler.core:unresolved-spec-error
      (starlangcompiler:compile-program-source source))))

(defun run-tests ()
  (unless (run! 'starlang-final-authority-tests)
    (error "StarLang final authority tests failed.")))
