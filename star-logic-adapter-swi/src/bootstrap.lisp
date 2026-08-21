(in-package :starlogicadapterswi)

(defun %trusted-bootstrap-path ()
  (let ((path (asdf:system-relative-pathname
               "star-logic-adapter-swi"
               "prolog/star_logic_bootstrap.pl")))
    (%absolute-existing-file path
                             'swi-bootstrap-package-mismatch-error
                             "Trusted SWI bootstrap")))

(defun %prolog-quoted-atom (value)
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for char across value
          do (if (char= char #\')
                 (write-string "''" out)
                 (write-char char out)))
    (write-char #\' out)))

(defun %bootstrap-load-and-identity-message (bootstrap-path)
  ;; LOAD_FILES is deliberately confined to this private function.  Its path is
  ;; derived from the installed ASDF system, never from caller input.
  (format nil
          "run((load_files(~A,[silent(true)]),current_predicate(star_logic_bootstrap:star_logic_handshake/5),star_logic_bootstrap:star_logic_handshake(~A,~A,_,_,_)),-1)"
          (%prolog-quoted-atom (namestring bootstrap-path))
          (%prolog-quoted-atom +bootstrap-id+)
          (%prolog-quoted-atom +bootstrap-backend-id+)))

(defun %bootstrap-version-message (major minor patch)
  (format nil
          "run(star_logic_bootstrap:star_logic_handshake(~A,~A,~D,~D,~D),-1)"
          (%prolog-quoted-atom +bootstrap-id+)
          (%prolog-quoted-atom +bootstrap-backend-id+)
          major minor patch))
