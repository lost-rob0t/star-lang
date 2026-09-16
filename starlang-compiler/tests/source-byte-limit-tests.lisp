(defpackage #:starlang-source-byte-limit-tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:starlang-source-byte-limit-tests)

(def-suite source-byte-limit-tests
  :description "Host string source-byte admission tests for the final compiler.")

(in-suite source-byte-limit-tests)

(defun capture-source-error (thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (star-lang.compiler.core:star-lang-source-error (condition)
      condition)))

(defun source-limit-condition (source limit &key source-id pathname origin actor-p)
  (capture-source-error
   (lambda ()
     (let ((limits
             (star-lang.compiler.core:make-star-parser-limits
              :source-bytes limit)))
       (if actor-p
           (starlangcompiler:compile-actor-source
            source
            :limits limits
            :source-id source-id
            :pathname pathname
            :origin origin)
           (star-lang.compiler.core:read-star-syntax
            source
            :limits limits
            :source-id source-id
            :pathname pathname
            :origin origin)))))))

(defun assert-source-byte-boundary (source octets byte-length)
  (let* ((at-limit
           (star-lang.compiler.core:make-star-parser-limits
            :source-bytes byte-length))
         (string-syntax
           (star-lang.compiler.core:read-star-syntax
            source :limits at-limit :source-id "string.star"))
         (octet-syntax
           (star-lang.compiler.core:read-star-syntax
            octets :limits at-limit :source-id "octets.star"))
         (over-condition
           (source-limit-condition source (1- byte-length))))
    (is (equal (star-lang.compiler.core:star-syntax-to-datum string-syntax)
               (star-lang.compiler.core:star-syntax-to-datum octet-syntax)))
    (is (= byte-length
           (star-lang.compiler.core:star-source-span-end-byte
            (star-lang.compiler.core:star-syntax-span string-syntax))))
    (is (= byte-length
           (star-lang.compiler.core:star-source-span-end-byte
            (star-lang.compiler.core:star-syntax-span octet-syntax))))
    (is (typep over-condition
               'star-lang.compiler.core:star-lang-source-error))
    (is (eq :source-byte-limit
            (star-lang.compiler.core:star-lang-core-error-code
             over-condition)))
    (is (eq :read
            (star-lang.compiler.core:star-lang-core-error-phase
             over-condition)))))

(test source-byte-limit-counts-utf-8-bytes
  "ASCII and two-, three-, and four-byte scalar values use UTF-8 byte limits."
  (assert-source-byte-boundary "x" #(120) 1)
  (assert-source-byte-boundary
   (string (code-char #x00E9))
   #(#xC3 #xA9)
   2)
  (assert-source-byte-boundary
   (string (code-char #x20AC))
   #(#xE2 #x82 #xAC)
   3)
  (assert-source-byte-boundary
   (string (code-char #x1F600))
   #(#xF0 #x9F #x98 #x80)
   4))

(test string-and-octet-source-remain-equivalent
  "Admitted host strings and their canonical UTF-8 octets keep datum and byte spans."
  (let* ((source
           (concatenate 'string
                        "("
                        (string (code-char #x03C0))
                        ")"))
         (octets #(#x28 #xCF #x80 #x29))
         (limits
           (star-lang.compiler.core:make-star-parser-limits
            :source-bytes 4))
         (string-syntax
           (star-lang.compiler.core:read-star-syntax
            source :limits limits :source-id "same.star"))
         (octet-syntax
           (star-lang.compiler.core:read-star-syntax
            octets :limits limits :source-id "same.star")))
    (is (equal (star-lang.compiler.core:star-syntax-to-datum string-syntax)
               (star-lang.compiler.core:star-syntax-to-datum octet-syntax)))
    (is (equal (star-lang.compiler.core:star-syntax-source-map string-syntax)
               (star-lang.compiler.core:star-syntax-source-map octet-syntax)))))

(test obvious-character-oversize-rejects-before-full-string-encoder
  "A character-count-obvious over-limit string never enters the full UTF-8 encoder."
  (let* ((source (make-string 65 :initial-element #\Space))
         (encoder-symbol
           (find-symbol "STRING-TO-UTF-8-OCTETS"
                        "STAR-LANG.COMPILER.CORE"))
         (original (symbol-function encoder-symbol))
         (called nil)
         (condition nil))
    (unwind-protect
         (progn
           (setf (symbol-function encoder-symbol)
                 (lambda (value)
                   (setf called t)
                   (funcall original value)))
           (setf condition (source-limit-condition source 64)))
      (setf (symbol-function encoder-symbol) original))
    (is (typep condition
               'star-lang.compiler.core:star-lang-source-error))
    (is (eq :source-byte-limit
            (star-lang.compiler.core:star-lang-core-error-code condition)))
    (is (not called))))

(test multibyte-source-overflow-is-byte-bounded
  "A string whose character count fits but UTF-8 byte count does not is rejected."
  (let* ((character (code-char #x1F600))
         (source (make-string 17 :initial-element character))
         (condition (source-limit-condition source 64)))
    (is (typep condition
               'star-lang.compiler.core:star-lang-source-error))
    (is (eq :source-byte-limit
            (star-lang.compiler.core:star-lang-core-error-code condition)))
    (is (eq :read
            (star-lang.compiler.core:star-lang-core-error-phase condition)))))

(test early-source-limit-preserves-diagnostic-context
  "Pre-encoding rejection retains caller identity, origin, pathname, and read phase."
  (let* ((origin
           (star-lang.compiler.core:make-star-origin-frame
            :kind :source
            :source-id "origin.star"))
         (pathname #p"diagnostic.star")
         (condition
           (source-limit-condition
            (make-string 65 :initial-element #\Space)
            64
            :source-id "explicit.star"
            :pathname pathname
            :origin origin)))
    (is (typep condition
               'star-lang.compiler.core:star-lang-source-error))
    (is (eq :source-byte-limit
            (star-lang.compiler.core:star-lang-core-error-code condition)))
    (is (eq :read
            (star-lang.compiler.core:star-lang-core-error-phase condition)))
    (is (eq origin
            (star-lang.compiler.core:star-lang-core-error-origin condition)))
    (let ((span (star-lang.compiler.core:star-lang-core-error-span condition)))
      (is (string= "explicit.star"
                   (star-lang.compiler.core:star-source-span-source-id span)))
      (is (equal pathname
                 (star-lang.compiler.core:star-source-span-pathname span))))))

(test compile-actor-source-uses-the-bounded-string-admission-path
  "The public single-actor compiler rejects before parsing an oversized host string."
  (let ((condition
          (source-limit-condition
           (make-string 65 :initial-element #\Space)
           64
           :source-id "actor-limit.star"
           :actor-p t)))
    (is (typep condition
               'star-lang.compiler.core:star-lang-source-error))
    (is (eq :source-byte-limit
            (star-lang.compiler.core:star-lang-core-error-code condition)))
    (is (eq :read
            (star-lang.compiler.core:star-lang-core-error-phase condition)))))

#+sbcl
(test oversized-host-string-does-not-cons-input-sized-octet-buffer
  "Pinned SBCL allocation evidence guards against reintroducing full-source encoding."
  (let* ((source (make-string (* 4 1024 1024) :initial-element #\Space))
         (limits
           (star-lang.compiler.core:make-star-parser-limits
            :source-bytes 64)))
    ;; Warm condition/reporting paths before measuring the rejected call.
    (capture-source-error
     (lambda ()
       (star-lang.compiler.core:read-star-syntax
        (make-string 65 :initial-element #\Space)
        :limits limits)))
    (sb-ext:gc :full t)
    (let ((before (sb-ext:get-bytes-consed)))
      (let ((condition
              (capture-source-error
               (lambda ()
                 (star-lang.compiler.core:read-star-syntax
                  source :limits limits)))))
        (is (eq :source-byte-limit
                (star-lang.compiler.core:star-lang-core-error-code
                 condition))))
      (let ((allocated (- (sb-ext:get-bytes-consed) before)))
        (is (< allocated (* 1024 1024)))))))

(defun run-tests ()
  (unless (run! 'source-byte-limit-tests)
    (error "source-byte-limit tests failed.")))
