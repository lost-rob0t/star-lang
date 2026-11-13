;;;; Two-process ingest fixture: SERVICE process (issue #72/#69 vertical
;;;; slice). Compiles the ingest spec library and the native StarLang actor
;;;; body through the final compiler, executes the body through the real
;;;; durable runtime, emits the portable manifest for downstream
;;;; registration (starintel-server#43 shape), and serves canonical wire
;;;; envelopes over ZeroMQ REP.
;;;;
;;;; Usage: sbcl --script ingest-service.lisp
;;;; Argument: <manifest-out.json> optionally writes the emitted portable
;;;; manifest JSON for downstream registration checks. Prints
;;;; "ENDPOINT <tcp://...>" once bound, serves exactly one command, replies,
;;;; and exits 0.

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
(asdf:load-system :starlang-runtime)
(asdf:load-system :star-canonical-json)
(asdf:load-system :star-transport-zmq)

(load (merge-pathnames "envelope-codec.lisp" *load-truename*))

(defpackage :star-ingest-service
  (:use :cl)
  (:import-from :starlangcompiler
                #:compile-actor-file
                #:load-star-form
                #:emit-portable-manifest)
  (:import-from :starlangruntime
                #:make-runtime
                #:make-body-actor-definition
                #:spawn
                #:ask
                #:shutdown-runtime)
  (:import-from :startransportzmq
                #:bind-zmq-rep-port
                #:zmq-endpoint-holder-endpoint
                #:close-zmq-port))

(in-package :star-ingest-service)

(defun fixture-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun service-actor-uri ()
  "star://starintel.dev/actor/ingest-service")

(defun program-manifest ()
  "Compile the fixture spec library plus the native-body service actor and
emit the portable manifest carrying the canonical resource URI. .star
sources enter through the closed parser only."
  (let* ((library
           (load-star-form
            (merge-pathnames "ingest-core.star" (fixture-directory))))
         (actor-ir
           (compile-actor-file
            (merge-pathnames "ingest-service.star" (fixture-directory))))
         (manifest
           (emit-portable-manifest library (list actor-ir))))
    (values library actor-ir manifest)))

(defun reply-envelope (command reply-payload)
  (staractorprotocol:make-wire-envelope
   :message-type "ingest/state@1"
   :message-id (format nil "ingest-service-reply-~6,'0D"
                       (mod (random most-positive-fixnum) 1000000))
   :actor (service-actor-uri)
   :dataset (getf command :dataset)
   :reply-to (getf command :message-id)
   :payload reply-payload))

(defun serve-one-command (runtime service-name manifest port)
  (let* ((request (staradaptersdk:transport-receive port))
         (command (star-ingest-fixture:decode-envelope request)))
    (star-ingest-fixture:envelope-plist manifest command)
    (let ((reply-payload
            (ask runtime service-name
                 (staractorprotocol:make-wire-envelope
                  :message-type (getf command :message-type)
                  :message-id (getf command :message-id)
                  :actor (getf command :actor)
                  :dataset (getf command :dataset)
                  :payload (getf command :payload)))))
      (let ((reply (reply-envelope command reply-payload)))
        (staradaptersdk:transport-publish
         port (star-ingest-fixture:encode-envelope manifest reply))
        reply))))

(defun main ()
  (multiple-value-bind (library actor-ir manifest)
      (program-manifest)
    (declare (ignore library))
    ;; Optional downstream manifest artifact (issue #72 slice 6).
    (let ((manifest-out (first (uiop:command-line-arguments))))
      (when (and manifest-out (plusp (length manifest-out)))
        (with-open-file (stream manifest-out
                                :direction :output :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string
           (starcanonicaljson:canonical-manifest-json manifest)
           stream)
          (terpri stream))))
    (let ((runtime (make-runtime))
          (service-name "ingest-service"))
      (spawn runtime (make-body-actor-definition actor-ir))
      (multiple-value-bind (port holder)
          (startransportzmq:bind-zmq-rep-port "127.0.0.1" :port-hint 42100)
        (format *standard-output* "ENDPOINT ~A~%"
                (zmq-endpoint-holder-endpoint holder))
        (finish-output *standard-output*)
        (unwind-protect
             (let ((reply (serve-one-command runtime service-name manifest port)))
               (format *standard-output* "REPLY ~A~%"
                       (getf reply :message-type))
               (finish-output *standard-output*))
          (close-zmq-port holder)
          (shutdown-runtime runtime))))
    (uiop:quit 0)))

(main)
