;;;; Final CLI tests: version, check, compile, and run commands over the
;;;; final systems only. Actor-semantic checks execute the real deterministic
;;;; wire dispatcher from starlang-runtime; no mocks replace actor semantics.

(defpackage :star-lang.cli-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :star-lang.cli-tests)

(def-suite star-lang.cli-tests
  :description "Final starlang-cli command surface and exit-code contract.")

(in-suite star-lang.cli-tests)

(defun actor-fixture ()
  (asdf:system-relative-pathname :starlang-cli
                                 "../fixtures/actor-compiler/enrichment-worker.star"))

(defun unknown-option-fixture ()
  (asdf:system-relative-pathname
   :starlang-cli "tests/fixtures/actor-unknown-option.star"))

(defun run-capturing (argv)
  "Run RUN-CLI capturing stdout and stderr; returns (values code stdout stderr)."
  (let* ((stdout (make-string-output-stream))
         (stderr (make-string-output-stream))
         (code (let ((*standard-output* stdout)
                     (*error-output* stderr))
                 (star-lang.cli:run-cli argv))))
    (values code
            (get-output-stream-string stdout)
            (get-output-stream-string stderr))))

(test no-arguments-exit-two-with-usage-on-stderr
  "Missing arguments print usage to stderr and exit 2."
  (multiple-value-bind (code stdout stderr)
      (run-capturing '())
    (is (= 2 code))
    (is (string= "" stdout))
    (is (search "Usage:" stderr))))

(test help-variants-exit-zero-with-usage-on-stdout
  "help, -h, and --help print usage to stdout and exit 0."
  (dolist (variant '("help" "-h" "--help"))
    (multiple-value-bind (code stdout stderr)
        (run-capturing (list variant))
      (is (= 0 code))
      (is (search "Usage:" stdout))
      (is (string= "" stderr)))))

(test usage-lists-all-commands-including-prototype-delegation
  "The usage surface lists every command and the prototype loader delegation."
  (multiple-value-bind (code stdout stderr)
      (run-capturing '("--help"))
    (declare (ignore stderr))
    (is (= 0 code))
    (is (search "version" stdout))
    (is (search "check" stdout))
    (is (search "compile" stdout))
    (is (search "run" stdout))
    (is (search "load FILE" stdout))
    (is (search "load-url" stdout))
    (is (search "prototype" stdout))))

(test unknown-command-exits-two
  "An unknown command is a usage error with exit 2."
  (multiple-value-bind (code stdout stderr)
      (run-capturing '("transmute" "x.star"))
    (is (= 2 code))
    (is (string= "" stdout))
    (is (search "Usage:" stderr))))

(test version-exits-zero-with-cli-and-compiler-versions
  "version reports the CLI version and the compiler system version."
  (multiple-value-bind (code stdout stderr)
      (run-capturing '("version"))
    (declare (ignore stderr))
    (is (= 0 code))
    (is (search "starlang-cli 0.1.0" stdout))
    (is (search "starlang-compiler" stdout))))

(test check-compiles-fixture-and-exits-zero
  "check runs the full closed pipeline on the actor fixture and exits 0."
  (multiple-value-bind (code stdout stderr)
      (run-capturing (list "check" (namestring (actor-fixture))))
    (declare (ignore stderr))
    (is (= 0 code))
    (is (search "ok: actor enrichment-worker" stdout))))

(test check-failure-exits-one-with-star-diagnostic
  "A .star unit with an unknown option fails with exit 1 and a diagnostic."
  (multiple-value-bind (code stdout stderr)
      (run-capturing
       (list "check" (namestring (unknown-option-fixture))))
    (is (= 1 code))
    (is (string= "" stdout))
    (is (search "starlang:" stderr))))

(test compile-emits-deterministic-canonical-manifest-to-stdout
  "Two compile invocations emit byte-identical canonical JSON wire data."
  (let ((argv (list "compile" (namestring (actor-fixture)))))
    (multiple-value-bind (code1 out1 err1) (run-capturing argv)
      (declare (ignore err1))
      (multiple-value-bind (code2 out2 err2) (run-capturing argv)
        (declare (ignore err2))
        (is (= 0 code1))
        (is (= 0 code2))
        (is (string= out1 out2))
        (is (search "\"wireVersion\":1" out1))
        (is (search "enrichment-worker" out1))
        (is (search "\"serviceUri\":\"star://starintel:localhost:enrichment-worker\""
                    out1))
        (is (char= #\newline (char out1 (1- (length out1)))))))))

(test compile-writes-manifest-file-with-trailing-newline
  "compile --manifest writes canonical JSON with a trailing newline."
  (uiop:with-temporary-file (:pathname manifest :suffix ".json" :keep t)
    (multiple-value-bind (code stdout stderr)
        (run-capturing
         (list "compile" (namestring (actor-fixture))
               "--manifest" (namestring manifest)))
      (declare (ignore stderr))
      (is (= 0 code))
      (is (string= "" stdout))
      (let ((text (uiop:read-file-string manifest)))
        (is (search "\"wireVersion\":1" text))
        (is (search "enrichment-worker" text))
        (is (char= #\newline (char text (1- (length text)))))))))

(test run-reports-materialization-summary
  "run compiles, materializes through the real dispatcher, and exits 0."
  (multiple-value-bind (code stdout stderr)
      (run-capturing
       (list "run" (namestring (actor-fixture))
             "--package" "STAR-LANG.CLI-TESTS"
             "--eval" "(defun enrichment-worker-handler (dispatcher command) (declare (ignore dispatcher command)) (list :outcome :complete))"))
    (declare (ignore stderr))
    (is (= 0 code))
    (is (search "run: materialized 1 actor(s); processed 0 command(s)" stdout))))

(test run-actor-program-registers-handler-with-the-real-dispatcher
  "The run path registers the package handler on the real deterministic
dispatcher, and the real dispatcher routes a live command through it."
  (let* ((manifest
           (starlangcompiler:emit-portable-manifest
            (list :kind :spec-library
                  :name "cli-dispatch-test"
                  :version "1"
                  :digest "sha256:cli-dispatch-test"
                  :imports '()
                  :declarations
                  (list (list :kind :message
                              :qualified-name "org.starintel/person@1"
                              :fields '())))
            (list (starlangcompiler:compile-actor-file (actor-fixture)))))
         (actor-ir (starlangcompiler:compile-actor-file (actor-fixture))))
    (multiple-value-bind (dispatcher actors processed)
        (star-lang.cli:run-actor-program
         manifest actor-ir
         :package-name "STAR-LANG.CLI-TESTS"
         :eval-forms
         (list '(defun enrichment-worker-handler (dispatcher command)
                  (declare (ignore dispatcher command))
                  (starlangruntime:complete-dispatch))))
      (is (= 1 actors))
      (is (= 0 processed))
      (is (starlangruntime:deterministic-dispatcher-p dispatcher))
      (let ((command
              (staractorprotocol:make-command-envelope
               :message-id "cli-dispatch-command-1"
               :message-type "org.starintel/person@1"
               :actor "enrichment-worker"
               :sender "star-lang.cli-tests"
               :idempotency-key "cli-dispatch-idem-1"
               :payload '())))
        (starlangruntime:submit-dispatch-envelope dispatcher command)
        (let ((statuses (starlangruntime:run-dispatcher dispatcher)))
          (is (equal '(:completed) statuses))
          (is (eql 1 (gethash "enrichment-worker"
                              (starlangruntime:deterministic-dispatcher-handler-count
                               dispatcher)
                              0)))
          (let* ((emitted
                   (starlangruntime:deterministic-dispatcher-emitted dispatcher))
                 (ack (first (last emitted))))
            (is (eq :ack (getf ack :kind)))
            (is (eq :completed (getf (getf ack :payload) :status)))))))))

(test run-without-resolvable-handler-fails-before-dispatching
  "run exits 1 with a structured diagnostic when a native handler is absent."
  (multiple-value-bind (code stdout stderr)
      (run-capturing (list "run" (namestring (actor-fixture))))
    (declare (ignore stdout))
    (is (= 1 code))
    (is (search "enrichment-worker-handler" stderr))
    (is (search "CL-USER" stderr))
    (is (search "enrichment-worker" stderr))))

(test fresh-sbcl-process-runs-cli-proof-without-prototype
  "A fresh SBCL process loads starlang-cli and never sees prototype packages."
  (let* ((script
           (asdf:system-relative-pathname :starlang-cli "tests/cli-proof.lisp"))
         (output
           (with-output-to-string (sink)
             (uiop:run-program
              (list (namestring sb-ext:*runtime-pathname*)
                    "--non-interactive"
                    "--load" (namestring script))
              :output sink
              :error-output sink
              :ignore-error-status nil))))
    (is (search "CLI-PROOF-OK" output))))

(defun run-tests ()
  ;; fiveam's run! returns T only when every check passed; surface failures
  ;; through the process exit code so ASDF/Nix/CI gates cannot pass silently.
  (unless (run! 'star-lang.cli-tests)
    (error "starlang-cli tests failed.")))
