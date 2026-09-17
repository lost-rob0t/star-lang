;;;; Final digest-locked StarLang loader.
;;;; Compiler policy remains pure; concrete filesystem/hash/HTTPS effects live
;;;; here and can be replaced through STAR-LANG.LOADER.EFFECTS.

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
(defvar *loader-current-syntax* nil)
(defvar *loader-active-chain* nil)

(defun fail-loader (condition-type control &rest arguments)
  (let ((syntax *loader-current-syntax*))
    (error condition-type
           :message (apply #'format nil control arguments)
           :primary-span
           (and syntax
                (star-lang.compiler.core:star-syntax-span syntax))
           :origin-chain
           (and syntax
                (star-lang.compiler.core:star-origin-chain
                 (star-lang.compiler.core:star-syntax-origin syntax)))
           :phase :resolve)))

(defmacro with-loader-syntax ((syntax) &body body)
  `(let ((*loader-current-syntax* ,syntax)) ,@body))

(defun string-prefix-p (prefix value)
  (and (stringp value)
       (<= (length prefix) (length value))
       (string= prefix value :end2 (length prefix))))

(defun https-url-p (value)
  (and (stringp value)
       (handler-case
           (string-equal "https" (quri:uri-scheme (quri:uri value)))
         (error () nil))))

(defun normalize-digest (value)
  (unless (starlangcompiler:full-sha256-digest-p value)
    (fail-loader 'digest-error
                 "Expected a full sha256:<64 hex digits> digest, received ~S."
                 value))
  (string-downcase value))

(defun default-cache-directory ()
  (merge-pathnames #P".cache/star-lang/specs/" (user-homedir-pathname)))

(defun ensure-cache-directory (pathname)
  (let ((directory (uiop:ensure-directory-pathname pathname)))
    (ensure-directories-exist (merge-pathnames #P".keep" directory))
    directory))

(defun source-byte-length (pathname)
  (with-open-file (stream pathname
                          :direction :input
                          :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun ensure-source-size (pathname maximum-source-bytes)
  (let ((size (source-byte-length pathname)))
    (when (> size maximum-source-bytes)
      (fail-loader 'source-error
                   "Star source ~A is ~D bytes; configured limit is ~D."
                   pathname size maximum-source-bytes))
    size))

(defun parser-limits-with-source-limit (limits maximum-source-bytes)
  (let ((base (or limits
                  (star-lang.compiler.core:make-star-parser-limits))))
    (star-lang.compiler.core:make-star-parser-limits
     :source-bytes maximum-source-bytes
     :nesting-depth
     (star-lang.compiler.core:star-parser-limits-nesting-depth base)
     :node-count
     (star-lang.compiler.core:star-parser-limits-node-count base)
     :token-bytes
     (star-lang.compiler.core:star-parser-limits-token-bytes base)
     :string-bytes
     (star-lang.compiler.core:star-parser-limits-string-bytes base)
     :collection-length
     (star-lang.compiler.core:star-parser-limits-collection-length base)
     :numeric-literal-bytes
     (star-lang.compiler.core:star-parser-limits-numeric-literal-bytes base)
     :numeric-magnitude
     (star-lang.compiler.core:star-parser-limits-numeric-magnitude base))))

(defun read-star-file (pathname limits origin)
  (let ((path (truename pathname)))
    (with-open-file (stream path
                            :direction :input
                            :element-type '(unsigned-byte 8))
      (let* ((length (file-length stream))
             (buffer (make-array length :element-type '(unsigned-byte 8))))
        (when (> length
                 (star-lang.compiler.core:star-parser-limits-source-bytes limits))
          (fail-loader 'source-error
                       "Star source ~A exceeds the configured byte limit."
                       path))
        (unless (= (read-sequence buffer stream) length)
          (fail-loader 'source-error
                       "Star source ~A changed while being read." path))
        (starlangcompiler:read-star-syntax
         buffer
         :source-id (namestring path)
         :pathname path
         :origin origin
         :limits limits)))))

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
    (star-lang.compiler.core:star-syntax
     (identifier-string
      (star-lang.compiler.core:star-syntax-datum value)))))

(defun loader-elements (syntax)
  (unless (and (star-lang.compiler.core:star-syntax-p syntax)
               (eq (star-lang.compiler.core:star-syntax-kind syntax) :list))
    (fail-loader 'source-error "Expected a StarLang list."))
  (star-lang.compiler.core:star-syntax-children syntax))

(defun declaration-kind (form)
  (let ((elements (loader-elements form)))
    (unless elements
      (fail-loader 'source-error "Invalid empty Star declaration."))
    (string-downcase (identifier-string (first elements)))))

(defun parse-library-header (form)
  (unless (and (star-lang.compiler.core:star-syntax-p form)
               (>= (length (loader-elements form)) 3)
               (string= (declaration-kind form) "spec-library"))
    (fail-loader 'source-error "Expected one spec-library form."))
  (destructuring-bind (operator name options &rest declarations)
      (loader-elements form)
    (declare (ignore operator declarations))
    (let ((name-datum (star-lang.compiler.core:star-syntax-datum name))
          (option-data (star-lang.compiler.core:star-syntax-to-datum options)))
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
    (destructuring-bind (operator name &rest options)
        (loader-elements declaration)
      (declare (ignore operator))
      (let* ((name-datum (star-lang.compiler.core:star-syntax-datum name))
             (option-data
               (mapcar #'star-lang.compiler.core:star-syntax-to-datum options)))
        (unless (and (stringp name-datum) (evenp (length option-data)))
          (fail-loader 'import-error "Invalid import declaration."))
        (let* ((version (require-option option-data :version "import"))
               (digest (normalize-digest
                        (require-option option-data :digest "import")))
               (url (getf option-data :url))
               (path (getf option-data :path)))
          (unless (stringp version)
            (fail-loader 'import-error
                         "Import ~A requires a string version." name-datum))
          (when (and url path)
            (fail-loader 'import-error
                         "Import ~A cannot declare both :url and :path."
                         name-datum))
          (unless (or url path)
            (fail-loader 'import-error
                         "Import ~A requires either :url or :path."
                         name-datum))
          (when (and url (not (https-url-p url)))
            (fail-loader 'import-error
                         "Import URL ~S must use https://." url))
          (when (and path (not (stringp path)))
            (fail-loader 'import-error "Import path must be a string."))
          (list :name name-datum
                :version version
                :digest digest
                :url url
                :path path
                :syntax declaration))))))

(defun ironclad-sha256-file (pathname)
  (let* ((digester (ironclad:make-digest :sha256))
         (digest (ironclad:digest-file digester pathname)))
    (format nil "sha256:~A"
            (string-downcase
             (ironclad:byte-array-to-hex-string digest)))))

(defun redirect-status-p (status)
  (member status '(301 302 303 307 308)))

(defun native-fetch-to-file
    (url destination
     &key maximum-bytes (maximum-redirects 5) (connect-timeout 10)
       (read-timeout 10) (deadline 60) proxy)
  "Fetch URL to DESTINATION without shelling out. Every hop must remain HTTPS."
  (unless (https-url-p url)
    (error "Resolver fetch requires https://, received ~S." url))
  (labels ((fetch-hop (current redirects-left)
             (multiple-value-bind (body status headers final-uri)
                 (dex:get current
                          :force-binary t
                          :max-redirects 0
                          :connect-timeout connect-timeout
                          :read-timeout (min read-timeout deadline)
                          :proxy proxy)
               (declare (ignore final-uri))
               (cond
                 ((redirect-status-p status)
                  (when (zerop redirects-left)
                    (error "HTTPS redirect limit exceeded for ~A." url))
                  (let ((location (gethash "location" headers)))
                    (unless location
                      (error "HTTP ~D response from ~A omitted Location."
                             status current))
                    (let* ((next-uri
                             (quri:merge-uris (quri:uri location)
                                              (quri:uri current)))
                           (next (quri:render-uri next-uri)))
                      (unless (https-url-p next)
                        (error "Resolver refused non-HTTPS redirect ~A." next))
                      (fetch-hop next (1- redirects-left)))))
                 ((and (<= 200 status) (< status 300))
                  (unless (typep body '(array (unsigned-byte 8) (*)))
                    (error "Resolver expected a binary response from ~A." current))
                  (when (and maximum-bytes (> (length body) maximum-bytes))
                    (error "Remote Star source exceeds ~D bytes." maximum-bytes))
                  (with-open-file (stream destination
                                          :direction :output
                                          :if-exists :supersede
                                          :if-does-not-exist :create
                                          :element-type '(unsigned-byte 8))
                    (write-sequence body stream))
                  (list :requested-uri url
                        :final-uri current
                        :bytes (length body)))
                 (t
                  (error "Unexpected HTTP status ~D for ~A." status current))))))
    (fetch-hop url maximum-redirects)))

(defun make-native-resolver-effects ()
  (star-lang.loader.effects:make-resolver-effects
   :digest-file #'ironclad-sha256-file
   :fetch-to-file #'native-fetch-to-file))

(defvar *resolver-effects* (make-native-resolver-effects))

(defun sha256-file (pathname &optional (effects *resolver-effects*))
  (handler-case
      (normalize-digest
       (star-lang.loader.effects:digest-file-through-effects effects pathname))
    (loader-error (condition) (error condition))
    (error (condition)
      (fail-loader 'dependency-error
                   "SHA-256 calculation failed through resolver effects: ~A"
                   condition))))

(defun verify-file-digest (pathname expected-digest
                            &optional (effects *resolver-effects*))
  (let ((actual (sha256-file pathname effects))
        (expected (normalize-digest expected-digest)))
    (unless (string= actual expected)
      (fail-loader 'digest-error
                   "Digest mismatch for ~A: expected ~A, received ~A."
                   pathname expected actual))
    actual))

(defun digest-cache-path (cache-directory digest)
  (merge-pathnames
   (make-pathname :name (subseq (normalize-digest digest) 7) :type "star")
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

(defun fetch-url-to-cache (url digest cache-directory maximum-source-bytes
                            &optional (effects *resolver-effects*))
  (let* ((cache-path (digest-cache-path cache-directory digest))
         (temporary-path (temporary-cache-path cache-directory digest)))
    (when (probe-file cache-path)
      (handler-case
          (progn
            (ensure-source-size cache-path maximum-source-bytes)
            (verify-file-digest cache-path digest effects)
            (return-from fetch-url-to-cache cache-path))
        (loader-error ()
          (ignore-errors (delete-file cache-path)))))
    (unwind-protect
         (progn
           (handler-case
               (star-lang.loader.effects:fetch-to-file-through-effects
                effects url temporary-path
                :maximum-bytes maximum-source-bytes
                :maximum-redirects 5
                :connect-timeout 10
                :read-timeout 10
                :deadline 60
                :proxy nil)
             (error (condition)
               (fail-loader 'dependency-error
                            "Remote specification fetch failed: ~A" condition)))
           (unless (probe-file temporary-path)
             (fail-loader 'dependency-error
                          "Resolver fetch did not create ~A." temporary-path))
           (ensure-source-size temporary-path maximum-source-bytes)
           (verify-file-digest temporary-path digest effects)
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
      (fail-loader 'import-error "Imported Star file ~A does not exist." resolved))
    (truename resolved)))

(defun library-key (name version)
  (format nil "~A@~A" name version))

(defun compile-library-form (form &optional macro-environment)
  (let ((expanded
          (star-lang.compiler.core:expand-star-syntax
           form :environment macro-environment)))
    (star-lang.compiler.core:validate-star-core expanded)
    (starlangcompiler:validate-library-semantics
     (star-lang.compiler.core:compile-star-core expanded))))

(defun library-macro-environment (node)
  (apply
   #'star-lang.compiler.core:merge-star-macro-environments
   (append
    (mapcar #'library-macro-environment (library-node-imports node))
    (list
     (star-lang.compiler.core:collect-star-macro-environment
      (library-node-form node)
      :library-name (library-node-name node)
      :library-version (library-node-version node)
      :library-digest (library-node-digest node))))))

(defun fail-import-cycle (key origin)
  (let* ((chain (append (mapcar #'car *loader-active-chain*) (list key)))
         (primary
           (or (and *loader-current-syntax*
                    (star-lang.compiler.core:star-syntax-span
                     *loader-current-syntax*))
               (and origin
                    (star-lang.compiler.core:star-origin-frame-import-site-span
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
           :origin-chain (star-lang.compiler.core:star-origin-chain origin)
           :related-spans spans
           :details (list :ordered-chain chain)
           :phase :resolve)))

(defun import-origin (import parent-name parent-version parent-digest parent-origin)
  (let* ((syntax (getf import :syntax))
         (span (star-lang.compiler.core:star-syntax-span syntax)))
    (star-lang.compiler.core:make-star-origin-frame
     :kind :import
     :source-id
     (and span (star-lang.compiler.core:star-source-span-source-id span))
     :library-name parent-name
     :library-version parent-version
     :library-digest parent-digest
     :import-site-span span
     :parent parent-origin)))

(defun load-star-file
    (pathname
     &key (allow-network nil)
       (cache-directory (default-cache-directory))
       (maximum-source-bytes *maximum-source-bytes*)
       limits
       (resolver-effects *resolver-effects*))
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
                  (actual-digest (sha256-file path resolver-effects)))
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
                                  "Library ~A resolved with conflicting digests."
                                  key))
                   (return-from load-library existing))
                 (setf (gethash key active) t)
                 (unwind-protect
                      (let* ((*loader-active-chain*
                               (append *loader-active-chain*
                                       (list
                                        (cons key
                                              (and origin
                                                   (star-lang.compiler.core:star-origin-frame-import-site-span
                                                    origin))))))
                             (imports
                               (mapcar
                                (lambda (declaration)
                                  (with-loader-syntax (declaration)
                                    (resolve-import
                                     (parse-import-declaration declaration)
                                     path name version actual-digest
                                     (star-lang.compiler.core:star-syntax-origin form))))
                                (raw-import-declarations form)))
                             (macro-environment
                               (apply
                                #'star-lang.compiler.core:merge-star-macro-environments
                                (mapcar #'library-macro-environment imports)))
                             (compiled (compile-library-form form macro-environment))
                             (node
                               (make-library-node
                                :name name
                                :version version
                                :digest actual-digest
                                :source source
                                :cache-path path
                                :form form
                                :compiled compiled
                                :imports imports
                                :source-map
                                (star-lang.compiler.core:star-syntax-source-map form))))
                        (setf (gethash key seen) node)
                        (push node ordered)
                        node)
                   (remhash key active)))))))
         (resolve-import (import parent-path parent-name parent-version
                                 parent-digest parent-origin)
           (let ((url (getf import :url))
                 (path (getf import :path))
                 (digest (getf import :digest))
                 (origin (import-origin import parent-name parent-version
                                        parent-digest parent-origin)))
             (cond
               (url
                (let ((cached (digest-cache-path cache digest)))
                  (when (and (not allow-network) (not (probe-file cached)))
                    (fail-loader 'network-disabled-error
                                 "Remote import ~A is not cached; enable network loading."
                                 url)))
                (let ((cached
                        (if allow-network
                            (fetch-url-to-cache
                             url digest cache maximum-source-bytes resolver-effects)
                            (let ((cached-path (digest-cache-path cache digest)))
                              (verify-file-digest cached-path digest resolver-effects)
                              cached-path))))
                  (load-library cached url
                                (getf import :name)
                                (getf import :version)
                                digest origin)))
               (path
                (let ((resolved (resolve-local-import-path path parent-path)))
                  (load-library resolved (namestring resolved)
                                (getf import :name)
                                (getf import :version)
                                digest origin)))
               (t
                (fail-loader 'import-error "Unreachable import state."))))))
      (let* ((root-path (truename pathname))
             (root (load-library root-path (namestring root-path)
                                 nil nil nil nil)))
        (make-loaded-graph
         :root root
         :libraries (nreverse ordered)
         :cache-directory cache)))))

(defun load-star-url
    (url
     &key name version digest (allow-network nil)
       (cache-directory (default-cache-directory))
       (maximum-source-bytes *maximum-source-bytes*)
       limits
       (resolver-effects *resolver-effects*))
  (unless (and name version digest)
    (fail-loader 'import-error
                 "Loading a root URL requires :name, :version, and :digest."))
  (unless (https-url-p url)
    (fail-loader 'import-error "Root URL ~S must use https://." url))
  (let* ((cache (ensure-cache-directory cache-directory))
         (normalized (normalize-digest digest))
         (cached (digest-cache-path cache normalized)))
    (setf cached
          (if allow-network
              (fetch-url-to-cache url normalized cache maximum-source-bytes
                                  resolver-effects)
              (progn
                (unless (probe-file cached)
                  (fail-loader 'network-disabled-error
                               "Root URL ~A is not cached; enable network loading."
                               url))
                (verify-file-digest cached normalized resolver-effects)
                cached)))
    (let ((graph
            (load-star-file cached
                            :allow-network allow-network
                            :cache-directory cache
                            :maximum-source-bytes maximum-source-bytes
                            :limits limits
                            :resolver-effects resolver-effects)))
      (let ((root (loaded-graph-root graph)))
        (unless (and (string= name (library-node-name root))
                     (string= version (library-node-version root))
                     (string= normalized (library-node-digest root)))
          (fail-loader 'import-error
                       "Root URL identity did not match the requested library lock.")))
      graph)))

(defun load-star (source &rest arguments &key &allow-other-keys)
  (if (https-url-p source)
      (apply #'load-star-url source arguments)
      (apply #'load-star-file source arguments)))

(defun library-node-summary (node)
  (list :name (library-node-name node)
        :version (library-node-version node)
        :digest (library-node-digest node)
        :source (library-node-source node)
        :imports
        (mapcar (lambda (imported)
                  (library-key (library-node-name imported)
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
             (mapcar #'library-node-summary (loaded-graph-libraries graph)))
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
