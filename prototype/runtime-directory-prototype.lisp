(in-package #:star-lang.core-surface.prototype)

(export '(make-runtime-directory-port
          resolve-star-service-uri
          runtime-directory-snapshot))

(define-condition runtime-directory-error (star-lang-core-error) ())

(defstruct (runtime-directory-port
            (:constructor %make-runtime-directory-port))
  snapshot-fn)

(defun make-runtime-directory-port (&key snapshot)
  (unless (functionp snapshot)
    (fail 'runtime-directory-error
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
        (fail 'runtime-directory-error
              "Runtime directory actor ~A capabilities must be a string list."
              (getf entry :name))))))

(defun validate-runtime-directory-service-uri (entry)
  (let ((service-uri (getf entry :service-uri)))
    (when service-uri
      (let ((uri (ensure-star-service-uri service-uri)))
        (unless (string= (getf entry :name)
                         (star-service-uri-actor-name uri))
          (fail 'runtime-directory-error
                "Runtime directory actor ~A does not match STAR service URI actor name ~A."
                (getf entry :name)
                (star-service-uri-actor-name uri)))
        (let ((domain (getf entry :domain))
              (address (getf entry :address)))
          (when (and domain
                     (not (string= domain (star-service-uri-domain uri))))
            (fail 'runtime-directory-error
                  "Runtime directory service domain ~A does not match URI domain ~A."
                  domain (star-service-uri-domain uri)))
          (when (and address
                     (not (string= address (star-service-uri-address uri))))
            (fail 'runtime-directory-error
                  "Runtime directory service address ~A does not match URI address ~A."
                  address (star-service-uri-address uri))))))))

(defun validate-runtime-directory-entry (entry)
  (ensure-plist entry "runtime directory entry" 'runtime-directory-error)
  (required-nonempty-string
   (getf entry :name)
   "runtime directory actor name")
  (unless (keywordp (getf entry :runtime))
    (fail 'runtime-directory-error
          "Runtime directory actor ~A requires a keyword runtime."
          (getf entry :name)))
  (unless (valid-runtime-alive-value-p (getf entry :alive))
    (fail 'runtime-directory-error
          "Runtime directory actor ~A has invalid alive value ~S."
          (getf entry :name)
          (getf entry :alive)))
  (validate-runtime-directory-capabilities entry)
  (validate-runtime-directory-service-uri entry)
  (copy-tree entry))

(defun runtime-directory-snapshot (port context)
  (unless (runtime-directory-port-p port)
    (fail 'runtime-directory-error
          "Runtime directory snapshot requires a directory port."))
  (handler-case
      (let ((entries
              (funcall (runtime-directory-port-snapshot-fn port)
                       context)))
        (unless (listp entries)
          (fail 'runtime-directory-error
                "Runtime directory snapshot must return a list."))
        (mapcar #'validate-runtime-directory-entry entries))
    (runtime-directory-error (condition)
      (error condition))
    (star-lang-core-error (condition)
      (error condition))
    (error (condition)
      (fail 'runtime-directory-error
            "Runtime directory snapshot failed: ~A"
            condition))))

(defun resolve-star-service-uri (port context uri-value)
  (let* ((uri (ensure-star-service-uri uri-value))
         (canonical (star-service-uri-string uri))
         (matches
           (remove-if-not
            (lambda (entry)
              (let ((service-uri (getf entry :service-uri)))
                (and service-uri
                     (string= canonical service-uri))))
            (runtime-directory-snapshot port context))))
    (cond
      ((null matches)
       (fail 'star-service-not-found-error
             "STAR service ~A is not registered in the runtime directory."
             canonical))
      ((rest matches)
       (fail 'runtime-directory-error
             "STAR service ~A has duplicate runtime-directory registrations."
             canonical))
      ((null (getf (first matches) :alive))
       (fail 'star-service-unavailable-error
             "STAR service ~A is registered but not alive."
             canonical))
      (t
       (copy-tree (first matches))))))
