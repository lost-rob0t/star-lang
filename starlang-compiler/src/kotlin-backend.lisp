(in-package :starlangcompiler)

(defun kotlin-string-literal (value)
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop for character across value
          do (case character
               (#\\ (write-string "\\\\" stream))
               (#\" (write-string "\\\"" stream))
               (#\Newline (write-string "\\n" stream))
               (#\Return (write-string "\\r" stream))
               (#\Tab (write-string "\\t" stream))
               (otherwise (write-char character stream))))
    (write-char #\" stream)))

(defun kotlin-list-of-strings (values)
  (if values
      (format nil "listOf(~{~A~^, ~})"
              (mapcar #'kotlin-string-literal values))
      "emptyList()"))

(defun kotlin-restart-policy (restart)
  (ecase restart
    (:permanent "RestartPolicy.PERMANENT")
    (:transient "RestartPolicy.TRANSIENT")
    (:temporary "RestartPolicy.TEMPORARY")))

(defun kotlin-metadata-value (value)
  (etypecase value
    (string
     (format nil "PortableValue.Text(~A)"
             (kotlin-string-literal value)))
    (integer
     (unless (<= (- (expt 2 63)) value (1- (expt 2 63)))
       (error "Kotlin runtime metadata integer ~S is outside signed 64-bit range."
              value))
     (format nil "PortableValue.Int64(~DL)" value))))

(defun kotlin-metadata-map (metadata)
  (if metadata
      (format nil "mapOf(~{~A~^, ~})"
              (mapcar
               (lambda (entry)
                 (format nil "~A to ~A"
                         (kotlin-string-literal (car entry))
                         (kotlin-metadata-value (cdr entry))))
               metadata))
      "emptyMap()"))

(defun kotlin-object-name (actor-name)
  (let ((capitalize-next t))
    (with-output-to-string (stream)
      (loop for character across actor-name
            do (cond
                 ((alphanumericp character)
                  (write-char
                   (if capitalize-next
                       (char-upcase character)
                       character)
                   stream)
                  (setf capitalize-next nil))
                 (t
                  (setf capitalize-next t)))))))

(defun actor-mailbox-capacity-for-kotlin (actor)
  (let ((mailbox (getf actor :mailbox)))
    (unless (and (eq (getf mailbox :kind) :bounded)
                 (integerp (getf mailbox :capacity))
                 (plusp (getf mailbox :capacity)))
      (error "Kotlin backend requires a bounded positive mailbox, received ~S."
             mailbox))
    (getf mailbox :capacity)))

(defun actor-service-uri-for-kotlin (actor)
  (or (getf actor :service-uri)
      (format nil "star://local:localhost:~A" (getf actor :name))))

(defun generate-kotlin-actor-binding
    (actor &key
             (package-name "actor.starintel.starlang.generated")
             object-name)
  "Emit deterministic Kotlin source that materializes one runtime-neutral actor IR.

The generated unit targets runtime-jvm and resolves native handlers from an
explicit handler map. It never evaluates host code or consults a global handler
registry."
  (unless (and (listp actor) (eq (getf actor :kind) :actor))
    (error "Expected StarLang actor IR, received ~S." actor))
  (let* ((name (getf actor :name))
         (runtime (getf actor :runtime))
         (object
           (or object-name
               (concatenate
                'string
                (kotlin-object-name name)
                "StarActor")))
         (service-uri (actor-service-uri-for-kotlin actor))
         (accepts (kotlin-list-of-strings (getf actor :accepts)))
         (produces (kotlin-list-of-strings (getf actor :produces)))
         (capabilities
           (kotlin-list-of-strings (getf actor :capabilities)))
         (metadata (kotlin-metadata-map (getf actor :metadata)))
         (restart (kotlin-restart-policy (getf actor :restart)))
         (mailbox-capacity (actor-mailbox-capacity-for-kotlin actor)))
    (with-output-to-string (stream)
      (format stream "package ~A~%~%" package-name)
      (format stream "import actor.starintel.starlang.runtime.*~%~%")
      (format stream "object ~A {~%" object)
      (format stream "    const val ACTOR_NAME: String = ~A~%"
              (kotlin-string-literal name))
      (format stream "    const val SERVICE_URI: String = ~A~%~%"
              (kotlin-string-literal service-uri))
      (ecase runtime
        (:native
         (let ((handler (getf actor :handler)))
           (unless handler
             (error "Native actor ~A has no handler in IR." name))
           (format stream "    const val HANDLER_NAME: String = ~A~%~%"
                   (kotlin-string-literal handler))
           (format stream "    @JvmStatic~%")
           (format stream
                   "    fun definition(handlers: Map<String, ActorHandler>): ActorDefinition =~%")
           (format stream "        ActorDefinition.nativeActor(~%")
           (format stream "            name = ACTOR_NAME,~%")
           (format stream "            serviceUri = SERVICE_URI,~%")
           (format stream
                   "            handler = handlers.getValue(HANDLER_NAME),~%")
           (format stream "            accepts = ~A,~%" accepts)
           (format stream "            produces = ~A,~%" produces)
           (format stream "            restartPolicy = ~A,~%" restart)
           (format stream "            mailboxCapacity = ~D,~%"
                   mailbox-capacity)
           (format stream "            capabilities = ~A,~%" capabilities)
           (format stream "            metadata = ~A,~%" metadata)
           (format stream "        )~%")))
        (:external
         (format stream "    @JvmStatic~%")
         (format stream "    fun definition(): ActorDefinition =~%")
         (format stream "        ActorDefinition.externalActor(~%")
         (format stream "            name = ACTOR_NAME,~%")
         (format stream "            serviceUri = SERVICE_URI,~%")
         (format stream "            protocol = ~A,~%"
                 (kotlin-string-literal (getf actor :protocol)))
         (format stream "            endpoint = ~A,~%"
                 (kotlin-string-literal (getf actor :endpoint)))
         (format stream "            accepts = ~A,~%" accepts)
         (format stream "            produces = ~A,~%" produces)
         (format stream "            restartPolicy = ~A,~%" restart)
         (format stream "            mailboxCapacity = ~D,~%"
                 mailbox-capacity)
         (format stream "            capabilities = ~A,~%" capabilities)
         (format stream "            metadata = ~A,~%" metadata)
         (format stream "        )~%")))
      (format stream "~%    @JvmStatic~%")
      (if (eq runtime :native)
          (progn
            (format stream
                    "    fun register(runtime: StarRuntime, handlers: Map<String, ActorHandler>): ActorInstance =~%")
            (format stream
                    "        runtime.spawn(definition(handlers))~%"))
          (progn
            (format stream
                    "    fun register(runtime: StarRuntime): ActorInstance =~%")
            (format stream
                    "        runtime.spawn(definition())~%")))
      (format stream "}~%"))))
