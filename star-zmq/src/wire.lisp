(defpackage :star-zmq-actors
  (:use :cl)
  (:export #:wire-error #:encode-envelope #:decode-envelope
           #:peer-error #:peer-timeout-error #:peer-protocol-error #:peer-exited-error
           #:open-peer #:close-peer #:peer-request #:peer-live-p #:peer-generation))
(in-package :star-zmq-actors)

(define-condition wire-error (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "Invalid or unsupported StarLang JSON frame." stream))))

(defconstant +wire-byte-limit+ 1048576)
(defconstant +wire-depth-limit+ 32)
(defconstant +wire-value-limit+ 16384)

(defparameter +envelope-fields+
  '(("starVersion" . :star-version) ("kind" . :kind)
    ("messageId" . :message-id) ("messageType" . :message-type)
    ("actor" . :actor) ("sender" . :sender)
    ("correlationId" . :correlation-id) ("causationId" . :causation-id)
    ("attempt" . :attempt) ("idempotencyKey" . :idempotency-key)
    ("dataset" . :dataset) ("replyTo" . :reply-to)
    ("sentAt" . :sent-at) ("deadline" . :deadline) ("payload" . :payload)))
(defparameter +control-fields+
  '(("status" . :status) ("forMessageId" . :for-message-id)
    ("reason" . :reason) ("retryAfterMs" . :retry-after-ms)
    ("code" . :code) ("message" . :message) ("retryable" . :retryable)
    ("details" . :details) ("targetMessageId" . :target-message-id)
    ("targetCorrelationId" . :target-correlation-id)))

