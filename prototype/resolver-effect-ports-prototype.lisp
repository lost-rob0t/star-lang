;;;; Resolver effect protocol for explicit specification-build side effects.
;;;;
;;;; The loader owns import/cache/digest policy.  Concrete adapters only perform
;;;; the requested effects.  Keeping the protocol function-valued makes fake
;;;; ports trivial and keeps Phase 1 dependency-free.

(defpackage #:star-lang.loader.effects
  (:use #:cl)
  (:export
   #:resolver-effects
   #:resolver-effects-p
   #:make-resolver-effects
   #:resolver-effects-digest-file
   #:resolver-effects-fetch-to-file
   #:digest-file-through-effects
   #:fetch-to-file-through-effects))

(in-package #:star-lang.loader.effects)

(defstruct (resolver-effects
             (:constructor make-resolver-effects
                 (&key digest-file fetch-to-file)))
  (digest-file nil :type (or null function))
  (fetch-to-file nil :type (or null function)))

(defun require-effect-function (effects accessor label)
  (unless (resolver-effects-p effects)
    (error "Expected RESOLVER-EFFECTS, received ~S." effects))
  (let ((function (funcall accessor effects)))
    (unless (functionp function)
      (error "Resolver effects do not provide ~A." label))
    function))

(defun digest-file-through-effects (effects pathname)
  (funcall
   (require-effect-function effects
                            #'resolver-effects-digest-file
                            "a digest-file effect")
   pathname))

(defun fetch-to-file-through-effects
    (effects url destination
     &key
       maximum-bytes
       (maximum-redirects 5)
       (connect-timeout 10)
       (read-timeout 10)
       (deadline 60)
       proxy)
  (funcall
   (require-effect-function effects
                            #'resolver-effects-fetch-to-file
                            "a fetch-to-file effect")
   url
   destination
   :maximum-bytes maximum-bytes
   :maximum-redirects maximum-redirects
   :connect-timeout connect-timeout
   :read-timeout read-timeout
   :deadline deadline
   :proxy proxy))

(in-package #:cl-user)
