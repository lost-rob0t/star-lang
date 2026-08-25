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
  "Encode one private MQI term/string using the protocol's UTF-8 byte count."
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

Raw heartbeat '.' bytes preceding a response header are discarded."
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

(defun %strip-mqi-term-terminator (payload)
  (let ((length (length payload)))
    (unless (and (>= length 2)
                 (char= (char payload (- length 2)) #\.)
                 (char= (char payload (1- length)) #\Newline))
      (%swi-fail-diagnostic
       'swi-mqi-malformed-response-error
       (%bounded-diagnostic payload)
       "MQI response payload does not end in dot + newline."))
    (subseq payload 0 (- length 2))))

(defun %parse-mqi-json-response (source)
  (let* ((payload (%decode-mqi-payload-string source))
         (json (%strip-mqi-term-terminator payload)))
    (handler-case
        (let ((yason:*parse-json-arrays-as-vectors* nil))
          (yason:parse json))
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
