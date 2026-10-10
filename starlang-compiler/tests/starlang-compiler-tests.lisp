(defpackage :starlangcompiler-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlangcompiler-tests)

(def-suite starlangcompiler-tests
  :description "Final compiler compatibility tests.")

(in-suite starlangcompiler-tests)

(test closed-parser-normalizes-lf-cr-and-crlf-source-spans
  "Comments end on LF or CR; CRLF counts as one logical line."
  (dolist (newline (list (string #\Newline)
                         (string #\Return)
                         (format nil "~C~C" #\Return #\Newline)))
    (let* ((source
             (format nil
                     "; header~A(spec-library \"test/newlines@1\"~A  (:version \"1\")~A  (message ping (:fields ())))"
                     newline newline newline))
           (syntax (starlangcompiler:read-star-syntax
                    source :source-id "newline-regression.star"))
           (children (star-lang.compiler.core:star-syntax-children syntax))
           (root (star-lang.compiler.core:star-syntax-span syntax))
           (message (fourth children))
           (span (star-lang.compiler.core:star-syntax-span message)))
      (is (= 2 (star-lang.compiler.core:star-source-span-start-line root)))
      (is (= 1 (star-lang.compiler.core:star-source-span-start-column root)))
      (is (= (length (format nil "; header~A" newline))
             (star-lang.compiler.core:star-source-span-start-byte root)))
      (is (= 4 (star-lang.compiler.core:star-source-span-start-line span)))
      (is (= 3 (star-lang.compiler.core:star-source-span-start-column span))))))

(test closed-parser-reports-cr-only-diagnostic-line
  "After a CR-only source, invalid trailing input has the physical line."
  (let* ((source
           (format nil "; header~C(spec-library \"test/line@1\"~C  (:version \"1\"))~C extra"
                   #\Return #\Return #\Return))
         (condition
           (handler-case
               (progn (starlangcompiler:read-star-syntax source) nil)
             (star-lang.compiler.core:star-lang-source-error (caught)
               caught))))
    (is (typep condition 'star-lang.compiler.core:star-lang-source-error))
    (is (eq :multiple-top-level-forms
            (star-lang.compiler.core:star-lang-core-error-code condition)))
    (is (= 4 (star-lang.compiler.core:star-lang-core-error-line condition)))))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun make-test-identity ()
  (starlogicir:make-logic-package-identity
   :package-id "logic.compiler-test"
   :package-version "1.0.0"
   :package-digest "sha256:compiler-test-package"
   :mapping-id "mapping.compiler-test"
   :mapping-digest "sha256:compiler-test-mapping"))

(defun compile-test-call (&key backend-policy)
  (let ((arguments
          (list
           :operation-id "compiler-op-1"
           :named-operation-id "lookup"
           :operation-kind "solve"
           :semantic-profile "star.logic.query/1"
           :bindings '(("subject" . "alice"))
           :answer-policy '(("limit" . 1))
           :proof-policy '(("mode" . "optional"))
           :required-capabilities '("named-query")
           :required-hard-limits '("answers")
           :required-isolation "process"
           :package-identity (make-test-identity)
           :budget '(("answers" . 1))
           :source-span '(("sourceId" . "compiler-test.star")
                          ("startLine" . 7)
                          ("startColumn" . 3)))))
    (when backend-policy
      (setf arguments (append arguments (list :backend-policy backend-policy))))
    (apply #'starlangcompiler:compile-logic-call arguments)))

(test compiler-forwards-to-final-logic-ir
  "The compiler compatibility API returns the final star-logic-ir authority."
  (let ((call (compile-test-call)))
    (is (starlogicir:logic-call-p call))
    (is (string= "auto" (starlogicir:logic-call-backend-policy call)))
    (is (equal '(("sourceId" . "compiler-test.star")
                 ("startColumn" . 3)
                 ("startLine" . 7))
               (starlogicir:logic-call-source-span call)))))

(test compiler-preserves-logic-policy-diagnostics
  "IR validation failures retain a dedicated compiler diagnostic and source span."
  (let ((condition
          (handler-case
              (progn
                (compile-test-call :backend-policy "unknown-engine")
                nil)
            (starlangcompiler:logic-policy-compiler-error (condition)
              condition))))
    (is (typep condition 'starlangcompiler:logic-policy-compiler-error))
    (is (eq :unknown-logic-backend
            (starlangcompiler:logic-policy-compiler-error-code condition)))
    (is (equal '(("sourceId" . "compiler-test.star")
                 ("startLine" . 7)
                 ("startColumn" . 3))
               (starlangcompiler:logic-policy-compiler-error-source-span
                condition)))))

(test compiler-materialization-uses-portable-selector
  "Compiler materialization delegates to the existing backend selector."
  (let* ((backend
           (starlogictesting:make-fake-logic-backend
            :id "swi-prolog"
            :semantic-profiles '("star.logic.query/1")
            :capabilities '("named-query")
            :isolation-classes '("process")
            :hard-limits '("answers")))
         (registry (starlogicprotocol:make-logic-backend-registry))
         (call (compile-test-call :backend-policy "swi-prolog")))
    (starlogicprotocol:register-logic-backend registry backend)
    (let ((plan
            (starlangcompiler:materialize-compiled-logic-call call registry)))
      (is (starlogicir:materialized-logic-call-p plan))
      (is (string= "swi-prolog"
                   (starlogicir:materialized-logic-call-backend-id plan))))))

(test compiler-materialization-preserves-source-aware-failure
  "Backend incompatibility becomes a source-aware compiler diagnostic."
  (let* ((backend
           (starlogictesting:make-fake-logic-backend
            :id "swi-prolog"
            :semantic-profiles '("star.logic.tabled/1")
            :capabilities '("named-query")
            :isolation-classes '("process")
            :hard-limits '("answers")))
         (registry (starlogicprotocol:make-logic-backend-registry))
         (call (compile-test-call :backend-policy "swi-prolog")))
    (starlogicprotocol:register-logic-backend registry backend)
    (let ((condition
            (handler-case
                (progn
                  (starlangcompiler:materialize-compiled-logic-call call registry)
                  nil)
              (starlangcompiler:logic-policy-compiler-error (condition)
                condition))))
      (is (eq :logic-backend-incompatible
              (starlangcompiler:logic-policy-compiler-error-code condition)))
      (is (equal (starlogicir:logic-call-source-span call)
                 (starlangcompiler:logic-policy-compiler-error-source-span
                  condition))))))

(test resolver-effects-are-final-compiler-owned
  "Digest effects execute through the final compiler-owned effect protocol."
  ;; let* is required: the effect lambda must capture the seen binding, and a
  ;; parallel let's init-forms are outside the scope of that let's bindings.
  (let* ((seen nil)
         (effects
           (star-lang.loader.effects:make-resolver-effects
            :digest-file
            (lambda (pathname)
              (setf seen pathname)
              "sha256:test"))))
    (is (string= "sha256:test"
                 (star-lang.loader.effects:digest-file-through-effects
                  effects #p"/tmp/spec.star")))
    (is (equal #p"/tmp/spec.star" seen))))

(test resolver-effects-forward-fetch-bounds
  "Fetch effects preserve every compiler-supplied resource bound."
  ;; let* is required: the effect lambda must capture the seen binding, and a
  ;; parallel let's init-forms are outside the scope of that let's bindings.
  (let* ((seen nil)
         (effects
           (star-lang.loader.effects:make-resolver-effects
            :fetch-to-file
            (lambda (url destination &rest arguments)
              (setf seen (list url destination arguments))
              :ok))))
    (is (eq :ok
            (star-lang.loader.effects:fetch-to-file-through-effects
             effects
             "https://example.invalid/spec.star"
             #p"/tmp/spec.star"
             :maximum-bytes 1024
             :maximum-redirects 2
             :connect-timeout 3
             :read-timeout 4
             :deadline 5
             :proxy nil)))
    (destructuring-bind (url destination arguments) seen
      (is (string= "https://example.invalid/spec.star" url))
      (is (equal #p"/tmp/spec.star" destination))
      (is (= 1024 (getf arguments :maximum-bytes)))
      (is (= 2 (getf arguments :maximum-redirects)))
      (is (= 3 (getf arguments :connect-timeout)))
      (is (= 4 (getf arguments :read-timeout)))
      (is (= 5 (getf arguments :deadline))))))

(test resolver-effects-require-explicit-capability
  "A compiler effect is unavailable unless an adapter explicitly supplies it."
  (signals error
    (star-lang.loader.effects:digest-file-through-effects
     (star-lang.loader.effects:make-resolver-effects)
     #p"/tmp/spec.star")))

(test lifecycle-bindings-are-final-compiler-owned
  "Portable lifecycle bindings are emitted by the final compiler and preserve lower camelCase."
  (let ((python (starlangcompiler:generate-python-lifecycle-bindings))
        (typescript (starlangcompiler:generate-typescript-lifecycle-bindings)))
    (is (search "messageId: str" python))
    (is (search "correlationId: str" python))
    (is (search "messageId: string" typescript))
    (is (search "correlationId: string" typescript))
    (is (null (search "message_id" python)))
    (is (null (search "message_id" typescript)))))

(test compiler-preserves-explicit-false-default-through-manifest-json
  "The final source/compiler/manifest path keeps default presence separate from NIL truthiness."
  (let* ((source
           "(spec-library \"test/defaults@1\" (:version \"1.0.0\")
              (document preferences (:persistence transient)
                (enabled boolean :optional :default nil)))")
         (library
           (starlangcompiler:compile-spec-library
            (starlangcompiler:read-star-syntax source)))
         (declaration (first (getf library :declarations)))
         (field (first (getf declaration :fields)))
         (manifest (starlangcompiler:emit-portable-manifest library nil))
         (portable-document (first (getf manifest :types)))
         (portable-field (first (getf portable-document :fields)))
         (json (starcanonicaljson:canonical-manifest-json manifest)))
    (is (getf field :default-p))
    (is (null (getf field :default)))
    (is (plist-key-present-p portable-field :default))
    (is (null (getf portable-field :default)))
    (is (search
         "{\"default\":false,\"name\":\"enabled\",\"required\":false,\"type\":\"boolean\"}"
         json))))

(defun starintel-0101-manifest ()
  (let* ((pathname
           (asdf:system-relative-pathname
            :starlang-compiler
            "../specs/starintel/0.10.1/core.star"))
         (source (uiop:read-file-string pathname))
         (library
           (starlangcompiler:compile-spec-library
            (starlangcompiler:read-star-syntax
             source
             :source-id (namestring pathname)))))
    (starlangcompiler:emit-portable-manifest library nil)))

(test portable-schema-bindings-cover-language-matrix
  "The final compiler owns every declared portable language boundary."
  (is (equal
       '(:common-lisp :kotlin :java :python :typescript :nim :go :rust
         :emacs-lisp :prolog)
       (starlangcompiler:supported-binding-languages))))

(test starintel-0101-is-canonical-starlang-and-generates-every-binding
  "StarIntel 0.10.1 media/network/file vocabulary compiles once and feeds every language binding."
  (let* ((manifest (starintel-0101-manifest))
         (names
           (mapcar (lambda (contract) (getf contract :name))
                   (getf manifest :types)))
         (outputs (starlangcompiler:generate-all-bindings manifest)))
    (dolist (required
             '("org.starintel/core@1/file"
               "org.starintel/core@1/image"
               "org.starintel/core@1/picture"
               "org.starintel/core@1/video"
               "org.starintel/core@1/video-frame"
               "org.starintel/core@1/audio"
               "org.starintel/core@1/transcript"
               "org.starintel/core@1/person-identifier"
               "org.starintel/core@1/geo"
               "org.starintel/core@1/geo-point"
               "org.starintel/core@1/geo-line-string"
               "org.starintel/core@1/geo-polygon"
               "org.starintel/core@1/geo-multi-point"
               "org.starintel/core@1/geo-multi-line-string"
               "org.starintel/core@1/geo-multi-polygon"
               "org.starintel/core@1/geo-geometry-collection"
               "org.starintel/core@1/location"
               "org.starintel/core@1/mission"
               "org.starintel/core@1/mission-target"
               "org.starintel/core@1/route"
               "org.starintel/core@1/geofence"
               "org.starintel/core@1/encounter"
               "org.starintel/core@1/map-layer"
               "org.starintel/core@1/http-transaction"
               "org.starintel/core@1/web-capture"
               "org.starintel/core@1/pcap-capture"
               "org.starintel/core@1/network-device"
               "org.starintel/core@1/wireless-network"
               "org.starintel/core@1/wireless-station"))
      (is (member required names :test #'string=)))
    (is (= 10 (length outputs)))
    (dolist (entry outputs)
      (is (> (length (cdr entry)) 100)))
    (is (search "File = TypedDict" (cdr (assoc :python outputs))))
    (is (search "PersonIdentifier = TypedDict" (cdr (assoc :python outputs))))
    (is (search "GeoPoint = TypedDict" (cdr (assoc :python outputs))))
    (is (search "Transcript = TypedDict" (cdr (assoc :python outputs))))
    (is (search "VideoFrame = TypedDict" (cdr (assoc :python outputs))))
    (is (null (search "schema_version" (cdr (assoc :python outputs)))))
    (is (search "export interface VideoFrame" (cdr (assoc :typescript outputs))))
    (is (search "data class VideoFrame" (cdr (assoc :kotlin outputs))))
    (is (search "record VideoFrame" (cdr (assoc :java outputs))))
    (is (search "VideoFrame* = object" (cdr (assoc :nim outputs))))
    (is (search "type VideoFrame struct" (cdr (assoc :go outputs))))
    (is (search "pub struct VideoFrame" (cdr (assoc :rust outputs))))
    (is (search "(defstruct video-frame" (cdr (assoc :common-lisp outputs))))
    (is (search "starintel-video-frame" (cdr (assoc :emacs-lisp outputs))))
    (is (search "org.starintel/core@1/video-frame" (cdr (assoc :prolog outputs))))))

(test starintel-0101-common-lisp-binding-is-loadable
  "The generated Common Lisp artifact is executable source, not merely recognizable text."
  (let* ((manifest (starintel-0101-manifest))
         (source (starlangcompiler:generate-common-lisp-bindings manifest))
         (package-name "ORG.STARINTEL.CORE.V1"))
    (when (find-package package-name)
      (delete-package package-name))
    (unwind-protect
         (let ((*package* (find-package :cl-user)))
           (with-input-from-string (stream source)
             (loop for form = (read stream nil stream)
                   until (eq form stream)
                   do (eval form)))
           (let ((package (find-package package-name)))
             (is (not (null package)))
             (is (eq :external (nth-value 1 (find-symbol "PERSON-IDENTIFIER" package))))
             (is (eq :external (nth-value 1 (find-symbol "+GEO-POINT-WIRE-FIELDS+" package))))
             (is (eq :external (nth-value 1 (find-symbol "TRANSCRIPT" package))))))
      (when (find-package package-name)
        (delete-package package-name)))))

(test starintel-0101-geo-scalars-enforce-coordinate-ranges
  "First-class geo coordinates reject values outside WGS84 longitude/latitude bounds."
  (let ((manifest (starintel-0101-manifest)))
    (is (staractorprotocol:validate-portable-wire-value
         manifest "org.starintel/core@1/longitude" "-180.00000000"))
    (is (staractorprotocol:validate-portable-wire-value
         manifest "org.starintel/core@1/latitude" "90.00000000"))
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-wire-value
       manifest "org.starintel/core@1/longitude" "180.00000001"))
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-wire-value
       manifest "org.starintel/core@1/latitude" "-90.00000001"))))

(test starintel-0101-mission-and-spatial-contracts-are-first-class
  "Mission planning and spatial querying compile from StarLang without private downstream schemas."
  (let* ((manifest (starintel-0101-manifest))
         (types (getf manifest :types))
         (messages (getf manifest :messages))
         (find-type
           (lambda (name)
             (find name types :key (lambda (contract) (getf contract :name))
                   :test #'string=)))
         (field-names
           (lambda (contract)
             (mapcar (lambda (field) (getf field :name))
                     (getf contract :fields)))))
    (dolist (name '("org.starintel/core@1/mission"
                    "org.starintel/core@1/mission-target"
                    "org.starintel/core@1/route"
                    "org.starintel/core@1/geofence"
                    "org.starintel/core@1/encounter"
                    "org.starintel/core@1/map-layer"))
      (is (funcall find-type name)))
    (dolist (field '("name" "objective" "state" "targets" "geofences" "route"))
      (is (member field
                  (funcall field-names
                           (funcall find-type "org.starintel/core@1/mission"))
                  :test #'string=)))
    (dolist (field '("participants" "kind" "startedAt" "observations" "evidence"))
      (is (member field
                  (funcall field-names
                           (funcall find-type "org.starintel/core@1/encounter"))
                  :test #'string=)))
    (is (find "org.starintel/core@1/query-spatial"
              messages
              :key (lambda (message) (getf message :name))
              :test #'string=))
    (let ((outputs (starlangcompiler:generate-all-bindings manifest)))
      (is (search "Mission = TypedDict" (cdr (assoc :python outputs))))
      (is (search "Geofence = TypedDict" (cdr (assoc :python outputs))))
      (is (search "Encounter = TypedDict" (cdr (assoc :python outputs))))
      (is (search "export interface Route" (cdr (assoc :typescript outputs))))
      (is (search "data class MissionTarget" (cdr (assoc :kotlin outputs))))
      (is (search "pub struct MapLayer" (cdr (assoc :rust outputs)))))))

(test starintel-0101-network-capture-profile-is-canonical
  "The retired 0.9.2 HTTP/browser profile is represented by canonical 0.10.1 StarLang contracts."
  (let* ((manifest (starintel-0101-manifest))
         (types (getf manifest :types))
         (find-type
           (lambda (name)
             (find name types :key (lambda (contract) (getf contract :name))
                   :test #'string=)))
         (field-names
           (lambda (contract)
             (mapcar (lambda (field) (getf field :name))
                     (getf contract :fields)))))
    (let ((http (funcall find-type "org.starintel/core@1/http-transaction"))
          (web (funcall find-type "org.starintel/core@1/web-capture")))
      (is (not (null http)))
      (is (not (null web)))
      (dolist (field '("transactionId" "method" "url" "responseStatus"
                       "requestHeaders" "responseHeaders" "captureActorUri"
                       "redactedHeaders" "bodyCapturePolicy"))
        (is (member field (funcall field-names http) :test #'string=)))
      (dolist (field '("captureId" "url" "screenshotUri" "screenshotHash"
                       "capturedAt" "httpTransactionIds" "captureActorUri"))
        (is (member field (funcall field-names web) :test #'string=))))
    (let ((outputs (starlangcompiler:generate-all-bindings manifest)))
      (is (search "HttpTransaction = TypedDict" (cdr (assoc :python outputs))))
      (is (search "WebCapture = TypedDict" (cdr (assoc :python outputs))))
      (is (search "transactionId" (cdr (assoc :python outputs))))
      (is (search "screenshotUri" (cdr (assoc :python outputs))))
      (is (null (search "transaction_id" (cdr (assoc :python outputs)))))
      (is (null (search "screenshot_uri" (cdr (assoc :python outputs)))))
      (is (search "export interface HttpTransaction"
                  (cdr (assoc :typescript outputs))))
      (is (search "data class WebCapture" (cdr (assoc :kotlin outputs)))))))

(test starintel-0101-generates-deterministic-json-schema
  "The portable StarLang manifest is the source for JSON Schema, with lowerCamelCase wire keys."
  (let* ((manifest (starintel-0101-manifest))
         (first (starlangcompiler:generate-json-schema manifest))
         (second (starlangcompiler:generate-json-schema manifest)))
    (is (string= first second))
    (is (search "\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"" first))
    (is (search "\"PersonIdentifier\"" first))
    (is (search "\"GeoPoint\"" first))
    (is (search "\"Transcript\"" first))
    (is (search "\"schemaVersion\"" first))
    (is (null (search "schema_version" first)))))

(test final-compiler-logic-path-does-not-load-prototype
  "The final compiler logic compatibility path stays prototype-independent."
  (is (null (find-package "STAR-LANG.PROTOTYPE")))
  (is (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))))

(defun run-tests ()
  ;; fiveam's run! returns T only when every check passed; surface failures
  ;; through the process exit code so ASDF/Nix/CI gates cannot pass silently.
  (unless (run! 'starlangcompiler-tests)
    (error "starlang-compiler compatibility tests failed.")))
