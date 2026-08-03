(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "macro-expander-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun macro-assert (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun macro-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun macro-condition (type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught type) caught (error caught)))))

(defun without-macro-source-map (ir)
  (let ((copy (copy-list ir)))
    (remf copy :source-map)
    copy))

(defparameter *required-message-macro-source*
  "(spec-library \"test/macros@1\" (:version \"1\" :digest \"sha256:macro-test\")
     (macro required-message
       (:format 1
        :context declaration
        :rules
        (((required-message ?name ?field)
          (message ?name (:fields ((?field string :required))))))))
     (required-message ping messageId)
     (required-message pong correlationId))")

(defun test-declarative-expansion-and-equivalence ()
  (let* ((syntax (read-star-syntax *required-message-macro-source*
                                   :source-id "macro-equivalence"))
         (invocation (fifth (star-syntax-children syntax)))
         (use-name (second (star-syntax-children invocation)))
         (expanded (expand-star-syntax syntax))
         (declarations (nthcdr 3 (star-syntax-children expanded)))
         (first-message (first declarations))
         (generated-head (first (star-syntax-children first-message)))
         (copied-name (second (star-syntax-children first-message)))
         (handwritten
           (read-star-syntax
            "(spec-library \"test/macros@1\" (:version \"1\" :digest \"sha256:macro-test\")
               (message ping (:fields ((messageId string :required))))
               (message pong (:fields ((correlationId string :required)))))"
            :source-id "macro-handwritten")))
    (macro-equal 2 (length declarations) "macro definitions disappear")
    (macro-assert (eq use-name copied-name)
                  "pattern argument keeps use-site syntax identity")
    (macro-assert (star-syntax-scopes generated-head)
                  "template identifier receives introduction scope")
    (macro-equal nil (star-syntax-scopes copied-name)
                 "copied argument keeps use-site scopes")
    (macro-equal
     (without-macro-source-map (compile-star-core (expand-star-syntax handwritten)))
     (without-macro-source-map (compile-star-core expanded))
     "macro and handwritten core compile equivalently")
    (macro-equal 2 (length (star-syntax-expansion-trace expanded))
                 "two expansion records")
    (macro-equal 1 (length (star-macro-dependencies expanded))
                 "macro dependency recorded")))

(defun test-distinct-introduction-scopes-and-provenance ()
  (let* ((syntax (read-star-syntax *required-message-macro-source*
                                   :source-id "macro-hygiene"))
         (expanded (expand-star-syntax syntax))
         (declarations (nthcdr 3 (star-syntax-children expanded)))
         (first-head (first (star-syntax-children (first declarations))))
         (second-head (first (star-syntax-children (second declarations))))
         (first-scope (first (star-syntax-scopes first-head)))
         (second-scope (first (star-syntax-scopes second-head)))
         (origin (star-syntax-origin first-head)))
    (macro-assert (not (string= first-scope second-scope))
                  "invocations receive distinct introduction scopes")
    (macro-equal :macro-expansion (star-origin-frame-kind origin)
                 "generated syntax has macro origin")
    (macro-assert (star-origin-frame-definition-span origin)
                  "macro origin has definition span")
    (macro-assert (star-origin-frame-invocation-span origin)
                  "macro origin has invocation span")
    (macro-equal "rule-1" (star-origin-frame-rule-id origin)
                 "macro origin has rule id")))

(defun test-tail-repetition ()
  (let* ((syntax
           (read-star-syntax
            "(spec-library \"test/repeat@1\" (:version \"1\")
               (macro make-record
                 (:context declaration
                  :rules
                  (((make-record ?name ?field ...)
                    (document ?name (:persistence transient)
                      (?field string :optional) ...)))))
               (make-record person firstName lastName))"
            :source-id "macro-repeat"))
         (expanded (expand-star-syntax syntax))
         (ir (compile-star-core expanded))
         (document (first (getf ir :declarations))))
    (macro-equal '("firstName" "lastName")
                 (mapcar (lambda (field) (getf field :name))
                         (getf document :fields))
                 "tail repetition preserves ordered field arguments")))

