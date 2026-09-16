(defpackage :star-zmq
  (:use :cl)
  (:export #:zmq-error #:zmq-error-code #:zmq-error-operation
           #:socket-owner-error #:transport-limit-error
           #:make-context #:close-context #:open-socket #:close-socket
           #:bind-endpoint #:connect-endpoint #:send-frames #:receive-frames
           #:library-version))
(in-package :star-zmq)

;; Only the stable libzmq C ABI is bound. Never guess the size of zmq_msg_t.
(cffi:define-foreign-library libzmq
  (:darwin (:or "libzmq.5.dylib" "libzmq.dylib"))
  (:unix (:or "libzmq.so.5" "libzmq.so"))
  (:windows "libzmq.dll")
  (t (:default "libzmq")))
(cffi:defcfun ("zmq_ctx_new" %ctx-new) :pointer)
(cffi:defcfun ("zmq_ctx_term" %ctx-term) :int (context :pointer))
(cffi:defcfun ("zmq_socket" %socket) :pointer (context :pointer) (kind :int))
(cffi:defcfun ("zmq_close" %close) :int (socket :pointer))
(cffi:defcfun ("zmq_bind" %bind) :int (socket :pointer) (endpoint :string))
(cffi:defcfun ("zmq_connect" %connect) :int (socket :pointer) (endpoint :string))
(cffi:defcfun ("zmq_setsockopt" %setopt) :int
  (socket :pointer) (option :int) (value :pointer) (size :size))
(cffi:defcfun ("zmq_getsockopt" %getopt) :int
  (socket :pointer) (option :int) (value :pointer) (size :pointer))
(cffi:defcfun ("zmq_send" %send) :int
  (socket :pointer) (data :pointer) (size :size) (flags :int))
(cffi:defcfun ("zmq_recv" %recv) :int
  (socket :pointer) (data :pointer) (size :size) (flags :int))
(cffi:defcfun ("zmq_errno" %errno) :int)
(cffi:defcfun ("zmq_strerror" %strerror) :string (code :int))
(cffi:defcfun ("zmq_version" %version) :void
  (major :pointer) (minor :pointer) (patch :pointer))

(define-condition zmq-error (error)
  ((code :initarg :code :reader zmq-error-code)
   (operation :initarg :operation :reader zmq-error-operation)
   (text :initarg :text :reader error-text))
  (:report (lambda (condition stream)
             (format stream "libzmq ~A failed (~D): ~A"
                     (zmq-error-operation condition)
                     (zmq-error-code condition) (error-text condition)))))
(define-condition socket-owner-error (error) ())
(define-condition transport-limit-error (error) ())

(defvar *library-lock* (bordeaux-threads:make-lock "star-zmq library"))
(defvar *library-loaded* nil)
(defvar *context-lock* (bordeaux-threads:make-lock "star-zmq context"))
(defvar *process-context* nil)
(defstruct (context (:constructor %make-context (handle))) handle (sockets 0))
(defstruct (transport-socket (:constructor %make-socket))
  handle context owner kind (payload-limit 1048576) (endpoints 0))

(defun ensure-library ()
  (bordeaux-threads:with-lock-held (*library-lock*)
    (unless *library-loaded*
      (let ((override (uiop:getenv "STAR_ZMQ_LIBRARY")))
        (cffi:load-foreign-library (or override 'libzmq)))
      (setf *library-loaded* t))))

(defun library-version ()
  (ensure-library)
  (cffi:with-foreign-objects ((major :int) (minor :int) (patch :int))
    (%version major minor patch)
    (list (cffi:mem-ref major :int) (cffi:mem-ref minor :int)
          (cffi:mem-ref patch :int))))

(defun native-error (operation)
  ;; Capture errno before cleanup or any other native operation changes it.
  (let ((code (%errno)))
    (error 'zmq-error :operation operation :code code :text (%strerror code))))

(defun checked (value operation)
  (when (minusp value) (native-error operation))
  value)

(defun bounded-integer (value lower upper)
  (unless (and (integerp value) (<= lower value upper))
    (error 'transport-limit-error))
  value)

(defun make-context ()
  "Create the one context managed by this binding in this Lisp process."
  (ensure-library)
  (unless (>= (first (library-version)) 4)
    (error "star-zmq requires libzmq 4 or newer."))
  (bordeaux-threads:with-lock-held (*context-lock*)
    (when *process-context* (error "A star-zmq context is already open."))
    (let ((handle (%ctx-new)))
      (when (cffi:null-pointer-p handle) (native-error :context-new))
      (setf *process-context* (%make-context handle)))))

(defun close-context (context)
  "Refuse to terminate with live sockets: this must not deadlock shutdown."
  (check-type context context)
  (bordeaux-threads:with-lock-held (*context-lock*)
    (when (context-handle context)
      (unless (zerop (context-sockets context))
        (error "Close every socket on its owner thread before its context."))
      (checked (%ctx-term (context-handle context)) :context-term)
      (setf (context-handle context) nil)
      (when (eq *process-context* context) (setf *process-context* nil))))
  nil)

(defun owned-handle (socket)
  (check-type socket transport-socket)
  (unless (eq (transport-socket-owner socket)
              (bordeaux-threads:current-thread))
    (error 'socket-owner-error))
  (or (transport-socket-handle socket) (error "Socket is closed.")))

(defun set-integer-option (socket option value &optional (type :int))
  (cffi:with-foreign-object (pointer type)
    (setf (cffi:mem-ref pointer type) value)
    (checked (%setopt (owned-handle socket) option pointer
                     (cffi:foreign-type-size type)) :setsockopt)))

(defun with-octets (octets callback)
  (check-type octets (simple-array (unsigned-byte 8) (*)))
  (let* ((size (length octets))
         (pointer (cffi:foreign-alloc :uint8 :count (max 1 size))))
    (unwind-protect
         (progn
           (dotimes (index size)
             (setf (cffi:mem-aref pointer :uint8 index) (aref octets index)))
           (funcall callback pointer size))
      (cffi:foreign-free pointer))))

(defun open-socket (context kind &key identity (timeout-ms 1000)
                                    (high-water-mark 64) (payload-limit 1048576))
  "Open a single-owner ROUTER or DEALER. Timeout/HWM values are always finite."
  (check-type context context)
  (unless (member kind '(:router :dealer)) (error "Unsupported socket kind."))
  (bounded-integer timeout-ms 1 60000)
  (bounded-integer high-water-mark 1 65536)
  (bounded-integer payload-limit 1 16777216)
  (when identity
    (check-type identity (simple-array (unsigned-byte 8) (*)))
    (bounded-integer (length identity) 1 255)
    (when (zerop (aref identity 0)) (error "Routing identity must not start with NUL.")))
  (let ((socket nil) (configured nil))
    (bordeaux-threads:with-lock-held (*context-lock*)
      (unless (and (context-handle context) (eq context *process-context*))
        (error "Context is closed or unmanaged."))
      (let ((handle (%socket (context-handle context) (ecase kind (:dealer 5) (:router 6)))))
        (when (cffi:null-pointer-p handle) (native-error :socket))
        (setf socket (%make-socket :handle handle :context context :kind kind
                                  :owner (bordeaux-threads:current-thread)
                                  :payload-limit payload-limit))
        (incf (context-sockets context))))
    (unwind-protect
         (progn
           ;; Stable zmq.h constants: linger, HWM, receive/send deadlines.
           (dolist (entry `((17 . 0) (23 . ,high-water-mark) (24 . ,high-water-mark)
                            (27 . ,timeout-ms) (28 . ,timeout-ms)))
             (set-integer-option socket (car entry) (cdr entry)))
           (set-integer-option socket 22 (max 255 payload-limit) :int64)
           (ecase kind
             (:router (set-integer-option socket 33 1)) ; ROUTER_MANDATORY
             (:dealer (set-integer-option socket 39 1))) ; IMMEDIATE
           (when identity
             (with-octets identity
               (lambda (pointer size)
                 (checked (%setopt (owned-handle socket) 5 pointer size) :routing-id))))
           (setf configured t)
           socket)
      (unless configured (close-socket socket)))))

(defun close-socket (socket)
  (check-type socket transport-socket)
  (unless (eq (transport-socket-owner socket) (bordeaux-threads:current-thread))
    (error 'socket-owner-error))
  (when (transport-socket-handle socket)
    (checked (%close (transport-socket-handle socket)) :close)
    (setf (transport-socket-handle socket) nil)
    (bordeaux-threads:with-lock-held (*context-lock*)
      (decf (context-sockets (transport-socket-context socket)))))
  nil)

(defun local-endpoint-p (endpoint)
  "No DNS, wildcard, remote TCP, or peer-controlled network address in this slice."
  (and (stringp endpoint) (<= 1 (length endpoint) 1024)
       (not (find 0 endpoint :key #'char-code))
       (or (and (uiop:string-prefix-p "inproc://" endpoint) (> (length endpoint) 9))
           (and (uiop:string-prefix-p "ipc://" endpoint) (> (length endpoint) 6))
           (some (lambda (prefix)
                   (when (uiop:string-prefix-p prefix endpoint)
                     (let ((port (subseq endpoint (length prefix))))
                       (and (<= 1 (length port) 5)
                            (every (lambda (c) (find c "0123456789")) port)
                            (<= 1 (parse-integer port) 65535)))))
                 '("tcp://127.0.0.1:" "tcp://[::1]:")))))

(defun attach-endpoint (socket endpoint bind-p)
  (let ((handle (owned-handle socket)))
    (unless (local-endpoint-p endpoint) (error "Only local ZMQ endpoints are allowed."))
    ;; Multiple DEALER peers would silently round-robin addressed actor traffic.
    (bounded-integer (transport-socket-endpoints socket) 0
                     (if (eq (transport-socket-kind socket) :dealer) 0 31))
    (checked (if bind-p (%bind handle endpoint) (%connect handle endpoint))
             (if bind-p :bind :connect))
    (incf (transport-socket-endpoints socket)))
  socket)

(defun bind-endpoint (socket endpoint) (attach-endpoint socket endpoint t))
(defun connect-endpoint (socket endpoint) (attach-endpoint socket endpoint nil))

(defun expected-frames (socket)
  (ecase (transport-socket-kind socket) (:router 2) (:dealer 1)))

(defun frame-limit (socket index)
  (if (and (eq (transport-socket-kind socket) :router) (zerop index))
      255 (transport-socket-payload-limit socket)))

(defun send-frames (socket frames)
  "Queue one payload (DEALER) or routing-id + payload (ROUTER); not a delivery ACK."
  (let ((handle (owned-handle socket)) (progress 0) (complete nil))
    (unless (and (listp frames) (eql (list-length frames) (expected-frames socket)))
      (error 'transport-limit-error))
    ;; Validate the complete multipart message before touching the native socket.
    (loop for frame in frames for index from 0 do
      (check-type frame (simple-array (unsigned-byte 8) (*)))
      (bounded-integer (length frame)
                       (if (and (eq (transport-socket-kind socket) :router)
                                (zerop index)) 1 0)
                       (frame-limit socket index)))
    (unwind-protect
         (progn
           (loop for rest on frames do
             (with-octets (car rest)
               (lambda (pointer size)
                 (let ((written (checked (%send handle pointer size (if (cdr rest) 2 0))
                                         :send)))
                   (incf progress)
                   (unless (= written size) (error "Unexpected short ZMQ send."))))))
           (setf complete t)
           :queued)
      ;; A partially sent envelope must never be completed by the next message.
      (when (and (> progress 0) (not complete)) (close-socket socket)))))

(defun receive-more-p (handle)
  (cffi:with-foreign-objects ((value :int) (size :size))
    (setf (cffi:mem-ref size :size) (cffi:foreign-type-size :int))
    (checked (%getopt handle 13 value size) :receive-more)
    (not (zerop (cffi:mem-ref value :int)))))

(defun receive-frames (socket)
  "Read exactly the route/body shape. Truncation and extra parts close the socket."
  (let ((handle (owned-handle socket)) (progress 0) (complete nil) (frames nil))
    (unwind-protect
         (progn
           (dotimes (index (expected-frames socket))
             (let* ((limit (frame-limit socket index))
                    (pointer (cffi:foreign-alloc :uint8 :count limit)))
               (unwind-protect
                    (let ((size (checked (%recv handle pointer limit 0) :receive)))
                      (incf progress)
                      ;; zmq_recv returns the original size, including truncated bytes.
                      (when (> size limit) (error 'transport-limit-error))
                      (when (and (eq (transport-socket-kind socket) :router)
                                 (zerop index) (zerop size))
                        (error 'transport-limit-error))
                      (let ((frame (make-array size :element-type '(unsigned-byte 8))))
                        (dotimes (i size) (setf (aref frame i) (cffi:mem-aref pointer :uint8 i)))
                        (push frame frames))
                      (unless (eql (receive-more-p handle)
                                   (< index (1- (expected-frames socket))))
                        (error 'transport-limit-error)))
                 (cffi:foreign-free pointer))))
           (setf complete t)
           (nreverse frames))
      ;; A timeout before the first frame is recoverable; partial messages are not.
      (when (and (> progress 0) (not complete)) (close-socket socket)))))
