(defpackage :starlangcompiler-tests
  (:use :cl :fiveam)
  (:export))

(in-package :starlangcompiler-tests)

(def-suite starlangcompiler-tests
  :description "Final compiler compatibility tests.")

(in-suite starlangcompiler-tests)

(defun make-test-identity ()
  (starlogicir:make-logic-package-identity
   :package-id "logic.compiler-test"
   :package-version "1.0.0"
   :package-digest "sha256:compiler-test-package"
   :mapping-id "mapping.compiler-test"
   :mapping-digest "sha256:compiler-test-mapping"))

(defun compile-test-call (&key backend-policy)
  (let ((arguments
          (list
           :operation-id "compiler-op-1"
           :named-operation-id "lookup"
           :operation-kind "solve"
           :semantic-profile "star.logic.query/1"
           :bindings '(("subject" . "alice"))
           :answer-policy '(("limit" . 1))
           :proof-policy '(("mode" . "optional"))
           :required-capabilities '("named-query")
           :required-hard-limits '("answers")
           :required-isolation "process"
           :package-identity (make-test-identity)
           :budget '(("answers" . 1))
           :source-span '(("sourceId" . "compiler-test.star")
                          ("startLine" . 7)
                          ("startColumn" . 3)))))
    (when backend-policy
      (setf arguments (append arguments (list :backend-policy backend-policy))))
    (apply #'starlangcompiler:compile-logic-call arguments)))

(test compiler-forwards-to-final-logic-ir
  "The compiler compatibility API returns the final star-logic-ir authority."
  (let ((call (compile-test-call)))
    (is (starlogicir:logic-call-p call))
    (is (string= "auto" (starlogicir:logic-call-backend-policy call)))
    (is (equal '(("sourceId" . "compiler-test.star")
                 ("startColumn" . 3)
                 ("startLine" . 7))
               (starlogicir:logic-call-source-span call)))))

(test compiler-preserves-logic-policy-diagnostics
  "IR validation failures retain a dedicated compiler diagnostic and source span."
  (let ((condition
          (handler-case
              (progn
                (compile-test-call :backend-policy "unknown-engine")
                nil)
            (starlangcompiler:logic-policy-compiler-error (condition)
              condition))))
    (is (typep condition 'starlangcompiler:logic-policy-compiler-error))
    (is (eq :unknown-logic-backend
            (starlangcompiler:logic-policy-compiler-error-code condition)))
    (is (equal '(("sourceId" . "compiler-test.star")
                 ("startLine" . 7)
                 ("startColumn" . 3))
               (starlangcompiler:logic-policy-compiler-error-source-span
                condition)))))

(test compiler-materialization-uses-portable-selector
  "Compiler materialization delegates to the existing backend selector."
  (let* ((backend
           (starlogictesting:make-fake-logic-backend
            :id "swi-prolog"
            :semantic-profiles '("star.logic.query/1")
            :capabilities '("named-query")
            :isolation-classes '("process")
            :hard-limits '("answers")))
         (registry (starlogicprotocol:make-logic-backend-registry))
         (call (compile-test-call :backend-policy "swi-prolog")))
    (starlogicprotocol:register-logic-backend registry backend)
    (let ((plan
            (starlangcompiler:materialize-compiled-logic-call call registry)))
      (is (starlogicir:materialized-logic-call-p plan))
      (is (string= "swi-prolog"
                   (starlogicir:materialized-logic-call-backend-id plan))))))

(test compiler-materialization-preserves-source-aware-failure
  "Backend incompatibility becomes a source-aware compiler diagnostic."
  (let* ((backend
           (starlogictesting:make-fake-logic-backend
            :id "swi-prolog"
            :semantic-profiles '("star.logic.tabled/1")
            :capabilities '("named-query")
            :isolation-classes '("process")
            :hard-limits '("answers")))
         (registry (starlogicprotocol:make-logic-backend-registry))
         (call (compile-test-call :backend-policy "swi-prolog")))
    (starlogicprotocol:register-logic-backend registry backend)
    (let ((condition
            (handler-case
                (progn
                  (starlangcompiler:materialize-compiled-logic-call call registry)
                  nil)
              (starlangcompiler:logic-policy-compiler-error (condition)
                condition))))
      (is (eq :logic-backend-incompatible
              (starlangcompiler:logic-policy-compiler-error-code condition)))
      (is (equal (starlogicir:logic-call-source-span call)
                 (starlangcompiler:logic-policy-compiler-error-source-span
                  condition))))))

(test final-compiler-logic-path-does-not-load-prototype
  "The final compiler logic compatibility path stays prototype-independent."
  (is (null (find-package "STAR-LANG.PROTOTYPE")))
  (is (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))))
