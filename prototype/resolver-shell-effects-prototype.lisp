;;;; Transitional shell adapters plus loader integration for resolver effects.
;;;;
;;;; Phase 1 intentionally preserves curl/sha256sum behavior behind an explicit
;;;; port.  Phase 2 replaces these adapters with native Common Lisp adapters.

(require :asdf)

(unless (find-package "STAR-LANG.LOADER.EFFECTS")
  (load (merge-pathnames "resolver-effect-ports-prototype.lisp" *load-truename*)))

(defpackage #:star-lang.loader.shell-effects
  (:use #:cl)
  (:import-from #:star-lang.loader.effects
                #:make-resolver-effects)
  (:export
   #:*curl-program*
   #:*sha256-program*
   #:make-shell-resolver-effects))

(in-package #:star-lang.loader.shell-effects)

(defparameter *curl-program* "curl")
(defparameter *sha256-program* "sha256sum")

(defun shell-command-output (program arguments)
  (string-trim
   '(#\Space #\Tab #\Newline #\Return)
   (uiop:run-program
    (cons program arguments)
    :output :string
    :error-output :string
    :ignore-error-status nil)))

(defun shell-sha256-file (pathname)
  (let* ((output
           (shell-command-output
            *sha256-program*
            (list (namestring pathname))))
         (separator
           (position-if
            (lambda (character)
              (find character '(#\Space #\Tab)))
            output))
         (hex (if separator (subseq output 0 separator) output)))
    (unless (and (= (length hex) 64)
                 (every (lambda (character)
                          (or (digit-char-p character)
                              (find character "abcdefABCDEF")))
                        hex))
      (error "Could not parse sha256sum output ~S." output))
    (format nil "sha256:~A" (string-downcase hex))))

(defun shell-fetch-to-file
    (url destination
     &key
       maximum-bytes
       (maximum-redirects 5)
       (connect-timeout 10)
       read-timeout
       (deadline 60)
       proxy)
  ;; The Phase-1 adapter deliberately preserves the existing curl behavior.
  ;; MAXIMUM-BYTES is still enforced by loader policy immediately after fetch;
  ;; streaming enforcement moves into the native Phase-2 adapter.
  (declare (ignore maximum-bytes read-timeout))
  (let ((arguments
          (append
           (list "--fail"
                 "--silent"
                 "--show-error"
                 "--location"
                 "--max-redirs" (princ-to-string maximum-redirects)
                 "--connect-timeout" (princ-to-string connect-timeout)
                 "--max-time" (princ-to-string deadline)
                 "--proto" "=https"
                 "--proto-redir" "=https")
           (when proxy
             (list "--proxy" proxy))
           (list "--output" (namestring destination) url))))
    (uiop:run-program
     (cons *curl-program* arguments)
     :output :string
     :error-output :string
     :ignore-error-status nil)
    (list :requested-uri url
          :final-uri url
          :bytes (and (probe-file destination)
                      (with-open-file
                          (stream destination
                                  :direction :input
                                  :element-type '(unsigned-byte 8))
                        (file-length stream))))))

(defun make-shell-resolver-effects ()
  (make-resolver-effects
   :digest-file #'shell-sha256-file
   :fetch-to-file #'shell-fetch-to-file))

(in-package #:star-lang.loader)

(defvar *resolver-effects*
  (star-lang.loader.shell-effects:make-shell-resolver-effects))

(defvar *resolver-effects-legacy-load-star-file* nil)
(defvar *resolver-effects-legacy-load-star-url* nil)

(unless *resolver-effects-legacy-load-star-file*
  (setf *resolver-effects-legacy-load-star-file*
        (symbol-function 'load-star-file)))

(unless *resolver-effects-legacy-load-star-url*
  (setf *resolver-effects-legacy-load-star-url*
        (symbol-function 'load-star-url)))

(defun without-keyword-argument (arguments keyword)
  (loop for (key value) on arguments by #'cddr
        unless (eq key keyword)
          append (list key value)))

(defun sha256-file (pathname &optional (effects *resolver-effects*))
  (handler-case
      (normalize-digest
       (star-lang.loader.effects:digest-file-through-effects effects pathname))
    (loader-error (condition)
      (error condition))
    (error (condition)
      (fail-loader 'dependency-error
                   "SHA-256 calculation failed through the resolver digest port: ~A"
                   condition))))

(defun fetch-url-to-cache
    (url digest cache-directory maximum-source-bytes
     &optional (effects *resolver-effects*))
  (let* ((cache-path (digest-cache-path cache-directory digest))
         (temporary-path (temporary-cache-path cache-directory digest)))
    (when (probe-file cache-path)
      (handler-case
          (progn
            (ensure-source-size cache-path maximum-source-bytes)
            (verify-file-digest cache-path digest)
            (return-from fetch-url-to-cache cache-path))
        (loader-error ()
          (ignore-errors (delete-file cache-path)))))
    (unwind-protect
         (progn
           (handler-case
               (star-lang.loader.effects:fetch-to-file-through-effects
                effects
                url
                temporary-path
                :maximum-bytes maximum-source-bytes
                :maximum-redirects 5
                :connect-timeout 10
                :read-timeout 10
                :deadline 60
                :proxy nil)
             (loader-error (condition)
               (error condition))
             (error (condition)
               (fail-loader 'dependency-error
                            "Remote specification fetch failed through the resolver fetch port: ~A"
                            condition)))
           (unless (probe-file temporary-path)
             (fail-loader 'dependency-error
                          "Resolver fetch port did not create ~A."
                          temporary-path))
           (ensure-source-size temporary-path maximum-source-bytes)
           (verify-file-digest temporary-path digest)
           (rename-file temporary-path cache-path)
           cache-path)
      (when (probe-file temporary-path)
        (ignore-errors (delete-file temporary-path))))))

(defun load-star-file
    (pathname &rest arguments &key resolver-effects &allow-other-keys)
  (let ((*resolver-effects* (or resolver-effects *resolver-effects*)))
    (apply *resolver-effects-legacy-load-star-file*
           pathname
           (without-keyword-argument arguments :resolver-effects))))

(defun load-star-url
    (url &rest arguments &key resolver-effects &allow-other-keys)
  (let ((*resolver-effects* (or resolver-effects *resolver-effects*)))
    (apply *resolver-effects-legacy-load-star-url*
           url
           (without-keyword-argument arguments :resolver-effects))))

(in-package #:cl-user)
