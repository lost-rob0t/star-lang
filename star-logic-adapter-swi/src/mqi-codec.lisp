(in-package :starlogicadapterswi)

(defparameter +default-max-mqi-frame-bytes+ (* 4 1024 1024))
(defparameter +max-mqi-header-digits+ 12)
(defparameter +max-native-diagnostic-chars+ 512)

(defun %bounded-diagnostic (value)
  (let ((string (princ-to-string (or value ""))))
    (if (> (length string) +max-native-diagnostic-chars+)
        (concatenate 'string
                     (subseq string 0 +max-native-diagnostic-chars+)
                     "…")
        string)))

(defun %concat-octets (&rest vectors)
  (let* ((size (reduce #'+ vectors :key #'length :initial-value 0))
         (result (make-array size :element-type '(unsigned-byte 8)))
         (offset 0))
    (dolist (vector vectors result)
      (replace result vector :start1 offset)
      (incf offset (length vector)))))

(defun %encode-mqi-frame (message)
  "Encode one outbound MQI Prolog message using its UTF-8 byte count."
  (let* ((wire-string (format nil "~A.~%" message))
         (payload (babel:string-to-octets wire-string :encoding :utf-8))
         (header (babel:string-to-octets
                  (format nil "~D.~%" (length payload))
                  :encoding :ascii)))
    (%concat-octets header payload)))

(defun %write-octets (stream octets)
  (write-sequence octets stream)
  (finish-output stream))

(defun %stream-byte-source (stream)
  (lambda ()
    (handler-case
        (let ((byte (read-byte stream nil :eof)))
          (if (eq byte :eof)
              (values nil nil)
              (values byte t)))
      (error (cause)
        (%swi-fail-diagnostic
         'swi-socket-connection-error
         (%bounded-diagnostic cause)
         "MQI socket read failed.")))))

(defun %next-byte (source eof-condition)
  (multiple-value-bind (byte present-p) (funcall source)
    (unless present-p
      (%swi-fail eof-condition "Unexpected EOF while reading MQI frame."))
    byte))

(defun %decode-mqi-frame (source &key
                                   (max-frame-bytes +default-max-mqi-frame-bytes+))
  "Read one MQI frame from SOURCE, a function returning BYTE,PRESENT-P.

Raw heartbeat '.' bytes preceding a response header are discarded. The
returned octets are exactly the byte-counted payload; interpretation of that
payload is direction/message-specific."
  (let ((first nil))
    (loop
      (setf first (%next-byte source 'swi-unexpected-eof-error))
      (unless (= first (char-code #\.))
        (return)))
    (unless (<= (char-code #\0) first (char-code #\9))
      (%swi-fail 'swi-mqi-malformed-frame-error
                 "MQI frame length does not start with an ASCII digit."))
    (let ((length-value 0)
          (digits 0)
          (current first))
      (loop
        (cond
          ((<= (char-code #\0) current (char-code #\9))
           (incf digits)
           (when (> digits +max-mqi-header-digits+)
             (%swi-fail 'swi-mqi-malformed-frame-error
                        "MQI frame length header is too long."))
           (setf length-value
                 (+ (* length-value 10) (- current (char-code #\0))))
           (when (> length-value max-frame-bytes)
             (%swi-fail 'swi-mqi-malformed-frame-error
                        "MQI frame length ~D exceeds configured limit ~D."
                        length-value max-frame-bytes))
           (setf current (%next-byte source 'swi-unexpected-eof-error)))
          ((= current (char-code #\.))
           (return))
          (t
           (%swi-fail 'swi-mqi-malformed-frame-error
                      "Malformed MQI frame length header."))))
      (unless (= (%next-byte source 'swi-unexpected-eof-error)
                 (char-code #\Newline))
        (%swi-fail 'swi-mqi-malformed-frame-error
                   "MQI frame length terminator is not dot + newline."))
      (let ((payload (make-array length-value :element-type '(unsigned-byte 8))))
        (dotimes (index length-value)
          (setf (aref payload index)
                (%next-byte source 'swi-unexpected-eof-error)))
        payload))))

(defun %decode-mqi-payload-string (source &key
                                            (max-frame-bytes
                                             +default-max-mqi-frame-bytes+))
  (let ((payload (%decode-mqi-frame source :max-frame-bytes max-frame-bytes)))
    (handler-case
        (babel:octets-to-string payload :encoding :utf-8)
      (error (cause)
        (%swi-fail-diagnostic
         'swi-mqi-malformed-response-error
         (%bounded-diagnostic cause)
         "MQI payload is not valid UTF-8.")))))

(defun %json-response-text (payload)
  "Return JSON text from an inbound MQI response payload.

SWI's JSON response body is parsed as the exact byte-counted payload. Some MQI
representations include the generic Prolog term dot/newline suffix in that
count; accept that exact suffix when present, but never require or synthesize
it. JSON parsing remains authoritative for the response body."
  (let ((length (length payload)))
    (if (and (>= length 2)
             (char= (char payload (- length 2)) #\.)
             (char= (char payload (1- length)) #\Newline))
        (subseq payload 0 (- length 2))
        payload)))

(defun %json-whitespace-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return) :test #'char=))

(defun %parse-json-whole (json)
  "Parse exactly one JSON value and reject any non-whitespace tail."
  (with-input-from-string (stream json)
    (let ((value (let ((yason:*parse-json-arrays-as-vectors* nil))
                   (yason:parse stream))))
      (loop for char = (read-char stream nil nil)
            while char
            unless (%json-whitespace-p char)
              do (%swi-fail 'swi-mqi-malformed-response-error
                            "MQI JSON response contains trailing data."))
      value)))

(defun %parse-mqi-json-response (source)
  (let* ((payload (%decode-mqi-payload-string source))
         (json (%json-response-text payload)))
    (handler-case
        (%parse-json-whole json)
      (swi-adapter-error (cause)
        (error cause))
      (error (cause)
        (%swi-fail-diagnostic
         'swi-mqi-malformed-response-error
         (%bounded-diagnostic json)
         "MQI response is not valid JSON: ~A" cause)))))

(defun %json-field (object key)
  (and (hash-table-p object) (gethash key object)))

(defun %compound-p (object functor)
  (and (hash-table-p object)
       (string= (or (%json-field object "functor") "") functor)
       (listp (%json-field object "args"))))

(defun %compound-args (object)
  (%json-field object "args"))

(defun %simple-true-response-p (response)
  (and (%compound-p response "true")
       (equal (%compound-args response) '((())))))

(defun %extract-authentication-metadata (response)
  (unless (%compound-p response "true")
    (%swi-fail 'swi-authentication-error
               "SWI MQI rejected authentication or returned an unexpected response."))
  (let* ((outer (%compound-args response))
         (answers (and (= (length outer) 1) (first outer)))
         (answer (and (listp answers) (= (length answers) 1) (first answers))))
    (unless (listp answer)
      (%swi-fail 'swi-authentication-error
                 "SWI MQI authentication response has an unexpected shape."))
    (let ((threads (find-if (lambda (item) (%compound-p item "threads")) answer))
          (version (find-if (lambda (item) (%compound-p item "version")) answer)))
      (unless (and threads version)
        (%swi-fail 'swi-authentication-error
                   "SWI MQI authentication response omitted thread/version metadata."))
      (let ((thread-args (%compound-args threads))
            (version-args (%compound-args version)))
        (unless (and (= (length thread-args) 2)
                     (= (length version-args) 2))
          (%swi-fail 'swi-authentication-error
                     "SWI MQI authentication metadata has an unexpected shape."))
        (values (first version-args)
                (second version-args)
                (first thread-args)
                (second thread-args))))))
