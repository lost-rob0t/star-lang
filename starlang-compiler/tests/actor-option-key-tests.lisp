;;;; Actor option key closure/uniqueness regressions for issue #80.
;;;; These tests exercise the final closed source parser and final actor lowering.

(defpackage :starlang-actor-option-key-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-actor-option-key-tests)

(def-suite starlang-actor-option-key-tests
  :description "Closed and unique actor option keys at the final compiler boundary.")

(in-suite starlang-actor-option-key-tests)

(defparameter *native-base-options*
  ":runtime native
   :accepts ()
   :produces ()
   :handler handle-probe
   :restart temporary
   :mailbox (bounded 1)
   :capabilities (read)
   :metadata ((team \"one\"))")

(defun native-actor-source (&optional extra)
  (format nil "(actor probe (~A~@[ ~A~]))" *native-base-options* extra))

(defun external-actor-source (&optional extra)
  (format nil
          "(actor probe
             (:runtime external
              :accepts ()
              :produces ()
              :protocol star-message-v1
              :endpoint \"fake:probe\"
              :restart temporary
              :mailbox (bounded 1)~@[ ~A~]))"
          extra))

(defun capture-invalid-actor (source)
  (handler-case
      (progn
        (starlangcompiler:compile-actor-source source)
        nil)
    (star-lang.compiler.core:invalid-actor-error (condition)
      condition)))

(test duplicate-actor-options-are-rejected
  "Every currently supported native actor option is unique, even when the
repeated value is identical."
  (dolist (duplicate
           '(":runtime native"
             ":handler handle-probe"
             ":accepts ()"
             ":produces ()"
             ":restart temporary"
             ":mailbox (bounded 1)"
             ":capabilities (read)"
             ":metadata ((team \"one\"))"))
    (signals star-lang.compiler.core:invalid-actor-error
      (starlangcompiler:compile-actor-source
       (native-actor-source duplicate)))))

(test actor-option-key-vocabulary-is-closed
  "Known-but-inapplicable keywords and non-keyword key syntax are rejected by
actor lowering rather than silently ignored."
  (dolist (extra '(":maximum 5"
                   "bogus 1"
                   "\"bogus\" 1"
                   "(bogus) 1"
                   ":protocol star-message-v1"))
    (signals star-lang.compiler.core:invalid-actor-error
      (starlangcompiler:compile-actor-source
       (native-actor-source extra))))
  (signals star-lang.compiler.core:invalid-actor-error
    (starlangcompiler:compile-actor-source
     (external-actor-source ":handler handle-probe"))))

(test duplicate-diagnostic-points-at-second-and-relates-first
  "A duplicate source option reports the offending second occurrence and
retains the first occurrence as related source evidence."
  (let* ((source (native-actor-source ":runtime native"))
         (condition (capture-invalid-actor source)))
    (is condition)
    (when condition
      (let ((span (star-lang.compiler.core:star-lang-core-error-span condition))
            (related
              (star-lang.compiler.core:star-lang-core-error-related-spans
               condition)))
        (is span)
        (is (= 1 (length related)))
        (when (and span (= 1 (length related)))
          (let ((first (first related)))
            (is (< (star-lang.compiler.core:star-source-span-start-byte first)
                   (star-lang.compiler.core:star-source-span-start-byte span)))
            (is (= (search ":runtime native" source :from-end t)
                   (star-lang.compiler.core:star-source-span-start-byte span)))))))))

(test invalid-key-diagnostic-points-at-offending-occurrence
  "Closed-key errors carry the exact source occurrence rather than the whole
actor form."
  (dolist (token '(":maximum" "bogus" ":protocol"))
    (let* ((extra (cond
                    ((string= token ":maximum") ":maximum 5")
                    ((string= token "bogus") "bogus 1")
                    (t ":protocol star-message-v1")))
           (source (native-actor-source extra))
           (condition (capture-invalid-actor source)))
      (is condition)
      (when condition
        (let ((span (star-lang.compiler.core:star-lang-core-error-span condition)))
          (is span)
          (when span
            (is (= (search token source :from-end t)
                   (star-lang.compiler.core:star-source-span-start-byte span)))))))))

(test trusted-host-actor-options-enforce-the-same-key-rules
  "Trusted Common Lisp forms retain their representation but not a looser
semantic option-key policy."
  (dolist (form
           '((actor probe
               (:runtime native :runtime native
                :accepts () :produces () :handler handle-probe
                :restart temporary :mailbox (bounded 1)))
             (actor probe
               (:runtime native bogus 1
                :accepts () :produces () :handler handle-probe
                :restart temporary :mailbox (bounded 1)))
             (actor probe
               (:runtime native :maximum 5
                :accepts () :produces () :handler handle-probe
                :restart temporary :mailbox (bounded 1)))
             (actor probe
               (:runtime external :handler handle-probe
                :accepts () :produces ()
                :protocol star-message-v1 :endpoint "fake:probe"
                :restart temporary :mailbox (bounded 1)))))
    (signals star-lang.compiler.core:invalid-actor-error
      (star-lang.compiler.core:compile-actor form))))

(defun run-tests ()
  (unless (run! 'starlang-actor-option-key-tests)
    (error "starlang-compiler actor option key tests failed.")))
