;;;; Transport port contract tests: explicit settlement operations plus an
;;;; in-memory loopback used only as the external-effect test double.

(defpackage :staradaptersdk-tests
  (:use :cl)
  (:import-from :staradaptersdk
                #:transport-port-error
                #:make-transport-port
                #:transport-receive
                #:transport-publish
                #:transport-ack
                #:transport-requeue
                #:transport-reject
                #:transport-now
                #:transport-delivery-envelope
                #:make-transport-delivery)
  (:export #:run-tests))

(in-package :staradaptersdk-tests)

(defun assert-test (condition label)
  (unless condition
    (error "star-adapter-sdk test failed: ~A" label)))

(defun loopback-port ()
  "An in-memory queue pair standing in for the external socket."
  (let ((queue '())
        (acked '())
        (requeued '())
        (rejected '())
        (clock 0))
    (make-transport-port
     :name "loopback"
     :receive
     (lambda ()
       (if queue
           (pop queue)
           :empty))
     :publish
     (lambda (envelope)
       (let ((delivery
               (make-transport-delivery
                :tag (format nil "tag-~D" (length queue))
                :envelope envelope)))
         (setf queue (append queue (list delivery)))
         :published))
     :ack
     (lambda (delivery)
       (push delivery acked)
       :acked)
     :requeue
     (lambda (delivery replacement delay-ms)
       (push (list delivery replacement delay-ms) requeued)
       :requeued)
     :reject
     (lambda (delivery reason)
       (push (list delivery reason) rejected)
       :rejected)
     :now
     (lambda ()
       (incf clock)
       (format nil "clock-~D" clock)))))

(defun run-tests ()
  (let ((port (loopback-port)))
    (assert-test (eq :empty (transport-receive port)) "empty receive")

    (assert-test (eq :published
                     (transport-publish port (list (cons "kind" "ping"))))
                 "publish accepted")

    (let ((delivery (transport-receive port)))
      (assert-test (equal (transport-delivery-envelope delivery)
                          (list (cons "kind" "ping")))
                   "receive returns the published envelope")

      (assert-test (eq :acked (transport-ack port delivery)) "ack settles"))

    (let ((delivery (make-transport-delivery :tag "t2" :envelope '())))
      (assert-test (eq :requeued
                       (transport-requeue port delivery '(:replacement) 5))
                   "requeue settles")
      (assert-test (eq :rejected
                       (transport-reject port delivery "bad frame"))
                   "reject settles"))

    (assert-test (stringp (transport-now port)) "clock reads"))

  (assert-test
   (handler-case (progn (make-transport-port :name "broken") nil)
     (transport-port-error () t))
   "port without operations is rejected")

  (format t "star-adapter-sdk transport port tests passed~%")
  t)
