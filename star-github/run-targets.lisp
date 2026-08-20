(require :asdf)
(asdf:load-system :star-github)

(defun target-files (root)
  (directory (merge-pathnames "targets/*.json" root)))

(defun run-target-file (runtime pathname)
  (let ((document (stargithub:read-starintel-json-document pathname)))
    (when (stargithub:github-target-document-p document)
      (let ((result (starlangruntime:invoke-actor runtime "github" document)))
        (format t "~&github target ~A: ~A, ~D documents, run ~A~%"
                pathname
                (stargithub:github-run-result-status result)
                (stargithub:github-run-result-documents-written result)
                (stargithub:github-run-result-run-id result))
        (when (stargithub:github-run-result-error result)
          (format t "github target error: ~A~%"
                  (stargithub:github-run-result-error result)))
        result))))

(defun main ()
  (let* ((arguments (uiop:command-line-arguments))
         (root (uiop:ensure-directory-pathname
                (pathname (or (first arguments) "data/"))))
         (runtime (starlangruntime:make-runtime))
         (failures 0)
         (runs 0))
    (starartifact:create-json-file-writer-actor runtime "json-files" root)
    (stargithub:create-github-actor runtime "github" "json-files")
    (dolist (pathname (target-files root))
      (let ((result (run-target-file runtime pathname)))
        (when result
          (incf runs)
          (when (eq :failed (stargithub:github-run-result-status result))
            (incf failures)))))
    (format t "~&github target runner: ~D run(s), ~D failure(s)~%" runs failures)
    (when (plusp failures)
      (uiop:quit 1))))

(main)
