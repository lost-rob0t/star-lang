;;;; Final StarLang compiler core: closed .star parser, syntax model,
;;;; expansion boundary, grammar validation, and specification lowering.
;;;; Moved verbatim from prototype/core-surface-prototype.lisp; that file is
;;;; now a compatibility re-export shell over this package.

(defpackage #:star-lang.compiler.core
  (:use #:cl)
  (:nicknames #:star-lang.core)
  (:export
   ;; Pipeline entry points and constants.
   #:compile-actor
   #:compile-actor-source
   #:compile-spec-library
   #:compile-star-core
   #:emit-portable-manifest
   #:emit-a2a-agent-card
   #:a2a-actor-p
   #:valid-a2a-interface-url-p
   #:+a2a-actor-protocol+
   #:+a2a-wire-version+
   #:+normalized-ir-schema+
   #:+normalized-ir-version+
   #:expand-star-syntax
   #:load-star-form
   #:portable-actor
   #:read-star-syntax
   #:trusted-form-to-star-syntax
   #:validate-star-core
   #:declarations-of-kind
   ;; Syntax model and spans.
   #:make-star-origin-frame
   #:make-star-parser-limits
   #:make-star-syntax
   #:star-origin-chain
   #:star-origin-frame
   #:star-origin-frame-import-site-span
   #:star-origin-frame-kind
   #:star-origin-frame-library-digest
   #:star-origin-frame-library-name
   #:star-origin-frame-library-version
   #:star-origin-frame-parent
   #:star-origin-frame-source-id
   #:star-origin-frame-definition-span
   #:star-origin-frame-expansion-ordinal
   #:star-origin-frame-invocation-span
   #:star-origin-frame-macro-name
   #:star-origin-frame-output-context
   #:star-origin-frame-rule-id
   #:star-parser-limits
   #:star-parser-limits-p
   #:star-parser-limits-collection-length
   #:star-parser-limits-nesting-depth
   #:star-parser-limits-node-count
   #:star-parser-limits-numeric-literal-bytes
   #:star-parser-limits-numeric-magnitude
   #:star-parser-limits-source-bytes
   #:star-parser-limits-string-bytes
   #:star-parser-limits-token-bytes
   #:star-source-span
   #:star-source-span-end-byte
   #:star-source-span-end-column
   #:star-source-span-end-line
   #:star-source-span-pathname
   #:star-source-span-source-id
   #:star-source-span-start-byte
   #:star-source-span-start-column
   #:star-source-span-start-line
   #:star-source-span-map
   #:star-syntax
   #:star-syntax-children
   #:star-syntax-datum
   #:star-syntax-introduced-by
   #:star-syntax-kind
   #:star-syntax-origin
   #:star-syntax-p
   #:star-syntax-scopes
   #:star-syntax-span
   #:star-syntax-source-map
   #:star-syntax-expansion-trace
   #:star-syntax-macro-dependencies
   #:star-syntax-to-datum
   ;; Conditions and diagnostics.
   #:star-lang-core-error
   #:star-lang-core-error-code
   #:star-lang-core-error-column
   #:star-lang-core-error-details
   #:star-lang-core-error-line
   #:star-lang-core-error-message
   #:star-lang-core-error-origin
   #:star-lang-core-error-pathname
   #:star-lang-core-error-phase
   #:star-lang-core-error-related-spans
   #:star-lang-core-error-span
   #:star-lang-core-error-syntax-kind
   #:star-lang-source-error
   ;; Shared compiler helpers used by compatibility composition files.
   #:declaration-kind
   #:declaration-name
   #:declared-local-types
   #:digest-p
   #:ensure-plist
   #:ensure-unique-declarations
   #:ensure-unique-fields
   #:ensure-unique-library-names
   #:ensure-unique-local-types
   #:fail
   #:field-key-string
   #:identifier-key
   #:identifier-string
   #:lower-camel-field-name-p
   #:normalize-mailbox
   #:normalize-persistence
   #:normalize-restart
   #:normalize-runtime
   #:normalize-type-expression
   #:optional-option
   #:plist-elements
   #:plist-has-key-p
   #:qualified-name-p
   #:qualify-name
   #:require-lower-camel-field-name
   #:required-option
   #:star-lang-source-error
   #:syntax-atom
   #:syntax-elements
   #:syntax-head-name
   #:syntax-list-p
   #:with-star-source-position
   #:*star-current-phase*
   #:*star-current-syntax*
   #:invalid-actor-error
   #:invalid-declaration-error
   #:invalid-envelope-error
   #:invalid-field-error
   #:invalid-library-error
   #:invalid-star-service-uri-error
   #:invalid-type-error
   #:unsupported-macro-error
   #:test-error))

(in-package #:star-lang.compiler.core)

(defconstant +normalized-ir-version+ 2)
(defparameter +normalized-ir-schema+ "org.star-lang/normalized-ir@2")

(defstruct star-source-span
  source-id
  pathname
  start-byte
  end-byte
  start-line
  start-column
  end-line
  end-column)

(defstruct star-origin-frame
  kind
  source-id
  library-name
  library-version
  library-digest
  import-site-span
  macro-name
  rule-id
  definition-span
  invocation-span
  expansion-ordinal
  output-context
  parent)

(defstruct star-syntax
  kind
  datum
  children
  span
  (scopes nil)
  origin
  introduced-by
  expansion-trace
  macro-dependencies)

(defstruct (star-parser-limits
             (:constructor make-star-parser-limits
                 (&key
                    (source-bytes (* 16 1024 1024))
                    (nesting-depth 128)
                    (node-count 100000)
                    (token-bytes 65536)
                    (string-bytes (* 4 1024 1024))
                    (collection-length 100000)
                    (numeric-literal-bytes 1024)
                    (numeric-magnitude (1- (expt 10 100))))))
  source-bytes
  nesting-depth
  node-count
  token-bytes
  string-bytes
  collection-length
  numeric-literal-bytes
  numeric-magnitude)

(defvar *star-source-pathname* nil)
(defvar *star-source-line* nil)
(defvar *star-source-column* nil)
(defvar *star-current-syntax* nil)
(defvar *star-current-phase* nil)

(define-condition star-lang-core-error (error)
  ((message :initarg :message :reader star-lang-core-error-message)
   (code :initarg :code :initform :star-lang-error
         :reader star-lang-core-error-code)
   (span :initarg :span :initform nil :reader star-lang-core-error-span)
   (origin :initarg :origin :initform nil :reader star-lang-core-error-origin)
   (syntax-kind :initarg :syntax-kind :initform nil
                :reader star-lang-core-error-syntax-kind)
   (related-spans :initarg :related-spans :initform nil
                  :reader star-lang-core-error-related-spans)
   (phase :initarg :phase :initform *star-current-phase*
          :reader star-lang-core-error-phase)
   (details :initarg :details :initform nil
            :reader star-lang-core-error-details)
   (pathname
    :initarg :pathname
    :initform *star-source-pathname*
    :reader star-lang-core-error-legacy-pathname)
   (line
    :initarg :line
    :initform *star-source-line*
    :reader star-lang-core-error-legacy-line)
   (column
    :initarg :column
    :initform *star-source-column*
    :reader star-lang-core-error-legacy-column))
  (:report (lambda (condition stream)
             (let ((pathname (star-lang-core-error-pathname condition))
                   (line (star-lang-core-error-line condition))
                   (column (star-lang-core-error-column condition)))
               (when pathname
                 (format stream "~A" pathname)
                 (when line
                   (format stream ":~D" line)
                   (when column
                     (format stream ":~D" column)))
                 (write-string ": " stream))
               (write-string
                (star-lang-core-error-message condition)
                stream)))))

(defun star-lang-core-error-pathname (condition)
  (let ((span (star-lang-core-error-span condition)))
    (if span
        (star-source-span-pathname span)
        (star-lang-core-error-legacy-pathname condition))))

(defun star-lang-core-error-line (condition)
  (let ((span (star-lang-core-error-span condition)))
    (if span
        (star-source-span-start-line span)
        (star-lang-core-error-legacy-line condition))))

(defun star-lang-core-error-column (condition)
  (let ((span (star-lang-core-error-span condition)))
    (if span
        (star-source-span-start-column span)
        (star-lang-core-error-legacy-column condition))))