(in-package :staractorprotocol)

(defun make-wire-envelope
    (&key message-type message-id actor dataset reply-to payload)
  (unless (and (stringp message-type)
               (stringp message-id)
               (stringp actor))
    (fail-invalid-wire-envelope
     "Wire envelope requires string message-type, message-id, and actor."))
  (list :star-version 1
        :message-type message-type
        :message-id message-id
        :actor actor
        :dataset dataset
        :reply-to reply-to
        :payload payload))

(defun portable-map-entry (map key)
  (cond
    ((and (listp map)
          (every #'consp map))
     (assoc key map :test #'string=))
    ((listp map)
     (let ((keyword (intern (string-upcase key) :keyword)))
       (loop for tail on map by #'cddr
             when (eq (first tail) keyword)
               do (return (cons key (second tail)))
             finally (return nil))))
    (t nil)))

(defun portable-manifest-message-contract (manifest message-type)
  (find message-type
        (getf manifest :messages)
        :key (lambda (message) (getf message :name))
        :test #'string=))

(defun validate-wire-envelope (manifest envelope)
  (unless (= (getf envelope :star-version) 1)
    (fail-invalid-wire-envelope "Unsupported Star wire version."))
  (let* ((message-type (getf envelope :message-type))
         (contract
           (portable-manifest-message-contract manifest message-type))
         (payload (getf envelope :payload)))
    (unless contract
      (fail-invalid-wire-envelope
       "Unknown message type ~A."
       message-type))
    (dolist (field (getf contract :fields))
      (when (and (getf field :required)
                 (null (portable-map-entry payload (getf field :name))))
        (fail-invalid-wire-envelope
         "Message ~A is missing required field ~A."
         message-type
         (getf field :name))))
    t))

(defun portable-manifest-actor-contract (manifest actor-target)
  (let ((actors (getf manifest :actors)))
    (if (star-service-uri-target-p actor-target)
        (let ((canonical
                (star-service-uri-string
                 (ensure-star-service-uri actor-target))))
          (find-if
           (lambda (actor)
             (let ((service-uri (getf actor :service-uri)))
               (and service-uri
                    (string= canonical service-uri))))
           actors))
        (find actor-target
              actors
              :key (lambda (actor) (getf actor :name))
              :test #'string=))))

(defun portable-actor-accepts-message-p (actor-contract message-type)
  (not
   (null
    (member message-type
            (getf actor-contract :accepts)
            :test #'string=))))
