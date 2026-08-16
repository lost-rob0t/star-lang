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

(defun test-explicit-canonical-pins-materialize ()
  (dolist (id '("lisa" "swi-prolog" "n-prolog"))
    (let* ((backend (make-test-backend id))
           (registry (registry-with backend))
           (plan (starlogicir:materialize-logic-call
                  (make-test-call :backend-policy id)
                  registry)))
      (check (string= id (starlogicir:materialized-logic-call-backend-id plan))
             "Explicit pin ~A materialized the wrong backend." id)
      (check (string= id
                      (starlogicprotocol:logic-selection-evidence-selected
                       (starlogicir:materialized-logic-call-selection-evidence plan)))
             "Explicit pin ~A did not retain selection evidence." id))))

(defun test-unknown-and-missing-policy-fail-in-ir ()
  (check
   (signals-p 'starlogicir:invalid-logic-backend-policy-error
              (lambda () (make-test-call :backend-policy "bogus")))
   "Normalized IR accepted an unknown backend policy.")
  (check
   (signals-p 'starlogicir:invalid-logic-backend-policy-error
              (lambda () (make-test-call :backend-policy nil)))
   "Normalized IR accepted a missing backend policy."))

(defun test-known-but-unregistered-backend-fails ()
  (check
   (signals-p
    'starlogicprotocol:logic-backend-not-found-error
    (lambda ()
      (starlogicir:materialize-logic-call
       (make-test-call :backend-policy "swi-prolog")
       (starlogicprotocol:make-logic-backend-registry))))
   "Materialization accepted a known explicit backend that was not registered."))

(defun test-incompatible-semantic-profile-fails ()
  (let ((registry
          (registry-with
           (make-test-backend "swi-prolog"
                              :profiles '("star.logic.tabled/1")))))
    (check
     (signals-p
      'starlogicprotocol:logic-backend-incompatible-error
      (lambda ()
        (starlogicir:materialize-logic-call
         (make-test-call :backend-policy "swi-prolog") registry)))
     "Explicit materialization ignored a semantic-profile mismatch.")))

(defun test-missing-capability-fails ()
  (let ((registry
          (registry-with
           (make-test-backend "swi-prolog" :capabilities '("named-query")))))
    (check
     (signals-p
      'starlogicprotocol:logic-backend-incompatible-error
      (lambda ()
        (starlogicir:materialize-logic-call
         (make-test-call :backend-policy "swi-prolog"
                         :required-capabilities '("named-query" "tabling"))
         registry)))
     "Explicit materialization ignored a missing capability.")))

(defun test-missing-hard-limit-fails ()
  (let ((registry
          (registry-with
           (make-test-backend "swi-prolog" :hard-limits '("answers")))))
    (check
     (signals-p
      'starlogicprotocol:logic-backend-incompatible-error
      (lambda ()
        (starlogicir:materialize-logic-call
         (make-test-call :backend-policy "swi-prolog"
                         :required-hard-limits '("answers" "output-bytes"))
         registry)))
     "Explicit materialization ignored a missing hard limit.")))

(defun test-missing-isolation-fails ()
  (let ((registry
          (registry-with
           (make-test-backend "swi-prolog" :isolation '("in-process")))))
    (check
     (signals-p
      'starlogicprotocol:logic-backend-incompatible-error
      (lambda ()
        (starlogicir:materialize-logic-call
         (make-test-call :backend-policy "swi-prolog") registry)))
     "Explicit materialization ignored a missing isolation class.")))

(defun test-auto-selects-exactly-one-compatible-candidate ()
  (let* ((swi (make-test-backend "swi-prolog"))
         (registry
           (registry-with
            (make-test-backend "lisa"
                               :profiles '("star.expert.production/1"))
            (make-test-backend "n-prolog"
                               :profiles '("star.logic.portable-prolog/1"))
            swi))
         (plan (starlogicir:materialize-logic-call (make-test-call) registry)))
    (check (string= "swi-prolog"
                    (starlogicir:materialized-logic-call-backend-id plan))
           "AUTO did not choose the sole compatible candidate.")))

(defun test-ambiguous-auto-selection-fails ()
  (let ((registry
          (registry-with
           (make-test-backend "swi-prolog")
           (make-test-backend "n-prolog"))))
    (check
     (signals-p
      'starlogicprotocol:logic-backend-selection-error
      (lambda ()
        (starlogicir:materialize-logic-call (make-test-call) registry)))
     "AUTO silently chose between multiple compatible backends.")))

(defun test-selection-evidence-retains-all-candidates-and-reasons ()
  (let* ((registry
           (registry-with
            (make-test-backend "lisa"
                               :profiles '("star.expert.production/1"))
            (make-test-backend "n-prolog"
                               :profiles '("star.logic.portable-prolog/1"))
            (make-test-backend "swi-prolog")))
         (plan (starlogicir:materialize-logic-call (make-test-call) registry))
         (evidence (starlogicir:materialized-logic-call-selection-evidence plan))
         (candidates (starlogicprotocol:logic-selection-evidence-candidates evidence)))
    (check (equal '("lisa" "n-prolog" "swi-prolog")
                  (mapcar #'starlogicprotocol:logic-selection-candidate-backend-id
                          candidates))
           "Selection evidence candidate order is not deterministic: ~S" candidates)
    (check (equal '("semantic profile unavailable"
                    "semantic profile unavailable"
                    nil)
                  (mapcar #'starlogicprotocol:logic-selection-candidate-reason
                          candidates))
           "Selection evidence did not preserve deterministic rejection reasons.")
    (check (equal '(:rejected :rejected :accepted)
                  (mapcar #'starlogicprotocol:logic-selection-candidate-status
                          candidates))
           "Selection evidence candidate statuses are incorrect.")
    (check (string= "swi-prolog"
                    (starlogicprotocol:logic-selection-evidence-selected evidence))
           "Selection evidence lost the selected backend.")))

(defun test-materialized-backend-identity-is-immutable ()
  (let* ((backend
           (make-test-backend "swi-prolog"
                              :version "9.0"
                              :build-id "swi-build-1"))
         (plan
           (starlogicir:materialize-logic-call
            (make-test-call :backend-policy "swi-prolog")
            (registry-with backend))))
    (check (not (fboundp '(setf starlogicir:materialized-logic-call-backend-id)))
           "Materialized backend ID unexpectedly exposes a public SETF writer.")
    (let ((returned-id (starlogicir:materialized-logic-call-backend-id plan)))
      (setf (char returned-id 0) #\X)
      (check (string= "swi-prolog"
                      (starlogicir:materialized-logic-call-backend-id plan))
             "Mutating a returned backend ID changed the materialized plan."))
    (check
     (starlogicir:ensure-materialized-backend-compatible
      plan
      (make-test-backend "swi-prolog"
                         :version "9.0"
                         :build-id "swi-build-1"))
     "Equivalent same-backend/build recovery was rejected.")
    (dolist (replacement
             (list
              (make-test-backend "lisa" :version "9.0" :build-id "swi-build-1")
              (make-test-backend "swi-prolog" :version "9.1" :build-id "swi-build-1")
              (make-test-backend "swi-prolog" :version "9.0" :build-id "swi-build-2")))
      (check
       (signals-p
        'starlogicir:logic-materialized-backend-change-error
        (lambda ()
          (starlogicir:ensure-materialized-backend-compatible plan replacement)))
       "Materialized plan accepted a backend identity/build change."))))

(defun test-package-and-mapping-identity-survive-materialization ()
  (let* ((identity (make-test-identity))
         (call (make-test-call :backend-policy "swi-prolog"
                               :package-identity identity))
         (plan
           (starlogicir:materialize-logic-call
            call (registry-with (make-test-backend "swi-prolog"))))
         (materialized-identity
           (starlogicir:materialized-logic-call-package-identity plan)))
    (check (eq identity materialized-identity)
           "Materialization replaced the checked package identity object.")
    (check (string= "logic.ownership"
                    (starlogicir:logic-package-identity-package-id
                     materialized-identity))
           "Materialization lost package identity.")
    (check (string= "sha256:package-ownership-v1"
                    (starlogicir:logic-package-identity-package-digest
                     materialized-identity))
           "Materialization lost package digest.")
    (check (string= "mapping.ownership"
                    (starlogicir:logic-package-identity-mapping-id
                     materialized-identity))
           "Materialization lost mapping identity.")
    (check (string= "sha256:mapping-ownership-v1"
                    (starlogicir:logic-package-identity-mapping-digest
                     materialized-identity))
           "Materialization lost mapping digest.")))

(defun test-native-engine-handles-cannot-enter-normalized-ir ()
  (check
   (signals-p
    'starlogicir:invalid-logic-value-error
    (lambda ()
      (make-test-call :bindings
                      (list (cons "engineHandle" (make-hash-table))))))
   "Normalized IR accepted a hash-table engine handle.")
  (check
   (signals-p
    'starlogicir:invalid-logic-value-error
    (lambda ()
      (make-test-call :bindings
                      (list (cons "engineHandle"
                                  (make-test-backend "swi-prolog"))))))
   "Normalized IR accepted a native backend object."))

(defun test-raw-backend-executable-forms-are-rejected ()
  (check
   (signals-p
    'starlogicir:invalid-logic-value-error
    (lambda ()
      (make-test-call :bindings
                      '(("goal" . (parent alice bob))))))
   "Normalized IR accepted a raw Prolog-style executable form.")
  (check
   (signals-p
    'starlogicir:invalid-logic-value-error
    (lambda ()
      (make-test-call :bindings
                      '(("rule" . (defrule risky-rule (person ?x) => (call-host ?x)))))))
   "Normalized IR accepted a raw LISA/Common Lisp executable form."))

(defun test-invalid-operation-and-package-identity-fail-early ()
  (check
   (signals-p 'starlogicir:invalid-logic-operation-error
              (lambda () (make-test-call :operation-kind "native-call")))
   "Normalized IR accepted an unknown operation kind.")
  (check
   (signals-p
    'starlogicir:invalid-logic-package-identity-error
    (lambda ()
      (starlogicir:make-logic-package-identity
       :package-id "logic.ownership"
       :package-version "1.0.0"
       :package-digest "not-a-digest"
       :mapping-id "mapping.ownership"
       :mapping-digest "sha256:mapping")))
   "Package identity accepted an unlocked package digest."))

(defun test-normalization-is-deterministic-and-defensive ()
  (let* ((bindings '(("zeta" . 2) ("alpha" . 1)))
         (call
           (make-test-call
            :bindings bindings
            :required-capabilities '("tabling" "named-query" "tabling")
            :required-hard-limits '("output-bytes" "answers" "answers"))))
    (check (equal '(("alpha" . 1) ("zeta" . 2))
                  (starlogicir:logic-call-bindings call))
           "Bindings were not normalized deterministically.")
    (check (equal '("named-query" "tabling")
                  (starlogicir:logic-call-required-capabilities call))
           "Capabilities were not normalized deterministically.")
    (check (equal '("answers" "output-bytes")
                  (starlogicir:logic-call-required-hard-limits call))
           "Hard-limit requirements were not normalized deterministically.")
    (setf (cdar bindings) "mutated")
    (check (equal '(("alpha" . 1) ("zeta" . 2))
                  (starlogicir:logic-call-bindings call))
           "Caller mutation changed normalized IR.")))

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

(defun test-canonical-materialized-fixture-is-frozen ()
  (let* ((fixture
           (asdf:system-relative-pathname
            :star-logic-ir "../fixtures/canonical/logic-call-materialized-v1.json"))
         (expected
           (string-right-trim '(#\Newline #\Return)
                              (read-file-string fixture)))
         (actual
           (starlogicir:materialized-logic-call-canonical-json
            (make-canonical-fixture-plan))))
    (check (string= expected actual)
           "Canonical materialized logic fixture drifted.~%Expected: ~A~%Actual:   ~A"
           expected actual)))

(defun test-final-logic-ir-is-prototype-independent ()
  (check (null (find-package "STAR-LANG.PROTOTYPE"))
         "star-logic-ir loaded STAR-LANG.PROTOTYPE transitively.")
  (check (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
         "star-logic-ir loaded the core-surface prototype transitively."))

(defun run-tests ()
  (test-explicit-canonical-pins-materialize)
  (test-unknown-and-missing-policy-fail-in-ir)
  (test-known-but-unregistered-backend-fails)
  (test-incompatible-semantic-profile-fails)
  (test-missing-capability-fails)
  (test-missing-hard-limit-fails)
  (test-missing-isolation-fails)
  (test-auto-selects-exactly-one-compatible-candidate)
  (test-ambiguous-auto-selection-fails)
  (test-selection-evidence-retains-all-candidates-and-reasons)
  (test-materialized-backend-identity-is-immutable)
  (test-package-and-mapping-identity-survive-materialization)
  (test-native-engine-handles-cannot-enter-normalized-ir)
  (test-raw-backend-executable-forms-are-rejected)
  (test-invalid-operation-and-package-identity-fail-early)
  (test-normalization-is-deterministic-and-defensive)
  (test-canonical-materialized-fixture-is-frozen)
  (test-final-logic-ir-is-prototype-independent)
  (format t "~&star-logic-ir tests passed.~%")
  t)
