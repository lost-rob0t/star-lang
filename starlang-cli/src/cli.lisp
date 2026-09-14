;;;; Final starlang CLI implementation: explicit version/check/compile/run
;;;; behavior with deterministic exit status and structured diagnostics.
;;;; This system is a leaf over final systems only: it depends on the final
;;;; compiler and runtime and never loads starlang-prototype or anything
;;;; under prototype/. The transitional load/load-url commands stay in the
;;;; prototype loader script (prototype/run-star.lisp) and reach the installed
;;;; starlang wrapper through wrapper-level dispatch, never through here.
;;;;
;;;; Program manifests carry the compiled unit's digest inside a synthetic
;;;; single-library envelope until program-level compilation (multi-actor and
;;;; dataflow programs) lands in the compiler.
;;;;
;;;; Exit codes: 0 success; 1 runtime or diagnostic failure; 2 usage error.

(in-package :star-lang.cli)

(defparameter +cli-version+ "0.1.0")

(define-condition cli-error (error)
  ((message :initarg :message :reader cli-error-message))
  (:report (lambda (condition stream)
             (write-string (cli-error-message condition) stream))))

(define-condition cli-usage-error (cli-error) ())

(defun fail-cli (control &rest arguments)
  (error 'cli-error :message (apply #'format nil control arguments)))

