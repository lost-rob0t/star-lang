(defpackage :starcanonicaljson-tests
  (:use :cl)
  (:import-from :starcanonicaljson
                #:invalid-canonical-json-error
                #:make-json-object
                #:json-object-entries
                #:make-json-array
                #:+json-true+
                #:+json-false+
                #:+json-null+
                #:canonical-json-string)
  (:export #:run-tests))

(in-package :starcanonicaljson-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

#+sbcl
(defun double-float-from-bits (hex)
  (let* ((bits (parse-integer hex :radix 16))
         (high (ldb (byte 32 32) bits))
         (low (ldb (byte 32 0) bits))
         (signed-high (if (logbitp 31 high)
                          (- high #x100000000)
                          high)))
    (sb-kernel:make-double-float signed-high low)))

#-sbcl
(defun double-float-from-bits (hex)
  (declare (ignore hex))
  (error "The canonical binary64 test oracle requires the pinned SBCL runtime."))

(defun test-object-keys-sort-deterministically ()
  (let* ((entries (list (cons "z" 2)
                        (cons "a" 1)))
         (object (make-json-object entries)))
    (check
     (string= "{\"a\":1,\"z\":2}"
              (canonical-json-string object))
     "Canonical JSON object keys were not sorted.")
    (check
     (equal '("z" "a")
            (mapcar #'car (json-object-entries object)))
     "Canonical JSON serialization mutated object entry order.")))

(defun test-array-and-json-sentinels ()
  (check
   (string= "[\"x\",true,false,null,-7]"
            (canonical-json-string
             (make-json-array
              (list "x"
                    +json-true+
                    +json-false+
                    +json-null+
                    -7))))
   "Canonical JSON array/scalar encoding changed."))

(defun test-string-escaping ()
  (let* ((value
           (coerce
            (list #\" #\\ #\Newline #\Tab (code-char 1))
            'string))
         (expected
           (coerce
            (list #\"
                  #\\ #\"
                  #\\ #\\
                  #\\ #\n
                  #\\ #\t
                  #\\ #\u #\0 #\0 #\0 #\1
                  #\")
            'string)))
    (check
     (string= expected (canonical-json-string value))
     "Canonical JSON string escaping changed.")))

(defun test-nested-structures ()
  (check
   (string=
    "{\"array\":[1,{\"x\":\"y\"}],\"null\":null}"
    (canonical-json-string
     (make-json-object
      (list
       (cons "null" +json-null+)
       (cons "array"
             (make-json-array
              (list 1
                    (make-json-object
                     (list (cons "x" "y"))))))))))
   "Nested canonical JSON encoding changed."))

(defun test-pinned-double-float-is-ieee-binary64 ()
  (check (= 2 (float-radix 1d0))
         "Pinned SBCL double-float radix is not binary.")
  (check (= 53 (float-digits 1d0))
         "Pinned SBCL double-float precision is not binary64.")
  (check (= -1021 (float-min-exponent 1d0))
         "Pinned SBCL double-float minimum exponent is not binary64.")
  (check (= 1024 (float-max-exponent 1d0))
         "Pinned SBCL double-float maximum exponent is not binary64."))

(defun test-rfc8785-appendix-b-binary64-vectors ()
  (dolist (case
           '(("0000000000000000" "0")
             ("8000000000000000" "0")
             ("0000000000000001" "5e-324")
             ("8000000000000001" "-5e-324")
             ("7fefffffffffffff" "1.7976931348623157e+308")
             ("ffefffffffffffff" "-1.7976931348623157e+308")
             ("4340000000000000" "9007199254740992")
             ("c340000000000000" "-9007199254740992")
             ("4430000000000000" "295147905179352830000")
             ("44b52d02c7e14af5" "9.999999999999997e+22")
             ("44b52d02c7e14af6" "1e+23")
             ("44b52d02c7e14af7" "1.0000000000000001e+23")
             ("444b1ae4d6e2ef4e" "999999999999999700000")
             ("444b1ae4d6e2ef4f" "999999999999999900000")
             ("444b1ae4d6e2ef50" "1e+21")
             ("3eb0c6f7a0b5ed8c" "9.999999999999997e-7")
             ("3eb0c6f7a0b5ed8d" "0.000001")
             ("41b3de4355555553" "333333333.3333332")
             ("41b3de4355555554" "333333333.33333325")
             ("41b3de4355555555" "333333333.3333333")
             ("41b3de4355555556" "333333333.3333334")
             ("41b3de4355555557" "333333333.33333343")
             ("becbf647612f3696" "-0.0000033333333333333333")
             ("43143ff3c1cb0959" "1424953923781206.2")))
    (destructuring-bind (hex expected) case
      (let ((actual (canonical-json-string (double-float-from-bits hex))))
        (check (string= expected actual)
               "RFC 8785 Appendix B mismatch for ~A: expected ~A, got ~A."
               hex expected actual)))))

(defun test-rfc8785-non-finite-values-are-rejected ()
  (dolist (hex '("7ff0000000000000"
                 "fff0000000000000"
                 "7fffffffffffffff"))
    (check
     (signals-p
      'invalid-canonical-json-error
      (lambda ()
        (canonical-json-string (double-float-from-bits hex))))
     "RFC 8785 non-finite binary64 value ~A was not rejected with a typed canonical JSON error."
     hex)))

(defun test-unsupported-node-is-typed ()
  (check
   (signals-p
    'invalid-canonical-json-error
    (lambda ()
      (canonical-json-string #\x)))
   "Unsupported JSON node did not signal the final typed condition."))

(defun test-final-system-is-prototype-independent ()
  (check
   (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
   "star-canonical-json loaded the prototype package transitively."))

(defun run-tests ()
  (test-object-keys-sort-deterministically)
  (test-array-and-json-sentinels)
  (test-string-escaping)
  (test-nested-structures)
  (test-pinned-double-float-is-ieee-binary64)
  (test-rfc8785-appendix-b-binary64-vectors)
  (test-rfc8785-non-finite-values-are-rejected)
  (test-unsupported-node-is-typed)
  (test-final-system-is-prototype-independent)
  (format t "~&star-canonical-json tests passed~%")
  t)
