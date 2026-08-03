(require :asdf)

(load (merge-pathnames "star-loader.lisp" *load-truename*))

(in-package #:star-lang.loader)

(define-condition loader-test-error (error)
  ((message :initarg :message :reader loader-test-error-message))
  (:report (lambda (condition stream)
             (write-string (loader-test-error-message condition) stream))))

(defun fail-test (control &rest arguments)
  (error 'loader-test-error :message (apply #'format nil control arguments)))

(defun assert-true (value label)
  (unless value
    (fail-test "Assertion failed: ~A." label))
  value)

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail-test "~A expected ~S, received ~S." label expected actual))
  actual)

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun captured-loader-condition (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          caught
          (error caught)))))

(defun temporary-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "star-loader-tests-~36R-~36R/"
                   (get-universal-time)
                   (random most-positive-fixnum))
           (uiop:temporary-directory))))
    (ensure-directories-exist
     (merge-pathnames #P".keep" directory))
    directory))

(defun write-text-file (pathname content)
  (ensure-directories-exist pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string content stream))
  pathname)

(defun declarations-of-kind (library kind)
  (remove-if-not
   (lambda (declaration)
     (eq (getf declaration :kind) kind))
   (getf library :declarations)))

(defun find-document (library name)
  (find name
        (declarations-of-kind library :document)
        :key (lambda (document) (getf document :name))
        :test #'string=))

(defun find-field (document name)
  (find name
        (getf document :fields)
        :key (lambda (field) (getf field :name))
        :test #'string=))

(defun test-starintel-schema ()
  (let* ((fixture
           (merge-pathnames
            "../fixtures/starintel-core.star"
            *load-truename*))
         (cache (temporary-test-directory)))
    (unwind-protect
         (let* ((graph
                  (load-star-file
                   fixture
                   :cache-directory cache))
                (library
                  (library-node-compiled
                   (loaded-graph-root graph)))
                (document (find-document library "document"))
                (expected
                  '("document" "person" "org" "relation" "domain"
                    "service" "port" "network" "asn" "host" "url"
                    "breach" "email" "email-message" "user" "phone"
                    "geo" "address" "message" "socialmpost" "target"
                    "actor-manifest" "artifact" "finding" "scope")))
           (assert-equal "org.starintel/core@1"
                         (library-node-name (loaded-graph-root graph))
                         "root library name")
           (assert-equal 1
                         (length (loaded-graph-libraries graph))
                         "single local library")
           (dolist (name expected)
             (assert-true
              (find-document library name)
              (format nil "ported document ~A" name)))
           (dolist (field
                    '("id" "dataset" "dtype" "schemaVersion"
                      "sources" "sourceUrls" "collectedAt"
                      "observedAt" "confidence" "provenance"
                      "chainOfCustody" "labels" "tags"
                      "sensitivity" "visibility" "contentHash"
                      "raw" "extensions"))
             (assert-true
              (find-field document field)
              (format nil "base metadata field ~A" field))))
      (uiop:delete-directory-tree
       cache
       :validate t
       :if-does-not-exist :ignore))))

(defun test-local-import-and-cache ()
  (let* ((directory (temporary-test-directory))
         (cache (merge-pathnames #P"cache/" directory))
         (dependency (merge-pathnames #P"dependency.star" directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            dependency
            "(spec-library \"test/dependency@1\"
  (:version \"1.0.0\")
  (document item
    (:persistence persistent)
    (id string :required)))
")
           (let ((digest (sha256-file dependency)))
             (write-text-file
              root
              (format nil
                      "(spec-library \"test/root@1\"
  (:version \"1.0.0\")
  (import \"test/dependency@1\"
    :version \"1.0.0\"
    :digest ~S
    :path \"dependency.star\")
  (document root-item
    (:persistence persistent)
    (id string :required)))
"
                      digest))
             (let ((graph
                     (load-star-file
                      root
                      :cache-directory cache)))
               (assert-equal
                2
                (length (loaded-graph-libraries graph))
                "local import graph size")
               (assert-equal
                "test/root@1"
                (library-node-name (loaded-graph-root graph))
                "local import root")
               (assert-equal
                "test/dependency@1"
                (library-node-name
                 (first
                  (library-node-imports
                   (loaded-graph-root graph))))
                "local dependency identity"))))
      (uiop:delete-directory-tree
       directory
       :validate t
       :if-does-not-exist :ignore))))

(defun test-bad-digest-rejected ()
  (let* ((directory (temporary-test-directory))
         (dependency (merge-pathnames #P"dependency.star" directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            dependency
            "(spec-library \"test/dependency@1\"
  (:version \"1.0.0\")
  (document item
    (:persistence persistent)
    (id string :required)))
")
           (write-text-file
            root
            "(spec-library \"test/root@1\"
  (:version \"1.0.0\")
  (import \"test/dependency@1\"
    :version \"1.0.0\"
    :digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"
    :path \"dependency.star\")
  (document root-item
    (:persistence persistent)
    (id string :required)))
")
           (assert-true
            (condition-signaled-p
             'digest-error
             (lambda ()
               (load-star-file
                root
                :cache-directory
                (merge-pathnames #P"cache/" directory))))
            "bad local import digest rejected"))
      (uiop:delete-directory-tree
       directory
       :validate t
       :if-does-not-exist :ignore))))

(defun test-nested-import-origin-chain ()
  (let* ((directory (temporary-test-directory))
         (cache (merge-pathnames #P"cache/" directory))
         (leaf (merge-pathnames #P"leaf.star" directory))
         (middle (merge-pathnames #P"middle.star" directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            leaf
            "(spec-library \"test/leaf@1\" (:version \"1.0.0\") (enum State (Ready)))")
           (let ((leaf-digest (sha256-file leaf)))
             (write-text-file
              middle
              (format nil
                      "(spec-library \"test/middle@1\" (:version \"1.0.0\") (import \"test/leaf@1\" :version \"1.0.0\" :digest ~S :path \"leaf.star\"))"
                      leaf-digest)))
           (let ((middle-digest (sha256-file middle)))
             (write-text-file
              root
              (format nil
                      "(spec-library \"test/root@1\" (:version \"1.0.0\") (import \"test/middle@1\" :version \"1.0.0\" :digest ~S :path \"middle.star\"))"
                      middle-digest))
             (let* ((root-digest (sha256-file root))
                    (graph (load-star-file root :cache-directory cache))
                    (leaf-node
                      (find "test/leaf@1"
                            (loaded-graph-libraries graph)
                            :key #'library-node-name
                            :test #'string=))
                    (leaf-syntax (library-node-form leaf-node))
                    (span
                      (star-lang.core-surface.prototype:star-syntax-span
                       leaf-syntax))
                    (chain
                      (star-lang.core-surface.prototype:star-origin-chain
                       (star-lang.core-surface.prototype:star-syntax-origin
                        leaf-syntax))))
               (assert-true leaf-node "nested leaf loaded")
               (assert-equal (namestring (truename leaf))
                             (star-lang.core-surface.prototype:star-source-span-source-id
                              span)
                             "leaf retains own source span")
               (assert-equal '(nil "test/root@1" "test/middle@1")
                             (mapcar (lambda (frame)
                                       (getf frame :library-name))
                                     chain)
                             "ordered import-origin libraries")
               (assert-equal root-digest
                             (getf (second chain) :library-digest)
                             "root import frame digest")
               (assert-equal middle-digest
                             (getf (third chain) :library-digest)
                             "middle import frame digest")
               (assert-true (getf (second chain) :import-site)
                            "root import site retained")
               (assert-true (getf (third chain) :import-site)
                            "middle import site retained"))))
      (uiop:delete-directory-tree
       directory
       :validate t
       :if-does-not-exist :ignore))))

(defun test-import-cycle-diagnostic-chain ()
  (let* ((syntax
           (star-lang.core-surface.prototype:read-star-syntax
            "(import \"test/a@1\" :version \"1\" :digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\" :path \"a.star\")"
            :source-id "cycle"))
         (span
           (star-lang.core-surface.prototype:star-syntax-span syntax))
         (source-origin
           (star-lang.core-surface.prototype:star-syntax-origin syntax))
         (origin
           (star-lang.core-surface.prototype:make-star-origin-frame
            :kind :import
            :source-id "cycle"
            :library-name "test/b@1"
            :library-version "1"
            :library-digest
            "sha256:0000000000000000000000000000000000000000000000000000000000000000"
            :import-site-span span
            :parent source-origin))
         (*loader-active-chain*
           (list (cons "test/a@1@1" span)
                 (cons "test/b@1@1" span)))
         (*loader-current-syntax* syntax)
         (condition
           (captured-loader-condition
            'import-error
            (lambda () (fail-import-cycle "test/a@1@1" origin)))))
    (assert-equal :import-cycle (loader-error-code condition)
                  "cycle diagnostic code")
    (assert-equal '("test/a@1@1" "test/b@1@1" "test/a@1@1")
                  (getf (loader-error-details condition) :ordered-chain)
                  "ordered cycle chain")
    (assert-equal 3 (length (loader-error-related-spans condition))
                  "cycle import-site spans")))

(defun test-network-disabled-before-fetch ()
  (let* ((directory (temporary-test-directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            root
            "(spec-library \"test/root@1\"
  (:version \"1.0.0\")
  (import \"test/remote@1\"
    :version \"1.0.0\"
    :digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"
    :url \"https://example.invalid/remote.star\")
  (document root-item
    (:persistence persistent)
    (id string :required)))
")
           (assert-true
            (condition-signaled-p
             'network-disabled-error
             (lambda ()
               (load-star-file
                root
                :cache-directory
                (merge-pathnames #P"cache/" directory))))
            "network imports require explicit enablement"))
      (uiop:delete-directory-tree
       directory
       :validate t
       :if-does-not-exist :ignore))))

(defun test-http-import-rejected ()
  (assert-true
   (condition-signaled-p
    'import-error
    (lambda ()
      (parse-import-declaration
       (star-lang.core-surface.prototype:read-star-syntax
        "(import \"test/remote@1\"
           :version \"1.0.0\"
           :digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"
           :url \"http://example.test/remote.star\")"))))
   "plain HTTP imports rejected"))

(defun test-http-root-url-rejected ()
  (assert-true
   (condition-signaled-p
    'import-error
    (lambda ()
      (load-star-url
       "http://example.test/root.star"
       :name "test/root@1"
       :version "1.0.0"
       :digest "sha256:0000000000000000000000000000000000000000000000000000000000000000")))
   "plain HTTP root URLs rejected"))

(defun test-dispatch-reader-rejected ()
  (assert-true
   (condition-signaled-p
    'star-lang.core-surface.prototype:star-lang-source-error
    (lambda ()
      (star-lang.core-surface.prototype:read-star-syntax
       "(spec-library \"bad@1\" (:version \"1\") #.(error \"boom\"))"
       :source-id "reader-test")))
   "dispatch reader syntax rejected"))

(defun test-locked-imported-macro-expansion ()
  (let* ((directory (temporary-test-directory))
         (macro-library (merge-pathnames #P"macro-library.star" directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            macro-library
            "(spec-library \"test/macros@1\" (:version \"1.0.0\")
               (macro make-ping
                 (:context declaration
                  :rules (((make-ping ?name)
                           (message ?name (:fields ())))))))")
           (let ((digest (sha256-file macro-library)))
             (write-text-file
              root
              (format nil
                      "(spec-library \"test/root@1\" (:version \"1.0.0\")
                         (import \"test/macros@1\"
                           :version \"1.0.0\"
                           :digest ~S
                           :path \"macro-library.star\")
                         (make-ping ping))"
                      digest))
             (let* ((graph
                      (load-star-file
                       root :cache-directory
                       (merge-pathnames #P"cache/" directory)))
                    (compiled
                      (library-node-compiled (loaded-graph-root graph)))
                    (message
                      (first (declarations-of-kind compiled :message))))
               (assert-equal "ping" (getf message :name)
                             "locked imported macro expands through loader")
               (assert-equal 2 (length (loaded-graph-libraries graph))
                             "macro library participates in locked graph"))))
      (uiop:delete-directory-tree
       directory :validate t :if-does-not-exist :ignore))))

(defun run-tests ()
  (test-starintel-schema)
  (test-local-import-and-cache)
  (test-nested-import-origin-chain)
  (test-import-cycle-diagnostic-chain)
  (test-bad-digest-rejected)
  (test-network-disabled-before-fetch)
  (test-http-import-rejected)
  (test-http-root-url-rejected)
  (test-dispatch-reader-rejected)
  (test-locked-imported-macro-expansion)
  (format t "Star-Lang .star loader tests passed.~%")
  t)

(unless (run-tests)
  (error "Star-Lang loader tests failed."))