(defun fail-wire () (error 'wire-error))

(defun scan-json-frame (text)
  "Bound recursion/tokens and require RFC 8259 syntax before calling YASON.
YASON remains the value parser. In particular, do not accept its permissive
unquoted-key, number, trailing-comma, or trailing-input extensions."
  (let ((index 0) (size (length text)) (values 0))
    (labels ((peek () (and (< index size) (char text index)))
             (space () (loop while (member (peek) '(#\Space #\Tab #\Return #\Newline))
                             do (incf index)))
             (take (char) (unless (eql (peek) char) (fail-wire)) (incf index))
             (digit () (let ((c (peek))) (and c (find c "0123456789"))))
             (string-token ()
               (let ((start index))
                 (take #\")
                 (loop
                   (let ((c (peek)))
                     (unless c (fail-wire))
                     (cond
                       ((eql c #\") (incf index) (return))
                       ((< (char-code c) 32) (fail-wire))
                       ((eql c #\\)
                        (incf index)
                        (let ((escape (peek)))
                          (unless (and escape (find escape "\"\\/bfnrtu")) (fail-wire))
                          (incf index)
                          (when (eql escape #\u)
                            (dotimes (i 4)
                              (declare (ignore i))
                              (unless (and (peek) (digit-char-p (peek) 16)) (fail-wire))
                              (incf index)))))
                       (t (incf index)))))
                 ;; Decode only the validated string token, never Lisp source.
                 (let ((value (yason:parse (subseq text start index))))
                   (unless (and (stringp value)
                                (every (lambda (c) (not (<= #xD800 (char-code c) #xDFFF))) value))
                     (fail-wire))
                   value)))
             (number-token ()
               (let ((start index))
                 (when (eql (peek) #\-) (incf index))
                 (if (eql (peek) #\0)
                     (incf index)
                     (progn
                       (unless (and (digit) (not (eql (peek) #\0))) (fail-wire))
                       (loop while (digit) do (incf index))))
                 (when (eql (peek) #\.)
                   (incf index)
                   (unless (digit) (fail-wire))
                   (loop while (digit) do (incf index)))
                 (when (member (peek) '(#\e #\E))
                   (incf index)
                   (when (member (peek) '(#\+ #\-)) (incf index))
                   (unless (digit) (fail-wire))
                   (loop while (digit) do (incf index)))
                 (when (> (- index start) 128) (fail-wire))))
             (literal (word)
               (loop for c across word do (take c)))
             (value (depth)
               (when (or (> depth +wire-depth-limit+)
                         (> (incf values) +wire-value-limit+)) (fail-wire))
               (space)
               (case (peek)
                 (#\" (string-token))
                 (#\{
                  (incf index) (space)
                  (let ((keys (make-hash-table :test #'equal)))
                    (unless (eql (peek) #\})
                      (loop
                        (space)
                        (let ((key (string-token)))
                          (when (gethash key keys) (fail-wire))
                          (setf (gethash key keys) t))
                        (space) (take #\:) (value (1+ depth)) (space)
                        (unless (eql (peek) #\,) (return))
                        (incf index))))
                  (take #\}))
                 (#\[
                  (incf index) (space)
                  (unless (eql (peek) #\])
                    (loop (value (1+ depth)) (space)
                          (unless (eql (peek) #\,) (return)) (incf index)))
                  (take #\]))
                 (#\t (literal "true")) (#\f (literal "false")) (#\n (literal "null"))
                 (otherwise (number-token)))))
      (value 0) (space)
      (unless (= index size) (fail-wire))
      t)))

(defun portable-json-value (value)
  (cond
    ((eq value 'yason:true) t)
    ((or (eq value 'yason:false) (eq value :null)) nil)
    ((hash-table-p value)
     (loop for key being the hash-keys of value using (hash-value child)
           collect (cons key (portable-json-value child))))
    ((and (vectorp value) (not (stringp value)))
     (map 'list #'portable-json-value value))
    (t value)))

(defun mapped-plist (object fields)
  (unless (hash-table-p object) (fail-wire))
  (loop for key being the hash-keys of object using (hash-value value)
        for mapping = (assoc key fields :test #'string=)
        unless mapping do (fail-wire)
        append (list (cdr mapping) (portable-json-value value))))

(defun closed-name (value choices)
  ;; Never intern peer-controlled strings into the Lisp image.
  (or (and (stringp value) (cdr (assoc value choices :test #'string=))) (fail-wire)))

(defun encode-envelope (manifest envelope)
  "Use the canonical serializer and authoritative manifest validation unchanged."
  (let* ((text (starcanonicaljson:canonical-lifecycle-envelope-json manifest envelope))
         (bytes (babel:string-to-octets text :encoding :utf-8)))
    (unless (<= 1 (length bytes) +wire-byte-limit+) (fail-wire))
    (scan-json-frame text)
    bytes))

(defun decode-envelope (manifest bytes)
  "Decode a bounded JSON frame, preserving payload key spelling and no new schema."
  (handler-case
      (progn
        (check-type bytes (simple-array (unsigned-byte 8) (*)))
        (unless (<= 1 (length bytes) +wire-byte-limit+) (fail-wire))
        (let* ((text (babel:octets-to-string bytes :encoding :utf-8))
               (checked (scan-json-frame text))
               (object (yason:parse text :object-as :hash-table
                                        :json-arrays-as-vectors t
                                        :json-booleans-as-symbols t
                                        :json-nulls-as-keyword t))
               (envelope (mapped-plist object +envelope-fields+)))
          (declare (ignore checked))
          (unless (equalp bytes (babel:string-to-octets text :encoding :utf-8)) (fail-wire))
          (setf (getf envelope :kind)
                (closed-name (getf envelope :kind)
                             '(("command" . :command) ("event" . :event) ("reply" . :reply)
                               ("ack" . :ack) ("error" . :error) ("cancel" . :cancel))))
          (dolist (field +envelope-fields+)
            (unless (member (cdr field) '(:kind :payload :star-version :attempt))
              (multiple-value-bind (value present) (gethash (car field) object)
                (when (and present (not (stringp value))) (fail-wire)))))
          (when (member (getf envelope :kind) '(:ack :error :cancel))
            (let ((payload (mapped-plist (gethash "payload" object) +control-fields+)))
              (when (eq (getf envelope :kind) :ack)
                (setf (getf payload :status)
                      (closed-name (getf payload :status)
                                   '(("accepted" . :accepted) ("completed" . :completed)
                                     ("rejected" . :rejected) ("retry" . :retry)))))
              (when (eq (getf envelope :kind) :error)
                (unless (member (gethash "retryable" (gethash "payload" object))
                                '(yason:true yason:false)) (fail-wire)))
              (setf (getf envelope :payload) payload)))
          (staractorprotocol:validate-lifecycle-envelope-against-manifest manifest envelope)
          ;; JSON false/null, empty object/array and unknown payload fields must
          ;; not collapse silently in the portable Lisp representation. Reuse
          ;; the canonical authority and require a lossless value round trip.
          (let ((round-trip (yason:parse
                             (babel:octets-to-string (encode-envelope manifest envelope) :encoding :utf-8)
                             :object-as :hash-table :json-arrays-as-vectors t
                             :json-booleans-as-symbols t :json-nulls-as-keyword t)))
            (unless (equalp object round-trip) (fail-wire)))
          envelope))
    (wire-error (condition) (error condition))
    (error () (fail-wire))))
