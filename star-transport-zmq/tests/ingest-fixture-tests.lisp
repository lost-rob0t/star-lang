;;;; Two-process ingest fixture test: spawns a REAL ingest service process
;;;; (StarLang native body actor over the durable runtime) and a REAL client
;;;; process, exchanges canonical wire envelopes over ZeroMQ loopback TCP,
;;;; and asserts the reply contract plus the emitted portable manifest.
;;;; This executes the real runtime and transport boundary; no mocks stand
;;;; in for actor semantics.

(defpackage :startransportzmq-ingest-tests
  (:use :cl)
  (:import-from :starprocessport
                #:launch-process
                #:process-stdout
                #:process-alive-p
                #:wait-process
                #:terminate-process
                #:dispose-process)
  (:export #:run-tests))

(in-package :startransportzmq-ingest-tests)

(defun assert-test (condition label)
  (unless condition
    (error "star-transport-zmq ingest fixture test failed: ~A" label)))

(defun fixture-directory ()
  (asdf:system-relative-pathname :star-transport-zmq "../fixtures/ingest/"))

(defun fixture-file (name)
  (merge-pathnames name (fixture-directory)))

(defun sbcl-command ()
  "The same SBCL wrapper this test process runs under, so spawned fixture
processes inherit the nix ASDF registry and library paths through env."
  (or (uiop:getenv "STARLANG_TEST_SBCL") "sbcl"))

(defun read-until-prefix (process prefix &key (timeout-seconds 90))
  "Read the service/client stdout until a line starting with PREFIX."
  (let ((deadline (+ (get-universal-time) timeout-seconds))
        (buffer (make-array 0 :element-type 'character :fill-pointer 0)))
    (loop
      (when (> (get-universal-time) deadline)
        (error "process did not print ~S within ~Ds (buffer: ~A)"
               prefix timeout-seconds buffer))
      (let ((ch (read-char-no-hang (process-stdout process) nil nil)))
        (cond
          ((null ch) (sleep 0.02))
          ((char= ch #\Newline)
           (when (uiop:string-prefix-p prefix buffer)
             (return buffer))
           (setf buffer (make-array 0 :element-type 'character
                                   :fill-pointer 0)))
          (t (vector-push-extend ch buffer)))))))

(defun reap (process)
  (nth-value 0 (wait-process process)))

(defun stop-process (process)
  (when (process-alive-p process)
    (terminate-process process)
    (reap process)))

(defun run-tests ()
  (let ((manifest-path
         (uiop:merge-pathnames*
          "starlang-ingest-manifest.json"
          (uiop:temporary-directory))))
    (let ((service
            (launch-process
             (sbcl-command)
             (list "--script"
                   (namestring (fixture-file "ingest-service.lisp"))
                   (namestring manifest-path)))))
      (unwind-protect
           (let* ((endpoint-line
                    (read-until-prefix service "ENDPOINT "))
                  (endpoint
                    (string-trim " " (subseq endpoint-line
                                              (length "ENDPOINT ")))))
             (assert-test (uiop:string-prefix-p "tcp://" endpoint)
                          "service endpoint is a tcp URI")
             (let ((client
                     (launch-process
                      (sbcl-command)
                      (list "--script"
                            (namestring (fixture-file "ingest-client.lisp"))
                            endpoint))))
               (unwind-protect
                    (progn
                      (let ((client-exit (reap client)))
                        (assert-test (eql client-exit 0)
                                     "client exited 0 after a successful
canonical envelope exchange"))
                      (let ((service-line
                              (read-until-prefix service "REPLY ")))
                        (assert-test
                         (search "ingest/state@1" service-line)
                         "service served the command and replied"))
                      (let ((service-exit (reap service)))
                        (assert-test (eql service-exit 0)
                                     "service exited 0 after serving"))
                      (assert-test (probe-file manifest-path)
                                   "portable manifest artifact emitted")
                      (let ((json
                              (uiop:read-file-string manifest-path)))
                        (assert-test
                         (search
                          "\"resourceUri\":\"star://starintel.dev/actor/ingest-service\""
                          json)
                         "manifest carries the canonical resource URI")
                        (assert-test
                         (search "\"journaled\"" json)
                         "manifest carries typed state persistence")
                        (format
                         t
                         "star-transport-zmq two-process ingest fixture passed~%")))
                 (stop-process client))))
        (stop-process service)
        (uiop:delete-file-if-exists manifest-path))))
  t)
