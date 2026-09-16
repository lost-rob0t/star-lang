(defpackage :starlangruntime-ownership-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:actor-runtime-error
                #:actor-already-registered-error
                #:make-runtime
                #:shutdown-runtime
                #:runtime-actor-count
                #:make-native-actor-definition
                #:instantiate-actor
                #:register-actor
                #:create-native-actor
                #:unregister-actor
                #:tell
                #:ask
                #:dispatch-next
                #:stop-actor
                #:start-actor
                #:restart-actor
                #:actor-mailbox-depth
                #:delivery-result-status)
  (:export #:run-tests))

(in-package :starlangruntime-ownership-tests)

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

(defun make-echo-actor (runtime name calls)
  (create-native-actor
   runtime
   name
   (lambda (message state owner)
     (declare (ignore state owner))
     (incf (car calls))
     message)))

(defun test-foreign-raw-instance-ask-rejected ()
  (let ((left (make-runtime))
        (right (make-runtime))
        (calls (list 0)))
    (unwind-protect
         (let ((actor (make-echo-actor left "owned" calls)))
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (ask right actor :foreign)))
            "Foreign runtime ASK accepted a raw actor instance.")
           (check (zerop (car calls))
                  "Foreign runtime ASK executed the owner actor handler.")
           (check (= 1 (runtime-actor-count left))
                  "Foreign runtime ASK changed owner registry state.")
           (check (zerop (runtime-actor-count right))
                  "Foreign runtime ASK populated the foreign registry.")
           (check (eq :owner (ask left actor :owner))
                  "Owner runtime could not invoke its registered actor."))
      (shutdown-runtime left)
      (shutdown-runtime right))))

(defun test-foreign-unregister-cannot-delete-same-name-actor ()
  (let ((left (make-runtime))
        (right (make-runtime))
        (left-calls (list 0))
        (right-calls (list 0)))
    (unwind-protect
         (let ((left-actor (make-echo-actor left "same-name" left-calls))
               (right-actor (make-echo-actor right "same-name" right-calls)))
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (unregister-actor right left-actor)))
            "Foreign UNREGISTER-ACTOR accepted another runtime's raw instance.")
           (check (= 1 (runtime-actor-count left))
                  "Foreign unregister changed owner registry state.")
           (check (= 1 (runtime-actor-count right))
                  "Foreign unregister removed the same-named local actor.")
           (check (eq :left (ask left left-actor :left))
                  "Owner actor stopped resolving after rejected foreign unregister.")
           (check (eq :right (ask right right-actor :right))
                  "Same-named foreign actor was removed by rejected unregister."))
      (shutdown-runtime left)
      (shutdown-runtime right))))

(defun test-foreign-instance-operations-have-no-effects ()
  (let ((left (make-runtime))
        (right (make-runtime))
        (calls (list 0)))
    (unwind-protect
         (let ((actor (make-echo-actor left "operations" calls)))
           (dolist (operation
                    (list
                     (cons "TELL" (lambda () (tell right actor :foreign)))
                     (cons "DISPATCH-NEXT" (lambda () (dispatch-next right actor)))
                     (cons "STOP-ACTOR" (lambda () (stop-actor right actor)))
                     (cons "START-ACTOR" (lambda () (start-actor right actor)))
                     (cons "RESTART-ACTOR" (lambda () (restart-actor right actor)))))
             (check
              (signals-p 'actor-runtime-error (cdr operation))
              "Foreign runtime ~A accepted another runtime's raw actor instance."
              (car operation)))
           (check (zerop (car calls))
                  "Rejected foreign instance operations executed the actor handler.")
           (check (zerop (actor-mailbox-depth actor))
                  "Rejected foreign instance operations mutated the owner mailbox.")
           (check (= 1 (runtime-actor-count left))
                  "Rejected foreign instance operations changed the owner registry.")
           (check (zerop (runtime-actor-count right))
                  "Rejected foreign instance operations changed the foreign registry.")
           (check (eq :owner (ask left actor :owner))
                  "Rejected foreign operations changed owner actor liveness."))
      (shutdown-runtime left)
      (shutdown-runtime right))))

(defun test-detached-instance-is-not-in-vocation-target ()
  (let ((runtime (make-runtime))
        (calls (list 0)))
    (unwind-protect
         (let* ((definition
                  (make-native-actor-definition
                   "detached"
                   (lambda (message state owner)
                     (declare (ignore state owner))
                     (incf (car calls))
                     message)))
                (actor (instantiate-actor definition)))
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (ask runtime actor :before-register)))
            "Unregistered actor instance was invocable through ASK.")
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (tell runtime actor :before-register)))
            "Unregistered actor instance accepted TELL.")
           (check (zerop (car calls))
                  "Unregistered actor instance executed its handler.")
           (check (zerop (actor-mailbox-depth actor))
                  "Unregistered actor instance accepted mailbox work.")
           (register-actor runtime actor)
           (check (eq :registered (ask runtime actor :registered))
                  "Registered actor instance was not invocable by its owner.")
           (unregister-actor runtime actor)
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (ask runtime actor :after-unregister)))
            "Unregistered actor instance remained invocable after removal.")
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (tell runtime actor :after-unregister)))
            "Unregistered actor instance accepted TELL after removal.")
           (check (zerop (runtime-actor-count runtime))
                  "Unregister did not leave the runtime registry empty."))
      (shutdown-runtime runtime))))

