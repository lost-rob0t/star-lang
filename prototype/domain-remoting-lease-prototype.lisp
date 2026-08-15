(in-package #:star-lang.core-surface.prototype)

(export '(configure-main-domain-gateway-lease
          expire-main-domain-gateway-nodes
          main-domain-gateway-live-node-count))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARLEASE")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames "../star-lease/star-lease.asd" *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-lease)))

(defvar *main-domain-gateway-leases* (make-hash-table :test #'eq))

(defun call-final-heartbeat-lease (thunk)
  (handler-case
      (funcall thunk)
    (starlease:star-lease-error (condition)
      (fail 'domain-remoting-error "~A" condition))))

(defun configure-main-domain-gateway-lease
    (gateway &key (timeout-ms 15000) clock)
  (unless (main-domain-gateway-p gateway)
    (fail 'domain-remoting-error
          "Heartbeat lease configuration requires a main domain gateway."))
  (setf (gethash gateway *main-domain-gateway-leases*)
        (call-final-heartbeat-lease
         (lambda ()
           (starlease:make-heartbeat-lease
            :timeout-ms timeout-ms
            :clock clock))))
  gateway)

(defun main-domain-gateway-lease-state (gateway)
  (or (gethash gateway *main-domain-gateway-leases*)
      (progn
        (configure-main-domain-gateway-lease gateway)
        (gethash gateway *main-domain-gateway-leases*))))

(defun note-main-domain-node-seen (gateway node-id)
  (call-final-heartbeat-lease
   (lambda ()
     (starlease:heartbeat-lease-note-seen
      (main-domain-gateway-lease-state gateway)
      node-id))))

(defun expire-main-domain-gateway-nodes (gateway)
  (let* ((lease (main-domain-gateway-lease-state gateway))
         (now
           (call-final-heartbeat-lease
            (lambda () (starlease:heartbeat-lease-now lease))))
         (expired '()))
    (maphash
     (lambda (node-id node)
       (when (and
              (call-final-heartbeat-lease
               (lambda ()
                 (starlease:heartbeat-lease-expired-p lease node-id now)))
              (remote-domain-node-alive-p node))
         (setf (remote-domain-node-alive-p node) nil)
         (push node-id expired)))
     (main-domain-gateway-nodes gateway))
    (sort expired #'string<)))

(defun main-domain-gateway-live-node-count (gateway)
  (expire-main-domain-gateway-nodes gateway)
  (let ((count 0))
    (maphash
     (lambda (node-id node)
       (declare (ignore node-id))
       (when (remote-domain-node-alive-p node)
         (incf count)))
     (main-domain-gateway-nodes gateway))
    count))

(defvar *main-domain-register-node-without-lease*
  (symbol-function 'main-domain-register-node))

(defvar *main-domain-heartbeat-without-lease*
  (symbol-function 'main-domain-heartbeat))

(defvar *select-domain-node-without-lease*
  (symbol-function 'select-domain-node))

(defun main-domain-register-node (gateway message)
  (prog1
      (funcall *main-domain-register-node-without-lease* gateway message)
    (note-main-domain-node-seen gateway (getf message :node-id))))

(defun main-domain-heartbeat (gateway message)
  (prog1
      (funcall *main-domain-heartbeat-without-lease* gateway message)
    (note-main-domain-node-seen gateway (getf message :node-id))))

(defun select-domain-node (gateway command)
  (expire-main-domain-gateway-nodes gateway)
  (funcall *select-domain-node-without-lease* gateway command))
