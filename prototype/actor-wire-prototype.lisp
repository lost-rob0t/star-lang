(in-package #:star-lang.core-surface.prototype)

;; Standalone prototype tests historically load this file without ASDF.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARACTORPROTOCOL")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-actor-protocol/star-actor-protocol.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-actor-protocol)))

;; Actor compilation (compile-actor), portable actor manifest emission
;; (portable-actor, portable-declaration, portable-field,
;; declarations-of-kind, emit-portable-manifest) are final-owned by
;; starlang-compiler and re-exported through core-surface-prototype.lisp.
;; This file retains only the cl-gserver runtime binding composition and the
;; wire-envelope compatibility forwarders.

(defun bind-actor-runtime (actor)
  (ecase (getf actor :runtime)
    (:native
     (list :kind :actor-binding
           :name (getf actor :name)
           :service-uri (getf actor :service-uri)
           :runtime :cl-gserver
           :constructor :actor-of
           :send-operation :tell
           :handler (getf actor :handler)
           :accepts (copy-list (getf actor :accepts))
           :produces (copy-list (getf actor :produces))
           :restart (getf actor :restart)
           :mailbox (copy-tree (getf actor :mailbox))))
    (:external
     (list :kind :actor-binding
           :name (getf actor :name)
           :service-uri (getf actor :service-uri)
           :runtime :external
           :protocol (getf actor :protocol)
           :endpoint (getf actor :endpoint)
           :send-operation :dispatch
           :accepts (copy-list (getf actor :accepts))
           :produces (copy-list (getf actor :produces))
           :restart (getf actor :restart)
           :mailbox (copy-tree (getf actor :mailbox))))))

(defun call-final-wire-contract (thunk)
  (handler-case
      (funcall thunk)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail 'invalid-envelope-error "~A" condition))))

(defun make-wire-envelope (&rest arguments)
  (call-final-wire-contract
    (lambda ()
      (apply #'staractorprotocol:make-wire-envelope arguments))))

(defun message-contract (manifest message-type)
  (staractorprotocol:portable-manifest-message-contract
   manifest message-type))

(defun validate-wire-envelope (manifest envelope)
  (call-final-wire-contract
    (lambda ()
      (staractorprotocol:validate-wire-envelope manifest envelope))))
