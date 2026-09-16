(defpackage :starlang-loader-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-loader-tests)

(def-suite starlang-loader-tests
  :description "Final digest-locked loader behavior and prototype independence.")

(in-suite starlang-loader-tests)

(defun temporary-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "star-lang-loader-~36R-~36R/"
                   (get-universal-time)
                   (random most-positive-fixnum))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames ".keep" directory))
    directory))

(defun write-text-file (pathname text)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string text stream))
  pathname)

(defmacro with-test-directory ((directory) &body body)
  `(let ((,directory (temporary-test-directory)))
     (unwind-protect
          (progn ,@body)
       (uiop:delete-directory-tree ,directory
                                   :validate t
                                   :if-does-not-exist :ignore))))

(test local-import-graph-is-digest-locked
  (with-test-directory (directory)
    (let* ((child (merge-pathnames "child.star" directory))
           (root (merge-pathnames "root.star" directory))
           (cache (merge-pathnames "cache/" directory)))
      (write-text-file
       child
       "(spec-library \"test/child@1\"
          (:version \"1.0.0\")
          (message ping (:fields ())))")
      (let ((digest (star-lang.loader::ironclad-sha256-file child)))
        (write-text-file
         root
         (format nil
                 "(spec-library \"test/root@1\"
                    (:version \"1.0.0\")
                    (import \"test/child@1\"
                      :version \"1.0.0\"
                      :digest ~S
                      :path \"child.star\")
                    (message rootMessage (:fields ())))"
                 digest))
        (let* ((graph (star-lang.loader:load-star-file
                       root :cache-directory cache))
               (root-node (star-lang.loader:loaded-graph-root graph))
               (libraries (star-lang.loader:loaded-graph-libraries graph)))
          (is (string= "test/root@1"
                       (star-lang.loader:library-node-name root-node)))
          (is (= 2 (length libraries)))
          (is (= 1 (length (star-lang.loader:library-node-imports root-node))))
          (dolist (node libraries)
            (is (eq :spec-library
                    (getf (star-lang.loader:library-node-compiled node) :kind)))))))))

(test local-import-digest-mismatch-fails-closed
  (with-test-directory (directory)
    (let ((child (merge-pathnames "child.star" directory))
          (root (merge-pathnames "root.star" directory)))
      (write-text-file
       child
       "(spec-library \"test/child@1\" (:version \"1.0.0\")
          (message ping (:fields ())))")
      (write-text-file
       root
       "(spec-library \"test/root@1\" (:version \"1.0.0\")
          (import \"test/child@1\"
            :version \"1.0.0\"
            :digest \"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
            :path \"child.star\"))")
      (signals star-lang.loader:digest-error
        (star-lang.loader:load-star-file root)))))

(test network-loading-is-explicitly-disabled-by-default
  (with-test-directory (directory)
    (signals star-lang.loader:network-disabled-error
      (star-lang.loader:load-star-url
       "https://example.invalid/library.star"
       :name "test/root@1"
       :version "1.0.0"
       :digest "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
       :cache-directory directory))))

(test final-loader-does-not-load-prototype
  (dolist (package-name '("STAR-LANG.PROTOTYPE"
                          "STAR-LANG.CORE-SURFACE.PROTOTYPE"
                          "STAR-LANG.COMPILER-IR.PROTOTYPE"
                          "STAR-LANG.SPEC-DOMAIN.PROTOTYPE"))
    (is (null (find-package package-name)))))

(defun run-tests ()
  (unless (run! 'starlang-loader-tests)
    (error "StarLang loader tests failed.")))
