(in-package :star-actor-wire-tests)

(defun file-bytes (name)
  (with-open-file (s (asdf:system-relative-pathname
                      :star-actor-wire (concatenate 'string "../fixtures/actor2actor/lifecycle-v1/" name))
                     :element-type '(unsigned-byte 8))
    (let ((b (make-array (file-length s) :element-type '(unsigned-byte 8))))
      (read-sequence b s) b)))
(defun field (object key) (cdr (assoc key object :test #'equal)))
(defun exact-manifest ()
  ;; Profile shape fixture only. Document validity is independently checked with
  ;; the pinned generated StarIntel JSON Schema in test_exact_document.py.
  '(:messages
    ((:name "star.documents.put@1"
      :fields ((:name "document" :type "map" :required t)
               (:name "scope" :type "map" :required t)
               (:name "precondition" :type "map" :required t)))
     (:name "conformance.document-result@1" :fields ((:name "document" :type "map" :required t))))))
(defun exact-request ()
  (staractorprotocol:make-command-envelope
   :message-id "exact-request" :correlation-id "exact-correlation" :actor "documents"
   :message-type "star.documents.put@1" :idempotency-key "exact-key"
   :deadline "2026-10-04T18:00:00Z"
   :payload (list (cons "document" (star-actor-wire:decode-json-value (file-bytes "exact-document.json")))
                  (cons "scope" '(("databaseId" . "intel") ("datasetId" . "conformance")
                                   ("documentId" . "person:exact")))
                  (cons "precondition" '(("ifAbsent" . t))))))
(defun exact-json-tests ()
  (let* ((request (exact-request))
         (source-document (field (getf request :payload) "document"))
         (encoded (star-actor-wire:encode-envelope (exact-manifest) request))
         (decoded (star-actor-wire:decode-command-message :zmq '("star.actor2actor/1")
                                                        (exact-manifest) encoded))
         (document (field (getf decoded :payload) "document"))
         (extensions (field document "extensions"))
         (nested (field extensions "nested"))
         (numbers (field extensions "numbers")))
    (check (equalp encoded (star-actor-wire:encode-envelope (exact-manifest) decoded)))
    (check (equalp (star-actor-wire:encode-json-value source-document)
                   (star-actor-wire:encode-json-value document)))
    (check (= 9007199254740993 (aref numbers 1)))
    (check (= -1234567890123456789012345678901234567890 (aref numbers 2)))
    (check (equal "0.12345678901234567890123456789"
                   (staractorprotocol:portable-json-number-lexeme (aref numbers 0))))
    (check (equal "1e999999999999999999999"
                   (staractorprotocol:portable-json-number-lexeme (aref numbers 8))))
    (check (eq (field nested "false") staractorprotocol:+portable-json-false+))
    (check (eq (field nested "null") staractorprotocol:+portable-json-null+))
    (check (eq (field nested "object") staractorprotocol:+portable-json-empty-object+))
    (check (equalp (field nested "empty") #()))
    (check (null (assoc "missing" nested :test #'equal)))
    (check (find (code-char 0) (field document "fname")))
    (check (find (code-char #x1f600) (field document "fname")))
    (check (eq (field (field extensions "__proto__") "polluted") staractorprotocol:+portable-json-false+))
    (let* ((reply (staractorprotocol:make-reply-envelope request :message-id "exact-reply"
                    :message-type "conformance.document-result@1" :actor "documents"
                    :payload (list (cons "document" document))))
           (snapshot (staractorprotocol:snapshot-portable-wire-value reply))
           (before (star-actor-wire:encode-envelope (exact-manifest) snapshot)))
      (setf (char (staractorprotocol:portable-json-number-lexeme (aref numbers 0)) 0) #\9)
      (check (equalp before (star-actor-wire:encode-envelope (exact-manifest) snapshot)))
      (fails 'star-actor-wire:wire-error
        (lambda () (star-actor-wire:decode-command-message :zmq '("star.actor2actor/1")
                     (exact-manifest) (star-actor-wire:encode-envelope (exact-manifest) snapshot)))))
    (let ((event (staractorprotocol:make-event-envelope :message-id "event" :actor "documents"
                   :message-type "conformance.document-result@1" :payload (list (cons "document" document)))))
      (fails 'star-actor-wire:wire-error
        (lambda () (star-actor-wire:decode-command-message :zmq '("star.actor2actor/1")
                     (exact-manifest) (star-actor-wire:encode-envelope (exact-manifest) event))))))
  ;; Integer-form negative zero carries observable JSON sign information.
  (dolist (raw '("-0" "[-0]" "{\"value\":-0}"))
    (check (equal raw (babel:octets-to-string
      (star-actor-wire:encode-json-value
        (staractorprotocol:snapshot-portable-wire-value
          (star-actor-wire:decode-json-value (bytes raw)))) :encoding :utf-8))))
  (let* ((request (exact-request))
         (document (field (getf request :payload) "document")))
    (push (cons "negativeZero" (staractorprotocol:make-portable-json-number "-0"))
          (cdr (assoc "extensions" document :test #'equal)))
    (let* ((encoded (star-actor-wire:encode-envelope (exact-manifest) request))
           (decoded (star-actor-wire:decode-command-message :zmq '("star.actor2actor/1")
                        (exact-manifest) encoded)))
      (check (search "\"negativeZero\":-0" (babel:octets-to-string encoded :encoding :utf-8)))
      (check (equalp encoded (star-actor-wire:encode-envelope (exact-manifest)
                              (staractorprotocol:snapshot-portable-wire-value decoded))))))
  (let* ((manifest '(:messages ((:name "maybe@1"
                    :fields ((:name "flag" :type (:optional "boolean") :required t))))))
         (command (staractorprotocol:make-command-envelope
           :message-id "optional" :message-type "maybe@1" :actor "documents"
           :idempotency-key "optional" :payload
           (list (cons "flag" staractorprotocol:+portable-json-false+))))
         (encoded (star-actor-wire:encode-envelope manifest command)))
    (check (search "\"flag\":false" (babel:octets-to-string encoded :encoding :utf-8)))
    (check (equalp encoded (star-actor-wire:encode-envelope manifest
                            (star-actor-wire:decode-envelope manifest encoded)))))
  (let* ((request (exact-request))
         (document (field (getf request :payload) "document"))
         (reply (staractorprotocol:make-reply-envelope request :message-id "zero-reply"
                  :message-type "conformance.document-result@1" :actor "documents"
                  :payload (list (cons "document" document)))))
    (push (cons "negativeZero" (staractorprotocol:make-portable-json-number "-0"))
          (cdr (assoc "extensions" document :test #'equal)))
    (let* ((frame (staractorprotocol:make-actor2actor-stream-frame
                    :task-id "zero-task" :correlation-id "exact-correlation"
                    :sequence 1 :envelope reply :terminal-p nil))
           (encoded (star-actor-wire:encode-envelope (exact-manifest)
                      (staractorprotocol:actor2actor-stream-frame-envelope frame))))
      (check (search "\"negativeZero\":-0" (babel:octets-to-string encoded :encoding :utf-8)))
      (check (equalp encoded (star-actor-wire:encode-envelope (exact-manifest)
                              (star-actor-wire:decode-envelope (exact-manifest) encoded))))))
  (let ((manifest '(:types ((:kind :document :name "maybe-doc@1"
                            :fields ((:name "flag" :type (:optional "boolean") :required nil))))
                    :messages ((:name "nested-maybe@1"
                                :fields ((:name "nested" :type "maybe-doc@1" :required t)))))))
    (dolist (case (list (cons (list (cons "flag" staractorprotocol:+portable-json-false+))
                            "\"flag\":false")
                       (cons '(("flag" . nil)) "\"flag\":null")
                       (cons nil "\"nested\":{}")))
      (let* ((command (staractorprotocol:make-command-envelope
                       :message-id "nested" :message-type "nested-maybe@1" :actor "documents"
                       :idempotency-key "nested" :payload (list (cons "nested" (car case)))))
             (encoded (star-actor-wire:encode-envelope manifest command)))
        (check (search (cdr case) (babel:octets-to-string encoded :encoding :utf-8)))
        (check (equalp encoded (star-actor-wire:encode-envelope manifest
                                (star-actor-wire:decode-envelope manifest encoded)))))))
  (dolist (bad '("01" "-01" "+1" "1." ".1" "1e" "1e+" "NaN" "Infinity" "1 2" "1e2,0"))
    (check (not (staractorprotocol:portable-json-number-token-p bad)))
    (fails 'star-actor-wire:wire-error (lambda () (star-actor-wire:decode-json-value (bytes bad)))))
  (dolist (bad '("{\"a\":null,\"a\":false}" "{\"__proto__\":{},\"__proto__\":{}}" "[1,]"))
    (fails 'star-actor-wire:wire-error (lambda () (star-actor-wire:decode-json-value (bytes bad)))))
  (let* ((source (copy-seq "1.2345")) (n (staractorprotocol:make-portable-json-number source)))
    (setf (char source 0) #\9)
    (check (equal "1.2345" (staractorprotocol:portable-json-number-lexeme n))))
  t)
