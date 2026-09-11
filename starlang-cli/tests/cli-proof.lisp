;;;; Fresh-process acceptance proof: the installed starlang CLI path loads
;;;; only final systems. Run as `sbcl --non-interactive --load cli-proof.lisp`.
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

(asdf:load-system :starlang-cli)

;; The final CLI path must not load starlang-prototype or any prototype-owned
;; package: the loader, document runtime, constructor runtime, and public
;; product API remain prototype-owned (ci/prototype-migration.tsv).
(dolist (package-name '("STAR-LANG.PROTOTYPE"
                        "STAR-LANG.LOADER"
                        "STAR-LANG.DOCUMENT-RUNTIME"
                        "STAR-LANG.CONSTRUCTOR-RUNTIME"
                        "STAR-LANG.API"))
  (proof-assert (null (find-package package-name))
                (format nil "package ~A must not exist" package-name)))

;; The installed command surface reports versions and exit status 0.
(let ((code (star-lang.cli:run-cli '("version"))))
  (proof-assert (= code 0) "version command must exit 0"))

;; check and compile exercise the closed pipeline without the prototype.
(let ((fixture
        (merge-pathnames
         "../../fixtures/actor-compiler/enrichment-worker.star"
         *load-truename*)))
  (proof-assert
   (= (star-lang.cli:run-cli (list "check" (namestring fixture))) 0)
   "check must compile the actor fixture and exit 0")
  (let ((manifest
          (star-lang.cli:compile-program-manifest fixture)))
    (proof-assert (eql 1 (getf manifest :wire-version))
                  "program manifest must carry wire version 1")
    (proof-assert
     (= 1 (length (getf manifest :actors)))
     "program manifest must carry the compiled actor unit")))

;; The prototype packages still must not exist after CLI execution.
(dolist (package-name '("STAR-LANG.PROTOTYPE"
                        "STAR-LANG.LOADER"
                        "STAR-LANG.DOCUMENT-RUNTIME"
                        "STAR-LANG.CONSTRUCTOR-RUNTIME"
                        "STAR-LANG.API"))
  (proof-assert (null (find-package package-name))
                (format nil "package ~A must still not exist" package-name)))

(format t "CLI-PROOF-OK~%")
(force-output)
(sb-ext:exit :code 0)
