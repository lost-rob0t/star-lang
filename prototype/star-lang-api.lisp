(require :asdf)

(unless (find-package "STAR-LANG.CONSTRUCTOR-RUNTIME")
  (load (merge-pathnames "constructor-runtime.lisp" *load-truename*)))

(unless (find-package "STAR-LANG.RELATION-COMPATIBILITY")
  (load (merge-pathnames "relation-compatibility.lisp" *load-truename*)))

(defpackage #:star-lang.api
  (:use #:cl)
  (:export
   #:load-star
   #:load-star-file
   #:load-star-url
   #:read-star-syntax
   #:expand-star-syntax
   #:validate-star-core
   #:compile-star-core
   #:load-star-runtime
   #:normalize-runtime-compiler
   #:install-constructors
   #:generate-constructor-source
   #:create-document
   #:encode-document
   #:decode-document
   #:relate-documents
   #:generate-id
   #:make-ulid
   #:make-uuidv4
   #:make-digest-id))

(in-package #:star-lang.api)

(defun read-star-syntax (source &rest arguments &key &allow-other-keys)
  (apply #'star-lang.core-surface.prototype:read-star-syntax source arguments))

(defun expand-star-syntax (syntax &rest arguments &key &allow-other-keys)
  (apply #'star-lang.core-surface.prototype:expand-star-syntax syntax arguments))

(defun validate-star-core (syntax &rest arguments &key &allow-other-keys)
  (apply #'star-lang.core-surface.prototype:validate-star-core syntax arguments))

(defun compile-star-core (syntax &rest arguments &key &allow-other-keys)
  (apply #'star-lang.core-surface.prototype:compile-star-core syntax arguments))

(defun remove-options (plist keys)
  (loop for (key value) on plist by #'cddr
        unless (member key keys :test #'eq)
          append (list key value)))

(defun normalize-runtime-compiler (runtime-compiler)
  (cond
    ((eq runtime-compiler :eval) :eval)
    ((and (symbolp runtime-compiler)
          (string-equal (symbol-name runtime-compiler) "eval"))
     :eval)
    ((and (stringp runtime-compiler)
          (string-equal runtime-compiler "eval"))
     :eval)
    (t
     (error 'star-lang.constructor-runtime:constructor-runtime-error
            :message
            (format nil
                    "Unsupported runtime compiler ~S. Supported runtime compilers: EVAL."
                    runtime-compiler)))))

(defun load-star (source &rest arguments &key &allow-other-keys)
  (apply #'star-lang.loader:load-star source arguments))

(defun load-star-file (pathname &rest arguments &key &allow-other-keys)
  (apply #'star-lang.loader:load-star-file pathname arguments))

(defun load-star-url (url &rest arguments &key &allow-other-keys)
  (apply #'star-lang.loader:load-star-url url arguments))

(defun install-constructors (graph &rest arguments
                             &key
                               (runtime-compiler :eval)
                             &allow-other-keys)
  (let ((compiler (normalize-runtime-compiler runtime-compiler))
        (constructor-arguments
          (remove-options arguments '(:runtime-compiler))))
    (ecase compiler
      (:eval
       (apply #'star-lang.constructor-runtime:install-constructors
              graph constructor-arguments)))))

(defun generate-constructor-source (graph stream &rest arguments
                                    &key &allow-other-keys)
  (apply #'star-lang.constructor-runtime:generate-constructor-source
         graph stream arguments))

(defun load-star-runtime (source &rest arguments
                          &key
                            constructor-package
                            (include-default-constructors t)
                            (constructor-if-exists :supersede)
                            (runtime-compiler :eval)
                          &allow-other-keys)
  (let* ((compiler (normalize-runtime-compiler runtime-compiler))
         (loader-arguments
           (remove-options
            arguments
            '(:constructor-package
              :include-default-constructors
              :constructor-if-exists
              :runtime-compiler)))
         (graph (apply #'star-lang.loader:load-star source loader-arguments)))
    (when constructor-package
      (install-constructors
       graph
       :package constructor-package
       :include-defaults include-default-constructors
       :if-exists constructor-if-exists
       :runtime-compiler compiler))
    graph))

(defun create-document (graph document-type values &rest arguments
                        &key &allow-other-keys)
  (apply #'star-lang.document-runtime:create-document
         graph document-type values arguments))

(defun encode-document (document &rest arguments &key &allow-other-keys)
  (apply #'star-lang.document-runtime:encode-document document arguments))

(defun decode-document (graph document-type encoded &rest arguments
                        &key &allow-other-keys)
  (apply #'star-lang.document-runtime:decode-document
         graph document-type encoded arguments))

(defun relate-documents (graph source destination &rest arguments
                         &key &allow-other-keys)
  (apply #'star-lang.document-runtime:relate-documents
         graph source destination arguments))

(defun generate-id (kind &rest arguments &key &allow-other-keys)
  (apply #'star-lang.document-runtime:generate-id kind arguments))

(defun make-ulid (&rest arguments &key &allow-other-keys)
  (apply #'star-lang.document-runtime:make-ulid arguments))

(defun make-uuidv4 ()
  (star-lang.document-runtime:make-uuidv4))

(defun make-digest-id (algorithm value &rest arguments
                       &key &allow-other-keys)
  (apply #'star-lang.document-runtime:make-digest-id
         algorithm value arguments))