(defun test-locked-imported-macro-environment ()
  (let* ((library
           (read-star-syntax
            "(spec-library \"test/macro-lib@1\"
               (:version \"1.2.3\" :digest \"sha256:locked-macro-library\")
               (macro imported-message
                 (:context declaration
                  :rules (((imported-message ?name)
                           (message ?name (:fields ())))))))"
            :source-id "macro-library"))
         (environment (collect-star-macro-environment library))
         (consumer
           (read-star-syntax
            "(spec-library \"test/consumer@1\" (:version \"1\")
               (import \"test/macro-lib@1\"
                 :version \"1.2.3\"
                 :digest \"sha256:locked-macro-library\")
               (imported-message ping))"
            :source-id "macro-consumer"))
         (expanded (expand-star-syntax consumer :environment environment))
         (dependency (first (star-macro-dependencies expanded))))
    (macro-equal "message"
                 (syntax-head-name
                  (fifth (star-syntax-children expanded)))
                 "imported macro expands in consumer")
    (macro-equal "test/macro-lib@1/imported-message"
                 (getf dependency :name)
                 "imported macro dependency qualified")
    (macro-equal "sha256:locked-macro-library"
                 (getf dependency :library-digest)
                 "imported macro dependency is digest locked")))

(defun test-bounded-failures ()
  (let ((cycle
          (read-star-syntax
           "(spec-library \"test/cycle@1\" (:version \"1\")
              (macro loop (:context declaration :rules (((loop) (loop)))))
              (loop))"
           :source-id "macro-cycle"))
        (ambiguous
          (read-star-syntax
           "(spec-library \"test/ambiguous@1\" (:version \"1\")
              (macro duplicate
                (:context declaration
                 :rules (((duplicate ?name) (message ?name (:fields ())))
                         ((duplicate ?name) (message ?name (:fields ()))))))
              (duplicate ping))"
           :source-id "macro-ambiguous"))
        (unknown
          (read-star-syntax
           "(spec-library \"test/unknown@1\" (:version \"1\")
              (macro bad (:context declaration :rules (((bad) (not-core x)))))
              (bad))"
           :source-id "macro-unknown")))
    (macro-assert
     (macro-condition 'macro-expansion-error
                      (lambda () (expand-star-syntax cycle)))
     "recursive macro cycle rejected")
    (macro-assert
     (macro-condition 'macro-expansion-error
                      (lambda () (expand-star-syntax ambiguous)))
     "ambiguous rules rejected")
    (macro-assert
     (macro-condition 'invalid-declaration-error
                      (lambda ()
                        (validate-star-core (expand-star-syntax unknown))))
     "generated unknown core form rejected before compilation")
    (macro-assert
     (macro-condition
      'macro-limit-error
      (lambda ()
        (expand-star-syntax
         (read-star-syntax *required-message-macro-source*)
         :expansion-limits
         (make-star-expansion-limits :generated-nodes 2))))
     "generated-node budget enforced")))

(defun test-stable-expanded-source ()
  (let ((syntax (read-star-syntax *required-message-macro-source*
                                  :source-id "macro-render")))
    (macro-equal (expanded-star-source syntax)
                 (expanded-star-source syntax)
                 "expanded source is deterministic")
    (macro-assert (not (search "(macro " (expanded-star-source syntax)))
                  "expanded source contains core only")))

(defun test-single-expansion-step ()
  (let* ((syntax
           (read-star-syntax
            "(spec-library \"test/one-step@1\" (:version \"1\")
               (macro outer
                 (:context declaration
                  :rules (((outer ?name) (inner ?name)))))
               (macro inner
                 (:context declaration
                  :rules (((inner ?name) (message ?name (:fields ()))))))
               (outer ping))"
            :source-id "macro-one-step"))
         (once (expand-star-syntax-1 syntax))
         (once-declaration (sixth (star-syntax-children once)))
         (fully (expand-star-syntax syntax))
         (fully-declaration (fourth (star-syntax-children fully))))
    (macro-equal "inner" (syntax-head-name once-declaration)
                 "single-step expansion stops before nested invocation")
    (macro-equal "message" (syntax-head-name fully-declaration)
                 "full expansion reaches core declaration")))

(defun run-macro-expander-tests ()
  (mapc #'funcall
        (list #'test-declarative-expansion-and-equivalence
              #'test-distinct-introduction-scopes-and-provenance
              #'test-tail-repetition
              #'test-locked-imported-macro-environment
              #'test-bounded-failures
              #'test-stable-expanded-source
              #'test-single-expansion-step))
  (format t "Star-Lang declarative hygienic macro tests passed.~%")
  t)

(unless (run-macro-expander-tests)
  (error "Star-Lang declarative hygienic macro tests failed."))
