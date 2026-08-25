(in-package :starlogicadapterswi-tests)

(test package-expectation-rejects-partial-or-foreign-identity
  ;; This is a pure check over a synthetic backend record; it never launches SWI.
  (let ((backend (starlogicadapterswi::%make-swi-backend
                  :bootstrap-digest "sha256:trusted")))
    (signals starlogicadapterswi:swi-bootstrap-package-mismatch-error
      (starlogicadapterswi::%validate-package-expectation
       backend "star.logic.bootstrap/1" nil))
    (signals starlogicadapterswi:swi-bootstrap-package-mismatch-error
      (starlogicadapterswi::%validate-package-expectation
       backend "foreign.package" "sha256:trusted"))))

(test startup-line-bound-allows-exact-limit
  (let ((process
          (starprocessport::%make-managed-process
           :stdout (make-string-input-stream (format nil "4242~%")))))
    (is (string= "4242"
                 (starlogicadapterswi::%read-startup-line
                  process :max-chars 4)))))

(test startup-line-bound-rejects-oversize-before-newline
  (let ((process
          (starprocessport::%make-managed-process
           :stdout (make-string-input-stream (format nil "12345~%")))))
    (signals starlogicadapterswi:swi-malformed-startup-data-error
      (starlogicadapterswi::%read-startup-line process :max-chars 4))))
