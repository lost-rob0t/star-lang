(require :asdf)
(asdf:load-system :sento-remoting)
(asdf:load-system :star-sento-compat)

(defpackage :starsentocompat-remoting-smoke-worker
  (:use :cl)
  (:import-from :starsentocompat
                #:sento-make-actor-system
                #:sento-enable-remoting
                #:sento-make-remote-ref
                #:sento-ask
                #:sento-future-complete-p
                #:sento-future-result
                #:sento-disable-remoting
                #:sento-shutdown))

(in-package :starsentocompat-remoting-smoke-worker)

(defun read-marker (pathname)
  (with-open-file (stream pathname :direction :input)
    (or (read-line stream nil nil)
        (error "Marker ~A is empty." pathname))))

(defun write-marker (pathname value)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (format stream "~A~%" value)))

(defun await-future (future &key (attempts 300) (sleep-seconds 0.05d0))
  (loop repeat attempts
        when (sento-future-complete-p future)
          return (sento-future-result future)
        do (sleep sleep-seconds)
        finally (error "Timed out waiting for remote Sento reply.")))

(let ((system nil)
      (remoting-enabled-p nil))
  (unwind-protect
       (progn
         (let* ((port-text (read-marker "real-sento-main.ready"))
                (port (parse-integer port-text :junk-allowed nil))
                (uri (format nil
                             "sento://127.0.0.1:~D/user/star-final-remoting-smoke"
                             port)))
           (setf system (sento-make-actor-system))
           (sento-enable-remoting system '(:host "127.0.0.1" :port 0))
           (setf remoting-enabled-p t)
           (let* ((remote (sento-make-remote-ref system uri nil))
                  (future (sento-ask remote "hello-final-star" 2 nil))
                  (result (await-future future)))
             (unless (equal result '(:pong "hello-final-star"))
               (error "Unexpected remote Sento result: ~S" result)))
           (write-marker "real-sento-smoke.success" "ok")
           (write-marker "real-sento-main.stop" "stop")
           (format t "Final-only two-process Sento remoting smoke passed.~%")))
    (when remoting-enabled-p
      (ignore-errors (sento-disable-remoting system)))
    (when system
      (ignore-errors (sento-shutdown system :wait t)))))
