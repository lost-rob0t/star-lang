(defpackage :star-actor-wire-tests (:use :cl) (:export #:run-tests))
(in-package :star-actor-wire-tests)

(defvar *assertions* 0)
(defun check (value)
  (incf *assertions*)
  (assert value))
(defun fails (type thunk)
  (let ((caught nil))
    (handler-case (funcall thunk)
      (error (condition)
        (unless (typep condition type) (error condition))
        (setf caught t)))
    (check caught)))
(defun bytes (text) (babel:string-to-octets text :encoding :utf-8))

(defun manifest ()
  '(:messages
    ((:name "star.zmq/ready@1" :fields ((:name "generation" :type "integer" :required t)))
     (:name "star.zmq/echo@1" :fields ((:name "text" :type "string" :required t)))
     (:name "star.zmq/stop@1" :fields nil)
     (:name "unknown@1" :fields nil)
     (:name "boolean@1" :fields ((:name "flag" :type "boolean" :required t))))))

(defun command (id &key (actor "nim.echo") (type "star.zmq/echo@1")
                         (payload '(("text" . "hello ☃"))))
  (staractorprotocol:make-command-envelope
   :message-id id :message-type type :actor actor :sender "caller"
   :reply-to "caller" :correlation-id (concatenate 'string "correlation/" id)
   :idempotency-key id :dataset "fixture" :payload payload))

(defun replace-once (text before after)
  (let ((position (search before text)))
    (assert position)
    (concatenate 'string (subseq text 0 position) after (subseq text (+ position (length before))))))

(defun codec-tests ()
  (let* ((contract (manifest))
         (envelope (command "one"))
         (encoded (star-actor-wire:encode-envelope contract envelope))
         (decoded (star-actor-wire:decode-envelope contract encoded))
         (text (babel:octets-to-string encoded :encoding :utf-8)))
    (check (equal (getf decoded :payload) (getf envelope :payload)))
    (check (equalp encoded (star-actor-wire:encode-envelope contract decoded)))
    (dolist (bad (list "{}" "[]" "null" "{unquoted:1}" "{\"x\":1,}" "{\"x\":01}"
                      "{\"x\":1} false" "{\"x\":1,\"\\u0078\":2}" "{\"x\":\"\\ud800\"}"
                      (replace-once text "\"starVersion\":1" "\"starVersion\":2")
                      (replace-once text "\"attempt\":1" "\"attempt\":0")
                      (replace-once text "\"attempt\":1" "\"attempt\":true")
                      (replace-once text "\"attempt\":1" "\"attempt\":1,\"attempt\":2")
                      (replace-once text "\"payload\":{" "\"payload\":{\"extra\":1,")
                      (concatenate 'string text "{}")))
      (fails 'star-actor-wire:wire-error
             (lambda () (star-actor-wire:decode-envelope contract (bytes bad)))))
    (fails 'star-actor-wire:wire-error
           (lambda () (star-actor-wire:decode-envelope contract
                        (make-array 1 :element-type '(unsigned-byte 8) :initial-element 255))))
    (fails 'star-actor-wire:wire-error
           (lambda () (star-actor-wire:decode-envelope contract
                        (make-array 1048577 :element-type '(unsigned-byte 8) :initial-element 32))))
    (fails 'star-actor-wire:wire-error
           (lambda () (star-actor-wire:decode-envelope contract
                        (bytes (concatenate 'string (make-string 40 :initial-element #\[)
                                            "0" (make-string 40 :initial-element #\]))))))
    (let* ((boolean (command "bool" :type "boolean@1" :payload '(("flag" . nil))))
           (boolean-json (babel:octets-to-string
                          (star-actor-wire:encode-envelope contract boolean) :encoding :utf-8)))
      (check (search "false" boolean-json))
      (check (equal (getf (star-actor-wire:decode-envelope contract (bytes boolean-json)) :payload)
                    '(("flag" . nil))))
      (fails 'star-actor-wire:wire-error
             (lambda () (star-actor-wire:decode-envelope contract
                          (bytes (replace-once boolean-json "false" "null"))))))))


(defun binding-tests ()
  (let* ((profiles '("star.actor2actor/1"))
         (request (command "req"))
         (reply (staractorprotocol:make-reply-envelope request :message-id "reply"
                  :message-type "star.zmq/echo@1" :actor "nim.echo"
                  :payload '(("text" . "result"))))
         (unknown (staractorprotocol:make-error-envelope request :message-id "unknown"
                    :actor "nim.echo" :code "star.outcome-unknown" :message "reconcile"
                    :retryable nil))
         (cancel (staractorprotocol:make-cancel-envelope request :message-id "cancel"
                   :actor "nim.echo" :reason "requested")))
    (setf (getf request :deadline) "2026-10-04T17:00:00Z")
    (dolist (envelope (list request reply unknown cancel))
      (multiple-value-bind (rabbit-body headers)
          (star-actor-wire:encode-binding-message :rabbit profiles (manifest) envelope)
        (multiple-value-bind (zmq-body zmq-headers)
            (star-actor-wire:encode-binding-message :zmq profiles (manifest) envelope)
          (check (null zmq-headers))
          (check (equalp rabbit-body zmq-body))
          (check (equalp
                  (star-actor-wire:decode-binding-message :rabbit profiles (manifest)
                                                         rabbit-body headers)
                  (star-actor-wire:decode-binding-message :zmq profiles (manifest) zmq-body)))
          (dolist (key '(:message-id :correlation-id :content-type :profile))
            (let ((bad (copy-list headers)))
              (setf (getf bad key) "wrong")
              (fails 'star-actor-wire:wire-error
                (lambda () (star-actor-wire:decode-binding-message
                             :rabbit profiles (manifest) rabbit-body bad)))))
          (fails 'star-actor-wire:wire-error
            (lambda () (star-actor-wire:decode-binding-message
                         :rabbit profiles (manifest) rabbit-body
                         (append headers '(:message-id "duplicate")))))
          (fails 'star-actor-wire:wire-error
            (lambda () (star-actor-wire:decode-binding-message
                         :zmq profiles (manifest) zmq-body headers))))))
    (fails 'star-actor-wire:unsupported-peer-protocol
      (lambda () (star-actor-wire:encode-binding-message :zmq '("SC01")
                                                         (manifest) request)))
    (fails 'star-actor-wire:unsupported-peer-protocol
      (lambda () (star-actor-wire:decode-binding-message :rabbit '("SR01")
                    (manifest) (bytes "{}"))))
    (fails 'star-actor-wire:wire-error
      (lambda () (star-actor-wire:negotiate-actor2actor-profile
                   '("star.actor2actor/1" "star.actor2actor/1"))))))

(defun fixture-tests ()
  (dolist (name '("request" "reply" "accepted" "completed" "unknown" "cancel"))
    (let* ((path (asdf:system-relative-pathname
                  :star-actor-wire
                  (format nil "../fixtures/actor2actor/lifecycle-v1/~A.json" name)))
           (bytes (with-open-file (s path :element-type '(unsigned-byte 8)) (let ((b (make-array (file-length s) :element-type '(unsigned-byte 8)))) (read-sequence b s) b)))
           (envelope (star-actor-wire:decode-envelope (manifest) bytes)))
      (check (equalp bytes (star-actor-wire:encode-envelope (manifest) envelope)))
      (check (equal "correlation/req" (getf envelope :correlation-id))))))

(defun run-tests ()
  (setf *assertions* 0)
  (codec-tests)
  (binding-tests)
  (fixture-tests)
  (exact-json-tests)
  (format t "Shared Actor2Actor wire/binding tests passed (~D assertions; no sockets).~%"
          *assertions*)
  t)
