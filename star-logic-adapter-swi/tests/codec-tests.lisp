(defpackage :starlogicadapterswi-tests
  (:use :cl :fiveam)
  (:import-from :starlogicprotocol
                #:logic-backend-descriptor-of
                #:logic-backend-descriptor-semantic-profiles
                #:logic-backend-descriptor-capabilities
                #:logic-backend-descriptor-isolation-classes))
(in-package :starlogicadapterswi-tests)

(def-suite starlogicadapterswi-tests
  :description "Pure SWI MQI adapter codec and boundary tests.")
(in-suite starlogicadapterswi-tests)

(defun octets (&rest bytes)
  (make-array (length bytes)
              :element-type '(unsigned-byte 8)
              :initial-contents bytes))

(defun ascii-octets (string)
  (babel:string-to-octets string :encoding :ascii))

(defun mqi-line (control &rest arguments)
  (apply #'format nil (concatenate 'string control "~%") arguments))

(defun chunked-source (&rest chunks)
  (let ((chunks (copy-list chunks))
        (current nil)
        (index 0))
    (lambda ()
      (loop
        (when (and current (< index (length current)))
          (return (values (aref current index) (progn (incf index) t))))
        (unless chunks
          (return (values nil nil)))
        (setf current (pop chunks)
              index 0)))))

(defun inbound-octet-frame (payload-octets)
  (let ((header (ascii-octets (format nil "~D.~%" (length payload-octets)))))
    (starlogicadapterswi::%concat-octets header payload-octets)))

(defun inbound-frame (payload)
  "Construct the receive-side framing SWI uses for JSON payloads."
  (inbound-octet-frame
   (babel:string-to-octets payload :encoding :utf-8)))

(test utf8-byte-length-not-character-count
  (let* ((message "run(atom('λ'),-1)")
         (frame (starlogicadapterswi::%encode-mqi-frame message))
         (separator (position (char-code #\Newline) frame))
         (header (babel:octets-to-string (subseq frame 0 separator)
                                         :encoding :ascii))
         (payload (babel:string-to-octets
                   (mqi-line "~A." message)
                   :encoding :utf-8)))
    (is (string= header (format nil "~D." (length payload))))
    (is (> (length payload) (+ (length message) 2)))))

(test ascii-frame-roundtrip
  (let* ((frame (starlogicadapterswi::%encode-mqi-frame "close"))
         (payload (starlogicadapterswi::%decode-mqi-frame
                   (chunked-source frame))))
    (is (string= (mqi-line "close.")
                 (babel:octets-to-string payload :encoding :utf-8)))))

(test zero-length-frame-is-framed-data
  (let ((payload (starlogicadapterswi::%decode-mqi-frame
                  (chunked-source (ascii-octets (mqi-line "0."))))))
    (is (= 0 (length payload)))))

(test fragmented-frame-across-many-chunks
  (let* ((frame (starlogicadapterswi::%encode-mqi-frame "quit"))
         (chunks (loop for byte across frame collect (octets byte)))
         (payload (starlogicadapterswi::%decode-mqi-frame
                   (apply #'chunked-source chunks))))
    (is (string= (mqi-line "quit.")
                 (babel:octets-to-string payload :encoding :utf-8)))))

(test heartbeat-bytes-are-discarded-before-header
  (let* ((frame (inbound-frame "{\"args\":[[[]]],\"functor\":\"true\"}"))
         (response (starlogicadapterswi::%parse-mqi-json-response
                    (chunked-source (ascii-octets "...")
                                    (subseq frame 0 2)
                                    (subseq frame 2)))))
    (is (starlogicadapterswi::%simple-true-response-p response))))

(test malformed-length-is-rejected
  (signals starlogicadapterswi:swi-mqi-malformed-frame-error
    (starlogicadapterswi::%decode-mqi-frame
     (chunked-source (ascii-octets (mqi-line "x."))))))

(test oversized-length-is-rejected-before-allocation
  (signals starlogicadapterswi:swi-mqi-malformed-frame-error
    (starlogicadapterswi::%decode-mqi-frame
     (chunked-source (ascii-octets (mqi-line "99999999.")))
     :max-frame-bytes 1024)))

(test truncated-payload-is-unexpected-eof
  (signals starlogicadapterswi:swi-unexpected-eof-error
    (starlogicadapterswi::%decode-mqi-frame
     (chunked-source (ascii-octets (format nil "5.~%ab"))))))

(test invalid-utf8-response-is-rejected
  (signals starlogicadapterswi:swi-mqi-malformed-response-error
    (starlogicadapterswi::%parse-mqi-json-response
     (chunked-source (inbound-octet-frame (octets #xC3 #x28))))))

(test invalid-json-response-is-rejected
  (signals starlogicadapterswi:swi-mqi-malformed-response-error
    (starlogicadapterswi::%parse-mqi-json-response
     (chunked-source (inbound-frame "not-json")))))

(test trailing-json-data-is-rejected
  (signals starlogicadapterswi:swi-mqi-malformed-response-error
    (starlogicadapterswi::%parse-mqi-json-response
     (chunked-source
      (inbound-frame
       "{\"args\":[[[]]],\"functor\":\"true\"}junk")))))

(test raw-json-response-without-prolog-terminator-is-accepted
  (let ((response (starlogicadapterswi::%parse-mqi-json-response
                   (chunked-source
                    (inbound-frame "{\"args\":[[[]]],\"functor\":\"true\"}")))))
    (is (starlogicadapterswi::%simple-true-response-p response))))

(test generic-mqi-terminated-json-response-is-also-accepted
  (let* ((json "{\"args\":[[[]]],\"functor\":\"true\"}")
         (response (starlogicadapterswi::%parse-mqi-json-response
                    (chunked-source (inbound-frame (mqi-line "~A." json))))))
    (is (starlogicadapterswi::%simple-true-response-p response))))

(test short-invalid-json-response-is-rejected
  (signals starlogicadapterswi:swi-mqi-malformed-response-error
    (starlogicadapterswi::%parse-mqi-json-response
     (chunked-source (inbound-frame "x")))))

(test documented-authentication-shape-is-parsed
  (let* ((json "{\"args\":[[[{\"args\":[\"comm\",\"goal\"],\"functor\":\"threads\"},{\"args\":[\"1\",\"0\"],\"functor\":\"version\"}]]],\"functor\":\"true\"}")
         (response (starlogicadapterswi::%parse-mqi-json-response
                    (chunked-source (inbound-frame json)))))
    (multiple-value-bind (major minor comm goal)
        (starlogicadapterswi::%extract-authentication-metadata response)
      (is (string= "1" major))
      (is (string= "0" minor))
      (is (string= "comm" comm))
      (is (string= "goal" goal)))))

(test unknown-mqi-major-version-fails-closed
  (signals starlogicadapterswi:swi-unsupported-mqi-protocol-error
    (starlogicadapterswi::%validate-mqi-version "2" "0")))

(test startup-values-are-strict
  (multiple-value-bind (port password)
      (starlogicadapterswi::%parse-startup-values "4242" "secret")
    (is (= 4242 port))
    (is (string= "secret" password)))
  (signals starlogicadapterswi:swi-malformed-startup-data-error
    (starlogicadapterswi::%parse-startup-values "not-a-port" "secret"))
  (signals starlogicadapterswi:swi-malformed-startup-data-error
    (starlogicadapterswi::%parse-startup-values "4242" "")))

(test final-system-has-no-prototype-dependency
  (let* ((system (asdf:find-system "star-logic-adapter-swi"))
         (dependencies (asdf:system-depends-on system)))
    (is (not (member "starlang-prototype" dependencies :test #'string-equal)))))

(test public-package-has-no-raw-prolog-execution-api
  (let ((forbidden '("RUN-PROLOG" "QUERY-PROLOG" "EXECUTE-GOAL"
                     "CALL-PREDICATE" "CALL-PROLOG" "CONSULT")))
    (do-external-symbols (symbol (find-package :starlogicadapterswi))
      (is (not (member (symbol-name symbol) forbidden :test #'string=))))))

(defun run-tests ()
  (let ((results (run 'starlogicadapterswi-tests)))
    (explain! results)
    (unless (results-status results)
      (error "star-logic-adapter-swi unit tests failed."))
    t))
