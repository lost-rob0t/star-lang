(in-package :starlogicadapternprolog)

;; Upstream truth (verified against builtin.c / superset.c, npl 5.20):
;; send_socket/2 writes exactly 256 bytes (payload, strcpy NUL, stack
;; padding); recv_socket/2 is one raw read(2) of up to STRSIZE-1 bytes and
;; truncates the atom at the first NUL. The protocol is therefore strict
;; lock-step with NUL-terminated frames.
(defparameter +nprolog-bridge-frame-bytes+ 256)
(defparameter +max-nprolog-bridge-payload-bytes+ 255)
(defparameter +max-nprolog-bridge-read-bytes+ 256)

;; create_server_socket/2 never reports the bound port, so the adapter
;; probes the kernel for a free loopback port and hands the number to the
;; bridge goal. The probe listener is closed before the worker binds; the
;; window is the documented race for this transport.
(defun %probe-free-loopback-port ()
  (let ((socket (usocket:socket-listen "127.0.0.1" 0 :reuseaddress nil)))
    (unwind-protect
         (let ((port (usocket:get-local-port socket)))
           (unless (and (integerp port) (plusp port))
             (%nprolog-fail 'nprolog-bridge-port-error
                            "Could not determine a free loopback port."))
           port)
      (usocket:socket-close socket))))

(defun %encode-bridge-frame (payload)
  "Encode one outbound request frame: UTF-8 payload, NUL-terminated, padded
to the fixed 256-byte upstream write size."
  (unless (and (stringp payload) (plusp (length payload)))
    (%nprolog-fail 'nprolog-bridge-wire-error
                   "Bridge request payload must be a non-empty string."))
  (let* ((octets (babel:string-to-octets payload :encoding :utf-8))
         (length (length octets)))
    (when (> length +max-nprolog-bridge-payload-bytes+)
      (%nprolog-fail 'nprolog-request-too-large-error
                     "Bridge request payload is ~D bytes; the upstream
send_socket buffer bound is ~D bytes."
                     length +max-nprolog-bridge-payload-bytes+))
    (let ((frame (make-array +nprolog-bridge-frame-bytes+
                             :element-type '(unsigned-byte 8)
                             :initial-element 0)))
      (replace frame octets)
      frame)))

(defun %write-bridge-frame (stream payload)
  (let ((frame (%encode-bridge-frame payload)))
    (handler-case
        (progn
          (write-sequence frame stream)
          (finish-output stream))
      (error (cause)
        (%nprolog-fail-diagnostic
         'nprolog-bridge-wire-error
         (%bounded-diagnostic cause)
         "Bridge request write failed.")))))

;; Every upstream send terminates the payload with one NUL; the trailing
;; bytes are uninitialized stack padding and are always discarded.
(defun %decode-bridge-payload (octets)
  (let ((end (position 0 octets)))
    (babel:octets-to-string octets :end (or end (length octets))
                            :encoding :utf-8)))

(defun %read-bridge-frame (stream process
                           &key
                             (timeout 10.0d0)
                             (max-bytes +max-nprolog-bridge-read-bytes+))
  (let ((deadline (%monotonic-deadline timeout))
        (octets (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0)))
    (loop
      (let ((byte (and (listen stream) (read-byte stream nil :eof))))
        (cond
          ((eq byte :eof)
           (%nprolog-fail 'nprolog-bridge-wire-error
                          "Bridge peer closed the connection mid-frame."))
          ((integerp byte)
           (when (>= (length octets) max-bytes)
             (%nprolog-fail 'nprolog-bridge-wire-error
                            "Bridge frame exceeds the ~D-byte upstream write bound."
                            max-bytes))
           (if (zerop byte)
               (return (%decode-bridge-payload octets))
               (vector-push-extend byte octets)))
          ((and process (not (process-alive-p process)))
           (%nprolog-fail 'nprolog-worker-exited-during-startup-error
                          "N-Prolog worker exited while a bridge reply was pending."))
          ((>= (get-internal-real-time) deadline)
           (%nprolog-fail 'nprolog-bridge-wire-error
                          "Timed out waiting for a bridge reply."))
          (t
           (sleep 0.005d0)))))))

;; One request, one reply: upstream recv_socket/2 consumes a single read, so
;; pipelining would silently drop coalesced frames.
(defun %bridge-exchange (stream process payload)
  (%write-bridge-frame stream payload)
  (%read-bridge-frame stream process))

(defun %bridge-handshake (stream process)
  (let ((reply (%bridge-exchange stream process "hello")))
    (unless (string= reply +star-logic-bridge-protocol+)
      (%nprolog-fail-diagnostic
       'nprolog-bridge-handshake-error
       (%bounded-diagnostic reply)
       "Bridge handshake replied ~S; expected ~S."
       reply +star-logic-bridge-protocol+))
    t))
