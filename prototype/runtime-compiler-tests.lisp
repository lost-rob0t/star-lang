(load (merge-pathnames "star-lang-api.lisp" *load-truename*))

(in-package #:cl-user)

(defun runtime-compiler-test-fail (control &rest arguments)
  (error (apply #'format nil control arguments)))

(defun assert-true (value label)
  (unless value
    (runtime-compiler-test-fail "Assertion failed: ~A." label)))

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (runtime-compiler-test-fail "~A expected ~S, received ~S."
                                label expected actual)))

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun package-function (package-name function-name)
  (let* ((package (or (find-package package-name)
                      (runtime-compiler-test-fail
                       "Missing package ~A." package-name)))
         (symbol (find-symbol (string-upcase function-name) package)))
    (unless (and symbol (fboundp symbol))
      (runtime-compiler-test-fail "Missing function ~A::~A."
                                  package-name function-name))
    (symbol-function symbol)))

(defun temp-cache (label)
  (merge-pathnames
   (format nil "star-lang-runtime-compiler-~A-~36R/"
           label
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun person-from-package (package-name)
  (funcall (package-function package-name "new-person")
           "people" "Ada" "Lovelace" "person"
           :bio "Mathematician"))

(defun run-runtime-compiler-tests (&optional fixture-path)
  (let* ((fixture
           (or fixture-path
               (merge-pathnames "../fixtures/star-cl-constructors.star"
                                *load-truename*)))
         (default-package "STARINTEL.RUNTIME-COMPILER.DEFAULT")
         (eval-package "STARINTEL.RUNTIME-COMPILER.EVAL"))
    (assert-equal :eval
                  (star-lang.api:normalize-runtime-compiler :eval)
                  "keyword runtime compiler normalization")
    (assert-equal :eval
                  (star-lang.api:normalize-runtime-compiler "eval")
                  "string runtime compiler normalization")

    (star-lang.api:load-star-runtime
     fixture
     :cache-directory (temp-cache "default")
     :constructor-package default-package)
    (star-lang.api:load-star-runtime
     fixture
     :cache-directory (temp-cache "eval")
     :constructor-package eval-package
     :runtime-compiler :eval)

    (let ((default-person (person-from-package default-package))
          (eval-person (person-from-package eval-package)))
      (dolist (field '("dataset" "fname" "lname" "etype" "bio"))
        (assert-equal
         (star-lang.document-runtime:document-value default-person field)
         (star-lang.document-runtime:document-value eval-person field)
         (format nil "default/eval equivalence for ~A" field))))

    (assert-true
     (condition-signaled-p
      'star-lang.constructor-runtime:constructor-runtime-error
      (lambda ()
        (star-lang.api:normalize-runtime-compiler :unsupported)))
     "unsupported runtime compiler rejection")

    (assert-true
     (condition-signaled-p
      'star-lang.constructor-runtime:constructor-runtime-error
      (lambda ()
        (star-lang.api:load-star-runtime
         fixture
         :cache-directory (temp-cache "unsupported")
         :constructor-package "STARINTEL.RUNTIME-COMPILER.UNSUPPORTED"
         :runtime-compiler :unsupported)))
     "load-star-runtime rejects unsupported compiler before materialization")

    (format t "Star-Lang runtime compiler tests passed.~%")
    t))

(unless (run-runtime-compiler-tests)
  (error "Star-Lang runtime compiler tests failed."))
