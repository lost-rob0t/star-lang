;;;; Fresh-process acceptance proof: every installed starlang command loads
;;;; final systems only. Run as `sbcl --non-interactive --load cli-proof.lisp`.

(require :asdf)

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

(asdf:load-system :starlang-cli)

(proof-assert (find-package "STAR-LANG.LOADER")
              "final loader package must be present")

(dolist (package-name '("STAR-LANG.PROTOTYPE"
                        "STAR-LANG.CORE-SURFACE.PROTOTYPE"
                        "STAR-LANG.COMPILER-IR.PROTOTYPE"
                        "STAR-LANG.SPEC-DOMAIN.PROTOTYPE"
                        "STAR-LANG.DOCUMENT-RUNTIME"
                        "STAR-LANG.CONSTRUCTOR-RUNTIME"
                        "STAR-LANG.API"))
  (proof-assert (null (find-package package-name))
                (format nil "legacy package ~A must not exist" package-name)))

(let ((code (star-lang.cli:run-cli '("version"))))
  (proof-assert (= code 0) "version command must exit 0"))

(let ((fixture
        (merge-pathnames
         "../../fixtures/actor-compiler/enrichment-worker.star"
         *load-truename*)))
  (proof-assert
   (= (star-lang.cli:run-cli (list "check" (namestring fixture))) 0)
   "check must compile the actor fixture and exit 0")
  (let ((manifest (star-lang.cli:compile-program-manifest fixture)))
    (proof-assert (eql 1 (getf manifest :wire-version))
                  "program manifest must carry wire version 1")
    (proof-assert (= 1 (length (getf manifest :actors)))
                  "program manifest must carry the compiled actor unit")))

;; Exercise final loader command dispatch against the repository fixture.
(let* ((fixture
         (merge-pathnames "../../fixtures/star-cl.star" *load-truename*))
       (cache
         (merge-pathnames
          (format nil "star-lang-cli-proof-~36R/" (get-universal-time))
          (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (ensure-directories-exist (merge-pathnames ".keep" cache))
         (proof-assert
          (= (star-lang.cli:run-cli
              (list "load" (namestring fixture)
                    "--cache" (namestring cache)))
             0)
          "load command must use final loader and exit 0"))
    (uiop:delete-directory-tree cache
                                :validate t
                                :if-does-not-exist :ignore)))

(dolist (package-name '("STAR-LANG.PROTOTYPE"
                        "STAR-LANG.CORE-SURFACE.PROTOTYPE"
                        "STAR-LANG.COMPILER-IR.PROTOTYPE"
                        "STAR-LANG.SPEC-DOMAIN.PROTOTYPE"
                        "STAR-LANG.DOCUMENT-RUNTIME"
                        "STAR-LANG.CONSTRUCTOR-RUNTIME"
                        "STAR-LANG.API"))
  (proof-assert (null (find-package package-name))
                (format nil "legacy package ~A must still not exist" package-name)))

(format t "CLI-PROOF-OK~%")
(force-output)
(sb-ext:exit :code 0)
