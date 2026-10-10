(defpackage #:starlang-actor-source-boundary-tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:starlang-actor-source-boundary-tests)

(def-suite actor-source-boundary-tests
  :description "Source-aware actor-only compiler boundary diagnostics.")
(in-suite actor-source-boundary-tests)

(defun compile-boundary-error (source)
  (handler-case
      (progn
        (star-lang.compiler.core:compile-actor-source
         source :source-id "actor-boundary.star")
        nil)
    (star-lang.compiler.core:invalid-declaration-error (condition)
      condition)))

(test valid-non-actor-head-points-at-source-identifier
  "A recognized program declaration that is not an actor must retain its span."
  (let ((condition (compile-boundary-error
                    (format nil "~%  (document record (:persistence persistent))"))))
    (is (typep condition 'star-lang.compiler.core:invalid-declaration-error))
    (is (search "Expected an actor declaration"
                (star-lang.compiler.core:star-lang-core-error-message condition)))
    (is (eq :compile (star-lang.compiler.core:star-lang-core-error-phase condition)))
    (let ((span (star-lang.compiler.core:star-lang-core-error-span condition)))
      (is span)
      (when span
        (is (string= "actor-boundary.star"
                     (star-lang.compiler.core:star-source-span-source-id span)))
        (is (= 2 (star-lang.compiler.core:star-source-span-start-line span)))
        (is (= 4 (star-lang.compiler.core:star-source-span-start-column span)))
        (is (= 4 (star-lang.compiler.core:star-source-span-start-byte span)))
        (is (= 12 (star-lang.compiler.core:star-source-span-end-byte span)))))))

(test unknown-program-head-keeps-existing-source-diagnostic
  "An unknown head is still diagnosed by the closed program grammar."
  (let ((condition (compile-boundary-error "(imaginary-task worker)")))
    (is (typep condition 'star-lang.compiler.core:invalid-declaration-error))
    (is (eq :compile (star-lang.compiler.core:star-lang-core-error-phase condition)))
    (let ((span (star-lang.compiler.core:star-lang-core-error-span condition)))
      (is span)
      (when span
        (is (= 1 (star-lang.compiler.core:star-source-span-start-line span)))
        (is (= 2 (star-lang.compiler.core:star-source-span-start-column span)))))))

(test actual-actor-remains-compilable
  "The actor-only boundary still lowers a valid native actor."
  (let ((actor
          (star-lang.compiler.core:compile-actor-source
           "(actor worker (:runtime native :handler start :accepts () :produces () :restart permanent :mailbox (bounded 2)))"
           :source-id "actor-boundary.star")))
    (is (eq :actor (getf actor :kind)))
    (is (string= "worker" (getf actor :name)))
    (is (eq :native (getf actor :runtime)))))

(defun run-tests ()
  (unless (fiveam:run! 'actor-source-boundary-tests)
    (error "StarLang actor source boundary tests failed.")))
