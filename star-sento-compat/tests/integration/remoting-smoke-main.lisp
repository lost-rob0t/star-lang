(require :asdf)
(asdf:load-system :sento-remoting)
(asdf:load-system :star-sento-compat)

(defpackage :starsentocompat-remoting-smoke-main
  (:use :cl)
  (:import-from :starsentocompat
                #:sento-make-actor-system
                #:sento-enable-remoting
                #:sento-remoting-port
                #:sento-actor-of
                #:sento-reply
                #:sento-disable-remoting
                #:sento-shutdown))

(in-package :starsentocompat-remoting-smoke-main)

(defun write-marker (pathname value)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (format stream "~A~%" value)))

(defun wait-for-file (pathname &key (attempts 300) (sleep-seconds 0.05d0))
  (loop repeat attempts
        when (probe-file pathname)
          return t
        do (sleep sleep-seconds)
        finally (error "Timed out waiting for ~A." pathname)))

(let ((system nil)
      (remoting-enabled-p nil))
  (unwind-protect
       (progn
         (setf system (sento-make-actor-system))
         (sento-enable-remoting system '(:host "127.0.0.1" :port 0))
         (setf remoting-enabled-p t)
         (sento-actor-of
          system
          "star-final-remoting-smoke"
          (lambda (message)
            (sento-reply (list :pong message)))
          nil)
         (let ((port (sento-remoting-port system)))
           (unless (and (integerp port) (plusp port))
             (error "Sento did not expose a bound remoting port: ~S" port))
           (write-marker "real-sento-main.ready" port))
         (wait-for-file "real-sento-main.stop")
         (format t "Final-only Sento remoting smoke server stopped cleanly.~%"))
    (when remoting-enabled-p
      (ignore-errors (sento-disable-remoting system)))
    (when system
      (ignore-errors (sento-shutdown system :wait t)))))
