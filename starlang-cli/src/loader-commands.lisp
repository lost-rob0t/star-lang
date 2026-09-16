;;;; Final load/load-url CLI commands. Loaded after CLI core to replace only the
;;;; transitional dispatch branch while preserving the existing command code.

(in-package :star-lang.cli)

(defvar *pre-loader-dispatch-command* (symbol-function 'dispatch-command))

(defun normalize-loader-runtime-compiler (value)
  ;; Compatibility flag. Loader compilation is now always the final compiler;
  ;; EVAL remains accepted so existing scripts do not break.
  (if (and value (string-equal value "eval"))
      :eval
      (fail-cli-usage
       "Unsupported runtime compiler ~S. Supported value: eval." value)))

(defun parse-loader-arguments (arguments command)
  (unless arguments
    (fail-cli-usage "~A requires a source argument." command))
  (let ((source (pop arguments))
        (allow-network nil)
        (cache nil)
        (manifest nil)
        (name nil)
        (version nil)
        (digest nil)
        (runtime-compiler :eval))
    (loop while arguments
          for option = (pop arguments)
          do (cond
               ((string= option "--allow-network")
                (setf allow-network t))
               ((string= option "--cache")
                (multiple-value-setq (cache arguments)
                  (require-option-value arguments option)))
               ((string= option "--manifest")
                (multiple-value-setq (manifest arguments)
                  (require-option-value arguments option)))
               ((string= option "--name")
                (multiple-value-setq (name arguments)
                  (require-option-value arguments option)))
               ((string= option "--version")
                (multiple-value-setq (version arguments)
                  (require-option-value arguments option)))
               ((string= option "--digest")
                (multiple-value-setq (digest arguments)
                  (require-option-value arguments option)))
               ((string= option "--runtime-compiler")
                (multiple-value-bind (value rest)
                    (require-option-value arguments option)
                  (setf runtime-compiler
                        (normalize-loader-runtime-compiler value)
                        arguments rest)))
               (t
                (fail-cli-usage "Unknown option ~A for ~A." option command))))
    (values source allow-network cache manifest name version digest
            runtime-compiler)))

(defun default-loader-cache-directory ()
  (merge-pathnames #P".cache/star-lang/specs/" (user-homedir-pathname)))

(defun write-loader-manifest (graph pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (star-lang.loader:write-loaded-graph graph stream))
  pathname)

(defun run-final-loader-command (command arguments)
  (multiple-value-bind
        (source allow-network cache manifest name version digest runtime-compiler)
      (parse-loader-arguments arguments command)
    (declare (ignore runtime-compiler))
    (let* ((cache-directory (or cache (default-loader-cache-directory)))
           (graph
             (cond
               ((string= command "load")
                (star-lang.loader:load-star-file
                 source
                 :allow-network allow-network
                 :cache-directory cache-directory))
               ((string= command "load-url")
                (unless (and name version digest)
                  (fail-cli-usage
                   "load-url requires --name, --version, and --digest."))
                (star-lang.loader:load-star-url
                 source
                 :name name
                 :version version
                 :digest digest
                 :allow-network allow-network
                 :cache-directory cache-directory))
               (t
                (fail-cli-usage "Unknown loader command ~A." command)))))
      (star-lang.loader:print-loaded-graph graph)
      (when manifest
        (write-loader-manifest graph manifest)
        (format *standard-output* "Wrote loader manifest to ~A.~%" manifest))
      0)))

(defun dispatch-command (command arguments)
  (if (member command '("load" "load-url") :test #'string=)
      (run-final-loader-command command arguments)
      (funcall *pre-loader-dispatch-command* command arguments)))

(defun usage (&optional (stream *standard-output*))
  (format stream "Usage: starlang version~%")
  (format stream "       starlang check FILE~%")
  (format stream "       starlang compile FILE [--manifest FILE]~%")
  (format stream "       starlang run FILE [--eval FORM]... [--load FILE]... [--package PKG] [--manifest FILE]~%")
  (format stream "       starlang load FILE [--allow-network] [--cache DIR] [--manifest FILE] [--runtime-compiler eval]~%")
  (format stream "       starlang load-url URL --name NAME --version VERSION --digest SHA256 [options]~%")
  (format stream "~%All commands load final systems only. Network resolution is opt-in.~%")
  (format stream "Exit status: 0 success; 1 runtime or diagnostic failure; 2 usage error.~%")
  (values))
