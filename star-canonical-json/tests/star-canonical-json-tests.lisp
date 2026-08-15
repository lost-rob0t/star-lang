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

(defun test-unsupported-node-is-typed ()
  (check
   (signals-p
    'invalid-canonical-json-error
    (lambda ()
      (canonical-json-string 1.5d0)))
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
  (test-unsupported-node-is-typed)
  (test-final-system-is-prototype-independent)
  (format t "~&star-canonical-json tests passed~%")
  t)
