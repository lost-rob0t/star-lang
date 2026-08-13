(in-package :starlangruntime)

(define-condition actor-runtime-error (error)
  ((message :initarg :message :reader actor-runtime-error-message))
  (:report
   (lambda (condition stream)
     (write-string (actor-runtime-error-message condition) stream))))

(define-condition actor-definition-error (actor-runtime-error) ())
(define-condition actor-already-registered-error (actor-runtime-error) ())
(define-condition actor-not-found-error (actor-runtime-error) ())
(define-condition actor-stopped-error (actor-runtime-error) ())
(define-condition actor-external-dispatch-required-error (actor-runtime-error) ())
(define-condition actor-contract-error (actor-runtime-error) ())

(defun fail-actor (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defstruct (actor-definition
            (:constructor %make-actor-definition
                (&key name
                      service-uri
                      kind
                      handler
                      accepts
                      produces
                      input-validator
                      output-validator
                      initial-state
                      restart-policy
                      metadata)))
  (name "" :type string)
  (service-uri "" :type string)
  (kind :native :type keyword)
  handler
  accepts
  produces
  input-validator
  output-validator
  initial-state
  (restart-policy :permanent :type keyword)
  metadata)

(defstruct (actor-instance
            (:constructor %make-actor-instance
                (&key definition data)))
  (definition (error "DEFINITION is required") :type actor-definition)
  (status :running :type keyword)
  data
  (generation 0 :type (integer 0 *))
  (invocation-count 0 :type (integer 0 *))
  last-error)

(defstruct (runtime (:constructor %make-runtime))
  (actors-by-name (make-hash-table :test #'equal) :type hash-table)
  (actors-by-uri (make-hash-table :test #'equal) :type hash-table))

(defun make-runtime ()
  (%make-runtime))

(defun default-local-service-uri (name)
  (format nil "star://local:localhost:~A" name))

(defun ensure-actor-kind (kind)
  (unless (member kind '(:native :external) :test #'eq)
    (fail-actor 'actor-definition-error
                "Actor kind must be :NATIVE or :EXTERNAL, received ~S."
                kind))
  kind)

(defun ensure-validator (validator label)
  (unless (or (null validator) (functionp validator))
    (fail-actor 'actor-definition-error
                "Actor ~A validator must be a function or NIL, received ~S."
                label
                validator))
  validator)

(defun canonical-service-uri (name service-uri)
  (handler-case
      (staractorprotocol:canonical-star-service-uri-for-actor
       name
       (or service-uri (default-local-service-uri name)))
    (staractorprotocol:invalid-star-service-uri-error (condition)
      (fail-actor 'actor-definition-error "~A" condition))))

(defun make-native-actor-definition
    (name handler
     &key
       service-uri
       accepts
       produces
       input-validator
       output-validator
       initial-state
       (restart-policy :permanent)
       metadata)
  (unless (functionp handler)
    (fail-actor 'actor-definition-error
                "Native actor ~S requires a function handler."
                name))
  (%make-actor-definition
   :name name
   :service-uri (canonical-service-uri name service-uri)
   :kind :native
   :handler handler
   :accepts accepts
   :produces produces
   :input-validator (ensure-validator input-validator "input")
   :output-validator (ensure-validator output-validator "output")
   :initial-state initial-state
   :restart-policy restart-policy
   :metadata metadata))

(defun make-external-actor-definition
    (name service-uri
     &key
       accepts
       produces
       input-validator
       output-validator
       (restart-policy :permanent)
       metadata)
  (%make-actor-definition
   :name name
   :service-uri (canonical-service-uri name service-uri)
   :kind :external
   :handler nil
   :accepts accepts
   :produces produces
   :input-validator (ensure-validator input-validator "input")
   :output-validator (ensure-validator output-validator "output")
   :initial-state nil
   :restart-policy restart-policy
   :metadata metadata))

(defun initialized-actor-state (initial-state)
  (cond
    ((functionp initial-state) (funcall initial-state))
    ((consp initial-state) (copy-tree initial-state))
    (t initial-state)))

(defun validate-definition (definition)
  (unless (actor-definition-p definition)
    (fail-actor 'actor-definition-error
                "Expected an actor definition, received ~S."
                definition))
  (ensure-actor-kind (actor-definition-kind definition))
  (setf (actor-definition-service-uri definition)
        (canonical-service-uri
         (actor-definition-name definition)
         (actor-definition-service-uri definition)))
  (when (and (eq :native (actor-definition-kind definition))
             (not (functionp (actor-definition-handler definition))))
    (fail-actor 'actor-definition-error
                "Native actor ~A has no callable handler."
                (actor-definition-name definition)))
  (ensure-validator (actor-definition-input-validator definition) "input")
  (ensure-validator (actor-definition-output-validator definition) "output")
  definition)

(defun instantiate-actor (definition)
  (validate-definition definition)
  (%make-actor-instance
   :definition definition
   :data (initialized-actor-state (actor-definition-initial-state definition))))

(defun actor-running-p (actor)
  (and (actor-instance-p actor)
       (eq :running (actor-instance-status actor))))

(defun runtime-actor-count (runtime)
  (hash-table-count (runtime-actors-by-name runtime)))

(defun actor-name (actor)
  (actor-definition-name (actor-instance-definition actor)))

(defun actor-service-uri (actor)
  (actor-definition-service-uri (actor-instance-definition actor)))

(defun register-actor (runtime actor)
  (unless (runtime-p runtime)
    (fail-actor 'actor-runtime-error "Expected a StarLang runtime, received ~S." runtime))
  (unless (actor-instance-p actor)
    (fail-actor 'actor-definition-error "Expected an actor instance, received ~S." actor))
  (let ((name (actor-name actor))
        (service-uri (actor-service-uri actor)))
    (when (or (gethash name (runtime-actors-by-name runtime))
              (gethash service-uri (runtime-actors-by-uri runtime)))
      (fail-actor 'actor-already-registered-error
                  "Actor ~A (~A) is already registered."
                  name
                  service-uri))
    (setf (gethash name (runtime-actors-by-name runtime)) actor
          (gethash service-uri (runtime-actors-by-uri runtime)) actor)
    actor))

(defun create-actor (runtime definition)
  (register-actor runtime (instantiate-actor definition)))

(defun create-native-actor (runtime name handler &rest options)
  (create-actor runtime
                (apply #'make-native-actor-definition name handler options)))

(defun create-external-actor (runtime name service-uri &rest options)
  (create-actor runtime
                (apply #'make-external-actor-definition name service-uri options)))

(defun find-actor (runtime target)
  (cond
    ((actor-instance-p target) target)
    ((and (stringp target)
          (staractorprotocol:star-service-uri-target-p target))
     (handler-case
         (gethash
          (staractorprotocol:star-service-uri-string
           (staractorprotocol:parse-star-service-uri target))
          (runtime-actors-by-uri runtime))
       (staractorprotocol:invalid-star-service-uri-error () nil)))
    ((stringp target)
     (gethash target (runtime-actors-by-name runtime)))
    (t nil)))

(defun resolve-actor (runtime target)
  (or (find-actor runtime target)
      (fail-actor 'actor-not-found-error
                  "No actor registered for target ~S."
                  target)))

(defun unregister-actor (runtime target)
  (let* ((actor (resolve-actor runtime target))
         (name (actor-name actor))
         (service-uri (actor-service-uri actor)))
    (remhash name (runtime-actors-by-name runtime))
    (remhash service-uri (runtime-actors-by-uri runtime))
    actor))

(defun stop-actor (runtime target)
  (let ((actor (resolve-actor runtime target)))
    (setf (actor-instance-status actor) :stopped)
    actor))

(defun start-actor (runtime target)
  (let ((actor (resolve-actor runtime target)))
    (unless (eq :running (actor-instance-status actor))
      (incf (actor-instance-generation actor)))
    (setf (actor-instance-status actor) :running
          (actor-instance-last-error actor) nil)
    actor))

(defun restart-actor (runtime target)
  (let ((actor (resolve-actor runtime target)))
    (setf (actor-instance-status actor) :stopped)
    (start-actor runtime actor)))

(defun contract-valid-p (validator contract value)
  (or (null validator)
      (funcall validator contract value)))

(defun validate-contract (condition-label validator contract value actor)
  (unless (contract-valid-p validator contract value)
    (fail-actor 'actor-contract-error
                "Actor ~A rejected its ~A contract ~S for value ~S."
                (actor-name actor)
                condition-label
                contract
                value)))

(defun invoke-native-handler (actor message runtime)
  (let* ((definition (actor-instance-definition actor))
         (values
           (multiple-value-list
            (funcall (actor-definition-handler definition)
                     message
                     (actor-instance-data actor)
                     runtime))))
    (unless values
      (fail-actor 'actor-contract-error
                  "Actor ~A returned no values."
                  (actor-name actor)))
    (values (first values)
            (and (> (length values) 1) (second values))
            (> (length values) 1))))

(defun invoke-actor (runtime target message)
  (let* ((actor (resolve-actor runtime target))
         (definition (actor-instance-definition actor)))
    (handler-case
        (progn
          (unless (actor-running-p actor)
            (fail-actor 'actor-stopped-error
                        "Actor ~A is stopped."
                        (actor-name actor)))
          (when (eq :external (actor-definition-kind definition))
            (fail-actor 'actor-external-dispatch-required-error
                        "Actor ~A is external at ~A; a transport dispatcher is required."
                        (actor-name actor)
                        (actor-service-uri actor)))
          (validate-contract
           "input"
           (actor-definition-input-validator definition)
           (actor-definition-accepts definition)
           message
           actor)
          (multiple-value-bind (result next-state state-supplied-p)
              (invoke-native-handler actor message runtime)
            (validate-contract
             "output"
             (actor-definition-output-validator definition)
             (actor-definition-produces definition)
             result
             actor)
            ;; State changes commit only after the output contract succeeds.
            (when state-supplied-p
              (setf (actor-instance-data actor) next-state))
            (incf (actor-instance-invocation-count actor))
            (setf (actor-instance-last-error actor) nil)
            result))
      (actor-runtime-error (condition)
        (setf (actor-instance-last-error actor) condition)
        (error condition))
      (error (condition)
        (setf (actor-instance-last-error actor) condition)
        (error condition)))))
