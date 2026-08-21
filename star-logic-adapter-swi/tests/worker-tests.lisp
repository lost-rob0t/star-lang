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
