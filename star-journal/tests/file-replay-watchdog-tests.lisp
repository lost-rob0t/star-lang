(defpackage :starjournal-file-replay-watchdog-tests
  (:use :cl)
  (:import-from :starjournal
                #:star-journal-error)
  (:export #:run-tests))

(in-package :starjournal-file-replay-watchdog-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun temporary-journal-pathname (label)
  (pathname
   (format nil "/tmp/star-journal-~A-~D-~D.sexp"
           label
           (get-universal-time)
           (random 1000000000))))

(defun repository-root ()
  (merge-pathnames "../" (asdf:system-source-directory :star-journal)))

(defun replay-in-watchdog-child (path)
  (let* ((root (namestring (repository-root)))
         (path-string (namestring path))
         (source-registry
           (format nil
                   "(asdf:initialize-source-registry '(:source-registry (:tree ~S) :inherit-configuration))"
                   root))
         (replay
           (format nil
                   "(progn (format t \"STARLANG-JOURNAL-REPLAY-BEGIN~%\") (finish-output) (handler-case (progn (starjournal:runtime-journal-replay (starjournal:make-file-runtime-journal-port #p~S)) (uiop:quit 2)) (starjournal:star-journal-error (condition) (format t \"STARLANG-JOURNAL-REJECTED: ~A~%\" condition) (finish-output) (uiop:quit 0))))"
                   path-string)))
    (uiop:run-program
     (list "timeout"
           "--signal=TERM"
           "--kill-after=1s"
           "3s"
           "sbcl"
           "--dynamic-space-size" "256"
           "--noinform"
           "--disable-debugger"
           "--non-interactive"
           "--eval" "(require :asdf)"
           "--eval" source-registry
           "--eval" "(asdf:load-system :star-journal)"
           "--eval"
           "(progn (format t \"STARLANG-JOURNAL-CHILD-LOADED~%\") (finish-output))"
           "--eval" replay)
     :output :string
     :error-output :string
     :ignore-error-status t)))

(defun append-watchdog-diagnostic (label output error-output exit-code)
  ;; CI always uploads star-lang-*.log. Retain the child transcript so a failed
  ;; boundedness oracle is diagnosable without weakening or bypassing the test.
  (with-open-file (stream #p"star-lang-journal-watchdog.log"
                          :direction :output
                          :if-exists :append
                          :if-does-not-exist :create)
    (format stream "~&=== ~A ===~%exit-code: ~D~%stdout:~%~A~%stderr:~%~A~%"
            label exit-code output error-output)
    (finish-output stream)))

(defun check-bounded-typed-rejection (label contents expected-message)
  (let ((path (temporary-journal-pathname label)))
    (unwind-protect
         (progn
           (with-open-file (stream path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string contents stream)
             (terpri stream))
           (multiple-value-bind (output error-output exit-code)
               (replay-in-watchdog-child path)
             (append-watchdog-diagnostic label output error-output exit-code)
             (check (search "STARLANG-JOURNAL-CHILD-LOADED" output)
                    "Journal watchdog child failed before loading star-journal.~%stdout: ~A~%stderr: ~A"
                    output error-output)
             (check (search "STARLANG-JOURNAL-REPLAY-BEGIN" output)
                    "Journal watchdog child failed before replay began.~%stdout: ~A~%stderr: ~A"
                    output error-output)
             (check (= 0 exit-code)
                    "Journal input ~A did not terminate with typed rejection; child exit was ~D (124 means watchdog timeout).~%stdout: ~A~%stderr: ~A"
                    label exit-code output error-output)
             (check (search "STARLANG-JOURNAL-REJECTED:" output)
                    "Journal input ~A did not render the typed rejection before exit.~%stdout: ~A~%stderr: ~A"
                    label output error-output)
             (check (search expected-message output :test #'char-equal)
                    "Journal input ~A was rejected for the wrong reason; expected ~S.~%stdout: ~A~%stderr: ~A"
                    label expected-message output error-output)))
      (when (probe-file path)
        (delete-file path)))))

(defun test-file-journal-cycle-is-rejected-within-watchdog ()
  (check-bounded-typed-rejection
   "cycle"
   "#1=(:kind :pending . #1#)"
   "numeric # dispatch prefixes are not admitted"))

(defun test-file-journal-nested-cycle-is-rejected-within-watchdog ()
  (check-bounded-typed-rejection
   "nested-cycle"
   "(:outer (#1=(:value . #1#)))"
   "numeric # dispatch prefixes are not admitted"))

(defun test-file-journal-compact-vector-allocation-is-bounded ()
  ;; A tiny file can ask the host reader to allocate an enormous vector before
  ;; star-journal's post-read portable snapshot gets a chance to reject it.
  ;; The constrained child makes that pre-validation allocation bug observable
  ;; without risking the long-lived test process.
  (check-bounded-typed-rejection
   "compact-vector"
   "#100000000(0)"
   "numeric # dispatch prefixes are not admitted"))

(defun test-file-journal-reader-depth-is-bounded ()
  (check-bounded-typed-rejection
   "deep"
   (with-output-to-string (stream)
     (dotimes (index 65)
       (declare (ignore index))
       (write-char #\( stream))
     (write-string "NIL" stream)
     (dotimes (index 65)
       (declare (ignore index))
       (write-char #\) stream)))
   "reader depth exceeds 64"))

(defun test-file-journal-reader-eval-remains-disabled ()
  (let ((sentinel (temporary-journal-pathname "reader-eval-side-effect")))
    (unwind-protect
         (progn
           (when (probe-file sentinel)
             (delete-file sentinel))
           (check-bounded-typed-rejection
            "reader-eval"
            (format nil
                    "#.(progn (with-open-file (stream #p~S :direction :output :if-exists :supersede :if-does-not-exist :create) (write-string \"reader-eval-ran\" stream)) nil)"
                    (namestring sentinel))
            "reader dispatch #. is not admitted")
           (check (not (probe-file sentinel))
                  "File journal reader evaluation performed an external side effect."))
      (when (probe-file sentinel)
        (delete-file sentinel)))))

(defun test-file-journal-unsupported-reader-construct-is-rejected ()
  (check-bounded-typed-rejection
   "unsupported-dispatch"
   "#S(FAKE-JOURNAL-STRUCT :VALUE 1)"
   "reader dispatch #S is not admitted"))

(defun test-file-journal-truncated-record-is-rejected ()
  (check-bounded-typed-rejection
   "truncated"
   "(:kind :pending"
   "unterminated list or vector"))

(defun test-file-journal-malformed-middle-record-is-rejected ()
  (check-bounded-typed-rejection
   "malformed-middle"
   (format nil "NIL~%(:broken~%NIL")
   "unterminated list or vector"))

(defun run-tests ()
  (test-file-journal-cycle-is-rejected-within-watchdog)
  (test-file-journal-nested-cycle-is-rejected-within-watchdog)
  (test-file-journal-compact-vector-allocation-is-bounded)
  (test-file-journal-reader-depth-is-bounded)
  (test-file-journal-reader-eval-remains-disabled)
  (test-file-journal-unsupported-reader-construct-is-rejected)
  (test-file-journal-truncated-record-is-rejected)
  (test-file-journal-malformed-middle-record-is-rejected)
  (format t "~&star-journal file replay watchdog tests passed~%")
  t)
