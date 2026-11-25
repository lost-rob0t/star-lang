(in-package :starlogicadapternprolog)

;; Batch transport slice: load validation for Prolog files.
;;
;; Upstream truth (verified live against npl 5.20): `-s FILE` consults FILE
;; and then exits EXIT_SUCCESS unconditionally — consult failures, syntax
;; errors, and missing files all exit 0. A clean consult prints nothing at
;; all (not even the startup banner, which the -s path exits before). The
;; fail-closed validation contract is therefore: valid iff exit status 0
;; AND stdout is empty after ANSI stripping. Any diagnostic output, any
;; nonzero exit, or any timeout is invalid.

(defparameter +nprolog-batch-timeout+ 30.0d0)
(defparameter +max-nprolog-batch-output-chars+ 65536)

(defun %batch-verdict (exit-code stdout)
  (let ((diagnostic (%trim-whitespace
                     (%strip-ansi-escapes (or stdout "")))))
    (if (and (integerp exit-code) (zerop exit-code)
             (zerop (length diagnostic)))
        (values t "")
        (values nil diagnostic))))

(defun nprolog-batch-report (valid exit-code diagnostic file-digest)
  (list :valid valid
        :exit-code exit-code
        :diagnostic (and diagnostic (plusp (length diagnostic))
                         (%bounded-diagnostic diagnostic))
        :file-digest file-digest))

(defun nprolog-batch-validate (backend file-path &key (timeout +nprolog-batch-timeout+))
  "Validate that the exact pinned N-Prolog executable loads FILE cleanly.

The file is consulted through the same ./-relative resolution as the bridge
launch: the child runs in FILE's parent directory with `-s ./<name>`, so
upstream never prepends a home directory. FILE must have a dotted name:
upstream consult appends .pl to dot-free names, which would silently target
a different file. Returns a report plist: :valid, :exit-code, :diagnostic
(bounded, ANSI-stripped), and :file-digest (sha256 of the exact validated
bytes). Validation failure is a report, not a condition; only invalid
arguments signal."
  (let* ((resolved (%absolute-existing-file
                    file-path 'nprolog-batch-error "Batch file"))
         (base (file-namestring resolved)))
    (unless (find #\. base)
      (%nprolog-fail 'nprolog-batch-error
                     "Batch file ~A must have a dotted name: upstream consult appends .pl to dot-free names."
                     base))
    (let* ((consult-name (concatenate 'string "./" base))
           (directory (uiop:pathname-directory-pathname resolved))
           (digest (%sha256-file resolved))
           (process nil)
           (output (make-string-output-stream))
           (captured 0))
      (unwind-protect
           (progn
             (setf process
                   (ignore-errors
                    (launch-process (nprolog-backend-executable backend)
                                    (list "-s" consult-name)
                                    :directory directory)))
             (unless process
               (%nprolog-fail 'nprolog-batch-error
                              "Could not launch exact N-Prolog executable ~A for batch validation."
                              (nprolog-backend-executable backend)))
             (let ((stdout-stream (process-stdout process)))
               (loop for line = (read-line stdout-stream nil nil)
                     while line
                     do (incf captured (length line))
                        (when (> captured +max-nprolog-batch-output-chars+)
                          (ignore-errors (kill-process process))
                          (return-from nprolog-batch-validate
                            (nprolog-batch-report nil nil
                                                  "batch consult output exceeded the capture bound"
                                                  digest)))
                        (write-line line output)))
             (let ((stdout (get-output-stream-string output)))
               (multiple-value-bind (exit status)
                   (wait-process process :timeout timeout)
                 (when (eq status :timeout)
                   (ignore-errors (kill-process process))
                   (return-from nprolog-batch-validate
                     (nprolog-batch-report nil nil
                                           (format nil "batch consult timed out after ~As" timeout)
                                           digest)))
                 (when (and (integerp exit) (plusp exit)
                            (zerop (length (%trim-whitespace stdout))))
                   ;; Upstream -s writes errors to stdout, but keep stderr in
                   ;; the diagnostic for nonzero exits with silent stdout.
                   (let ((stderr (with-output-to-string (sink)
                                   (loop for line = (read-line (process-stderr process) nil nil)
                                         while line
                                         do (write-line line sink)))))
                     (unless (zerop (length (%trim-whitespace stderr)))
                       (setf stdout stderr))))
                 (multiple-value-bind (valid diagnostic)
                     (%batch-verdict exit stdout)
                   (nprolog-batch-report valid exit diagnostic digest)))))
        (when (and process (not (process-reaped-p process)))
          (ignore-errors (dispose-process process)))))))
