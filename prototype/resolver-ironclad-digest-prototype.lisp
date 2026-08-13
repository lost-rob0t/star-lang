;;;; Native Common Lisp SHA-256 adapter for resolver effects.
;;;;
;;;; HTTPS fetch remains on the Phase-1 compatibility adapter in this slice.
;;;; Digest calculation no longer requires sha256sum on the ASDF-authoritative
;;;; default path.

(defpackage #:star-lang.loader.ironclad-effects
  (:use #:cl)
  (:import-from #:star-lang.loader.effects
                #:make-resolver-effects
                #:resolver-effects-fetch-to-file)
  (:import-from #:star-lang.loader.shell-effects
                #:make-shell-resolver-effects)
  (:export
   #:ironclad-sha256-file
   #:make-native-digest-resolver-effects))

(in-package #:star-lang.loader.ironclad-effects)

(defun ironclad-sha256-file (pathname)
  (let* ((digester (ironclad:make-digest :sha256))
         (digest (ironclad:digest-file digester pathname)))
    (format nil "sha256:~A"
            (string-downcase
             (ironclad:byte-array-to-hex-string digest)))))

(defun make-native-digest-resolver-effects
    (&optional (fetch-effects (make-shell-resolver-effects)))
  (make-resolver-effects
   :digest-file #'ironclad-sha256-file
   :fetch-to-file
   (resolver-effects-fetch-to-file fetch-effects)))

(in-package #:star-lang.loader)

(setf *resolver-effects*
      (star-lang.loader.ironclad-effects:make-native-digest-resolver-effects))

(in-package #:cl-user)
