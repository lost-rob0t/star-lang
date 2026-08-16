(defpackage :starlogicir-tests
  (:use :cl)
  (:export #:run-tests))

(in-package :starlogicir-tests)

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

(defun make-test-identity ()
  (starlogicir:make-logic-package-identity
   :package-id "logic.ownership"
   :package-version "1.0.0"
   :package-digest "sha256:package-ownership-v1"
   :mapping-id "mapping.ownership"
   :mapping-digest "sha256:mapping-ownership-v1"))

(defun make-test-call
    (&key
       (backend-policy "auto")
       (operation-kind "solutions")
       (named-operation-id "ownership-path")
       (semantic-profile "star.logic.query/1")
       (required-capabilities '("named-query"))
       (required-hard-limits '("answers"))
       (required-isolation "process")
       (bindings '(("subject" . "alice")))
       (answer-policy '(("limit" . 10)))
       (proof-policy '(("mode" . "optional")))
       (budget '(("answers" . 10)))
       (source-span '(("sourceId" . "fixture.star")
                      ("startLine" . 1)
                      ("startColumn" . 1)))
       (package-identity (make-test-identity)))
  (starlogicir:make-logic-call
   :operation-id "op-001"
   :named-operation-id named-operation-id
   :operation-kind operation-kind
   :semantic-profile semantic-profile
   :backend-policy backend-policy
   :bindings bindings
   :answer-policy answer-policy
   :proof-policy proof-policy
   :required-capabilities required-capabilities
   :required-hard-limits required-hard-limits
   :required-isolation required-isolation
   :package-identity package-identity
   :budget budget
   :source-span source-span))

(defun make-test-backend
    (id &key
          (version "1")
          (build-id (format nil "~A-build" id))
          (profiles '("star.logic.query/1"))
          (capabilities '("named-query"))
          (isolation '("process"))
          (hard-limits '("answers")))
  (starlogictesting:make-fake-logic-backend
   :id id
   :version version
   :build-id build-id
   :semantic-profiles profiles
   :capabilities capabilities
   :isolation-classes isolation
   :hard-limits hard-limits))

(defun registry-with (&rest backends)
  (let ((registry (starlogicprotocol:make-logic-backend-registry)))
    (dolist (backend backends registry)
      (starlogicprotocol:register-logic-backend registry backend))))

(defun make-canonical-fixture-plan ()
  (let* ((call
           (make-test-call
            :backend-policy "auto"
            :bindings '(("from" . "source-1") ("to" . "?target"))
            :answer-policy '(("duplicates" . "preserve")
                             ("limit" . 10)
                             ("order" . "canonical"))
            :proof-policy '(("mode" . "optional"))
            :budget '(("answers" . 10))))
         (registry
           (registry-with
            (make-test-backend "lisa"
                               :version "0.8"
                               :build-id "lisa-build-1"
                               :profiles '("star.expert.production/1"))
            (make-test-backend "n-prolog"
                               :version "1.94"
                               :build-id "nprolog-build-1"
                               :profiles '("star.logic.portable-prolog/1"))
            (make-test-backend "swi-prolog"
                               :version "9.0"
                               :build-id "swi-build-1"))))
    (starlogicir:materialize-logic-call call registry)))

(defun read-file-string (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))
