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
                   "(progn (format t \"STARLANG-JOURNAL-REPLAY-BEGIN~%\") (finish-output) (handler-case (progn (starjournal:runtime-journal-replay (starjournal:make-file-runtime-journal-port #p~S)) (uiop:quit 2)) (starjournal:star-journal-error () (uiop:quit 0))))"
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

(defun check-bounded-typed-rejection (label contents)
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
             (check (search "STARLANG-JOURNAL-CHILD-LOADED" output)
                    "Journal watchdog child failed before loading star-journal.~%stdout: ~A~%stderr: ~A"
                    output error-output)
             (check (search "STARLANG-JOURNAL-REPLAY-BEGIN" output)
                    "Journal watchdog child failed before replay began.~%stdout: ~A~%stderr: ~A"
                    output error-output)
             (check (= 0 exit-code)
                    "Journal input ~A did not terminate with typed rejection; child exit was ~D (124 means watchdog timeout).~%stdout: ~A~%stderr: ~A"
                    label exit-code output error-output)))
      (when (probe-file path)
        (delete-file path)))))

(defun test-file-journal-cycle-is-rejected-within-watchdog ()
  (check-bounded-typed-rejection
   "cycle"
   "#1=(:kind :pending . #1#)"))

(defun test-file-journal-compact-vector-allocation-is-bounded ()
  ;; A tiny file can ask the host reader to allocate an enormous vector before
  ;; star-journal's post-read portable snapshot gets a chance to reject it.
  ;; The constrained child makes that pre-validation allocation bug observable
  ;; without risking the long-lived test process.
  (check-bounded-typed-rejection
   "compact-vector"
   "#100000000(0)"))

(defun run-tests ()
  (test-file-journal-cycle-is-rejected-within-watchdog)
  (test-file-journal-compact-vector-allocation-is-bounded)
  (format t "~&star-journal file replay watchdog tests passed~%")
  t)
