;;;; Two-process ingest fixture: CLIENT process. Connects a ZeroMQ REQ
;;;; transport port to the ingest service, publishes one canonical wire
;;;; envelope command, receives and validates the reply envelope, prints
;;;; "CLIENT OK <lastSource>", and exits 0 on success (1 otherwise).
;;;;
;;;; Usage: sbcl --script ingest-client.lisp <endpoint>

(require :asdf)

(let* ((root (butlast (pathname-directory *load-truename*) 2)))
  (unless (and (uiop:getenv "CL_SOURCE_REGISTRY")
               (plusp (length (uiop:getenv "CL_SOURCE_REGISTRY"))))
    (asdf:initialize-source-registry
     (list :source-registry
           (list :tree (namestring
                        (make-pathname :directory root :name nil :type nil)))
           :inherit-configuration))))

(asdf:load-system :starlang-compiler)
(asdf:load-system :star-canonical-json)
(asdf:load-system :star-transport-zmq)

(load (merge-pathnames "envelope-codec.lisp" *load-truename*))

(defpackage :star-ingest-client
  (:use :cl)
  (:import-from :starlangcompiler
                #:load-star-form
                #:emit-portable-manifest)
  (:import-from :startransportzmq
                #:connect-zmq-req-port
                #:close-zmq-port))

(in-package :star-ingest-client)

(defun fixture-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun fixture-manifest ()
  ;; The client compiles the same closed spec library so the exchange is
  ;; contract-checked on both ends without sharing mutable state.
  (let ((library
          (load-star-form
           (merge-pathnames "ingest-core.star" (fixture-directory)))))
    (emit-portable-manifest library '())))

(defun run-client (endpoint)
  (let ((manifest (fixture-manifest)))
    (multiple-value-bind (port holder)
        (startransportzmq:connect-zmq-req-port endpoint)
      (unwind-protect
           (let* ((command
                    (star-ingest-fixture:make-command-envelope
                     "ingest/record@1"
                     (list (cons "programId" "fixture-program")
                           (cons "sourceId" "example.invalid")
                           (cons "note" "two-process ingest fixture"))))
                  (encoded
                    (star-ingest-fixture:encode-envelope manifest command)))
             (star-ingest-fixture:envelope-plist manifest command)
             (staradaptersdk:transport-publish port encoded)
             (let* ((reply-json (staradaptersdk:transport-receive port))
                    (reply (star-ingest-fixture:decode-envelope reply-json)))
               (star-ingest-fixture:envelope-plist manifest reply)
               (unless (string= (getf reply :message-type) "ingest/state@1")
                 (error "Unexpected reply message type ~A."
                        (getf reply :message-type)))
               (let ((last-source
                       (cdr (assoc "lastSource"
                                   (getf reply :payload)
                                   :test #'string=))))
                 (unless (string= last-source "example.invalid")
                   (error "Reply lastSource ~S is not the ingested source."
                          last-source))
                 (format *standard-output* "CLIENT OK ~A~%" last-source)
                 (finish-output *standard-output*)
                 t)))
        (close-zmq-port holder)))))

(defun main ()
  (let ((endpoint
          (or (and (uiop:command-line-arguments)
                   (first (uiop:command-line-arguments)))
              (progn
                (format *error-output*
                        "usage: ingest-client.lisp <tcp://host:port>~%")
                (uiop:quit 2)))))
    (handler-case
        (when (run-client endpoint)
          (uiop:quit 0))
      (error (condition)
        (format *error-output* "ingest-client failed: ~A~%" condition)
        (uiop:quit 1)))))

(main)
