;;;; generate-manifest.lisp -- regenerate document-lifecycle.manifest.json
;;;; from the committed document-lifecycle.star fixture (issue star-lang#142;
;;;; fixture feed for the starintel-server#240 lifecycle executor slice).
;;;;
;;;; The single authoritative plist-to-canonical-JSON mapping lives in
;;;; :starlang-lifecycle-tests:manifest-fixture-json; this driver only loads
;;;; it and writes the bytes. Run from the repository root:
;;;;
;;;;   ci/with-nix-sbcl.sh --script fixtures/lifecycle/generate-manifest.lisp
;;;;
;;;; The byte-determinism test in starlang-compiler-tests re-derives the
;;;; committed JSON on every gate run, so stale fixture bytes fail CI.

(require :asdf)
(asdf:load-system :starlang-compiler-tests)

(let* ((here (or *load-truename* *default-pathname-defaults*))
       (output (merge-pathnames "document-lifecycle.manifest.json" here))
       (json (starlang-lifecycle-tests:manifest-fixture-json
              (starlang-lifecycle-tests:compiled-fixture-manifest))))
  (with-open-file (stream output
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string json stream)
    (terpri stream))
  (format t "wrote ~A~%" (namestring output)))
(sb-ext:quit)
