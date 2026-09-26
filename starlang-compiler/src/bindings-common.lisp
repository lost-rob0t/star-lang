;;;; Shared portable binding generator helpers.
;;;; StarLang source and its portable manifest are the only schema authority.

(in-package #:star-lang.compiler.core)

(defparameter +portable-binding-languages+
  '(:common-lisp :kotlin :java :python :typescript :nim :go :rust :emacs-lisp :prolog))

(defun supported-binding-languages ()
  (copy-list +portable-binding-languages+))

(defun binding-qualified-local-name (qualified-name)
  (let ((position (position #\/ qualified-name :from-end t)))
    (if position
        (subseq qualified-name (1+ position))
        qualified-name)))

(defun binding-identifier-words (value)
  (let ((words '())
        (current (make-string-output-stream)))
    (labels ((finish-word ()
               (let ((word (get-output-stream-string current)))
                 (unless (string= word "")
                   (push word words)))
               (setf current (make-string-output-stream))))
      (loop for character across value
            do (if (alphanumericp character)
                   (write-char character current)
                   (finish-word)))
      (finish-word))
    (nreverse words)))

(defun binding-pascal-name (value)
  (with-output-to-string (stream)
    (dolist (word (binding-identifier-words (binding-qualified-local-name value)))
      (when (> (length word) 0)
        (write-char (char-upcase (char word 0)) stream)
        (loop for character across (subseq word 1)
              do (write-char (char-downcase character) stream))))))

(defun binding-snake-name (value)
  (with-output-to-string (stream)
    (loop for word in (binding-identifier-words (binding-qualified-local-name value))
          for first-p = t then nil
          do (unless first-p (write-char #\_ stream))
             (write-string (string-downcase word) stream))))

(defun binding-upper-snake-name (value)
  (string-upcase (binding-snake-name value)))

(defun binding-kebab-name (value)
  (with-output-to-string (stream)
    (loop for word in (binding-identifier-words (binding-qualified-local-name value))
          for first-p = t then nil
          do (unless first-p (write-char #\- stream))
             (write-string (string-downcase word) stream))))

(defun binding-source-string (value)
  (starcanonicaljson:canonical-json-string value))

(defun binding-prolog-atom (value)
  (with-output-to-string (stream)
    (write-char #\' stream)
    (loop for character across value
          do (if (char= character #\')
                 (write-string "''" stream)
                 (write-char character stream)))
    (write-char #\' stream)))

(defun binding-document-fields (manifest contract)
  (staractorprotocol:portable-manifest-document-fields manifest contract))

(defun binding-type-contract (manifest type)
  (and (stringp type)
       (staractorprotocol:portable-manifest-type-contract manifest type)))

(defun binding-type-map (manifest type builtin mapper custom)
  (declare (ignore manifest))
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (funcall mapper :list (second type)))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (funcall mapper :optional (second type)))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate binding type for ~S." type))
    ((funcall builtin type))
    (t (funcall custom type))))

(defun binding-write-header (stream language)
  (format stream "// Generated from StarLang portable manifest. DO NOT EDIT. language=~(~A~)~%~%"
          language))

(defun binding-write-lisp-header (stream language)
  (format stream ";;;; Generated from StarLang portable manifest. DO NOT EDIT. language=~(~A~)~%~%"
          language))

(defun binding-write-prolog-header (stream)
  (format stream "%% Generated from StarLang portable manifest. DO NOT EDIT.~%~%"))

(defun binding-field-required-p (field)
  (not (null (getf field :required))))

(defun binding-contracts (manifest kind)
  (remove-if-not (lambda (contract) (eq (getf contract :kind) kind))
                 (getf manifest :types)))

(defun binding-message-contracts (manifest)
  (copy-list (getf manifest :messages)))
