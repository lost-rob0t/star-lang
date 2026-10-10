(in-package :star-actor-wire)

(define-condition unsupported-peer-protocol (wire-error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "Peer does not advertise star.actor2actor/1; no legacy fallback." stream))))

(defun negotiate-actor2actor-profile (peer-profiles)
  "Require a descriptor-negotiated semantic profile before any effectful send.
This is capability selection, not authentication or a new wire handshake."
  (unless (and (listp peer-profiles) (<= (length peer-profiles) 64)
               (every (lambda (item) (and (stringp item) (<= 1 (length item) 256)))
                      peer-profiles)
               (= (length peer-profiles)
                  (length (remove-duplicates peer-profiles :test #'equal))))
    (fail-wire))
  (or (find staractorprotocol:+actor2actor-semantic-profile+ peer-profiles :test #'equal)
      (error 'unsupported-peer-protocol)))

(defun ensure-binding (binding)
  (unless (member binding '(:zmq :rabbit)) (fail-wire)))

(defun binding-headers (envelope)
  ;; Internal adapter plist; names map to AMQP properties and profile metadata.
  (list :message-id (getf envelope :message-id)
        :correlation-id (getf envelope :correlation-id)
        :content-type "application/json"
        :profile staractorprotocol:+actor2actor-semantic-profile+))

(defun encode-binding-message (binding peer-profiles manifest envelope)
  "Return canonical body octets and binding-local headers; never a second envelope.
ZMQ sends exactly this body as its message payload. ROUTER identity is separate.
Rabbit uses the same body plus the returned AMQP identity/profile metadata.
Durability, broker settlement and application success are not implied."
  (ensure-binding binding)
  (negotiate-actor2actor-profile peer-profiles)
  (values (encode-envelope manifest envelope)
          (when (eq binding :rabbit) (binding-headers envelope))))

(defun decode-binding-message (binding peer-profiles manifest bytes &optional headers)
  "Decode canonical body and reject Rabbit header/body ambiguity before dispatch."
  (ensure-binding binding)
  (negotiate-actor2actor-profile peer-profiles)
  (let ((envelope (decode-envelope manifest bytes)))
    (ecase binding
      (:zmq (when headers (fail-wire)))
      (:rabbit
       (unless (and (listp headers) (= (length headers) 8)) (fail-wire))
       (let ((seen nil) (expected (binding-headers envelope)))
         (loop for (key value) on headers by #'cddr
               do (unless (and (member key '(:message-id :correlation-id :content-type :profile))
                               (not (member key seen))
                               (equal value (getf expected key)))
                    (fail-wire))
                  (push key seen)))))
    envelope))

(defun decode-command-message (binding peer-profiles manifest bytes &optional headers)
  "Canonical command admission for ALL foreign bindings, before transport effects.
Reply/event/control envelopes cannot enter a command invocation API."
  (let ((envelope (decode-binding-message binding peer-profiles manifest bytes headers)))
    (unless (eq (getf envelope :kind) :command) (fail-wire))
    envelope))
