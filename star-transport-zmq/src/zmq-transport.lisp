;;;; ZeroMQ REQ/REP transport ports.
;;;;
;;;; The concrete transport adapter: canonical wire envelope octets move
;;;; between real OS processes over ZeroMQ TCP. The REP side is the service
;;;; endpoint (receive a command, publish the reply); the REQ side is the
;;;; client endpoint (publish a command, receive the reply). ZeroMQ enforces
;;;; strict request/reply alternation per connection, so the port contract's
;;;; settlement operations (ack, requeue, reject) record-only here: REQ/REP
;;;; delivers exactly once per successful exchange and has no broker-side
;;;; redelivery surface.
;;;;
;;;; This is a bounded typed transport primitive implemented in Common Lisp
;;;; through the explicit pzmq binding — no arbitrary host execution.

(in-package :startransportzmq)

(define-condition zmq-transport-error (error)
  ((message :initarg :message :reader zmq-transport-error-message))
  (:report
   (lambda (condition stream)
     (write-string (zmq-transport-error-message condition) stream))))

(defun fail-zmq (control &rest arguments)
  (error 'zmq-transport-error
         :message (apply #'format nil control arguments)))

(defun octets->string (octets)
  (babel:octets-to-string octets :encoding :utf-8))

(defun string->octets (string)
  (babel:string-to-octets string :encoding :utf-8))

(defstruct (zmq-endpoint-holder (:constructor %make-zmq-endpoint-holder))
  "Lifecycle holder for the raw ZeroMQ context and socket behind a port."
  ctx socket endpoint kind (open-p t))

(defun close-zmq-port (holder)
  "Close the socket and destroy the ZeroMQ context. Idempotent."
  (when (and (zmq-endpoint-holder-p holder)
             (zmq-endpoint-holder-open-p holder))
    (pzmq:close (zmq-endpoint-holder-socket holder))
    (pzmq:ctx-destroy (zmq-endpoint-holder-ctx holder))
    (setf (zmq-endpoint-holder-open-p holder) nil))
  (values))

(defun %bind-rep (candidate-endpoint)
  "Bind one REP socket, returning (VALUES ctx socket) or (VALUES nil nil)
when the endpoint is already in use."
  (let ((ctx (pzmq:ctx-new)))
    (let ((socket (pzmq:socket ctx :rep)))
      (handler-case
          (progn (pzmq:bind socket candidate-endpoint)
                 (values ctx socket))
        (error ()
          (pzmq:close socket)
          (pzmq:ctx-destroy ctx)
          (values nil nil))))))

(defun %connect-req (endpoint)
  (let ((ctx (pzmq:ctx-new)))
    (let ((socket (pzmq:socket ctx :req)))
      (pzmq:connect socket endpoint)
      (values ctx socket))))

(defun bind-zmq-rep-port (host &key (port-hint 42220) (port-tries 64))
  "Bind a REP endpoint on HOST, trying ports PORT-HINT upward until one
binds. Returns (VALUES PORT HOLDER) where PORT satisfies the star-adapter-sdk
transport port contract: transport-receive reads one request envelope
string; transport-publish sends one reply envelope string."
  (loop :for attempt :from 0 :below port-tries
        :for port := (+ port-hint attempt)
        :for endpoint := (format nil "tcp://~A:~D" host port)
        :do (multiple-value-bind (ctx socket)
                (%bind-rep endpoint)
              (when ctx
                (let ((holder
                        (%make-zmq-endpoint-holder
                         :ctx ctx :socket socket
                         :endpoint endpoint :kind :rep)))
                  (return
                    (values
                     (let ((sock socket))
                       (staradaptersdk:make-transport-port
                        :name "zmq-rep"
                        :receive
                        (lambda ()
                          (octets->string (pzmq:recv-octets sock)))
                        :publish
                        (lambda (envelope)
                          (pzmq:send sock (string->octets envelope))
                          :published)
                        :ack
                        (lambda (delivery)
                          (declare (ignore delivery))
                          :acked)
                        :requeue
                        (lambda (delivery replacement delay-ms)
                          (declare (ignore delivery replacement delay-ms))
                          :requeued)
                        :reject
                        (lambda (delivery reason)
                          (declare (ignore delivery reason))
                          :rejected)
                        :now
                        (lambda () (get-universal-time))))
                     holder)))))
        :finally (fail-zmq "No bindable ZeroMQ port found from ~D." port-hint)))

(defun connect-zmq-req-port (endpoint)
  "Connect a REQ endpoint. Returns (VALUES PORT HOLDER): transport-publish
sends one request envelope string; transport-receive reads the reply string."
  (multiple-value-bind (ctx socket)
      (%connect-req endpoint)
    (let ((holder
            (%make-zmq-endpoint-holder
             :ctx ctx :socket socket
             :endpoint endpoint :kind :req)))
      (values
       (let ((sock socket))
         (staradaptersdk:make-transport-port
          :name "zmq-req"
          :receive
          (lambda ()
            (octets->string (pzmq:recv-octets sock)))
          :publish
          (lambda (envelope)
            (pzmq:send sock (string->octets envelope))
            :published)
          :ack
          (lambda (delivery)
            (declare (ignore delivery))
            :acked)
          :requeue
          (lambda (delivery replacement delay-ms)
            (declare (ignore delivery replacement delay-ms))
            :requeued)
          :reject
          (lambda (delivery reason)
            (declare (ignore delivery reason))
            :rejected)
          :now
          (lambda () (get-universal-time))))
       holder))))
