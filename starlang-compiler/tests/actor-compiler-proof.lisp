;;;; Fresh-process acceptance proof: actor compilation through final systems.
;;;; Run as `sbcl --non-interactive --load actor-compiler-proof.lisp`.
;;;; Exits 0 only when every claim holds with no prototype package loaded.

(require :asdf)

;; The proof script may run in a bare process without CL_SOURCE_REGISTRY;
;; register this repository tree explicitly so the final systems resolve.
(let* ((tests-directory
         (make-pathname :name nil :type nil :defaults *load-truename*))
       (repository-root (merge-pathnames "../../" tests-directory)))
  (asdf:initialize-source-registry
   `(:source-registry
     :inherit-configuration
     (:tree ,(namestring repository-root)))))

(defun proof-fail (control &rest arguments)
  (format *error-output* "~?~%" control arguments)
  (force-output *error-output*)
  (sb-ext:exit :code 1))

(defun proof-assert (condition label)
  (unless condition
    (proof-fail "proof failed: ~A" label)))

(asdf:load-system :starlang-compiler)

;; The final compiler path must not load the prototype system.
(proof-assert (null (find-package "STAR-LANG.PROTOTYPE"))
              "starlang-prototype package must not exist")
(proof-assert (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
              "core-surface prototype package must not exist")

(defparameter *proof-fixture*
  (merge-pathnames
   "../../fixtures/actor-compiler/enrichment-worker.star"
   *load-truename*))

(defparameter *expected-actor-ir*
  '(:kind :actor
    :name "enrichment-worker"
    :runtime :native
    :service-uri "star://starintel:localhost:enrichment-worker"
    :accepts ("org.starintel/person@1")
    :produces ("org.starintel/person@1")
    :restart :permanent
    :mailbox (:kind :bounded :capacity 128)
    :capabilities ()
    :handler "enrichment-worker-handler"
    :metadata (("domain" . "starintel") ("team" . "enrichment"))))

(defun proof-data-only-p (value)
  (typecase value
    ((or null boolean string integer keyword symbol) t)
    (cons (and (proof-data-only-p (car value))
               (proof-data-only-p (cdr value))))
    (t nil)))

;; The fixture is read by the closed .star parser and compiles deterministically.
(let ((first (starlangcompiler:compile-actor-file *proof-fixture*))
      (second (starlangcompiler:compile-actor-file *proof-fixture*)))
  (proof-assert (equal *expected-actor-ir* first)
                "compiled actor IR must match the expected normalized IR")
  (proof-assert (equal first second)
                "compilation must be deterministic")
  (proof-assert (proof-data-only-p first)
                "actor IR must be data-only and runtime-neutral")
  ;; The service URI stays canonical under the final protocol authority.
  (proof-assert (string= "star://starintel:localhost:enrichment-worker"
                         (getf first :service-uri))
                "service URI must be canonical"))

;; Actor name / service-name mismatch is rejected deterministically.
(handler-case
    (progn
      (starlangcompiler:compile-actor-source
       "(actor enrichment-worker
          (:runtime native
           :service-uri \"star://starintel:localhost:other-worker\"
           :accepts (org.starintel/person@1)
           :produces (org.starintel/person@1)
           :handler enrichment-worker-handler
           :restart permanent
           :mailbox (bounded 128)))")
      (proof-fail "proof failed: mismatched service URI was accepted"))
  (star-lang.compiler.core:invalid-star-service-uri-error ()
    ;; expected deterministic rejection
    ))

;; Malformed actor declarations fail deterministically.
(handler-case
    (progn
      (starlangcompiler:compile-actor-source
       "(actor enrichment-worker
          (:runtime native
           :accepts (org.starintel/person@1)
           :produces (org.starintel/person@1)
           :handler enrichment-worker-handler
           :restart eventually
           :mailbox (bounded 128)))")
      (proof-fail "proof failed: malformed restart policy was accepted"))
  (star-lang.compiler.core:invalid-actor-error ()
    ;; expected deterministic rejection
    ))

;; The prototype packages still must not exist after compiling.
(proof-assert (null (find-package "STAR-LANG.PROTOTYPE"))
              "starlang-prototype package must still not exist")

(format t "ACTOR-COMPILER-PROOF-OK~%")
(force-output)
(sb-ext:exit :code 0)
