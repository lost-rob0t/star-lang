(require :asdf)
(asdf:load-system :ironclad)

(load (merge-pathnames "star-loader.lisp" *load-truename*))
(load (merge-pathnames "resolver-effect-ports-prototype.lisp" *load-truename*))
(load (merge-pathnames "resolver-shell-effects-prototype.lisp" *load-truename*))
(load (merge-pathnames "resolver-ironclad-digest-prototype.lisp" *load-truename*))

(in-package #:star-lang.loader)

(defparameter *abc-sha256*
  "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

(defun ironclad-digest-test-assert (condition label)
  (unless condition
    (error "Ironclad digest assertion failed: ~A" label)))

(defun ironclad-digest-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "star-ironclad-digest-~36R-~36R/"
                   (get-universal-time)
                   (random most-positive-fixnum))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames #P".keep" directory))
    directory))

(defun write-abc-octets (pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :element-type '(unsigned-byte 8))
    (write-sequence #(97 98 99) stream))
  pathname)

(defun test-known-sha256-vector ()
  (let* ((directory (ironclad-digest-test-directory))
         (pathname (merge-pathnames #P"abc.bin" directory)))
    (unwind-protect
         (progn
           (write-abc-octets pathname)
           (ironclad-digest-test-assert
            (string=
             *abc-sha256*
             (star-lang.loader.ironclad-effects:ironclad-sha256-file pathname))
            "Ironclad adapter matches the SHA-256 abc test vector"))
      (uiop:delete-directory-tree directory
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun test-default-resolver-does-not-require-sha256sum ()
  (let* ((directory (ironclad-digest-test-directory))
         (pathname (merge-pathnames #P"abc.bin" directory))
         (star-lang.loader.shell-effects:*sha256-program*
           "star-lang-sha256sum-must-not-run"))
    (unwind-protect
         (progn
           (write-abc-octets pathname)
           (ironclad-digest-test-assert
            (string= *abc-sha256* (sha256-file pathname))
            "default resolver digest remains native when sha256sum is unavailable"))
      (uiop:delete-directory-tree directory
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun test-default-effects-retain-fetch-port ()
  (ironclad-digest-test-assert
   (functionp
    (star-lang.loader.effects:resolver-effects-fetch-to-file
     *resolver-effects*))
   "native digest default keeps an explicit fetch effect"))

(defun run-resolver-ironclad-digest-tests ()
  (test-known-sha256-vector)
  (test-default-resolver-does-not-require-sha256sum)
  (test-default-effects-retain-fetch-port)
  (format t "Native Ironclad resolver digest tests passed.~%")
  t)

(unless (run-resolver-ironclad-digest-tests)
  (error "Native Ironclad resolver digest tests failed."))
