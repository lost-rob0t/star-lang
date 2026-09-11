(in-package :starlangruntime)

(define-condition runtime-directory-error (actor-runtime-error) ())
(define-condition runtime-directory-service-not-found-error
    (runtime-directory-error)
  ())
(define-condition runtime-directory-service-unavailable-error
    (runtime-directory-error)
  ())

(defun proper-runtime-directory-plist-p (value)
  (loop with rest = value
        do (cond
             ((null rest) (return t))
             ((and (consp rest) (consp (cdr rest)))
              (setf rest (cddr rest)))
             (t (return nil)))))

(defun ensure-runtime-directory-plist (value context)
  (unless (proper-runtime-directory-plist-p value)
    (fail-actor 'runtime-directory-error
                "~A must be a property list."
                context))
  value)

(defun runtime-directory-required-string (value context)
  (unless (and (stringp value) (> (length value) 0))
    (fail-actor 'runtime-directory-error
                "~A requires a non-empty string."
                context))
  value)

(defstruct (runtime-directory-port
            (:constructor %make-runtime-directory-port))
  snapshot-fn)

(defun make-runtime-directory-port (&key snapshot)
  (unless (functionp snapshot)
    (fail-actor 'runtime-directory-error
                "Runtime directory snapshot operation must be a function."))
  (%make-runtime-directory-port :snapshot-fn snapshot))

(defun valid-runtime-alive-value-p (value)
  (or (eq value t)
      (null value)
      (eq value :unknown)))

(defun validate-runtime-directory-capabilities (entry)
  (let ((capabilities (getf entry :capabilities)))
    (when capabilities
      (unless (and (listp capabilities)
                   (every #'stringp capabilities))
        (fail-actor
         'runtime-directory-error
         "Runtime directory actor ~A capabilities must be a string list."
         (getf entry :name))))))

(defun validate-runtime-directory-service-uri (entry)
  (let ((service-uri (getf entry :service-uri)))
    (when service-uri
      (let ((uri (staractorprotocol:ensure-star-uri service-uri)))
        (unless (string= "actor" (staractorprotocol:star-uri-resource-kind uri))
          (fail-actor
           'runtime-directory-error
           "Runtime directory entry ~A requires an actor resource kind, received ~A."
           (getf entry :name)
           service-uri))
        (let ((resource-path (staractorprotocol:star-uri-resource-path uri)))
          (unless (and resource-path
                       (string= (getf entry :name)
                                (car (last resource-path))))
            (fail-actor
             'runtime-directory-error
             "Runtime directory actor ~A does not match the terminal actor path segment of ~A."
             (getf entry :name)
             service-uri)))
        ;; Portable URI/resource metadata is validated against the URI
        ;; (STAR-LANG-004); :ref and transport data stay opaque.
        (let ((authority (getf entry :authority))
              (resource-kind (getf entry :resource-kind))
              (resource-path (getf entry :resource-path)))
          (when (and authority
                     (not (string= authority
                                    (staractorprotocol:star-uri-authority uri))))
            (fail-actor
             'runtime-directory-error
             "Runtime directory authority ~A does not match URI authority ~A."
             authority
             (staractorprotocol:star-uri-authority uri)))
          (when (and resource-kind
                     (not (string= resource-kind
                                   (staractorprotocol:star-uri-resource-kind uri))))
            (fail-actor
             'runtime-directory-error
             "Runtime directory resource kind ~A does not match URI resource kind ~A."
             resource-kind
             (staractorprotocol:star-uri-resource-kind uri)))
          (when (and resource-path
                     (not (equal resource-path
                                (staractorprotocol:star-uri-resource-path uri))))
            (fail-actor
             'runtime-directory-error
             "Runtime directory resource path ~S does not match URI resource path ~S."
             resource-path
             (staractorprotocol:star-uri-resource-path uri))))))))

(defun validate-runtime-directory-entry (entry)
  (ensure-runtime-directory-plist entry "runtime directory entry")
  (runtime-directory-required-string
   (getf entry :name)
   "runtime directory actor name")
  (unless (keywordp (getf entry :runtime))
    (fail-actor
     'runtime-directory-error
     "Runtime directory actor ~A requires a keyword runtime."
     (getf entry :name)))
  (unless (valid-runtime-alive-value-p (getf entry :alive))
    (fail-actor
     'runtime-directory-error
     "Runtime directory actor ~A has invalid alive value ~S."
     (getf entry :name)
     (getf entry :alive)))
  (validate-runtime-directory-capabilities entry)
  (validate-runtime-directory-service-uri entry)
  (copy-tree entry))

(defun runtime-directory-snapshot (port context)
  (unless (runtime-directory-port-p port)
    (fail-actor 'runtime-directory-error
                "Runtime directory snapshot requires a directory port."))
  (handler-case
      (let ((entries
              (funcall (runtime-directory-port-snapshot-fn port)
                       context)))
        (unless (listp entries)
          (fail-actor 'runtime-directory-error
                      "Runtime directory snapshot must return a list."))
        (mapcar #'validate-runtime-directory-entry entries))
    (runtime-directory-error (condition)
      (error condition))
    (staractorprotocol:invalid-star-uri (condition)
      (error condition))
    (staractorprotocol:invalid-star-service-uri-error (condition)
      (error condition))
    (error (condition)
      (fail-actor 'runtime-directory-error
                  "Runtime directory snapshot failed: ~A"
                  condition))))

(defun resolve-star-service-uri (port context uri-value)
  (let* ((uri (staractorprotocol:ensure-star-uri uri-value))
         (canonical (staractorprotocol:serialize-star-uri uri))
         (matches
           (remove-if-not
            (lambda (entry)
              (let ((service-uri (getf entry :service-uri)))
                (and service-uri
                     (string= canonical service-uri))))
            (runtime-directory-snapshot port context))))
    (cond
      ((null matches)
       (fail-actor
        'runtime-directory-service-not-found-error
        "STAR service ~A is not registered in the runtime directory."
        canonical))
      ((rest matches)
       (fail-actor
        'runtime-directory-error
        "STAR service ~A has duplicate runtime-directory registrations."
        canonical))
      ((null (getf (first matches) :alive))
       (fail-actor
        'runtime-directory-service-unavailable-error
        "STAR service ~A is registered but not alive."
        canonical))
      (t
       (copy-tree (first matches))))))
