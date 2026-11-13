;;;; Shared fixture helper: canonical wire envelope JSON <-> plist codec.
;;;; Loaded by both ingest fixture processes (see ingest-service.lisp and
;;;; ingest-client.lisp). Encoding goes through the final canonical JSON
;;;; authority (star-canonical-json); decoding uses yason and rebuilds the
;;;; envelope plist with the payload kept as a camelCase string-keyed alist.

(require :asdf)

(asdf:load-system :star-actor-protocol)
(asdf:load-system :star-canonical-json)
(asdf:load-system :yason)

(defpackage :star-ingest-fixture
  (:use :cl)
  (:export
   #:encode-envelope
   #:decode-envelope
   #:make-command-envelope
   #:envelope-plist))

(in-package :star-ingest-fixture)

(defun json-lookup (object key)
  "Read KEY from a yason-parsed JSON object (hash table, alist, or plist)."
  (cond
    ((hash-table-p object) (gethash key object))
    ((and (listp object) (every #'consp object))
     (cdr (assoc key object :test #'string=)))
    ((listp object)
     (getf object (intern (string-upcase key) :keyword)))
    (t nil)))

(defun json-value (value)
  "Normalize one yason-parsed JSON value into portable wire data: objects
become camelCase string-keyed alists, arrays become lists, JSON booleans
become booleans."
  (typecase value
    (hash-table
     (let ((entries '()))
       (maphash (lambda (key val)
                  (push (cons key (json-value val)) entries))
                value)
       (nreverse entries)))
    (cons
     (mapcar #'json-value value))
    ((eql :true) t)
    ((eql :false) nil)
    (otherwise value)))

(defun encode-envelope (manifest envelope)
  (starcanonicaljson:canonical-envelope-json manifest envelope))

(defun decode-envelope (json)
  "Decode one canonical envelope JSON string back into the envelope plist.
The payload is normalized into a camelCase string-keyed alist so body
handlers can field-read it."
  (let ((parsed (yason:parse json)))
    (list :star-version 1
          :message-type (json-lookup parsed "messageType")
          :message-id (json-lookup parsed "messageId")
          :actor (json-lookup parsed "actor")
          :dataset (json-lookup parsed "dataset")
          :reply-to (json-lookup parsed "replyTo")
          :payload (json-value (json-lookup parsed "payload")))))

(defun make-command-envelope (message-type payload)
  (staractorprotocol:make-wire-envelope
   :message-type message-type
   :message-id (format nil "ingest-fixture-~D-~6,'0D"
                       (get-universal-time)
                       (mod (random most-positive-fixnum) 1000000))
   :actor "ingest-client"
   :payload payload))

(defun envelope-plist (manifest envelope)
  "Validate ENVELOPE against MANIFEST and return it, signaling a typed
wire error when the command does not satisfy its contract."
  (staractorprotocol:validate-wire-envelope manifest envelope)
  envelope)
