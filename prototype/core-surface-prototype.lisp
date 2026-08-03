(defpackage #:star-lang.core-surface.prototype
  (:use #:cl)
  (:export
   #:bind-actor-runtime
   #:compile-actor
   #:compile-spec-library
   #:emit-portable-manifest
   #:compile-star-core
   #:+normalized-ir-schema+
   #:+normalized-ir-version+
   #:expand-star-syntax
   #:field-key-string
   #:load-star-form
   #:lower-camel-field-name-p
   #:make-star-origin-frame
   #:make-star-parser-limits
   #:make-star-syntax
   #:make-wire-envelope
   #:read-star-syntax
   #:star-origin-chain
   #:star-origin-frame
   #:star-origin-frame-import-site-span
   #:star-origin-frame-kind
   #:star-origin-frame-library-digest
   #:star-origin-frame-library-name
   #:star-origin-frame-library-version
   #:star-origin-frame-parent
   #:star-origin-frame-source-id
   #:star-parser-limits
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
   #:star-syntax-to-datum
   #:trusted-form-to-star-syntax
   #:validate-star-core
   #:star-lang-core-error-code
   #:star-lang-core-error-column
   #:star-lang-core-error-details
   #:star-lang-core-error-line
   #:star-lang-core-error-origin
   #:star-lang-core-error-pathname
   #:star-lang-core-error-phase
   #:star-lang-core-error-related-spans
   #:star-lang-core-error-span
   #:star-lang-core-error-syntax-kind
   #:star-lang-source-error
   #:run-tests
   #:validate-wire-envelope))

(in-package #:star-lang.core-surface.prototype)

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
  parent)

(defstruct star-syntax
  kind
  datum
  children
  span
  (scopes nil)
  origin
  introduced-by)

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

(define-condition star-lang-source-error (star-lang-core-error) ())
(define-condition invalid-library-error (star-lang-core-error) ())
(define-condition invalid-declaration-error (star-lang-core-error) ())
(define-condition invalid-field-error (star-lang-core-error) ())
(define-condition invalid-type-error (star-lang-core-error) ())
(define-condition invalid-actor-error (star-lang-core-error) ())
(define-condition invalid-envelope-error (star-lang-core-error) ())
(define-condition unsupported-macro-error (star-lang-core-error) ())
(define-condition test-error (star-lang-core-error) ())

(defun fail (condition-type control &rest arguments)
  (let ((syntax *star-current-syntax*))
    (error condition-type
           :message (apply #'format nil control arguments)
           :span (and syntax (star-syntax-span syntax))
           :origin (and syntax (star-syntax-origin syntax))
           :syntax-kind (and syntax (star-syntax-kind syntax))
           :phase *star-current-phase*)))

(defmacro with-star-source-position ((value) &body body)
  `(let* ((syntax (and (star-syntax-p ,value) ,value))
          (span (and syntax (star-syntax-span syntax)))
          (*star-current-syntax* (or syntax *star-current-syntax*))
          (*star-source-pathname*
            (if span (star-source-span-pathname span) *star-source-pathname*))
          (*star-source-line*
            (if span (star-source-span-start-line span) *star-source-line*))
          (*star-source-column*
            (if span (star-source-span-start-column span) *star-source-column*)))
     ,@body))

(defun lower-camel-field-name-p (value)
  "Return true when VALUE is an ASCII lower camelCase field name.

Field names start with a lowercase ASCII letter and continue with ASCII
letters or digits. Hyphens, underscores, leading capitals, and other
punctuation are intentionally rejected at the language boundary."
  (and (stringp value)
       (> (length value) 0)
       (char<= #\a (char value 0) #\z)
       (loop for character across value
             always (or (char<= #\a character #\z)
                        (char<= #\A character #\Z)
                        (char<= #\0 character #\9)))))

(defun field-key-string (value)
  "Normalize a host-language string or keyword to a camelCase field key.

This is a compatibility adapter for trusted Common Lisp APIs. Star source is
validated separately and is never silently rewritten."
  (when (stringp value)
    (return-from field-key-string value))
  (let ((name (identifier-string value)))
    (if (lower-camel-field-name-p name)
        name
        (with-output-to-string (stream)
          (loop with uppercase-next = nil
                for character across name
                do (cond
                     ((or (char= character #\-) (char= character #\_))
                      (setf uppercase-next t))
                     (uppercase-next
                      (write-char (char-upcase character) stream)
                      (setf uppercase-next nil))
                     (t (write-char character stream))))))))

(defun require-lower-camel-field-name (syntax)
  (with-star-source-position (syntax)
    (let ((name (identifier-string syntax)))
      (unless (lower-camel-field-name-p name)
        (error 'invalid-field-error
               :message
               (format nil
                       "Field name ~S must use ASCII lower camelCase (for example, messageId)."
                       name)
               :code :invalid-field-name
               :span (and (star-syntax-p syntax) (star-syntax-span syntax))
               :origin (and (star-syntax-p syntax) (star-syntax-origin syntax))
               :syntax-kind (and (star-syntax-p syntax)
                                 (star-syntax-kind syntax))
               :phase *star-current-phase*))
      name)))

(defstruct (star-source-parser
             (:constructor make-star-source-parser
                 (octets source-id pathname origin limits)))
  octets
  source-id
  pathname
  origin
  limits
  (index 0 :type integer)
  (line 1 :type fixnum)
  (column 1 :type fixnum)
  (nodes 0 :type integer))

(defparameter *star-source-keywords*
  '(("algorithm" . :algorithm)
    ("base" . :base)
    ("bbp-domain-v1-research-fixture" . :bbp-domain-v1-research-fixture)
    ("bindings" . :bindings)
    ("constructors" . :constructors)
    ("core-v1-research-fixture" . :core-v1-research-fixture)
    ("dataset" . :dataset)
    ("default" . :default)
    ("destination" . :destination)
    ("digest" . :digest)
    ("document" . :document)
    ("email-domain" . :email-domain)
    ("email-user" . :email-user)
    ("extends" . :extends)
    ("fec-core-v1-research-fixture" . :fec-core-v1-research-fixture)
    ("fields" . :fields)
    ("format" . :format)
    ("generate-default-constructors" . :generate-default-constructors)
    ("id-policy" . :id-policy)
    ("kind" . :kind)
    ("lambda-list" . :lambda-list)
    ("maximum" . :maximum)
    ("minimum" . :minimum)
    ("optional" . :optional)
    ("or" . :or)
    ("path" . :path)
    ("pattern" . :pattern)
    ("persistence" . :persistence)
    ("required" . :required)
    ("rest-keywords" . :rest-keywords)
    ("scale" . :scale)
    ("source" . :source)
    ("space" . :space)
    ("url" . :url)
    ("validate" . :validate)
    ("validator" . :validator)
    ("version" . :version)))

(defun star-source-end-p (parser)
  (>= (star-source-parser-index parser)
      (length (star-source-parser-octets parser))))

(defun utf-8-continuation-p (octet)
  (= (logand octet #xC0) #x80))

(defun malformed-utf-8 (parser start end)
  (let ((span (make-star-source-span
               :source-id (star-source-parser-source-id parser)
               :pathname (star-source-parser-pathname parser)
               :start-byte start
               :end-byte end
               :start-line (star-source-parser-line parser)
               :start-column (star-source-parser-column parser)
               :end-line (star-source-parser-line parser)
               :end-column (1+ (star-source-parser-column parser)))))
    (error 'star-lang-source-error
           :message "Malformed UTF-8 in Star-Lang source."
           :code :malformed-utf-8
           :span span
           :origin (star-source-parser-origin parser)
           :phase :read)))

(defun decode-star-utf-8 (parser)
  (let* ((octets (star-source-parser-octets parser))
         (start (star-source-parser-index parser))
         (length (length octets)))
    (when (< start length)
      (let ((first (aref octets start)))
        (labels ((continuation (offset)
                   (let ((index (+ start offset)))
                     (unless (and (< index length)
                                  (utf-8-continuation-p (aref octets index)))
                       (malformed-utf-8 parser start (min length (1+ index))))
                     (aref octets index)))
                 (finish (code width)
                   (let ((character (code-char code)))
                     (unless character
                       (malformed-utf-8 parser start (+ start width)))
                     (values character (+ start width)))))
          (cond
            ((<= first #x7F)
             (finish first 1))
            ((<= #xC2 first #xDF)
             (finish (logior (ash (logand first #x1F) 6)
                             (logand (continuation 1) #x3F))
                     2))
            ((<= #xE0 first #xEF)
             (let ((second (continuation 1))
                   (third (continuation 2)))
               (when (or (and (= first #xE0) (< second #xA0))
                         (and (= first #xED) (> second #x9F)))
                 (malformed-utf-8 parser start (+ start 3)))
               (finish (logior (ash (logand first #x0F) 12)
                               (ash (logand second #x3F) 6)
                               (logand third #x3F))
                       3)))
            ((<= #xF0 first #xF4)
             (let ((second (continuation 1))
                   (third (continuation 2))
                   (fourth (continuation 3)))
               (when (or (and (= first #xF0) (< second #x90))
                         (and (= first #xF4) (> second #x8F)))
                 (malformed-utf-8 parser start (+ start 4)))
               (finish (logior (ash (logand first #x07) 18)
                               (ash (logand second #x3F) 12)
                               (ash (logand third #x3F) 6)
                               (logand fourth #x3F))
                       4)))
            (t
             (malformed-utf-8 parser start (1+ start)))))))))

(defun star-source-character (parser)
  (decode-star-utf-8 parser))

(defun advance-star-source (parser)
  (multiple-value-bind (character next-index)
      (decode-star-utf-8 parser)
    (when character
      (setf (star-source-parser-index parser) next-index)
      (if (char= character #\Newline)
          (progn
            (incf (star-source-parser-line parser))
            (setf (star-source-parser-column parser) 1))
          (incf (star-source-parser-column parser))))
    character))

(defun parser-span (parser start-byte start-line start-column)
  (make-star-source-span
   :source-id (star-source-parser-source-id parser)
   :pathname (star-source-parser-pathname parser)
   :start-byte start-byte
   :end-byte (star-source-parser-index parser)
   :start-line start-line
   :start-column start-column
   :end-line (star-source-parser-line parser)
   :end-column (star-source-parser-column parser)))

(defun fail-star-source (parser code control &rest arguments)
  (let* ((start (star-source-parser-index parser))
         (span (make-star-source-span
                :source-id (star-source-parser-source-id parser)
                :pathname (star-source-parser-pathname parser)
                :start-byte start
                :end-byte (min (length (star-source-parser-octets parser))
                               (1+ start))
                :start-line (star-source-parser-line parser)
                :start-column (star-source-parser-column parser)
                :end-line (star-source-parser-line parser)
                :end-column (1+ (star-source-parser-column parser)))))
  (error 'star-lang-source-error
         :message (apply #'format nil control arguments)
         :code code
         :span span
         :origin (star-source-parser-origin parser)
         :phase :read)))

(defun star-source-whitespace-p (character)
  (and character
       (find character '(#\Space #\Tab #\Newline #\Return #\Page))))

(defun skip-star-source-trivia (parser)
  (loop
    (cond
      ((star-source-whitespace-p (star-source-character parser))
       (advance-star-source parser))
      ((eql (star-source-character parser) #\;)
       (loop for character = (star-source-character parser)
             while (and character (not (char= character #\Newline)))
             do (advance-star-source parser)))
      (t
       (return parser)))))

(defun star-source-delimiter-p (character)
  (or (null character)
      (star-source-whitespace-p character)
      (find character '(#\( #\) #\" #\;))))

(defun account-star-node (parser span)
  (incf (star-source-parser-nodes parser))
  (when (> (star-source-parser-nodes parser)
           (star-parser-limits-node-count (star-source-parser-limits parser)))
    (error 'star-lang-source-error
           :message "Star source exceeds the configured syntax-node limit."
           :code :node-count-limit
           :span span
           :origin (star-source-parser-origin parser)
           :phase :read)))

(defun make-parsed-star-syntax (parser kind datum children span)
  (account-star-node parser span)
  (make-star-syntax :kind kind
                    :datum datum
                    :children children
                    :span span
                    :scopes nil
                    :origin (star-source-parser-origin parser)))

(defun fail-star-limit (parser code start-byte start-line start-column control
                         &rest arguments)
  (error 'star-lang-source-error
         :message (apply #'format nil control arguments)
         :code code
         :span (parser-span parser start-byte start-line start-column)
         :origin (star-source-parser-origin parser)
         :phase :read))

(defun parse-star-source-string (parser)
  (let ((start-byte (star-source-parser-index parser))
        (start-line (star-source-parser-line parser))
        (start-column (star-source-parser-column parser)))
  (advance-star-source parser)
  (let ((value (make-array 32
                           :element-type 'character
                           :adjustable t
                           :fill-pointer 0)))
    (loop
      (when (star-source-end-p parser)
        (fail-star-source parser :unterminated-string
                          "Unterminated string literal."))
      (let ((character (advance-star-source parser)))
        (cond
          ((char= character #\")
           (let ((span (parser-span parser start-byte start-line start-column)))
             (return (make-parsed-star-syntax parser :string value nil span))))
          ((char= character #\\)
           (when (star-source-end-p parser)
             (fail-star-source parser :unterminated-string-escape
                               "Unterminated string escape."))
           (let ((escaped (advance-star-source parser)))
             (vector-push-extend
              (case escaped
                (#\n #\Newline)
                (#\r #\Return)
                (#\t #\Tab)
                (#\\ #\\)
                (#\" #\")
                (otherwise
                 (fail-star-source parser :invalid-string-escape
                                   "Unsupported string escape \\~C." escaped)))
              value)))
          (t
           (vector-push-extend character value)))
        (when (> (- (star-source-parser-index parser) start-byte 1)
                 (star-parser-limits-string-bytes
                  (star-source-parser-limits parser)))
          (fail-star-limit parser :string-byte-limit
                           start-byte start-line start-column
                           "String literal exceeds the configured byte limit.")))))))

(defun star-source-integer (token limits)
  (let* ((length (length token))
         (signed-p (and (> length 0) (find (char token 0) '(#\+ #\-))))
         (start (if signed-p 1 0)))
    (when (and (> length start)
               (loop for index from start below length
                     always (digit-char-p (char token index))))
      (let ((magnitude 0)
            (maximum (star-parser-limits-numeric-magnitude limits)))
        (loop for index from start below length
              for digit = (digit-char-p (char token index))
              do (when (> magnitude (floor (- maximum digit) 10))
                   (return-from star-source-integer (values nil :magnitude)))
                 (setf magnitude (+ (* magnitude 10) digit)))
        (values (if (and signed-p (char= (char token 0) #\-))
                    (- magnitude)
                    magnitude)
                :integer)))))

(defun parse-star-source-atom (parser)
  (let ((start (star-source-parser-index parser))
        (start-line (star-source-parser-line parser))
        (start-column (star-source-parser-column parser)))
    (loop for character = (star-source-character parser)
          until (star-source-delimiter-p character)
          do
             (when (find character '(#\# #\' #\` #\,))
               (fail-star-source
                parser
                :reader-syntax
                "Reader syntax beginning with ~C is not part of Star-Lang."
                character))
             (advance-star-source parser)
             (when (> (- (star-source-parser-index parser) start)
                      (star-parser-limits-token-bytes
                       (star-source-parser-limits parser)))
               (fail-star-limit parser :token-byte-limit
                                start start-line start-column
                                "Token exceeds the configured byte limit.")))
    (let* ((token (utf-8-octets-to-string
                   start
                   (star-source-parser-index parser)
                   parser))
           (token-bytes (- (star-source-parser-index parser) start)))
      (when (zerop (length token))
        (fail-star-source parser :expected-token "Expected a Star-Lang token."))
      (when (string= token ".")
        (fail-star-source parser :dotted-list
                          "Dotted-list syntax is not part of Star-Lang."))
      (let ((span (parser-span parser start start-line start-column)))
        (cond
          ((char= (char token 0) #\:)
           (when (or (= (length token) 1)
                     (position #\: token :start 1))
             (fail-star-source parser :invalid-keyword
                               "Invalid Star-Lang keyword ~A." token))
           (let ((keyword
                   (cdr (assoc (string-downcase (subseq token 1))
                               *star-source-keywords*
                               :test #'string=))))
             (unless keyword
               (fail-star-source parser :unknown-keyword
                                 "Unknown Star-Lang keyword ~A." token))
             (make-parsed-star-syntax parser :keyword keyword nil span)))
          ((position #\: token)
           (fail-star-source parser :package-qualified-name
                             "Package-qualified names are not part of Star-Lang: ~A."
                             token))
          ((string-equal token "nil")
           (make-parsed-star-syntax parser :boolean nil nil span))
          ((string-equal token "t")
           (make-parsed-star-syntax parser :boolean t nil span))
          (t
           (when (> token-bytes
                    (star-parser-limits-numeric-literal-bytes
                     (star-source-parser-limits parser)))
             (when (or (digit-char-p (char token 0))
                       (and (> (length token) 1)
                            (find (char token 0) '(#\+ #\-))
                            (digit-char-p (char token 1))))
               (fail-star-limit parser :numeric-literal-byte-limit
                                start start-line start-column
                                "Numeric literal exceeds the configured byte limit.")))
           (multiple-value-bind (integer status)
               (star-source-integer token (star-source-parser-limits parser))
             (cond
               ((eq status :magnitude)
                (fail-star-limit parser :numeric-magnitude-limit
                                 start start-line start-column
                                 "Numeric literal exceeds the configured magnitude limit."))
               ((eq status :integer)
                (make-parsed-star-syntax parser :integer integer nil span))
               ((or (digit-char-p (char token 0))
                    (and (> (length token) 1)
                         (find (char token 0) '(#\+ #\-))
                         (digit-char-p (char token 1))))
                (fail-star-limit parser :unsupported-numeric-literal
                                 start start-line start-column
                                 "Unsupported numeric literal ~A." token))
               (t
                (make-parsed-star-syntax parser :identifier token nil span))))))))))

(defun parse-star-source-value (parser depth)
  (skip-star-source-trivia parser)
  (let ((character (star-source-character parser)))
    (cond
      ((null character)
       (fail-star-source parser :unexpected-end
                         "Unexpected end of Star-Lang source."))
      ((char= character #\()
       (when (> depth
                (star-parser-limits-nesting-depth
                 (star-source-parser-limits parser)))
         (fail-star-source parser :nesting-depth-limit
                           "Star source exceeds the configured nesting-depth limit."))
       (let ((start-byte (star-source-parser-index parser))
             (start-line (star-source-parser-line parser))
             (start-column (star-source-parser-column parser)))
         (advance-star-source parser)
         (let ((values '())
               (count 0))
           (loop
             (skip-star-source-trivia parser)
             (let ((next (star-source-character parser)))
               (cond
                 ((null next)
                  (fail-star-source parser :unterminated-list "Unterminated list."))
                 ((char= next #\))
                  (advance-star-source parser)
                  (let ((span (parser-span parser start-byte start-line start-column)))
                    (return (make-parsed-star-syntax
                             parser :list nil (nreverse values) span))))
                 (t
                  (when (>= count
                            (star-parser-limits-collection-length
                             (star-source-parser-limits parser)))
                    (fail-star-limit parser :collection-length-limit
                                     start-byte start-line start-column
                                     "List exceeds the configured collection-length limit."))
                  (push (parse-star-source-value parser (1+ depth)) values)
                  (incf count))))))))
      ((char= character #\))
       (fail-star-source parser :unexpected-close
                         "Unexpected closing parenthesis."))
      ((char= character #\")
       (parse-star-source-string parser))
      (t
       (parse-star-source-atom parser)))))

(defun string-to-utf-8-octets (source)
  (let ((result (make-array (max 16 (length source))
                            :element-type '(unsigned-byte 8)
                            :adjustable t
                            :fill-pointer 0)))
    (labels ((emit (octet) (vector-push-extend octet result)))
      (loop for character across source
            for code = (char-code character)
            do (cond
                 ((<= code #x7F)
                  (emit code))
                 ((<= code #x7FF)
                  (emit (logior #xC0 (ash code -6)))
                  (emit (logior #x80 (logand code #x3F))))
                 ((or (<= #xD800 code #xDFFF) (> code #x10FFFF))
                  (error 'star-lang-source-error
                         :message "Source string contains a non-Unicode character."
                         :code :invalid-source-character
                         :phase :read))
                 ((<= code #xFFFF)
                  (emit (logior #xE0 (ash code -12)))
                  (emit (logior #x80 (logand (ash code -6) #x3F)))
                  (emit (logior #x80 (logand code #x3F))))
                 (t
                  (emit (logior #xF0 (ash code -18)))
                  (emit (logior #x80 (logand (ash code -12) #x3F)))
                  (emit (logior #x80 (logand (ash code -6) #x3F)))
                  (emit (logior #x80 (logand code #x3F)))))))
    result))

(defun utf-8-octets-to-string (start end parser)
  (let ((result (make-array (max 8 (- end start))
                            :element-type 'character
                            :adjustable t
                            :fill-pointer 0))
        (saved (star-source-parser-index parser)))
    (unwind-protect
         (progn
           (setf (star-source-parser-index parser) start)
           (loop while (< (star-source-parser-index parser) end)
                 do (multiple-value-bind (character next)
                        (decode-star-utf-8 parser)
                      (when (> next end)
                        (malformed-utf-8 parser
                                         (star-source-parser-index parser)
                                         next))
                      (vector-push-extend character result)
                      (setf (star-source-parser-index parser) next)))
           result)
      (setf (star-source-parser-index parser) saved))))

(defun ensure-star-octets (source)
  (etypecase source
    (string (string-to-utf-8-octets source))
    ((vector (unsigned-byte 8)) source)))

(defun read-star-syntax (source &key origin limits source-id pathname)
  "Read exactly one StarLang unit. SOURCE is canonically UTF-8 octets; strings
are encoded to UTF-8 first. Columns are one-based decoded-character columns,
and byte spans are zero-based, half-open UTF-8 byte ranges."
  (let* ((octets (ensure-star-octets source))
         (effective-limits (or limits (make-star-parser-limits)))
         (effective-source-id
           (or source-id (and pathname (namestring pathname)) "<memory>"))
         (effective-origin
           (or origin
               (make-star-origin-frame :kind :source
                                       :source-id effective-source-id)))
         (parser (make-star-source-parser octets
                                          effective-source-id
                                          pathname
                                          effective-origin
                                          effective-limits)))
    (when (> (length octets)
             (star-parser-limits-source-bytes effective-limits))
      (fail-star-source parser :source-byte-limit
                        "Star source exceeds the configured source-byte limit."))
    (skip-star-source-trivia parser)
    (when (star-source-end-p parser)
      (fail-star-source parser :empty-source "Star file is empty."))
    (let ((form (parse-star-source-value parser 1)))
      (skip-star-source-trivia parser)
      (unless (star-source-end-p parser)
        (fail-star-source
         parser
         :multiple-top-level-forms
         "Star file must contain exactly one top-level form."))
      form)))

(defun star-syntax-to-datum (syntax)
  "Return plain host data for trusted compatibility code. This is lossy: spans,
scope sets, origin frames, occurrence identity, and introduction metadata are
discarded. It is never a StarLang source-reading operation."
  (if (star-syntax-p syntax)
      (if (eq (star-syntax-kind syntax) :list)
          (mapcar #'star-syntax-to-datum (star-syntax-children syntax))
          (star-syntax-datum syntax))
      syntax))

(defun trusted-form-to-star-syntax (form &key source-id pathname origin)
  "Convert trusted Common Lisp test data to syntax objects without parsing it as
StarLang source. The resulting nodes have no source span."
  (declare (ignore pathname))
  (let ((effective-origin
          (or origin
              (make-star-origin-frame :kind :trusted
                                      :source-id (or source-id "<trusted-host-data>")))))
    (labels ((convert (value)
               (cond
                 ((consp value)
                  (make-star-syntax :kind :list
                                    :children (mapcar #'convert value)
                                    :scopes nil
                                    :origin effective-origin
                                    :introduced-by :trusted-host-adapter))
                 ((null value)
                  (make-star-syntax :kind :list :children nil :scopes nil
                                    :origin effective-origin
                                    :introduced-by :trusted-host-adapter))
                 ((keywordp value)
                  (make-star-syntax :kind :keyword :datum value :scopes nil
                                    :origin effective-origin
                                    :introduced-by :trusted-host-adapter))
                 ((eq value t)
                  (make-star-syntax :kind :boolean :datum t :scopes nil
                                    :origin effective-origin
                                    :introduced-by :trusted-host-adapter))
                 ((symbolp value)
                  (make-star-syntax :kind :identifier
                                    :datum (string-downcase (symbol-name value))
                                    :scopes nil
                                    :origin effective-origin
                                    :introduced-by :trusted-host-adapter))
                 ((stringp value)
                  (make-star-syntax :kind :string :datum value :scopes nil
                                    :origin effective-origin
                                    :introduced-by :trusted-host-adapter))
                 ((integerp value)
                  (make-star-syntax :kind :integer :datum value :scopes nil
                                    :origin effective-origin
                                    :introduced-by :trusted-host-adapter))
                 (t
                  (fail 'invalid-declaration-error
                        "Trusted compatibility data contains unsupported value ~S."
                        value)))))
      (convert form))))

(defun star-source-span-map (span)
  (when span
    (list :source-id (star-source-span-source-id span)
          :pathname (and (star-source-span-pathname span)
                         (namestring (star-source-span-pathname span)))
          :start-byte (star-source-span-start-byte span)
          :end-byte (star-source-span-end-byte span)
          :start-line (star-source-span-start-line span)
          :start-column (star-source-span-start-column span)
          :end-line (star-source-span-end-line span)
          :end-column (star-source-span-end-column span))))

(defun star-origin-chain (origin)
  (labels ((collect (frame)
             (when frame
               (append (collect (star-origin-frame-parent frame))
                       (list
                        (list :kind (star-origin-frame-kind frame)
                              :source-id (star-origin-frame-source-id frame)
                              :library-name (star-origin-frame-library-name frame)
                              :library-version (star-origin-frame-library-version frame)
                              :library-digest (star-origin-frame-library-digest frame)
                              :import-site
                              (star-source-span-map
                               (star-origin-frame-import-site-span frame))))))))
    (collect origin)))

(defun star-syntax-source-map (syntax)
  "Return a stable preorder source map. Node references are deterministic
ordinals, never process-local object identities."
  (let ((ordinal 0)
        (entries '()))
    (labels ((walk (node)
               (let ((id ordinal))
                 (incf ordinal)
                 (push (list :node id
                             :kind (star-syntax-kind node)
                             :span (star-source-span-map
                                    (star-syntax-span node))
                             :origin (star-origin-chain
                                      (star-syntax-origin node)))
                       entries)
                 (when (syntax-list-p node)
                   (dolist (child (star-syntax-children node))
                     (walk child))))))
      (walk syntax))
    (nreverse entries)))

(defun syntax-list-p (value)
  (and (star-syntax-p value) (eq (star-syntax-kind value) :list)))

(defun syntax-elements (value)
  (if (syntax-list-p value)
      (star-syntax-children value)
      (fail 'invalid-declaration-error "Expected a StarLang list occurrence.")))

(defun syntax-atom (value)
  (if (and (star-syntax-p value) (not (syntax-list-p value)))
      (star-syntax-datum value)
      (fail 'invalid-declaration-error "Expected a StarLang atomic occurrence.")))

(defun syntax-head-name (syntax)
  (when (and (syntax-list-p syntax) (star-syntax-children syntax))
    (let ((head (first (star-syntax-children syntax))))
      (when (eq (star-syntax-kind head) :identifier)
        (string-downcase (star-syntax-datum head))))))

(defparameter *unsupported-macro-heads*
  '("macro" "macro-library" "define-macro" "syntax-rules"
    "datum-to-syntax" "capture"))

(defun expand-star-syntax (syntax &key environment limits)
  "Deterministic identity expansion boundary. Macro syntax is rejected until
the approved declarative hygienic macro language is implemented."
  (declare (ignore environment))
  (unless (star-syntax-p syntax)
    (fail 'invalid-declaration-error
          "Expansion requires a StarLang syntax object."))
  (let ((effective-limits (or limits (make-star-parser-limits)))
        (nodes 0)
        (*star-current-phase* :expand))
    (labels ((walk (node depth)
               (incf nodes)
               (with-star-source-position (node)
                 (when (> nodes (star-parser-limits-node-count effective-limits))
                   (fail 'star-lang-source-error
                         "Expansion input exceeds the configured syntax-node limit."))
                 (when (> depth
                          (star-parser-limits-nesting-depth effective-limits))
                   (fail 'star-lang-source-error
                         "Expansion input exceeds the configured nesting-depth limit."))
                 (when (and (eq (star-syntax-kind node) :identifier)
                            (plusp (length (star-syntax-datum node)))
                            (char= (char (star-syntax-datum node) 0) #\?))
                   (fail 'unsupported-macro-error
                         "Macro pattern variables are not supported yet."))
                 (when (syntax-list-p node)
                   (let ((head (syntax-head-name node)))
                     (when (member head *unsupported-macro-heads* :test #'string=)
                       (fail 'unsupported-macro-error
                             "Macro form ~A is not supported yet." head)))
                   (dolist (child (star-syntax-children node))
                     (walk child (1+ depth)))))))
      (walk syntax 1))
    syntax))

(defparameter *specification-declaration-heads*
  '("import" "scalar" "enum" "document" "predicate" "message"))

(defparameter *program-declaration-heads*
  '("spec-graph" "document" "actor" "domain-server" "dataflow"))

(defparameter *program-stage-heads*
  '("from-dataset" "relations" "send" "collect"))

(defun validate-list-head (syntax allowed context condition-type)
  (with-star-source-position (syntax)
    (unless (syntax-list-p syntax)
      (fail condition-type "~A must be a list." context))
    (let ((head (syntax-head-name syntax)))
      (unless (and head (member head allowed :test #'string=))
        (let ((*star-current-syntax*
                (or (first (star-syntax-children syntax)) syntax)))
          (fail condition-type "Unknown ~A form ~S."
                context
                (and (star-syntax-children syntax)
                     (star-syntax-to-datum
                      (first (star-syntax-children syntax))))))))
    syntax))

(defun validate-star-core (syntax &key specification-graph)
  "Validate the closed, versioned prototype core grammar without lowering it."
  (unless (star-syntax-p syntax)
    (fail 'invalid-declaration-error
          "Core validation requires a StarLang syntax object."))
  (let ((*star-current-phase* :validate))
    (cond
      ((eq specification-graph :program)
       (dolist (declaration (syntax-elements syntax))
         (validate-list-head declaration *program-declaration-heads*
                             "program declaration" 'invalid-declaration-error)
         (when (string= (syntax-head-name declaration) "dataflow")
           (dolist (stage (cddr (syntax-elements declaration)))
             (validate-list-head stage *program-stage-heads*
                                 "dataflow stage" 'invalid-declaration-error)))))
      (t
       (with-star-source-position (syntax)
         (unless (and (syntax-list-p syntax)
                      (>= (length (star-syntax-children syntax)) 3)
                      (string= (or (syntax-head-name syntax) "")
                               "spec-library"))
           (fail 'invalid-library-error "Expected one spec-library form.")))
       (dolist (declaration (cdddr (syntax-elements syntax)))
         (validate-list-head declaration *specification-declaration-heads*
                             "specification declaration"
                             'invalid-declaration-error))))
    syntax))

(defun identifier-string (value)
  (cond
    ((star-syntax-p value)
     (let ((datum (syntax-atom value)))
       (etypecase datum
         (string datum)
         (symbol (string-downcase (symbol-name datum))))))
    ((stringp value) value)
    ((symbolp value) (string-downcase (symbol-name value)))
    (t
     (fail 'invalid-declaration-error "Expected an identifier, received ~S." value))))

(defun identifier-key (value)
  (string-downcase (identifier-string value)))

(defun qualified-name-p (value)
  (and (stringp value) (position #\/ value)))

(defun qualify-name (library-name value)
  (let ((name (identifier-string value)))
    (if (qualified-name-p name)
        name
        (format nil "~A/~A" library-name name))))

(defun plist-has-key-p (plist key)
  (loop for tail on (plist-elements plist) by #'cddr
        thereis (eq (if (star-syntax-p (first tail))
                        (syntax-atom (first tail))
                        (first tail))
                    key)))

(defun plist-elements (value)
  (cond
    ((syntax-list-p value) (star-syntax-children value))
    ((and (listp value) (every #'star-syntax-p value)) value)
    ((listp value) value)
    (t nil)))

(defun ensure-plist (value context &optional condition-type)
  (unless (and (or (syntax-list-p value)
                   (listp value))
               (evenp (length (plist-elements value))))
    (fail (or condition-type 'invalid-declaration-error)
          "~A requires a property list." context))
  value)

(defun required-option (options key context &optional condition-type)
  (unless (plist-has-key-p options key)
    (with-star-source-position (options)
      (fail (or condition-type 'invalid-declaration-error)
            "~A requires option ~S."
            context key)))
  (loop for (candidate value) on (plist-elements options) by #'cddr
        when (eq (if (star-syntax-p candidate)
                     (syntax-atom candidate)
                     candidate)
                 key)
          return value))

(defun optional-option (options key)
  (when (plist-has-key-p options key)
    (required-option options key "options")))

(defun digest-p (value)
  (setf value (if (star-syntax-p value) (syntax-atom value) value))
  (and (stringp value)
       (> (length value) 7)
       (string= "sha256:" value :end2 7)))

(defun normalize-persistence (value)
  (let ((name (identifier-key value)))
    (cond
      ((string= name "persistent") :persistent)
      ((string= name "transient") :transient)
      (t
       (fail 'invalid-declaration-error
             "Persistence must be persistent or transient, received ~S."
             value)))))

(defun normalize-runtime (value)
  (let ((name (identifier-key value)))
    (cond
      ((string= name "native") :native)
      ((string= name "external") :external)
      (t
       (fail 'invalid-actor-error
             "Actor runtime must be native or external, received ~S."
             value)))))

(defun normalize-restart (value)
  (let ((name (identifier-key value)))
    (cond
      ((string= name "permanent") :permanent)
      ((string= name "transient") :transient)
      ((string= name "temporary") :temporary)
      (t
       (fail 'invalid-actor-error
             "Actor restart policy must be permanent, transient, or temporary.")))))

(defun normalize-mailbox (value)
  (when (and (listp value) (not (star-syntax-p value)))
    (unless (= (length value) 2)
      (fail 'invalid-actor-error "Mailbox must be (bounded positive-integer)."))
    (destructuring-bind (kind capacity) value
      (unless (and (string= (identifier-key kind) "bounded")
                   (integerp capacity) (> capacity 0))
        (fail 'invalid-actor-error "Mailbox must be (bounded positive-integer)."))
      (return-from normalize-mailbox
        (list :kind :bounded :capacity capacity))))
  (unless (and (syntax-list-p value)
               (= (length (star-syntax-children value)) 2))
    (fail 'invalid-actor-error "Mailbox must be (bounded positive-integer)."))
  (destructuring-bind (kind capacity) (star-syntax-children value)
    (unless (and (string= (identifier-key kind) "bounded")
                 (integerp (syntax-atom capacity))
                 (> (syntax-atom capacity) 0))
      (fail 'invalid-actor-error "Mailbox must be (bounded positive-integer)."))
    (list :kind :bounded :capacity (syntax-atom capacity))))

(defun normalize-type-expression (value library-name local-types)
  (cond
    ((and (consp value) (not (star-syntax-p value)))
     (let ((operator (identifier-key (first value))))
       (cond
         ((and (string= operator "list") (= (length value) 2))
          (list :list
                (normalize-type-expression (second value) library-name local-types)))
         ((and (string= operator "optional") (= (length value) 2))
          (list :optional
                (normalize-type-expression (second value) library-name local-types)))
         (t
          (fail 'invalid-type-error "Unknown type expression ~S." value)))))
    ((syntax-list-p value)
     (let* ((elements (star-syntax-children value))
            (operator (and elements (identifier-key (first elements)))))
       (cond
         ((and (string= operator "list") (= (length elements) 2))
          (list :list
                (normalize-type-expression (second elements) library-name local-types)))
         ((and (string= operator "optional") (= (length elements) 2))
          (list :optional
                (normalize-type-expression (second elements) library-name local-types)))
         (t
          (with-star-source-position (value)
            (fail 'invalid-type-error "Unknown type expression ~S."
                  (star-syntax-to-datum value)))))))
    ((or (star-syntax-p value) (symbolp value) (stringp value))
     (let* ((name (identifier-string value))
            (key (identifier-key value))
            (builtins '("any" "boolean" "decimal" "integer" "map" "reference"
                        "string" "symbol" "iso-date" "iso-datetime")))
       (cond
         ((member key builtins :test #'string=) key)
         ((qualified-name-p name) name)
         ((member name local-types :test #'string=)
          (qualify-name library-name name))
         (t
          (with-star-source-position (value)
            (fail 'invalid-type-error
                  "Unknown unqualified type ~A in library ~A."
                  name library-name))))))
    (t
     (fail 'invalid-type-error "Invalid type expression ~S." value))))

(defun declaration-kind (declaration)
  (if (star-syntax-p declaration)
      (progn
        (unless (and (syntax-list-p declaration)
                     (star-syntax-children declaration))
          (fail 'invalid-declaration-error "Invalid declaration."))
        (let ((head (first (star-syntax-children declaration))))
          (with-star-source-position (head)
            (unless (eq (star-syntax-kind head) :identifier)
              (fail 'invalid-declaration-error
                    "Declaration head must be an identifier."))
            (identifier-key head))))
      (progn
        (unless (and (listp declaration) declaration
                     (or (symbolp (first declaration))
                         (stringp (first declaration))))
          (fail 'invalid-declaration-error "Invalid trusted declaration."))
        (identifier-key (first declaration)))))

(defun declaration-name (declaration)
  (let ((elements (if (star-syntax-p declaration)
                      (syntax-elements declaration)
                      declaration)))
    (unless (>= (length elements) 2)
      (fail 'invalid-declaration-error "Declaration has no name."))
    (identifier-string (second elements))))

(defun ensure-unique-declarations (declarations)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (declaration declarations)
      (with-star-source-position (declaration)
        (let* ((kind (declaration-kind declaration))
               (name (declaration-name declaration))
               (key (cons kind name)))
          (when (gethash key seen)
            (fail 'invalid-declaration-error
                  "Duplicate ~A declaration named ~A."
                  kind name))
          (setf (gethash key seen) t))))))

(defun declared-local-types (declarations)
  (loop for declaration in declarations
        for kind = (declaration-kind declaration)
        when (member kind '("scalar" "enum" "document") :test #'string=)
          collect (declaration-name declaration)))

(defun ensure-unique-local-types (declarations)
  (let ((types (declared-local-types declarations)))
    (unless (= (length types)
               (length (remove-duplicates types :test #'string=)))
      (fail 'invalid-declaration-error
            "Scalar, enum, and document names share one type namespace."))))

(defun ensure-unique-library-names (declarations)
  (let ((names
          (loop for declaration in declarations
                for kind = (declaration-kind declaration)
                unless (string= kind "import")
                  collect (declaration-name declaration))))
    (unless (= (length names)
               (length (remove-duplicates names :test #'string=)))
      (fail 'invalid-declaration-error
            "Library declarations share one qualified-name namespace."))))

(defun ensure-unique-fields (fields context)
  (let ((names (mapcar (lambda (field) (getf field :name)) fields)))
    (unless (= (length names)
               (length (remove-duplicates names :test #'string=)))
      (fail 'invalid-field-error "~A declares a field more than once." context))))

(defun compile-import (declaration)
  (destructuring-bind (operator name &rest options) (syntax-elements declaration)
    (declare (ignore operator))
    (ensure-plist options "import" 'invalid-library-error)
    (let ((version (required-option options :version "import" 'invalid-library-error))
          (digest (required-option options :digest "import" 'invalid-library-error)))
      (unless (and (eq (star-syntax-kind name) :string)
                   (eq (star-syntax-kind version) :string)
                   (digest-p digest))
        (fail 'invalid-library-error
              "Imports require string name, exact version, and sha256 digest."))
      (list :kind :import
            :name (syntax-atom name)
            :version (syntax-atom version)
            :digest (syntax-atom digest)))))

(defun compile-scalar (declaration library-name local-types)
  (destructuring-bind (operator name options) (syntax-elements declaration)
    (declare (ignore operator))
    (ensure-plist options "scalar")
    (let ((base (required-option options :base "scalar")))
      (list :kind :scalar
            :name (identifier-string name)
            :qualified-name (qualify-name library-name name)
            :base (normalize-type-expression base library-name local-types)
            :pattern (and (optional-option options :pattern)
                          (star-syntax-to-datum
                           (optional-option options :pattern)))
            :format (and (plist-has-key-p options :format)
                         (identifier-string (required-option options :format "scalar")))
            :minimum (and (optional-option options :minimum)
                          (star-syntax-to-datum (optional-option options :minimum)))
            :maximum (and (optional-option options :maximum)
                          (star-syntax-to-datum (optional-option options :maximum)))
            :scale (and (optional-option options :scale)
                        (star-syntax-to-datum (optional-option options :scale)))))))

(defun compile-enum (declaration library-name)
  (destructuring-bind (operator name values) (syntax-elements declaration)
    (declare (ignore operator))
    (unless (and (syntax-list-p values) (star-syntax-children values))
      (fail 'invalid-declaration-error "Enum ~A requires at least one value." name))
    (let ((normalized (mapcar #'identifier-string (star-syntax-children values))))
      (unless (= (length normalized)
                 (length (remove-duplicates normalized :test #'string=)))
        (fail 'invalid-declaration-error "Enum ~A contains duplicate values." name))
      (list :kind :enum
            :name (identifier-string name)
            :qualified-name (qualify-name library-name name)
            :values normalized))))

(defun parse-field-markers (options field-name)
  (flet ((marker-p (node marker)
           (and (star-syntax-p node)
                (not (syntax-list-p node))
                (eq (star-syntax-datum node) marker))))
  (let* ((required-p (find-if (lambda (node) (marker-p node :required)) options))
         (optional-p (find-if (lambda (node) (marker-p node :optional)) options))
         (default-position
           (position-if (lambda (node) (marker-p node :default)) options))
         (default-p (not (null default-position)))
         (default
           (when default-p
             (unless (< default-position (1- (length options)))
               (fail 'invalid-field-error
                     "Field ~A declares :default without a value."
                     field-name))
             (star-syntax-to-datum (nth (1+ default-position) options)))))
    (when (and required-p optional-p)
      (fail 'invalid-field-error
            "Field ~A cannot be both required and optional."
            field-name))
    (unless (or required-p optional-p)
      (fail 'invalid-field-error
            "Field ~A must declare :required or :optional."
            field-name))
    (values (not (null required-p)) default default-p))))

(defun compile-field (field library-name local-types)
  (with-star-source-position (field)
    (unless (and (syntax-list-p field)
                 (>= (length (star-syntax-children field)) 3))
      (fail 'invalid-field-error "Invalid field declaration."))
    (destructuring-bind (name type &rest options) (star-syntax-children field)
      (multiple-value-bind (required-p default default-p)
          (parse-field-markers options name)
        (when (and required-p default-p)
          (fail 'invalid-field-error
                "Required field ~A cannot declare a default."
                name))
        (list :name (require-lower-camel-field-name name)
              :type (normalize-type-expression type library-name local-types)
              :required required-p
              :default-p default-p
              :default default)))))

(defun compile-document (declaration library-name local-types)
  (destructuring-bind (operator name options &rest fields)
      (syntax-elements declaration)
    (declare (ignore operator))
    (ensure-plist options "document")
    (let* ((extends (optional-option options :extends))
           (persistence (required-option options :persistence "document"))
           (compiled-fields
             (mapcar (lambda (field)
                       (compile-field field library-name local-types))
                     fields)))
      (ensure-unique-fields compiled-fields (format nil "Document ~A" name))
      (list :kind :document
            :name (identifier-string name)
            :qualified-name (qualify-name library-name name)
            :extends (and extends
                          (normalize-type-expression extends library-name local-types))
            :persistence (normalize-persistence persistence)
            :fields compiled-fields))))

(defun compile-predicate (declaration library-name local-types)
  (destructuring-bind (operator name options) (syntax-elements declaration)
    (declare (ignore operator))
    (ensure-plist options "predicate")
    (list :kind :predicate
          :name (identifier-string name)
          :qualified-name (qualify-name library-name name)
          :source (normalize-type-expression
                   (required-option options :source "predicate")
                   library-name local-types)
          :destination (normalize-type-expression
                        (required-option options :destination "predicate")
                        library-name local-types))))

(defun compile-message (declaration library-name local-types)
  (destructuring-bind (operator name options) (syntax-elements declaration)
    (declare (ignore operator))
    (ensure-plist options "message")
    (let ((fields (required-option options :fields "message")))
      (unless (syntax-list-p fields)
        (fail 'invalid-field-error "Message fields must be a list."))
      (let ((compiled-fields
              (mapcar (lambda (field)
                        (compile-field field library-name local-types))
                      (star-syntax-children fields))))
        (ensure-unique-fields compiled-fields (format nil "Message ~A" name))
        (list :kind :message
              :name (identifier-string name)
              :qualified-name (qualify-name library-name name)
              :fields compiled-fields)))))

(defun compile-library-declaration (declaration library-name local-types)
  (with-star-source-position (declaration)
    (let ((kind (declaration-kind declaration)))
      (cond
        ((string= kind "import") (compile-import declaration))
        ((string= kind "scalar")
         (compile-scalar declaration library-name local-types))
        ((string= kind "enum") (compile-enum declaration library-name))
        ((string= kind "document")
         (compile-document declaration library-name local-types))
        ((string= kind "predicate")
         (compile-predicate declaration library-name local-types))
        ((string= kind "message")
         (compile-message declaration library-name local-types))
        (t
         (fail 'invalid-declaration-error
               "Unknown specification declaration ~S."
               (star-syntax-to-datum
                (first (star-syntax-children declaration)))))))))

(defun %compile-spec-library-syntax (form)
  (with-star-source-position (form)
    (unless (and (syntax-list-p form)
                 (>= (length (star-syntax-children form)) 3)
                 (string= (declaration-kind form) "spec-library"))
      (fail 'invalid-library-error "Expected one spec-library form."))
    (destructuring-bind (operator name options &rest declarations)
        (syntax-elements form)
      (declare (ignore operator))
      (unless (eq (star-syntax-kind name) :string)
        (fail 'invalid-library-error
              "Specification library name must be a string."))
      (ensure-plist options "spec-library" 'invalid-library-error)
      (ensure-unique-declarations declarations)
      (ensure-unique-local-types declarations)
      (ensure-unique-library-names declarations)
      (let* ((version
               (required-option
                options :version "spec-library" 'invalid-library-error))
             (digest (optional-option options :digest))
             (library-name (syntax-atom name))
             (local-types (declared-local-types declarations))
             (compiled
               (mapcar (lambda (declaration)
                         (compile-library-declaration
                          declaration library-name local-types))
                       declarations)))
        (unless (eq (star-syntax-kind version) :string)
          (fail 'invalid-library-error
                "Specification library version must be a string."))
        (when (and digest (not (digest-p digest)))
          (fail 'invalid-library-error
                "Specification library digest must use sha256:."))
        (list :ir-version +normalized-ir-version+
              :ir-schema +normalized-ir-schema+
              :kind :spec-library
              :name (syntax-atom name)
              :version (syntax-atom version)
              :digest (and digest (syntax-atom digest))
              :source-map (star-syntax-source-map form)
              :imports (remove-if-not
                        (lambda (item) (eq (getf item :kind) :import))
                        compiled)
              :declarations (remove-if
                             (lambda (item) (eq (getf item :kind) :import))
                             compiled))))))

(defun compile-star-core (syntax &key specification-graph)
  (declare (ignore specification-graph))
  (let ((*star-current-phase* :compile))
    (validate-star-core syntax)
    (%compile-spec-library-syntax syntax)))

(defun compile-spec-library (form)
  "Trusted compatibility entry point. Raw Common Lisp forms are converted to
syntax objects explicitly; parsed .star source never arrives here as host data."
  (let* ((syntax (if (star-syntax-p form)
                     form
                     (trusted-form-to-star-syntax form)))
         (expanded (expand-star-syntax syntax)))
    (compile-star-core expanded)))

(defun read-star-path-octets (path limits)
  (with-open-file (stream path
                          :direction :input
                          :element-type '(unsigned-byte 8))
    (let ((length (file-length stream)))
      (when (> length (star-parser-limits-source-bytes limits))
        (error 'star-lang-source-error
               :message "Star source exceeds the configured source-byte limit."
               :code :source-byte-limit
               :span (make-star-source-span
                      :source-id (namestring path)
                      :pathname path
                      :start-byte 0
                      :end-byte 0
                      :start-line 1
                      :start-column 1
                      :end-line 1
                      :end-column 1)
               :phase :read))
      (let ((octets (make-array length :element-type '(unsigned-byte 8))))
        (unless (= (read-sequence octets stream) length)
          (error 'star-lang-source-error
                 :message "Star source changed while it was being read."
                 :code :source-read-race
                 :phase :read))
        octets))))

(defun load-star-form (pathname &key limits origin source-id)
  (let* ((candidate (pathname pathname))
         (path
           (handler-case
               (truename candidate)
             (file-error ()
               candidate))))
    (let ((*star-source-pathname* path)
          (*star-source-line* 1)
          (*star-source-column* 1)
          (effective-limits (or limits (make-star-parser-limits))))
      (unless (and (pathname-type path)
                   (string-equal (pathname-type path) "star"))
        (fail 'star-lang-source-error
              "Star source pathname must use the .star extension."))
      (handler-case
          (let* ((octets (read-star-path-octets path effective-limits))
                 (syntax (read-star-syntax
                          octets
                          :pathname path
                          :source-id (or source-id (namestring path))
                          :origin origin
                          :limits effective-limits))
                 (expanded (expand-star-syntax syntax :limits effective-limits)))
            (validate-star-core expanded)
            (compile-star-core expanded))
        (star-lang-core-error (condition)
          (error condition))
        (file-error (condition)
          (fail 'star-lang-source-error
                "Could not read Star source ~A: ~A."
                path condition))))))
