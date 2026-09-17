(defpackage :star-zmq-runtime
  (:use :cl)
  (:export
   #:zmq-runtime-error
   #:invalid-zmq-actor-ir-error
   #:closed-zmq-actor-binding-error
   #:zmq-actor-binding
   #:zmq-actor-binding-p
   #:zmq-actor-binding-actor
   #:zmq-actor-binding-peer-generation
   #:materialize-zmq-actor
   #:close-zmq-actor-binding))

(in-package :star-zmq-runtime)

(define-condition zmq-runtime-error (error)
  ((message :initarg :message :reader zmq-runtime-error-message))
  (:report
   (lambda (condition stream)
     (write-string (zmq-runtime-error-message condition) stream))))

(define-condition invalid-zmq-actor-ir-error (zmq-runtime-error) ())
(define-condition closed-zmq-actor-binding-error (zmq-runtime-error) ())

(defstruct (zmq-actor-binding (:constructor %make-zmq-actor-binding))
  runtime
  actor-ir
  manifest
  context
  executable
  identity
  (timeout-ms 5000 :type (integer 1 60000))
  actor
  peer
  peer-generation
  (closed-p nil :type boolean))

(defun fail-runtime (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun required-string (value label)
  (unless (and (stringp value) (plusp (length value)))
    (fail-runtime 'invalid-zmq-actor-ir-error
                  "~A must be a non-empty string."
                  label))
  value)

(defun bounded-timeout (value)
  (unless (and (integerp value) (<= 1 value 60000))
    (fail-runtime 'invalid-zmq-actor-ir-error
                  "ZMQ actor timeout must be an integer from 1 through 60000 ms."))
  value)

(defun mailbox-capacity (actor-ir)
  (let ((mailbox (getf actor-ir :mailbox)))
    (unless (and (listp mailbox)
                 (eq :bounded (getf mailbox :kind))
                 (integerp (getf mailbox :capacity))
                 (plusp (getf mailbox :capacity)))
      (fail-runtime 'invalid-zmq-actor-ir-error
                    "ZMQ external actor requires a bounded StarLang mailbox."))
    (getf mailbox :capacity)))

(defun validate-external-actor-ir (actor-ir)
  (unless (and (listp actor-ir)
               (eq :actor (getf actor-ir :kind))
               (eq :external (getf actor-ir :runtime)))
    (fail-runtime 'invalid-zmq-actor-ir-error
                  "Expected compiled StarLang external actor IR."))
  (required-string (getf actor-ir :name) "Actor name")
  (required-string (getf actor-ir :endpoint) "Actor endpoint")
  (unless (string= "star-message-v1"
                   (required-string (getf actor-ir :protocol) "Actor protocol"))
    (fail-runtime 'invalid-zmq-actor-ir-error
                  "ZMQ lowering currently requires protocol star-message-v1."))
  (mailbox-capacity actor-ir)
  actor-ir)

(defun ensure-open-binding (binding)
  (unless (zmq-actor-binding-p binding)
    (fail-runtime 'zmq-runtime-error
                  "Expected a ZMQ actor binding, received ~S."
                  binding))
  (when (zmq-actor-binding-closed-p binding)
    (fail-runtime 'closed-zmq-actor-binding-error
                  "ZMQ actor binding is closed."))
  binding)

(defun binding-actor-name (binding)
  (getf (zmq-actor-binding-actor-ir binding) :name))

(defun binding-actor-service-uri (binding)
  (getf (zmq-actor-binding-actor-ir binding) :service-uri))

(defun validate-command-for-binding (binding envelope)
  (let* ((actor-ir (zmq-actor-binding-actor-ir binding))
         (actor-name (getf actor-ir :name))
         (message-type (and (listp envelope) (getf envelope :message-type))))
    (and (listp envelope)
         (eq :command (getf envelope :kind))
         (stringp (getf envelope :actor))
         (string= actor-name (getf envelope :actor))
         (stringp message-type)
         (member message-type (getf actor-ir :accepts) :test #'string=)
         ;; The current local Nim actor deliberately has no deadline clock.
         ;; Reject before the external effect rather than executing late.
         (null (getf envelope :deadline))
         (handler-case
             (progn
               (staractorprotocol:validate-lifecycle-envelope-against-manifest
                (zmq-actor-binding-manifest binding)
                envelope)
               t)
           (error () nil)))))

(defun validate-reply-for-binding (binding envelope)
  (let* ((actor-ir (zmq-actor-binding-actor-ir binding))
         (kind (and (listp envelope) (getf envelope :kind)))
         (message-type (and (listp envelope) (getf envelope :message-type))))
    (and (member kind '(:reply :error))
         (or (eq kind :error)
             (and (stringp message-type)
                  (member message-type (getf actor-ir :produces) :test #'string=)))
         (handler-case
             (progn
               (staractorprotocol:validate-lifecycle-envelope-against-manifest
                (zmq-actor-binding-manifest binding)
                envelope)
               t)
           (error () nil)))))

(defun current-generation (binding)
  (starlangruntime:actor-instance-generation
   (starlangruntime:resolve-actor
    (zmq-actor-binding-runtime binding)
    (binding-actor-name binding))))

(defun discard-peer (binding)
  (when (zmq-actor-binding-peer binding)
    (star-zmq-actors:close-peer (zmq-actor-binding-peer binding))
    (setf (zmq-actor-binding-peer binding) nil
          (zmq-actor-binding-peer-generation binding) nil))
  binding)

(defun ensure-generation-peer (binding)
  (ensure-open-binding binding)
  (let ((generation (current-generation binding))
        (peer (zmq-actor-binding-peer binding)))
    (when peer
      (unless (and (eql generation (zmq-actor-binding-peer-generation binding))
                   (star-zmq-actors:peer-live-p peer))
        (discard-peer binding)
        (setf peer nil)))
    (unless peer
      (setf peer
            (star-zmq-actors:open-peer
             (zmq-actor-binding-context binding)
             (zmq-actor-binding-executable binding)
             (getf (zmq-actor-binding-actor-ir binding) :endpoint)
             (zmq-actor-binding-identity binding)
             (binding-actor-name binding)
             (zmq-actor-binding-manifest binding)
             :generation generation
             :timeout-ms (zmq-actor-binding-timeout-ms binding))
            (zmq-actor-binding-peer binding) peer
            (zmq-actor-binding-peer-generation binding) generation))
    peer))

(defun invoke-zmq-actor (binding envelope runtime)
  (ensure-open-binding binding)
  (unless (eq runtime (zmq-actor-binding-runtime binding))
    (fail-runtime 'zmq-runtime-error
                  "ZMQ actor invoked through a runtime other than its owner."))
  ;; ENSURE-GENERATION-PEER may replace a dead/stale peer before a NEW command,
  ;; but PEER-REQUEST never replays a command whose outcome became unknown.
  (star-zmq-actors:peer-request
   (ensure-generation-peer binding)
   envelope
   :timeout-ms (zmq-actor-binding-timeout-ms binding)))

(defun materialize-zmq-actor
    (runtime actor-ir manifest context executable
     &key identity (timeout-ms 5000))
  "Materialize compiled external ACTOR-IR as a real mailbox-backed StarLang proxy.

The compiler IR remains external and transport-neutral. This adapter owns only
the concrete ZMQ effect. STarlang-runtime remains the mailbox, generation,
admission and deterministic dispatch authority; star-zmq-actors remains the
process/wire transport authority."
  (validate-external-actor-ir actor-ir)
  (bounded-timeout timeout-ms)
  (let* ((name (getf actor-ir :name))
         (binding
           (%make-zmq-actor-binding
            :runtime runtime
            :actor-ir actor-ir
            :manifest manifest
            :context context
            :executable executable
            :identity (or identity (format nil "starlang/~A" name))
            :timeout-ms timeout-ms)))
    (required-string (zmq-actor-binding-identity binding) "ZMQ routing identity")
    (handler-case
        (let ((actor
                (starlangruntime:create-native-actor
                 runtime
                 name
                 (lambda (envelope state owner-runtime)
                   (declare (ignore state))
                   (invoke-zmq-actor binding envelope owner-runtime))
                 :service-uri (binding-actor-service-uri binding)
                 :accepts (copy-list (getf actor-ir :accepts))
                 :produces (copy-list (getf actor-ir :produces))
                 :input-validator
                 (lambda (contract envelope)
                   (declare (ignore contract))
                   (validate-command-for-binding binding envelope))
                 :output-validator
                 (lambda (contract envelope)
                   (declare (ignore contract))
                   (validate-reply-for-binding binding envelope))
                 :restart-policy (getf actor-ir :restart)
                 :mailbox-capacity (mailbox-capacity actor-ir)
                 :metadata (copy-tree (getf actor-ir :metadata)))))
          (setf (zmq-actor-binding-actor binding) actor)
          binding)
      (error (condition)
        (ignore-errors (discard-peer binding))
        (error condition)))))

(defun close-zmq-actor-binding (binding)
  "Close the concrete peer owned by BINDING. This never replays queued work."
  (when (and (zmq-actor-binding-p binding)
             (not (zmq-actor-binding-closed-p binding)))
    (discard-peer binding)
    (setf (zmq-actor-binding-closed-p binding) t))
  t)
