(in-package :starhttpdexador-tests)

(defun run-ownership-red-tests ()
  (let ((*ownership-failures* nil))
    (declare (special *ownership-failures*))
    (test-client-policy-is-explicit '*ownership-failures*)
    (test-explicit-pools-are-client-local '*ownership-failures*)
    (test-explicit-pool-reuses-live-connection '*ownership-failures*)
    (test-legacy-body-representation-is-explicit '*ownership-failures*)
    (when *ownership-failures*
      (error "star-http-dexador ownership RED failed as expected:~%~{ - ~A~%~}"
             (nreverse *ownership-failures*))))
  t)
