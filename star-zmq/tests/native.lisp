(defpackage :star-zmq-tests (:use :cl) (:export #:run-tests))
(in-package :star-zmq-tests)

(defun octets (&rest values)
  (make-array (length values) :element-type '(unsigned-byte 8) :initial-contents values))

(defun expect-error (type function)
  (let ((caught nil))
    (handler-case (funcall function)
      (error (condition)
        (unless (typep condition type) (error condition))
        (setf caught t)))
    (assert caught)))

(defun round-trip (context)
  (let ((router (star-zmq:open-socket context :router))
        (dealer (star-zmq:open-socket context :dealer :identity (octets 110 105 109))))
    (unwind-protect
         (progn
           (star-zmq:bind-endpoint router "inproc://star-zmq-native")
           (star-zmq:connect-endpoint dealer "inproc://star-zmq-native")
           (expect-error 'star-zmq:transport-limit-error
                         (lambda () (star-zmq:connect-endpoint dealer "inproc://other")))
           (expect-error 'error
                         (lambda () (star-zmq:bind-endpoint router "tcp://0.0.0.0:5555")))
           (expect-error 'error (lambda () (star-zmq:close-context context)))
           (dolist (body (list (octets) (octets 0 1 127 128 255)
                              (octets 123 34 120 34 58 34 226 152 131 34 125)))
             (assert (eq :queued (star-zmq:send-frames dealer (list body))))
             (let ((received (star-zmq:receive-frames router)))
               (assert (equalp (first received) (octets 110 105 109)))
               (assert (equalp (second received) body))
               (star-zmq:send-frames router received)
               (assert (equalp (star-zmq:receive-frames dealer) (list body)))))
           (expect-error 'star-zmq:zmq-error
                         (lambda () (star-zmq:send-frames router
                                     (list (octets 117 110 107 110 111 119 110) (octets 1)))))
           (expect-error 'star-zmq:transport-limit-error
                         (lambda () (star-zmq:send-frames dealer (list (octets 1) (octets 2)))))
           (let ((caught nil))
             (bordeaux-threads:join-thread
              (bordeaux-threads:make-thread
               (lambda ()
                 (handler-case (star-zmq:send-frames dealer (list (octets 1)))
                   (star-zmq:socket-owner-error () (setf caught t))))))
             (assert caught)))
      (star-zmq:close-socket dealer)
      (star-zmq:close-socket router))))

(defun nim-round-trip (context)
  ;; Optional in the ASDF unit gate, mandatory in checks.native-interop.
  (let ((executable (uiop:getenv "STAR_ZMQ_PEER")))
    (when executable
      (let* ((router (star-zmq:open-socket context :router :timeout-ms 5000))
             (endpoint (format nil "ipc://~Astar-zmq-~A.sock"
                               (uiop:temporary-directory) (symbol-name (gensym "PEER"))))
             (process nil)
             (body (octets 123 34 120 34 58 34 226 152 131 34 125)))
        (unwind-protect
             (progn
               (star-zmq:bind-endpoint router endpoint)
               (setf process (uiop:launch-program (list executable endpoint "nim-test")
                                                 :output :interactive :error-output :interactive))
               (let ((ready (star-zmq:receive-frames router)))
                 (assert (equalp (second ready) (octets 114 101 97 100 121)))
                 (star-zmq:send-frames router (list (first ready) body))
                 (let ((reply (star-zmq:receive-frames router)))
                   (assert (equalp reply (list (first ready) body))))
               ;; Keep shutdown bounded even if the child misbehaves.
               (let ((deadline (+ (get-internal-real-time) (* 5 internal-time-units-per-second))))
                 (star-zmq:send-frames router
                   (list (octets 110 105 109 45 116 101 115 116) (octets 100 111 110 101)))
                 (loop while (uiop:process-alive-p process)
                       do (when (>= (get-internal-real-time) deadline)
                            (error "Nim child did not stop."))
                          (sleep 0.01)))
               (assert (zerop (uiop:wait-process process))))
          (when (and process (uiop:process-alive-p process))
            (uiop:terminate-process process :urgent t)
            (uiop:wait-process process))
          (star-zmq:close-socket router)
          (ignore-errors (delete-file (subseq endpoint 6))))))))

(defun run-tests ()
  (let ((context (star-zmq:make-context)))
    (unwind-protect
         (progn
           (expect-error 'error (lambda () (star-zmq:make-context)))
           (round-trip context)
           (nim-round-trip context))
      (star-zmq:close-context context)))
  (format t "~&star-zmq native checks passed.~%")
  t)
