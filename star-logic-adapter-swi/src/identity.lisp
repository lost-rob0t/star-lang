(in-package :starlogicadapterswi)

(defparameter +swi-adapter-version+ "0.1.0")
(defparameter +supported-mqi-major+ 1)
(defparameter +supported-mqi-minor+ 0)
(defparameter +bootstrap-id+ "star.logic.bootstrap/1")
(defparameter +bootstrap-backend-id+ "swi-prolog")

(defun %sha256-file (pathname)
  (let* ((digester (ironclad:make-digest :sha256))
         (digest (ironclad:digest-file digester pathname)))
    (format nil "sha256:~A"
            (string-downcase
             (ironclad:byte-array-to-hex-string digest)))))

(defun %absolute-existing-file (path condition-type field)
  (unless (and (or (stringp path) (pathnamep path))
               (plusp (length (namestring (pathname path)))))
    (%swi-fail condition-type "~A must be a non-empty pathname designator." field))
  (let ((pathname (probe-file path)))
    (unless pathname
      (%swi-fail condition-type "~A does not exist: ~A" field path))
    (let ((resolved (truename pathname)))
      (unless (uiop:absolute-pathname-p resolved)
        (%swi-fail condition-type "~A must resolve to an absolute path: ~A"
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
                 (%swi-fail 'swi-worker-launch-error
                            "Timed out identifying exact SWI executable ~A."
                            executable))
               (values stdout stderr exit))))
      (when (and process (not (process-reaped-p process)))
        (ignore-errors (dispose-process process))))))

(defun %trim-whitespace (string)
  (string-trim '(#\Space #\Tab #\Newline #\Return) string))

(defun %parse-version-triplet (version-string)
  (let ((numbers '())
        (index 0)
        (length (length version-string)))
    (loop while (< index length)
          until (= (length numbers) 3)
          do (if (digit-char-p (char version-string index))
                 (let ((start index))
                   (loop while (and (< index length)
                                    (digit-char-p (char version-string index)))
                         do (incf index))
                   (push (parse-integer version-string :start start :end index)
                         numbers))
                 (incf index)))
    (setf numbers (nreverse numbers))
    (unless (= (length numbers) 3)
      (%swi-fail 'swi-backend-identity-mismatch-error
                 "Could not parse SWI version triplet from ~S." version-string))
    numbers))

(defun %identify-executable (executable-path)
  (let* ((resolved (%absolute-existing-file
                    executable-path 'swi-executable-unavailable-error
                    "SWI executable"))
         (resolved-string (namestring resolved)))
    (multiple-value-bind (stdout stderr exit-code)
        (%run-exact-capture resolved-string '("--version"))
      (unless (and (integerp exit-code) (zerop exit-code))
        (%swi-fail-diagnostic
         'swi-executable-unavailable-error
         (%bounded-diagnostic stderr)
         "Exact SWI executable failed --version: ~A (exit ~S)."
         resolved-string exit-code))
      (let ((version (%trim-whitespace stdout)))
        (unless (plusp (length version))
          (%swi-fail 'swi-backend-identity-mismatch-error
                     "Exact SWI executable returned an empty version string."))
        (values resolved-string
                version
                (%parse-version-triplet version)
                (%sha256-file resolved))))))
