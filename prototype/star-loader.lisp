(require :asdf)

(unless (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE")
  (load (merge-pathnames "core-surface-prototype.lisp" *load-truename*)))

(unless (boundp
         'star-lang.core-surface.prototype::*declarative-macro-expander-loaded*)
  (load (merge-pathnames "macro-expander-prototype.lisp" *load-truename*)))

(defpackage #:star-lang.loader
  (:use #:cl)
  (:export
   #:library-node
   #:library-node-name
   #:library-node-version
   #:library-node-digest
   #:library-node-source
   #:library-node-cache-path
   #:library-node-form
   #:library-node-source-map
   #:library-node-compiled
   #:library-node-imports
   #:loaded-graph
   #:loaded-graph-root
   #:loaded-graph-libraries
   #:loaded-graph-cache-directory
   #:loader-error
   #:loader-error-message
   #:load-star
   #:load-star-file
   #:load-star-url
   #:print-loaded-graph
   #:write-loaded-graph))

(in-package #:star-lang.loader)

(define-condition loader-error (error)
  ((message :initarg :message :reader loader-error-message)
   (code :initarg :code :initform :loader-error :reader loader-error-code)
   (primary-span :initarg :primary-span :initform nil
                 :reader loader-error-primary-span)
   (origin-chain :initarg :origin-chain :initform nil
                 :reader loader-error-origin-chain)
   (related-spans :initarg :related-spans :initform nil
                  :reader loader-error-related-spans)
   (phase :initarg :phase :initform :resolve :reader loader-error-phase)
   (details :initarg :details :initform nil :reader loader-error-details))
  (:report (lambda (condition stream)
             (write-string (loader-error-message condition) stream))))

(define-condition source-error (loader-error) ())
(define-condition import-error (loader-error) ())
(define-condition digest-error (loader-error) ())
(define-condition network-disabled-error (loader-error) ())
(define-condition dependency-error (loader-error) ())

(defstruct library-node
  name
  version
  digest
  source
  cache-path
  form
  compiled
  imports
  source-map)

(defstruct loaded-graph
  root
  libraries
  cache-directory)

(defparameter *maximum-source-bytes* (* 16 1024 1024))
(defparameter *curl-program* "curl")
(defparameter *sha256-program* "sha256sum")

(defvar *loader-current-syntax* nil)

(defun fail-loader (condition-type control &rest arguments)
  (let ((syntax *loader-current-syntax*))
    (error condition-type
           :message (apply #'format nil control arguments)
           :primary-span (and syntax
                              (star-lang.core-surface.prototype:star-syntax-span
                               syntax))
           :origin-chain
           (and syntax
                (star-lang.core-surface.prototype:star-origin-chain
                 (star-lang.core-surface.prototype:star-syntax-origin syntax)))
           :phase :resolve)))

(defmacro with-loader-syntax ((syntax) &body body)
  `(let ((*loader-current-syntax* ,syntax)) ,@body))

(defun string-prefix-p (prefix value)
  (and (stringp value)
       (<= (length prefix) (length value))
       (string= prefix value :end2 (length prefix))))

(defun url-p (value)
  (string-prefix-p "https://" value))

(defun full-sha256-digest-p (value)
  (and (stringp value)
       (= (length value) 71)
       (string-prefix-p "sha256:" value)
       (every (lambda (character)
                (or (digit-char-p character)
                    (find character "abcdefABCDEF")))
              (subseq value 7))))

(defun normalize-digest (value)
  (unless (full-sha256-digest-p value)
    (fail-loader 'digest-error
                 "Expected a full sha256:<64 hex digits> digest, received ~S."
                 value))
  (string-downcase value))

(defun default-cache-directory ()
  (merge-pathnames #P".cache/star-lang/specs/"
                   (user-homedir-pathname)))

(defun ensure-cache-directory (pathname)
  (let ((directory (uiop:ensure-directory-pathname pathname)))
    (ensure-directories-exist (merge-pathnames #P".keep" directory))
    directory))

(defun source-byte-length (pathname)
  (with-open-file (stream pathname :direction :input :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun ensure-source-size (pathname maximum-source-bytes)
  (let ((size (source-byte-length pathname)))
    (when (> size maximum-source-bytes)
      (fail-loader 'source-error
                   "Star source ~A is ~D bytes; the configured limit is ~D."
                   pathname size maximum-source-bytes))
    size))

(defun parser-limits-with-source-limit (limits maximum-source-bytes)
  (let ((base (or limits
                  (star-lang.core-surface.prototype:make-star-parser-limits))))
    (star-lang.core-surface.prototype:make-star-parser-limits
     :source-bytes maximum-source-bytes
     :nesting-depth
     (star-lang.core-surface.prototype:star-parser-limits-nesting-depth base)
     :node-count
     (star-lang.core-surface.prototype:star-parser-limits-node-count base)
     :token-bytes
     (star-lang.core-surface.prototype:star-parser-limits-token-bytes base)
     :string-bytes
     (star-lang.core-surface.prototype:star-parser-limits-string-bytes base)
     :collection-length
     (star-lang.core-surface.prototype:star-parser-limits-collection-length base)
     :numeric-literal-bytes
     (star-lang.core-surface.prototype:star-parser-limits-numeric-literal-bytes base)
     :numeric-magnitude
     (star-lang.core-surface.prototype:star-parser-limits-numeric-magnitude base))))

(defun read-star-file (pathname limits origin)
  (let* ((path (truename pathname))
         (octets
           (with-open-file (stream path
                                   :direction :input
                                   :element-type '(unsigned-byte 8))
             (let* ((length (file-length stream))
                    (buffer (make-array length
                                        :element-type '(unsigned-byte 8))))
               (when (> length
                        (star-lang.core-surface.prototype:star-parser-limits-source-bytes
                         limits))
                 (fail-loader 'source-error
                              "Star source ~A exceeds the configured byte limit."
                              path))
               (unless (= (read-sequence buffer stream) length)
                 (fail-loader 'source-error
                              "Star source ~A changed while being read." path))
               buffer))))
    (star-lang.core-surface.prototype:read-star-syntax
     octets
     :source-id (namestring path)
     :pathname path
     :origin origin
     :limits limits)))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun require-option (options key context)
  (unless (plist-key-present-p options key)
    (fail-loader 'import-error "~A requires ~S." context key))
  (getf options key))

(defun identifier-string (value)
  (etypecase value
    (string value)
    (symbol (string-downcase (symbol-name value)))
    (star-lang.core-surface.prototype:star-syntax
     (identifier-string
      (star-lang.core-surface.prototype:star-syntax-datum value)))))

(defun loader-elements (syntax)
  (unless (and (star-lang.core-surface.prototype:star-syntax-p syntax)
               (eq (star-lang.core-surface.prototype:star-syntax-kind syntax)
                   :list))
    (fail-loader 'source-error "Expected a StarLang list."))
  (star-lang.core-surface.prototype:star-syntax-children syntax))

(defun declaration-kind (form)
  (let ((elements (loader-elements form)))
    (unless elements
      (fail-loader 'source-error "Invalid empty Star declaration."))
    (string-downcase (identifier-string (first elements)))))

(defun parse-library-header (form)
  (unless (and (star-lang.core-surface.prototype:star-syntax-p form)
               (>= (length (loader-elements form)) 3)
               (string= (declaration-kind form) "spec-library"))
    (fail-loader 'source-error "Expected one spec-library form."))
  (destructuring-bind (operator name options &rest declarations) (loader-elements form)
    (declare (ignore operator declarations))
    (let ((name-datum
            (star-lang.core-surface.prototype:star-syntax-datum name))
          (option-data
            (star-lang.core-surface.prototype:star-syntax-to-datum options)))
      (unless (and (stringp name-datum)
                   (listp option-data)
                   (evenp (length option-data)))
        (fail-loader 'source-error "Invalid spec-library header."))
      (let ((version (require-option option-data :version "spec-library")))
      (unless (stringp version)
        (fail-loader 'source-error
                     "Specification library version must be a string."))
        (values name-datum version)))))

(defun raw-import-declarations (form)
  (remove-if-not
   (lambda (declaration)
     (string= (declaration-kind declaration) "import"))
   (cdddr (loader-elements form))))

(defun parse-import-declaration (declaration)
  (with-loader-syntax (declaration)
  (destructuring-bind (operator name &rest options) (loader-elements declaration)
    (declare (ignore operator))
    (let* ((name-datum
             (star-lang.core-surface.prototype:star-syntax-datum name))
           (option-data
             (mapcar #'star-lang.core-surface.prototype:star-syntax-to-datum
                     options)))
      (unless (and (stringp name-datum) (evenp (length option-data)))
        (fail-loader 'import-error "Invalid import declaration."))
    (let* ((version (require-option option-data :version "import"))
           (digest (normalize-digest
                    (require-option option-data :digest "import")))
           (url (getf option-data :url))
           (path (getf option-data :path)))
      (unless (stringp version)
        (fail-loader 'import-error
                     "Import ~A requires a string version."
                     name))
      (when (and url path)
        (fail-loader 'import-error
                     "Import ~A cannot declare both :url and :path."
                     name))
      (unless (or url path)
        (fail-loader 'import-error
                     "Import ~A requires either :url or :path."
                     name))
      (when (and url (not (url-p url)))
        (fail-loader 'import-error
                     "Import URL ~S must use https://."
                     url))
      (when (and path (not (stringp path)))
        (fail-loader 'import-error "Import path must be a string."))
      (list :name name-datum
            :version version
            :digest digest
            :url url
            :path path
            :syntax declaration))))))

(defun command-output (program arguments context)
  (handler-case
      (string-trim
       '(#\Space #\Tab #\Newline #\Return)
       (uiop:run-program
        (cons program arguments)
        :output :string
        :error-output :string
        :ignore-error-status nil))
    (error (condition)
      (fail-loader 'dependency-error
                   "~A failed through ~A: ~A"
                   context program condition))))

(defun sha256-file (pathname)
  (let* ((output (command-output
                  *sha256-program*
                  (list (namestring pathname))
                  "SHA-256 calculation"))
         (separator (position-if
                     (lambda (character)
                       (find character '(#\Space #\Tab)))
                     output))
         (hex (if separator (subseq output 0 separator) output)))
    (unless (and (= (length hex) 64)
                 (every (lambda (character)
                          (or (digit-char-p character)
                              (find character "abcdefABCDEF")))
                        hex))
      (fail-loader 'digest-error
                   "Could not parse sha256sum output ~S."
                   output))
    (format nil "sha256:~A" (string-downcase hex))))

(defun verify-file-digest (pathname expected-digest)
  (let ((actual (sha256-file pathname))
        (expected (normalize-digest expected-digest)))
    (unless (string= actual expected)
      (fail-loader 'digest-error
                   "Digest mismatch for ~A: expected ~A, received ~A."
                   pathname expected actual))
    actual))

(defun digest-cache-path (cache-directory digest)
  (merge-pathnames
   (make-pathname :name (subseq (normalize-digest digest) 7)
                  :type "star")
   cache-directory))

(defun temporary-cache-path (cache-directory digest)
  (merge-pathnames
   (make-pathname
    :name (format nil ".~A.~36R.~36R"
                  (subseq (normalize-digest digest) 7 23)
                  (get-universal-time)
                  (random most-positive-fixnum))
    :type "tmp")
   cache-directory))

(defun fetch-url-to-cache (url digest cache-directory maximum-source-bytes)
  (let* ((cache-path (digest-cache-path cache-directory digest))
         (temporary-path (temporary-cache-path cache-directory digest)))
    (when (probe-file cache-path)
      (handler-case
          (progn
            (ensure-source-size cache-path maximum-source-bytes)
            (verify-file-digest cache-path digest)
            (return-from fetch-url-to-cache cache-path))
        (loader-error ()
          (ignore-errors (delete-file cache-path)))))
    (unwind-protect
         (progn
           (uiop:run-program
            (list *curl-program*
                  "--fail"
                  "--silent"
                  "--show-error"
                  "--location"
                  "--max-redirs" "5"
                  "--connect-timeout" "10"
                  "--max-time" "60"
                  "--proto" "=https"
                  "--proto-redir" "=https"
                  "--output" (namestring temporary-path)
                  url)
            :output :string
            :error-output :string
            :ignore-error-status nil)
           (ensure-source-size temporary-path maximum-source-bytes)
           (verify-file-digest temporary-path digest)
           (rename-file temporary-path cache-path)
           cache-path)
      (when (probe-file temporary-path)
        (ignore-errors (delete-file temporary-path))))))

(defun resolve-local-import-path (path parent-path)
  (let* ((candidate (pathname path))
         (resolved
           (if (uiop:absolute-pathname-p candidate)
               candidate
               (merge-pathnames candidate
                                (uiop:pathname-directory-pathname parent-path)))))
    (unless (probe-file resolved)
      (fail-loader 'import-error
                   "Imported Star file ~A does not exist."
                   resolved))
    (truename resolved)))

(defun library-key (name version)
  (format nil "~A@~A" name version))

(defun compile-library-form (form &optional macro-environment)
  (let ((expanded
          (star-lang.core-surface.prototype:expand-star-syntax
           form :environment macro-environment)))
    (star-lang.core-surface.prototype:validate-star-core expanded)
    (star-lang.core-surface.prototype:compile-star-core expanded)))

(defun library-macro-environment (node)
  (apply
   #'star-lang.core-surface.prototype:merge-star-macro-environments
   (append
    (mapcar #'library-macro-environment (library-node-imports node))
    (list
     (star-lang.core-surface.prototype:collect-star-macro-environment
      (library-node-form node)
      :library-name (library-node-name node)
      :library-version (library-node-version node)
      :library-digest (library-node-digest node))))))

(defvar *loader-active-chain* nil)

(defun fail-import-cycle (key origin)
  (let* ((chain (append (mapcar #'car *loader-active-chain*) (list key)))
         (primary
           (or (and *loader-current-syntax*
                    (star-lang.core-surface.prototype:star-syntax-span
                     *loader-current-syntax*))
               (and origin
                    (star-lang.core-surface.prototype:star-origin-frame-import-site-span
                     origin))))
         (spans
           (remove nil
                   (append (mapcar #'cdr *loader-active-chain*)
                           (list primary)))))
    (error 'import-error
           :message (format nil "Specification import cycle: ~{~A~^ -> ~}."
                            chain)
           :code :import-cycle
           :primary-span primary
           :origin-chain
           (star-lang.core-surface.prototype:star-origin-chain origin)
           :related-spans spans
           :details (list :ordered-chain chain)
           :phase :resolve)))

(defun import-origin (import parent-name parent-version parent-digest parent-origin)
  (let* ((syntax (getf import :syntax))
         (span (star-lang.core-surface.prototype:star-syntax-span syntax)))
    (star-lang.core-surface.prototype:make-star-origin-frame
     :kind :import
     :source-id (and span
                     (star-lang.core-surface.prototype:star-source-span-source-id
                      span))
     :library-name parent-name
     :library-version parent-version
     :library-digest parent-digest
     :import-site-span span
     :parent parent-origin)))

(defun load-star-file (pathname
                       &key
                         (allow-network nil)
                         (cache-directory (default-cache-directory))
                         (maximum-source-bytes *maximum-source-bytes*)
                         limits)
  (let ((seen (make-hash-table :test #'equal))
        (active (make-hash-table :test #'equal))
        (ordered '())
        (cache (ensure-cache-directory cache-directory))
        (effective-limits
          (parser-limits-with-source-limit limits maximum-source-bytes)))
    (labels
        ((load-library (path source expected-name expected-version expected-digest
                            origin)
           (let* ((form (read-star-file path effective-limits origin))
                  (actual-digest (sha256-file path)))
             (multiple-value-bind (name version)
                 (parse-library-header form)
               (when (and expected-name (not (string= name expected-name)))
                 (fail-loader 'import-error
                              "Import expected library ~A but ~A declared itself."
                              expected-name name))
               (when (and expected-version (not (string= version expected-version)))
                 (fail-loader 'import-error
                              "Import ~A expected version ~A but received ~A."
                              name expected-version version))
               (let* ((key (library-key name version))
                      (existing (gethash key seen)))
                 (when (gethash key active)
                   (fail-import-cycle key origin))
                 (when expected-digest
                   (unless (string= actual-digest
                                    (normalize-digest expected-digest))
                     (fail-loader 'digest-error
                                  "Digest mismatch for imported library ~A."
                                  source)))
                 (when existing
                   (unless (string= (library-node-digest existing) actual-digest)
                     (fail-loader 'import-error
                                  "Library ~A was resolved with conflicting digests."
                                  key))
                   (return-from load-library existing))
                 (setf (gethash key active) t)
                 (let* ((*loader-active-chain*
                          (append *loader-active-chain*
                                  (list (cons key
                                              (and origin
                                                   (star-lang.core-surface.prototype:star-origin-frame-import-site-span
                                                    origin))))))
                        (imports
                          (mapcar
                           (lambda (declaration)
                             (with-loader-syntax (declaration)
                               (resolve-import
                                (parse-import-declaration declaration)
                                path name version actual-digest
                                (star-lang.core-surface.prototype:star-syntax-origin
                                 form))))
                           (raw-import-declarations form)))
                        (macro-environment
                          (apply
                           #'star-lang.core-surface.prototype:merge-star-macro-environments
                           (mapcar #'library-macro-environment imports)))
                        (compiled (compile-library-form form macro-environment))
                        (node (make-library-node
                               :name name
                               :version version
                               :digest actual-digest
                               :source source
                               :cache-path path
                               :form form
                               :compiled compiled
                               :imports imports
                               :source-map
                               (star-lang.core-surface.prototype:star-syntax-source-map
                                form))))
                   (remhash key active)
                   (setf (gethash key seen) node)
                   (push node ordered)
                   node)))))
         (resolve-import (import parent-path parent-name parent-version
                                 parent-digest parent-origin)
           (let ((url (getf import :url))
                 (path (getf import :path))
                 (digest (getf import :digest))
                 (origin (import-origin import parent-name parent-version
                                        parent-digest parent-origin)))
             (cond
               (url
                (unless allow-network
                  (let ((cached (digest-cache-path cache digest)))
                    (unless (probe-file cached)
                      (fail-loader 'network-disabled-error
                                   "Remote import ~A is not cached; rerun with network imports enabled."
                                   url))))
                (let ((cached
                        (if allow-network
                            (fetch-url-to-cache
                             url digest cache maximum-source-bytes)
                            (let ((cached-path
                                    (digest-cache-path cache digest)))
                              (unless (probe-file cached-path)
                                (fail-loader 'network-disabled-error
                                             "Remote import ~A is not cached."
                                             url))
                              (verify-file-digest cached-path digest)
                              cached-path))))
                  (load-library cached
                                url
                                (getf import :name)
                                (getf import :version)
                                digest
                                origin)))
               (path
                (let ((resolved (resolve-local-import-path path parent-path)))
                  (load-library resolved
                                (namestring resolved)
                                (getf import :name)
                                (getf import :version)
                                digest
                                origin)))
               (t
                (fail-loader 'import-error "Unreachable import state."))))))
      (let* ((root-path (truename pathname))
             (root (load-library root-path
                                 (namestring root-path)
                                 nil nil nil nil)))
        (make-loaded-graph
         :root root
         :libraries (nreverse ordered)
         :cache-directory cache)))))

(defun load-star-url (url
                      &key
                        name
                        version
                        digest
                        (allow-network nil)
                        (cache-directory (default-cache-directory))
                        (maximum-source-bytes *maximum-source-bytes*)
                        limits)
  (unless (and name version digest)
    (fail-loader 'import-error
                 "Loading a root URL requires :name, :version, and :digest."))
  (unless (url-p url)
    (fail-loader 'import-error
                 "Root URL ~S must use https://."
                 url))
  (let* ((cache (ensure-cache-directory cache-directory))
         (normalized (normalize-digest digest))
         (cached (digest-cache-path cache normalized)))
    (setf cached
          (if allow-network
              (fetch-url-to-cache
               url normalized cache maximum-source-bytes)
              (progn
                (unless (probe-file cached)
                  (fail-loader 'network-disabled-error
                               "Root URL ~A is not cached; enable network loading."
                               url))
                (verify-file-digest cached normalized)
                cached)))
    (let ((graph (load-star-file
                  cached
                  :allow-network allow-network
                  :cache-directory cache
                  :maximum-source-bytes maximum-source-bytes
                  :limits limits)))
      (let ((root (loaded-graph-root graph)))
        (unless (and (string= name (library-node-name root))
                     (string= version (library-node-version root))
                     (string= normalized (library-node-digest root)))
          (fail-loader 'import-error
                       "Root URL identity did not match the requested library lock.")))
      graph)))

(defun load-star (source &rest arguments &key &allow-other-keys)
  (if (url-p source)
      (apply #'load-star-url source arguments)
      (apply #'load-star-file source arguments)))

(defun library-node-summary (node)
  (list :name (library-node-name node)
        :version (library-node-version node)
        :digest (library-node-digest node)
        :source (library-node-source node)
        :imports
        (mapcar (lambda (imported)
                  (library-key
                   (library-node-name imported)
                   (library-node-version imported)))
                (library-node-imports node))))

(defun write-loaded-graph (graph stream)
  (with-standard-io-syntax
    (let ((*print-pretty* t)
          (*print-circle* nil))
      (write
       (list :root
             (library-key
              (library-node-name (loaded-graph-root graph))
              (library-node-version (loaded-graph-root graph)))
             :cache-directory
             (namestring (loaded-graph-cache-directory graph))
             :libraries
             (mapcar #'library-node-summary
                     (loaded-graph-libraries graph)))
       :stream stream)
      (terpri stream)))
  graph)

(defun print-loaded-graph (graph &optional (stream *standard-output*))
  (format stream "Loaded ~A version ~A.~%"
          (library-node-name (loaded-graph-root graph))
          (library-node-version (loaded-graph-root graph)))
  (format stream "Resolved ~D specification librar~:@P.~%"
          (length (loaded-graph-libraries graph)))
  (dolist (node (loaded-graph-libraries graph))
    (format stream "  ~A ~A  ~A~%"
            (library-node-name node)
            (library-node-version node)
            (library-node-digest node)))
  graph)
