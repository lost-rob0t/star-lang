(defpackage :star-zmq-actor-tests (:use :cl) (:export #:run-tests))
(in-package :star-zmq-actor-tests)

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
         (encoded (star-zmq-actors:encode-envelope contract envelope))
         (decoded (star-zmq-actors:decode-envelope contract encoded))
         (text (babel:octets-to-string encoded :encoding :utf-8)))
    (check (equal (getf decoded :payload) (getf envelope :payload)))
    (check (equalp encoded (star-zmq-actors:encode-envelope contract decoded)))
    (dolist (bad (list "{}" "[]" "null" "{unquoted:1}" "{\"x\":1,}" "{\"x\":01}"
                      "{\"x\":1} false" "{\"x\":1,\"\\u0078\":2}" "{\"x\":\"\\ud800\"}"
                      (replace-once text "\"starVersion\":1" "\"starVersion\":2")
                      (replace-once text "\"attempt\":1" "\"attempt\":0")
                      (replace-once text "\"attempt\":1" "\"attempt\":true")
                      (replace-once text "\"attempt\":1" "\"attempt\":1,\"attempt\":2")
                      (replace-once text "\"payload\":{" "\"payload\":{\"extra\":1,")
                      (concatenate 'string text "{}"))))
      (fails 'star-zmq-actors:wire-error
             (lambda () (star-zmq-actors:decode-envelope contract (bytes bad)))))
    (fails 'star-zmq-actors:wire-error
           (lambda () (star-zmq-actors:decode-envelope contract
                        (make-array 1 :element-type '(unsigned-byte 8) :initial-element 255))))
    (fails 'star-zmq-actors:wire-error
           (lambda () (star-zmq-actors:decode-envelope contract
                        (make-array 1048577 :element-type '(unsigned-byte 8) :initial-element 32))))
    (fails 'star-zmq-actors:wire-error
           (lambda () (star-zmq-actors:decode-envelope contract
                        (bytes (concatenate 'string (make-string 40 :initial-element #\[)
                                            "0" (make-string 40 :initial-element #\]))))))
    (let* ((boolean (command "bool" :type "boolean@1" :payload '(("flag" . nil))))
           (boolean-json (babel:octets-to-string
                          (star-zmq-actors:encode-envelope contract boolean) :encoding :utf-8)))
      (check (search "false" boolean-json))
      (check (equal (getf (star-zmq-actors:decode-envelope contract (bytes boolean-json)) :payload)
                    '(("flag" . nil))))
      (fails 'star-zmq-actors:wire-error
             (lambda () (star-zmq-actors:decode-envelope contract
                          (bytes (replace-once boolean-json "false" "null"))))))))

(defun peer-tests (context executable fixture directory)
  (flet ((endpoint (name) (format nil "ipc://~A/~A.sock" directory name)))
    (let ((peer (star-zmq-actors:open-peer context executable (endpoint "nim")
                                         "nim-test" "nim.echo" (manifest) :generation 12)))
      (unwind-protect
           (progn
             (check (= 12 (star-zmq-actors:peer-generation peer)))
             (check (star-zmq-actors:peer-live-p peer))
             (dolist (id '("one" "two" "three"))
               (let* ((request (command id))
                      (reply (star-zmq-actors:peer-request peer request)))
                 (check (eq :reply (getf reply :kind)))
                 (check (equal (getf reply :payload) (getf request :payload)))
                 (check (equal (getf reply :causation-id) id))))
             (let ((caught nil))
               (bordeaux-threads:join-thread
                (bordeaux-threads:make-thread
                 (lambda ()
                   (handler-case (star-zmq-actors:peer-request peer (command "wrongThread"))
                     (star-zmq:socket-owner-error () (setf caught t))))))
               (check caught))
             (check (star-zmq-actors:peer-live-p peer))
             (let ((reply (star-zmq-actors:peer-request peer (command "unknown" :type "unknown@1" :payload nil))))
               (check (eq :error (getf reply :kind)))
               (check (null (getf (getf reply :payload) :retryable))))
             (let ((reply (star-zmq-actors:peer-request peer (command "stop" :type "star.zmq/stop@1" :payload nil))))
               (check (eq :reply (getf reply :kind)))))
        (star-zmq-actors:close-peer peer))
      (check (not (star-zmq-actors:peer-live-p peer)))
      (check (starprocessport:process-reaped-p (star-zmq-actors::peer-process peer)))
      (check (null (star-zmq-actors::peer-drainers peer))))
    (dolist (scenario '("noReady" "staleGeneration" "wrongRoute"))
      (fails (if (string= scenario "noReady") 'star-zmq-actors:peer-timeout-error
                 'star-zmq-actors:peer-protocol-error)
             (lambda () (star-zmq-actors:open-peer context fixture (endpoint scenario)
                          "fault-test" scenario (manifest) :generation 9
                          :timeout-ms (if (string= scenario "noReady") 250 5000)))))
    (dolist (scenario '("wrongCorrelation" "dieOnCommand" "stallOnCommand" "malformed" "logFlood"))
      (let ((peer (star-zmq-actors:open-peer context fixture (endpoint scenario)
                                           "fault-test" scenario (manifest) :generation 10)))
        (unwind-protect
             (let ((request (command scenario :actor scenario)))
               (if (string= scenario "logFlood")
                   (check (eq :reply (getf (star-zmq-actors:peer-request peer request) :kind)))
                   (fails (cond ((string= scenario "wrongCorrelation") 'star-zmq-actors:peer-protocol-error)
                                ((string= scenario "dieOnCommand") 'star-zmq-actors:peer-exited-error)
                                ((string= scenario "stallOnCommand") 'star-zmq-actors:peer-timeout-error)
                                (t 'star-zmq-actors:wire-error))
                          (lambda () (star-zmq-actors:peer-request peer request :timeout-ms 500)))))
          (star-zmq-actors:close-peer peer))
        (check (starprocessport:process-reaped-p (star-zmq-actors::peer-process peer)))
        (check (null (star-zmq-actors::peer-drainers peer)))))))

(defun run-tests ()
  (setf *assertions* 0)
  (codec-tests)
  ;; This native gate is intentionally not optional: a missing executable is
  ;; an environment failure, never an actor test passing with zero execution.
  (let* ((executable (or (uiop:getenv "STAR_ZMQ_ACTOR") (error "STAR_ZMQ_ACTOR is required.")))
         (fixture (or (uiop:getenv "STAR_ZMQ_FAULT_PEER") (error "STAR_ZMQ_FAULT_PEER is required.")))
         (directory (string-trim '(#\Newline #\Return)
                                (uiop:run-program '("mktemp" "-d") :output :string)))
         (context (star-zmq:make-context)))
    (unwind-protect
         (peer-tests context executable fixture directory)
      (star-zmq:close-context context)
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname directory) :validate t :if-does-not-exist :ignore)))
  (format t "~&star-zmq actor codec/session checks: ~D assertions passed.~%" *assertions*)
  t)