(defun fail-cli-usage (control &rest arguments)
  (error 'cli-usage-error
         :message (apply #'format nil control arguments)))

(defun usage (&optional (stream *standard-output*))
  (format stream "Usage: starlang version~%")
  (format stream "       starlang check FILE~%")
  (format stream "       starlang compile FILE [--manifest FILE]~%")
  (format stream "       starlang run FILE [--eval FORM]... [--load FILE]... [--package PKG] [--manifest FILE]~%")
  (format stream "       starlang load FILE [--allow-network] [--cache DIR] [--manifest FILE] [--runtime-compiler eval]~%")
  (format stream "       starlang load-url URL --name NAME --version VERSION --digest SHA256 [options]~%")
  (format stream "~%")
  (format stream "Commands version, check, compile, and run load only final systems.~%")
  (format stream "Commands load and load-url delegate to the transitional prototype loader~%")
  (format stream "script (prototype/run-star.lisp) through the installed starlang wrapper.~%")
  (format stream "Exit status: 0 success; 1 runtime or diagnostic failure; 2 usage error.~%")
  (values))

(defun file-sha256 (file)
  "SHA-256 hex digest of the file octets, with the sha256: scheme prefix."
  (let ((digest (ironclad:digest-file (ironclad:make-digest :sha256) file)))
    (format nil "sha256:~A" (ironclad:byte-array-to-hex-string digest))))

(defun program-library-envelope (file library-name library-version)
  ;; Until program-level compilation (multi-actor/dataflow programs) lands in
  ;; the compiler, a program manifest wraps the compiled unit in a synthetic
  ;; single-library envelope whose digest pins the .star source octets.
  (list :kind :spec-library
        :name library-name
        :version library-version
        :digest (file-sha256 file)
        :imports '()
        :declarations '()))

(defun compile-program (file &key (library-name (pathname-name file))
                                  (library-version "1"))
  "Compile the single-actor .star unit FILE through the full closed pipeline
and return (values actor-ir portable-manifest)."
  (let* ((actor-ir (starlangcompiler:compile-actor-file file))
         (manifest
           (starlangcompiler:emit-portable-manifest
            (program-library-envelope file library-name library-version)
            (list actor-ir))))
    (values actor-ir manifest)))

(defun compile-program-manifest (file &key (library-name (pathname-name file))
                                           (library-version "1"))
  "Compile the single-actor .star unit FILE and return its portable manifest."
  (nth-value 1 (compile-program file
                                :library-name library-name
                                :library-version library-version)))

(defun evaluate-host-form (form package)
  ;; --eval and --load are trusted host-side CLI options; only they reach
  ;; EVAL. .star source never does: it enters through the closed parser.
  (let ((*package* package))
    (if (stringp form)
        (with-input-from-string (stream form)
          (loop for expression = (read stream nil stream)
                until (eq expression stream)
                do (eval expression)))
        (eval form)))
  (values))

(defun register-program-handlers (dispatcher actor-ir package package-name)
  ;; Resolve each native actor's handler in the requested package and
  ;; register it with the real deterministic dispatcher before running.
  ;; External actors dispatch through their endpoints and need no handler.
  (when (eq (getf actor-ir :runtime) :native)
    (let* ((actor-name (getf actor-ir :name))
           (handler-name (getf actor-ir :handler))
           (handler (and handler-name
                         (find-symbol (string-upcase handler-name) package))))
      (unless (and handler (fboundp handler))
        (fail-cli
         "Actor ~A requires handler function ~A in package ~A; no such function."
         actor-name (or handler-name "<missing>") package-name))
      (starlangruntime:register-dispatch-actor
       dispatcher actor-name (symbol-function handler))))
  (values))

(defun run-actor-program (manifest actor-ir
                          &key (package-name "CL-USER")
                          (eval-forms '())
                          (load-files '()))
  "Materialize the compiled actor program on the real deterministic wire
dispatcher: evaluate trusted host-side --load files then --eval forms with
*package* bound to PACKAGE-NAME, resolve and register every native handler
from that package, and drain the dispatcher queue. Returns
(values dispatcher actor-count processed-count)."
  (let ((dispatcher (starlangruntime:make-deterministic-dispatcher manifest))
        (package (or (find-package (string-upcase package-name))
                     (fail-cli "Unknown package ~A." package-name))))
    (dolist (file load-files)
      (let ((*package* package))
        (load file)))
    (dolist (form eval-forms)
      (evaluate-host-form form package))
    (register-program-handlers dispatcher actor-ir package package-name)
    (let ((processed (starlangruntime:run-dispatcher dispatcher)))
      (values dispatcher
              (length (getf manifest :actors))
              (length processed)))))

(defun write-manifest-json (json &optional file)
  (if file
      (with-open-file (stream file
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string json stream)
        (terpri stream))
      (progn
        (write-string json *standard-output*)
        (terpri *standard-output*)))
  (values))

(defun run-version-command ()
  (format *standard-output* "starlang-cli ~A~%" +cli-version+)
  (let ((compiler (ignore-errors (asdf:find-system "starlang-compiler" nil))))
    (when compiler
      (let ((version (asdf:component-version compiler)))
        (when version
          (format *standard-output* "starlang-compiler ~A~%" version)))))
  (values))

(defun require-option-value (arguments option)
  (unless arguments
    (fail-cli-usage "Option ~A requires a value." option))
  (values (first arguments) (rest arguments)))

(defun require-single-file (arguments command)
  (unless arguments
    (fail-cli-usage "~A requires a FILE argument." command))
  (when (rest arguments)
    (fail-cli-usage "~A takes exactly one FILE argument." command))
  (first arguments))

(defun plain-option-p (option)
  (and (plusp (length option))
       (char= (char option 0) #\-)))

(defun parse-compile-arguments (arguments)
  (let ((file nil)
        (manifest nil))
    (loop while arguments
          for option = (pop arguments)
          do (cond
               ((string= option "--manifest")
                (multiple-value-setq (manifest arguments)
                  (require-option-value arguments option)))
               ((plain-option-p option)
                (fail-cli-usage "Unknown option ~A for compile." option))
               (file
                (fail-cli-usage "compile takes exactly one FILE argument."))
               (t
                (setf file option))))
    (unless file
      (fail-cli-usage "compile requires a FILE argument."))
    (values file manifest)))

(defun parse-run-arguments (arguments)
  (let ((file nil)
        (manifest nil)
        (eval-forms '())
        (load-files '())
        (package "CL-USER"))
    (loop while arguments
          for option = (pop arguments)
          do (cond
               ((string= option "--manifest")
                (multiple-value-setq (manifest arguments)
                  (require-option-value arguments option)))
               ((string= option "--eval")
                (multiple-value-bind (value rest)
                    (require-option-value arguments option)
                  (push value eval-forms)
                  (setf arguments rest)))
               ((string= option "--load")
                (multiple-value-bind (value rest)
                    (require-option-value arguments option)
                  (push value load-files)
                  (setf arguments rest)))
               ((string= option "--package")
                (multiple-value-setq (package arguments)
                  (require-option-value arguments option)))
               ((plain-option-p option)
                (fail-cli-usage "Unknown option ~A for run." option))
               (file
                (fail-cli-usage "run takes exactly one FILE argument."))
               (t
                (setf file option))))
    (unless file
      (fail-cli-usage "run requires a FILE argument."))
    (values file
            (nreverse eval-forms)
            (nreverse load-files)
            package
            manifest)))

(defun run-check-command (arguments)
  (let* ((file (require-single-file arguments "check"))
         (ir (starlangcompiler:compile-actor-file file)))
    (format *standard-output* "ok: actor ~A~%" (getf ir :name))
    0))

(defun run-compile-command (arguments)
  (multiple-value-bind (file manifest-path)
      (parse-compile-arguments arguments)
    (let ((manifest (compile-program-manifest file)))
      (write-manifest-json
       (starcanonicaljson:canonical-manifest-json manifest)
       manifest-path)
      0)))

(defun run-run-command (arguments)
  (multiple-value-bind (file eval-forms load-files package manifest-path)
      (parse-run-arguments arguments)
    (multiple-value-bind (actor-ir manifest)
        (compile-program file)
      (when manifest-path
        (write-manifest-json
         (starcanonicaljson:canonical-manifest-json manifest)
         manifest-path))
      (multiple-value-bind (dispatcher actors processed)
          (run-actor-program manifest actor-ir
                             :package-name package
                             :eval-forms eval-forms
                             :load-files load-files)
        (declare (ignore dispatcher))
        (format *standard-output*
                "run: materialized ~D actor(s); processed ~D command(s)~%"
                actors processed)
        0))))

(defun run-delegated-command (command)
  (fail-cli-usage
   "Command ~A delegates to the transitional prototype loader script ~
    (prototype/run-star.lisp) and must be invoked through the installed ~
    starlang wrapper." command))

(defun dispatch-command (command arguments)
  (cond
    ((string= command "version")
     (run-version-command)
     0)
    ((string= command "check")
     (run-check-command arguments))
    ((string= command "compile")
     (run-compile-command arguments))
    ((string= command "run")
     (run-run-command arguments))
    ((member command '("load" "load-url") :test #'string=)
     (run-delegated-command command))
    (t
     (fail-cli-usage "Unknown command ~A." command))))

(defun print-star-diagnostic (condition)
  (let ((pathname (starlangcompiler:star-lang-core-error-pathname condition))
        (line (starlangcompiler:star-lang-core-error-line condition))
        (column (starlangcompiler:star-lang-core-error-column condition)))
    (format *error-output* "starlang: ")
    (when pathname
      (format *error-output* "~A" pathname)
      (when line
        (format *error-output* ":~D" line)
        (when column
          (format *error-output* ":~D" column)))
      (write-string ": " *error-output*))
    (format *error-output* "~A~%"
            (starlangcompiler:star-lang-core-error-message condition))))

(defun run-cli (argv)
  "Execute the starlang command surface for ARGV (uiop:command-line-arguments)
and return the integer exit code: 0 success, 1 runtime or diagnostic failure,
2 usage error. The caller script quits with the returned code."
  (cond
    ((null argv)
     (usage *error-output*)
     2)
    ((member (first argv) '("-h" "--help" "help") :test #'string=)
     (usage *standard-output*)
     0)
    (t
     (handler-case
         (dispatch-command (first argv) (rest argv))
       (cli-usage-error (condition)
         (format *error-output* "starlang: ~A~%" condition)
         (usage *error-output*)
         2)
       (starlangcompiler:star-lang-core-error (condition)
         (print-star-diagnostic condition)
         1)
       (starlangruntime:actor-runtime-error (condition)
         (format *error-output* "starlang: ~A~%" condition)
         1)
       (cli-error (condition)
         (format *error-output* "starlang: ~A~%" condition)
         1)))))
