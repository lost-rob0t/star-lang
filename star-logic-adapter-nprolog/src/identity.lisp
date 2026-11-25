(in-package :starlogicadapternprolog)

(defparameter +nprolog-adapter-version+ "0.1.0")

;; Disambiguation: another, unrelated "N-Prolog" exists. This adapter targets
;; sasagawa888/nprolog only, and records the upstream in descriptor metadata.
(defparameter +nprolog-engine-upstream+ "sasagawa888/nprolog")

;; Observed from npl main.c: `printf("N-Prolog Ver %1.2f\n", VERSION)` for -v,
;; and `printf("N-Prolog Ver %1.2f [%dM cells]\n", VERSION, ...)` at REPL start.
(defparameter +nprolog-version-banner-prefix+ "N-Prolog Ver ")

(defun %sha256-file (pathname)
  (let* ((digester (ironclad:make-digest :sha256))
         (digest (ironclad:digest-file digester pathname)))
    (format nil "sha256:~A"
            (string-downcase
             (ironclad:byte-array-to-hex-string digest)))))

(defun %absolute-existing-file (path condition-type field)
  (unless (and (or (stringp path) (pathnamep path))
               (plusp (length (namestring (pathname path)))))
    (%nprolog-fail condition-type "~A must be a non-empty pathname designator." field))
  (let ((pathname (probe-file path)))
    (unless pathname
      (%nprolog-fail condition-type "~A does not exist: ~A" field path))
    (let ((resolved (truename pathname)))
      (unless (uiop:absolute-pathname-p resolved)
        (%nprolog-fail condition-type "~A must resolve to an absolute path: ~A"
                       field resolved))
      resolved)))

(defun %collect-process-output (process)
  (let ((stdout (with-output-to-string (out)
                  (loop for line = (read-line (process-stdout process) nil nil)
                        while line
                        do (write-line line out))))
        (stderr (with-output-to-string (out)
                  (loop for line = (read-line (process-stderr process) nil nil)
                        while line
                        do (write-line line out)))))
    (values stdout stderr)))

(defun %run-exact-capture (executable argv)
  (let ((process nil))
    (unwind-protect
         (progn
           (setf process (launch-process executable argv))
           (multiple-value-bind (stdout stderr)
               (%collect-process-output process)
             (multiple-value-bind (exit status)
                 (wait-process process :timeout 10.0d0)
               (when (eq status :timeout)
                 (%nprolog-fail 'nprolog-worker-launch-error
                                "Timed out identifying exact N-Prolog executable ~A."
                                executable))
               (values stdout stderr exit))))
      (when (and process (not (process-reaped-p process)))
        (ignore-errors (dispose-process process))))))

(defun %trim-whitespace (string)
  (string-trim '(#\Space #\Tab #\Newline #\Return) string))

;; N-Prolog versions are one float printed with two decimals (VERSION 5.20 ->
;; "5.20"), so identity carries a major.minor pair rather than SWI's triplet.
;; Parsing is exact and fail-closed: only the observed "N-Prolog Ver X.Y" form
;; is accepted for -v output.
(defun %parse-version-banner (banner)
  (let* ((text (%trim-whitespace banner))
         (prefix-length (length +nprolog-version-banner-prefix+)))
    (unless (and (> (length text) prefix-length)
                 (string= text +nprolog-version-banner-prefix+
                          :end2 prefix-length))
      (%nprolog-fail 'nprolog-backend-identity-mismatch-error
                     "Could not parse an N-Prolog version banner from ~S." banner))
    (let* ((rest (subseq text prefix-length))
           (dot (position #\. rest)))
      (unless (and dot (> dot 0) (< (1+ dot) (length rest))
                   (every #'digit-char-p (subseq rest 0 dot))
                   (every #'digit-char-p (subseq rest (1+ dot))))
        (%nprolog-fail 'nprolog-backend-identity-mismatch-error
                       "Could not parse an N-Prolog major.minor pair from ~S."
                       banner))
      (values (parse-integer rest :end dot)
              (parse-integer rest :start (1+ dot))))))

;; The REPL startup banner carries a "[NNM cells]" suffix after the same
;; "N-Prolog Ver X.Y" body; nothing else may follow the whitespace.
(defun %parse-startup-banner (banner)
  (let* ((text (%trim-whitespace banner))
         (prefix-length (length +nprolog-version-banner-prefix+)))
    (unless (and (> (length text) prefix-length)
                 (string= text +nprolog-version-banner-prefix+
                          :end2 prefix-length))
      (%nprolog-fail 'nprolog-backend-identity-mismatch-error
                     "Could not parse an N-Prolog startup banner from ~S." banner))
    (let* ((rest (subseq text prefix-length))
           (dot (position #\. rest))
           (suffix (and dot (subseq rest (1+ dot))))
           (minor-end (and suffix
                           (position-if (complement #'digit-char-p) suffix))))
      (unless (and dot (> dot 0)
                   suffix
                   (plusp (length suffix))
                   (every #'digit-char-p (subseq rest 0 dot))
                   (every #'digit-char-p
                          (subseq suffix 0 (or minor-end (length suffix))))
                   (or (null minor-end)
                       (char= (char suffix minor-end) #\Space)))
        (%nprolog-fail 'nprolog-backend-identity-mismatch-error
                       "Could not parse an N-Prolog startup banner from ~S." banner))
      (values (parse-integer rest :end dot)
              (parse-integer suffix :end (or minor-end (length suffix)))))))

(defun %version-string (major minor)
  (format nil "~D.~2,'0D" major minor))

(defun %identify-executable (executable-path)
  (let* ((resolved (%absolute-existing-file
                    executable-path 'nprolog-executable-unavailable-error
                    "N-Prolog executable"))
         (resolved-string (namestring resolved)))
    (multiple-value-bind (stdout stderr exit-code)
        (%run-exact-capture resolved-string '("-v"))
      (unless (and (integerp exit-code) (zerop exit-code))
        (%nprolog-fail-diagnostic
         'nprolog-executable-unavailable-error
         (%bounded-diagnostic stderr)
         "Exact N-Prolog executable failed -v: ~A (exit ~S)."
         resolved-string exit-code))
      (let ((banner (%trim-whitespace stdout)))
        (multiple-value-bind (major minor) (%parse-version-banner banner)
          (values resolved-string
                  banner
                  major
                  minor
                  (%version-string major minor)
                  (%sha256-file resolved)))))))