(defun test-instance-registration-has-one-runtime-owner ()
  (let ((left (make-runtime))
        (right (make-runtime)))
    (unwind-protect
         (let* ((definition
                  (make-native-actor-definition
                   "exclusive-owner"
                   (lambda (message state owner)
                     (declare (ignore state owner))
                     message)))
                (actor (instantiate-actor definition)))
           (register-actor left actor)
           (check
            (signals-p 'actor-already-registered-error
                       (lambda () (register-actor left actor)))
            "Duplicate registration in the owning runtime was not rejected.")
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (register-actor right actor)))
            "The same actor instance was registered by a second runtime.")
           (check (= 1 (runtime-actor-count left))
                  "Registration conflict changed the owner registry.")
           (check (zerop (runtime-actor-count right))
                  "Registration conflict populated the second registry.")
           (check (eq :owner (ask left actor :owner))
                  "Registration conflict damaged the owner actor."))
      (shutdown-runtime left)
      (shutdown-runtime right))))

(defun test-shutdown-runtime-cannot-dispatch-foreign-instance ()
  (let ((owner (make-runtime))
        (stopped (make-runtime))
        (calls (list 0)))
    (unwind-protect
         (let ((actor (make-echo-actor owner "foreign-after-shutdown" calls)))
           (shutdown-runtime stopped)
           (check
            (signals-p 'actor-runtime-error
                       (lambda () (ask stopped actor :foreign)))
            "Shut-down runtime accepted ASK for a foreign live actor.")
           (check (zerop (car calls))
                  "Shut-down runtime executed a foreign actor handler.")
           (check (zerop (actor-mailbox-depth actor))
                  "Shut-down runtime mutated a foreign actor mailbox.")
           (check (eq :owner (ask owner actor :owner))
                  "Foreign shutdown probe changed the owner actor."))
      (shutdown-runtime owner)
      (shutdown-runtime stopped))))

(defun test-owner-shutdown-preserves-late-tell-contract ()
  (let ((runtime (make-runtime)))
    (let ((actor
            (create-native-actor
             runtime
             "owned-shutdown"
             (lambda (message state owner)
               (declare (ignore state owner))
               message))))
      (shutdown-runtime runtime)
      (check
       (eq :stopped (delivery-result-status (tell runtime actor :late)))
       "Owner runtime shutdown changed the documented late TELL result."))))

(defun run-tests ()
  (test-foreign-raw-instance-ask-rejected)
  (test-foreign-unregister-cannot-delete-same-name-actor)
  (test-foreign-instance-operations-have-no-effects)
  (test-detached-instance-is-not-in-vocation-target)
  (test-instance-registration-has-one-runtime-owner)
  (test-shutdown-runtime-cannot-dispatch-foreign-instance)
  (test-owner-shutdown-preserves-late-tell-contract)
  (format t "~&starlang-runtime ownership tests passed~%")
  t)
