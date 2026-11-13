;;;; Final compiler tests for canonical hierarchical actor URIs (issue #72),
;;;; native StarLang actor bodies (issue #69), and the domain-server lowering
;;;; migrated from the prototype shell into the final compiler.

(defpackage :starlang-actor-body-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-actor-body-tests)

(def-suite starlang-actor-body-tests
  :description "Canonical actor URIs, native bodies, and domain-server IR.")

(in-suite starlang-actor-body-tests)

(defun data-only-p (value)
  (typecase value
    ((or null boolean string integer keyword symbol) t)
    (cons (and (data-only-p (car value)) (data-only-p (cdr value))))
    (t nil)))

(defun compile-source (source)
  (starlangcompiler:compile-actor-source source))

;;; --------------------------------------------------------------- URIs

(test canonical-actor-uri-lowers-to-resource-uri
  "A hierarchical star:// service URI emits a canonical resource URI and
never a legacy tuple service URI."
  (let ((ir (compile-source
             "(actor ingest-service
                (:runtime native
                 :service-uri \"star://starintel.dev/actor/ingest-service\"
                 :accepts (record)
                 :produces (receipt)
                 :handler h
                 :restart permanent
                 :mailbox (bounded 8)))")))
    (is (string= "star://starintel.dev/actor/ingest-service"
                 (getf ir :resource-uri)))
    (is (null (getf ir :service-uri)))))

(test legacy-tuple-uri-remains-compatibility-input
  "Legacy tuple URIs keep lowering to :service-uri for existing contracts."
  (let ((ir (compile-source
             "(actor w
                (:runtime native
                 :service-uri \"star://fec:localhost:w\"
                 :accepts (x)
                 :produces (x)
                 :handler h
                 :restart permanent
                 :mailbox (bounded 8)))")))
    (is (string= "star://fec:localhost:w" (getf ir :service-uri)))
    (is (null (getf ir :resource-uri)))))

(test canonical-actor-uri-mismatch-is-rejected
  "A hierarchical URI binding a different actor name is rejected."
  (signals starlangcompiler:invalid-star-resource-uri-error
    (compile-source
     "(actor ingest-service
        (:runtime native
         :service-uri \"star://starintel.dev/actor/other\"
         :accepts (x) :produces (x) :handler h
         :restart permanent :mailbox (bounded 8)))")))

(test canonical-actor-uri-must-be-wellformed
  "Malformed hierarchical URIs are rejected with the typed outcome."
  (signals starlangcompiler:invalid-star-resource-uri-error
    (compile-source
     "(actor ingest-service
        (:runtime native
         :service-uri \"star://starintel.dev:4222/actor/ingest-service\"
         :accepts (x) :produces (x) :handler h
         :restart permanent :mailbox (bounded 8)))")))

;;; ------------------------------------------------------- native bodies

(defun body-actor-source ()
  "(actor tracker
     (:runtime native
      :service-uri \"star://starintel.dev/actor/tracker\"
      :accepts (ingest/record@1 ingest/reset@1)
      :produces (ingest/state@1)
      :restart permanent
      :mailbox (bounded 16))

   (state
     (lastSource string :initial \"\" :persistence journaled)
     (sessionNote string :persistence ephemeral))

   (on ingest/record@1 (message context)
     (let ((source (field message sourceId)))
       (when source
         (set lastSource source)))
     (set sessionNote (field message note))
     (reply (construct ingest/state@1
                       (lastSource (state lastSource))
                       (note sessionNote))))

   (on ingest/reset@1 (message context)
     (set lastSource \"\")
     (reply (construct ingest/state@1 (lastSource \"\")))))")

(test body-actor-compiles-without-handler
  "A native actor defined entirely in StarLang lowers to state and handler
IR with no :handler identity (issue #69 gate 2)."
  (let ((ir (compile-source (body-actor-source))))
    (is (null (getf ir :handler)))
    (is (= 2 (length (getf ir :states))))
    (is (= 2 (length (getf ir :handlers))))
    (is (data-only-p ir))))

(test body-actor-state-ir-shape
  "State slots lower to typed, persistence-classified IR slots."
  (let* ((ir (compile-source (body-actor-source)))
         (last-source (first (getf ir :states)))
         (session-note (second (getf ir :states))))
    (is (equal '(:name "lastSource" :type "string" :initial ""
                 :persistence :journaled)
               last-source))
    (is (equal '(:name "sessionNote" :type "string" :initial ""
                 :persistence :ephemeral)
               session-note))))

(test body-actor-handler-ir-shape
  "Handlers lower to typed, data-only bodies bound to message variables."
  (let* ((ir (compile-source (body-actor-source)))
         (record (first (getf ir :handlers))))
    (is (equal "ingest/record@1" (getf record :message-type)))
    (is (equal "message" (getf record :message-var)))
    (is (equal "context" (getf record :context-var)))
    (is (eq :do (first (getf record :body))))
    (is (data-only-p record))))

(test handler-plus-body-is-a-compile-error
  "A native actor cannot mix :handler with a StarLang body (gate 3)."
  (signals starlangcompiler:invalid-actor-error
    (compile-source
     "(actor w
        (:runtime native
         :accepts (x) :produces (x) :handler h
         :restart permanent :mailbox (bounded 1))
      (state (n integer :initial 0))
      (on x (message context) (reply message)))")))

(test external-actor-cannot-declare-a-body
  "Only native actors own StarLang bodies."
  (signals starlangcompiler:invalid-actor-error
    (compile-source
     "(actor w
        (:runtime external
         :protocol p :endpoint \"e\"
         :accepts (x) :produces (x)
         :restart permanent :mailbox (bounded 1))
      (state (n integer :initial 0))
      (on x (message context) (reply message)))")))

(test every-accepted-type-needs-a-handler
  "A declared accepted type without an on handler is rejected (gate 4)."
  (signals starlangcompiler:invalid-actor-error
    (compile-source
     "(actor w
        (:runtime native
         :accepts (x y) :produces (r)
         :restart permanent :mailbox (bounded 1))
      (on x (message context) (reply message)))")))

(test handler-for-undeclared-type-is-rejected
  "An on handler for a type outside accepts is rejected."
  (signals starlangcompiler:invalid-actor-error
    (compile-source
     "(actor w
        (:runtime native
         :accepts (x) :produces (r)
         :restart permanent :mailbox (bounded 1))
      (on y (message context) (reply message)))")))

(test body-forms-lower-deterministically
  "The closed body surface lowers to a deterministic data-only IR."
  (let ((source
          "(actor w
             (:runtime native
              :accepts (x) :produces (r)
              :restart permanent :mailbox (bounded 1))
           (state (lastSource string :initial \"\"))
           (on x (message context)
             (let ((v (field message v)))
               (when v
                 (set lastSource v))
               (unless v
                 (fail \"w/missing\" \"v is required.\")))
             (send \"peer\" (construct r (v (state lastSource))))
             (reply (construct r (v (state lastSource))))))"))
    (is (equal
         '(:do
           (:let (("v" . (:field (:context "message") "v")))
             (:do
              (:if (:local "v")
                   (:do (:state-write "lastSource" (:local "v")))
                   (:const nil))
              (:if (:local "v")
                   (:const nil)
                   (:do (:fail "w/missing" "v is required.")))))
           (:send (:const "peer") (:construct "r" (("v" . (:state-read "lastSource")))))
           (:reply (:construct "r" (("v" . (:state-read "lastSource"))))))
         (getf (first (getf (compile-source source) :handlers)) :body)))
    (is (equal (compile-source source) (compile-source source)))))

(test invalid-body-forms-are-rejected
  "Malformed body declarations fail with typed compiler conditions."
  (loop for (label . source) in
        `(("unknown body head" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (frobnicate x)")
          ("unknown expression head" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (on x (message context) (shout message))")
          ("state slot unknown type" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (state (n banana :initial 0))
            (on x (message context) (reply message))")
          ("state initial type mismatch" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (state (n integer :initial \"zero\"))
            (on x (message context) (reply message))")
          ("state persistence class" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (state (n integer :initial 0 :persistence eventually))
            (on x (message context) (reply message))")
          ("duplicate state slot" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (state (n integer :initial 0) (n integer :initial 1))
            (on x (message context) (reply message))")
          ("duplicate handler" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (on x (message context) (reply message))
            (on x (message context) (reply message))")
          ("write to unknown slot" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (state (n integer :initial 0))
            (on x (message context) (set m 1))")
          ("let shadows state slot" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (state (n integer :initial 0))
            (on x (message context)
              (let ((n 1)) (reply message)))")
          ("read unknown name" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (on x (message context) (reply unknown-name))")
          ("fail requires strings" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (on x (message context) (fail 1 2))")
          ("construct requires pairs" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (on x (message context) (reply (construct r n)))")
          ("if requires three parts" .
           "(actor w (:runtime native :accepts (x) :produces (x)
              :restart permanent :mailbox (bounded 1)))
            (on x (message context) (reply (if message 1)))"))
        do (signals starlangcompiler:star-lang-core-error
             (compile-source source))))

;;; ------------------------------------------------------ domain servers

(defun domain-fixture-library ()
  "A minimal compiled spec-library IR for domain lowering."
  (starlangcompiler:compile-spec-library
   '(spec-library "org.starintel/ingest@1"
     (:version "1.0.0")
     (scalar program-id
       (:base string))
     (document source
       (:persistence persistent
        :fields
        ((sourceId string :required))))
     (message ingest/record@1
       (:fields
        ((programId program-id :required)
         (total string :required))))
     (message ingest/count@1
       (:fields
        ((last string :required)))))))

(test domain-server-lowers-in-the-final-compiler
  "The keyed domain-server lowering is final-owned."
  (let ((domain
          (starlangcompiler:compile-domain-server
           '(domain-server ingest
             (:key-type program-id
              :owns (source)
              :accepts (ingest/record@1)
              :tools ()
              :restart permanent
              :mailbox (bounded 64)
              :dispatcher default
              :capabilities (ingest)))
           (domain-fixture-library)
           '())))
    (is (eq :domain-server (getf domain :kind)))
    (is (equal "org.starintel/ingest@1/program-id" (getf domain :key-type))
        "local key type qualifies with the library")
    (is (equal '("ingest/record@1") (getf domain :accepts))
        "already-qualified accepted message types stay qualified")
    (is (equal '("org.starintel/ingest@1/source") (getf domain :owns))
        "owned documents qualify with the library")
    (is (equal '("ingest/record@1") (getf domain :accepts))
        "already-qualified accepted types stay qualified")))

(test domain-server-with-native-body
  "Domain servers accept StarLang bodies with keyed bindings."
  (let ((domain
          (starlangcompiler:compile-domain-server
           '(domain-server ingest
             (:key-type program-id
              :owns (source)
              :accepts (ingest/record@1)
              :tools ()
              :restart permanent
              :mailbox (bounded 64)))
           (domain-fixture-library)
           '()
           :body
           '((state (count integer :initial 0 :persistence journaled))
             (on ingest/record@1 (key message context)
               (reply (construct ingest/count@1
                                 (last (field message total)))))))))
    (is (= 1 (length (getf domain :states))))
    (is (= 1 (length (getf domain :handlers))))
    (is (equal "key" (getf (first (getf domain :handlers)) :key-var)))
    (is (data-only-p domain))))

(test domain-manifest-entry-carries-body-and-resource-uri
  "Domain manifest entries expose canonical identity, state, and handlers."
  (let* ((domain
           (starlangcompiler:compile-domain-server
            '(domain-server ingest
              (:key-type program-id
               :owns (source)
               :accepts (ingest/record@1)
               :tools ()
               :restart permanent
               :mailbox (bounded 64)
               :service-uri "star://starintel.dev/service/ingest"))
            (domain-fixture-library)
            '()
            :body
            '((state (count integer :initial 0))
              (on ingest/record@1 (key message context)
                (reply (construct ingest/count@1 (last "")))))))
         (manifest
           (starlangcompiler:emit-domain-program-manifest
            (domain-fixture-library) '() '() (list domain)))
         (entry (first (getf manifest :domain-servers))))
    (is (string= "star://starintel.dev/service/ingest"
                 (getf entry :resource-uri)))
    (is (null (getf entry :service-uri)))
    (is (= 1 (length (getf entry :states))))
    (is (= 1 (length (getf entry :handlers))))))

(test actor-manifest-carries-resource-uri-and-body
  "Portable actor manifests expose canonical identity and body IR."
  (let* ((ir (compile-source (body-actor-source)))
         (manifest
           (starlangcompiler:emit-portable-manifest
            (list :kind :spec-library
                  :name "fixture@1"
                  :version "1"
                  :digest "sha256:x"
                  :imports '()
                  :declarations '())
            (list ir)))
         (actor (first (getf manifest :actors))))
    (is (string= "star://starintel.dev/actor/tracker"
                 (getf actor :resource-uri)))
    (is (= 2 (length (getf actor :states))))
    (is (= 2 (length (getf actor :handlers))))))

(test manifest-json-uses-canonical-camelcase-identity
  "Canonical resource URIs serialize as camelCase resourceUri entries."
  (let* ((ir (compile-source
              "(actor counter
                 (:runtime native
                  :service-uri \"star://starintel.dev/actor/counter\"
                  :accepts (x) :produces (x)
                  :restart permanent :mailbox (bounded 1))
               (state (count integer :initial 0 :persistence journaled))
               (on x (message context) (reply (construct x (total 0)))))"))
         (manifest
           (starlangcompiler:emit-portable-manifest
            (list :kind :spec-library
                  :name "fixture@1"
                  :version "1"
                  :digest "sha256:x"
                  :imports '()
                  :declarations '())
            (list ir)))
         (json (starcanonicaljson:canonical-manifest-json manifest)))
    (is (search "\"resourceUri\":\"star://starintel.dev/actor/counter\"" json))
    (is (not (search "\"serviceUri\"" json)))
    (is (search "\"journaled\"" json))))

(defun run-tests ()
  (let ((results (run 'starlang-actor-body-tests)))
    (unless results
      (error "starlang-compiler actor-body tests failed."))
    t))
