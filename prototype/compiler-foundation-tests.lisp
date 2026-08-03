(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(define-condition compiler-foundation-test-error (error)
  ((message :initarg :message :reader compiler-foundation-test-error-message))
  (:report (lambda (condition stream)
             (write-string (compiler-foundation-test-error-message condition)
                           stream))))

(defun foundation-fail (control &rest arguments)
  (error 'compiler-foundation-test-error
         :message (apply #'format nil control arguments)))

(defun foundation-assert (value label)
  (unless value
    (foundation-fail "Assertion failed: ~A." label))
  value)

(defun foundation-equal (expected actual label)
  (unless (equal expected actual)
    (foundation-fail "~A expected ~S, received ~S." label expected actual))
  actual)

(defun foundation-condition (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          caught
          (error caught)))))

(defun syntax-at (syntax &rest indexes)
  (dolist (index indexes syntax)
    (setf syntax (nth index (star-syntax-children syntax)))))

(defun test-occurrence-syntax-contract ()
  (let* ((syntax (read-star-syntax "(Same Same camelCase)" :source-id "occurrences"))
         (first (syntax-at syntax 0))
         (second (syntax-at syntax 1))
         (camel (syntax-at syntax 2)))
    (foundation-assert (star-syntax-p syntax) "root is syntax")
    (foundation-assert (eq (star-syntax-kind syntax) :list) "root is list syntax")
    (foundation-equal 0 (star-source-span-start-byte (star-syntax-span syntax))
                      "root start byte")
    (foundation-equal 21 (star-source-span-end-byte (star-syntax-span syntax))
                      "root end byte")
    (foundation-assert (and (star-syntax-p first) (star-syntax-p second))
                       "atoms are syntax")
    (foundation-assert (not (eq first second))
                       "repeated identifiers have distinct occurrence identity")
    (foundation-equal "Same" (star-syntax-datum first)
                      "first identifier spelling")
    (foundation-equal "Same" (star-syntax-datum second)
                      "second identifier spelling")
    (foundation-equal "camelCase" (star-syntax-datum camel)
                      "camelCase survives reading")
    (foundation-equal nil (star-syntax-scopes first) "empty immutable scope set")
    (foundation-equal '("Same" "Same" "camelCase")
                      (star-syntax-to-datum syntax)
                      "explicit lossy conversion")))

(defun test-ambient-reader-state-is-irrelevant ()
  (let* ((readtable (copy-readtable nil))
         (*package* (find-package "KEYWORD"))
         (*readtable* readtable))
    (set-macro-character
     #\(
     (lambda (stream character)
       (declare (ignore stream character))
       (error "Ambient readtable was invoked."))
     nil readtable)
    (let ((syntax (read-star-syntax "(camelCase)" :source-id "ambient")))
      (foundation-equal "camelCase" (star-syntax-datum (syntax-at syntax 0))
                        "ambient package and readtable do not affect parsing"))))

(defun test-closed-reader-rejections ()
  (dolist (source '("(#.(error \"boom\"))"
                    "('x)"
                    "(`x)"
                    "(,x)"
                    "(,@x)"
                    "(a . b)"
                    "(cl-user::x)"))
    (let ((condition
            (foundation-condition
             'star-lang-source-error
             (lambda () (read-star-syntax source :source-id "closed-reader")))))
      (foundation-assert condition (format nil "reject ~A" source))
      (foundation-assert (star-lang-core-error-span condition)
                         (format nil "source span for ~A" source))
      (foundation-equal :read (star-lang-core-error-phase condition)
                        (format nil "read phase for ~A" source)))))

(defun test-utf-8-byte-spans ()
  (let* ((syntax (read-star-syntax "(é x)" :source-id "utf8"))
         (accent (syntax-at syntax 0))
         (x (syntax-at syntax 1)))
    (foundation-equal '(0 6)
                      (list (star-source-span-start-byte (star-syntax-span syntax))
                            (star-source-span-end-byte (star-syntax-span syntax)))
                      "multibyte list byte span")
    (foundation-equal '(1 3 2 3)
                      (let ((span (star-syntax-span accent)))
                        (list (star-source-span-start-byte span)
                              (star-source-span-end-byte span)
                              (star-source-span-start-column span)
                              (star-source-span-end-column span)))
                      "multibyte identifier span")
    (foundation-equal '(4 5 4 5)
                      (let ((span (star-syntax-span x)))
                        (list (star-source-span-start-byte span)
                              (star-source-span-end-byte span)
                              (star-source-span-start-column span)
                              (star-source-span-end-column span)))
                      "post-multibyte identifier span")
    (let* ((commented
             (read-star-syntax (format nil ";é~%(\"é\\n\")")
                               :source-id "trivia"))
           (string (syntax-at commented 0)))
      (foundation-equal '(4 12)
                        (list (star-source-span-start-byte
                               (star-syntax-span commented))
                              (star-source-span-end-byte
                               (star-syntax-span commented)))
                        "comments and escaped string root bytes")
      (foundation-equal '(5 11)
                        (list (star-source-span-start-byte
                               (star-syntax-span string))
                              (star-source-span-end-byte
                               (star-syntax-span string)))
                        "escaped multibyte string bytes"))))

(defun test-malformed-utf-8 ()
  (let* ((octets (make-array 3 :element-type '(unsigned-byte 8)
                             :initial-contents '(40 192 41)))
         (condition
           (foundation-condition
            'star-lang-source-error
            (lambda () (read-star-syntax octets :source-id "bad-utf8")))))
    (foundation-assert condition "malformed UTF-8 rejected")
    (foundation-equal :malformed-utf-8
                      (star-lang-core-error-code condition)
                      "malformed UTF-8 diagnostic code")
    (foundation-equal 1
                      (star-source-span-start-byte
                       (star-lang-core-error-span condition))
                      "malformed UTF-8 byte")))

(defun expect-limit (source limits code label)
  (let ((condition
          (foundation-condition
           'star-lang-source-error
           (lambda ()
             (read-star-syntax source :source-id label :limits limits)))))
    (foundation-assert condition label)
    (foundation-equal code (star-lang-core-error-code condition) label)
    (foundation-assert (star-lang-core-error-span condition)
                       (format nil "~A has a span" label))))

(defun test-parser-limits ()
  (expect-limit "(x)" (make-star-parser-limits :source-bytes 2)
                :source-byte-limit "source limit")
  (expect-limit "((x))" (make-star-parser-limits :nesting-depth 1)
                :nesting-depth-limit "nesting limit")
  (expect-limit "(abc)" (make-star-parser-limits :token-bytes 2)
                :token-byte-limit "token limit")
  (expect-limit "(\"ab\")" (make-star-parser-limits :string-bytes 1)
                :string-byte-limit "string limit")
  (expect-limit "(a b)" (make-star-parser-limits :collection-length 1)
                :collection-length-limit "collection limit")
  (expect-limit "(a b)" (make-star-parser-limits :node-count 2)
                :node-count-limit "node limit")
  (expect-limit "(123)" (make-star-parser-limits :numeric-literal-bytes 2)
                :numeric-literal-byte-limit "numeric byte limit")
  (expect-limit "(10)" (make-star-parser-limits :numeric-magnitude 9)
                :numeric-magnitude-limit "numeric magnitude limit"))

(defun test-explicit-phases ()
  (let* ((syntax
           (read-star-syntax
            "(spec-library \"phase@1\" (:version \"1\") (enum State (One Two)))"
            :source-id "phases"))
         (expanded (expand-star-syntax syntax)))
    (foundation-assert (eq syntax expanded) "identity expansion preserves syntax")
    (foundation-assert (eq (star-syntax-span syntax)
                           (star-syntax-span expanded))
                       "identity expansion preserves spans")
    (foundation-assert (eq (star-syntax-origin syntax)
                           (star-syntax-origin expanded))
                       "identity expansion preserves origin")
    (foundation-assert (eq expanded (validate-star-core expanded))
                       "validation preserves syntax")
    (let ((first-ir (compile-star-core expanded))
          (second-ir
            (compile-star-core
             (expand-star-syntax
              (read-star-syntax
               "(spec-library \"phase@1\" (:version \"1\") (enum State (One Two)))"
               :source-id "phases")))))
      (foundation-equal first-ir second-ir "normalized IR and source map stable")
      (foundation-assert
       (not (labels ((contains-syntax-p (value)
                       (cond
                         ((star-syntax-p value) t)
                         ((consp value)
                          (or (contains-syntax-p (car value))
                              (contains-syntax-p (cdr value))))
                         (t nil))))
              (contains-syntax-p first-ir)))
       "normalized IR contains no syntax objects"))))

(defun test-macro-boundary ()
  (dolist (source '("(macro example)" "(?pattern value)"))
    (let* ((syntax (read-star-syntax source :source-id "macro-boundary"))
           (condition
             (foundation-condition
              'unsupported-macro-error
              (lambda () (expand-star-syntax syntax)))))
      (foundation-assert condition "macro syntax rejected")
      (foundation-equal :expand (star-lang-core-error-phase condition)
                        "macro rejected during expansion"))))

(defun test-semantic-occurrence-span ()
  (let* ((source
           (format nil
                   "(spec-library \"bad@1\" (:version \"1\")~%  (document Thing (:persistence persistent)~%    (field UnknownType :required)))"))
         (syntax (read-star-syntax source :source-id "semantic"))
         (condition
           (foundation-condition
            'invalid-type-error
            (lambda ()
              (compile-star-core (expand-star-syntax syntax)))))
         (expected (search "UnknownType" source)))
    (foundation-assert condition "semantic error captured")
    (foundation-equal expected
                      (star-source-span-start-byte
                       (star-lang-core-error-span condition))
                      "semantic error points to exact type occurrence")
    (foundation-equal :compile (star-lang-core-error-phase condition)
                      "semantic error phase")))

(defun slurp-static-source (pathname)
  (with-open-file (stream pathname :direction :input)
    (with-output-to-string (output)
      (loop for character = (read-char stream nil nil)
            while character
            do (write-char character output)))))

(defun test-loader-static-reader-conformance ()
  (let* ((pathname (merge-pathnames "star-loader.lisp" *load-truename*))
         (source (string-downcase (slurp-static-source pathname))))
    (foundation-assert (null (search "(read " source))
                       "production loader contains no Common Lisp READ call")
    (foundation-assert (null (search "(read-from-string" source))
                       "production loader contains no READ-FROM-STRING call")
    (foundation-assert (null (search "with-input-from-string" source))
                       "production loader contains no reader stream loop")))

(defun run-compiler-foundation-tests ()
  (mapc #'funcall
        (list #'test-occurrence-syntax-contract
              #'test-ambient-reader-state-is-irrelevant
              #'test-closed-reader-rejections
              #'test-utf-8-byte-spans
              #'test-malformed-utf-8
              #'test-parser-limits
              #'test-explicit-phases
              #'test-macro-boundary
              #'test-semantic-occurrence-span
              #'test-loader-static-reader-conformance))
  (format t "Star-Lang compiler foundation tests passed.~%")
  t)

(unless (run-compiler-foundation-tests)
  (error "Star-Lang compiler foundation tests failed."))
