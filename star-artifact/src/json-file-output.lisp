(in-package :starartifact)

(define-condition json-file-error (error)
  ((message :initarg :message :reader json-file-error-message))
  (:report
   (lambda (condition stream)
     (write-string (json-file-error-message condition) stream))))

(define-condition invalid-json-file-record-error (json-file-error) ())
(define-condition json-file-write-error (json-file-error) ())

(defun fail-json-file (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun safe-path-segment-p (value)
  (and (stringp value)
       (> (length value) 0)
       (not (member value '("." "..") :test #'string=))
       (every
        (lambda (character)
          (or (alphanumericp character)
              (find character "-_.@" :test #'char=)))
        value)))

(defun ensure-safe-path-segment (value label)
  (unless (safe-path-segment-p value)
    (fail-json-file
     'invalid-json-file-record-error
     "JSON file ~A must be a non-empty path-safe segment, received ~S."
     label
     value))
  value)

(defun ensure-canonical-json-value (value)
  (handler-case
      (progn
        (starcanonicaljson:canonical-json-string value)
        value)
    (error (condition)
      (fail-json-file
       'invalid-json-file-record-error
       "JSON file document is not canonical-JSON serializable: ~A"
       condition))))

(defstruct (json-file-write
            (:constructor %make-json-file-write
                (&key collection id document)))
  (collection "" :type string)
  (id "" :type string)
  document)

(defun make-json-file-write (collection id document)
  (%make-json-file-write
   :collection (ensure-safe-path-segment collection "collection")
   :id (ensure-safe-path-segment id "id")
   :document (ensure-canonical-json-value document)))

(defstruct (json-file-result
            (:constructor %make-json-file-result
                (&key status collection id path)))
  (status :written :type keyword)
  (collection "" :type string)
  (id "" :type string)
  (path "" :type string))

(defun normalize-root-directory (root)
  (handler-case
      (uiop:ensure-directory-pathname (pathname root))
    (error (condition)
      (fail-json-file
       'invalid-json-file-record-error
       "JSON file root ~S is not a valid directory pathname: ~A"
       root
       condition))))

(defun json-file-target-pathname (root write)
  (merge-pathnames
   (make-pathname
    :directory `(:relative ,(json-file-write-collection write))
    :name (json-file-write-id write)
    :type "json")
   (normalize-root-directory root)))

(defun json-file-temporary-pathname (target write)
  (make-pathname
   :name (format nil ".~A.json" (json-file-write-id write))
   :type "tmp"
   :defaults target))

(defun canonical-json-file-content (write)
  (concatenate
   'string
   (starcanonicaljson:canonical-json-string
    (json-file-write-document write))
   (string #\Newline)))

(defun existing-content-equal-p (target content)
  (and (probe-file target)
       (string= content
                (uiop:read-file-string target :external-format :utf-8))))

(defun replace-file-atomically (target temporary content)
  (ensure-directories-exist target)
  (unwind-protect
       (progn
         (with-open-file
             (stream temporary
                     :direction :output
                     :if-exists :supersede
                     :if-does-not-exist :create
                     :external-format :utf-8)
           (write-string content stream)
           (finish-output stream))
         (uiop:rename-file-overwriting-target temporary target))
    (when (probe-file temporary)
      (ignore-errors (delete-file temporary)))))

(defun write-json-file-record (root write)
  (unless (json-file-write-p write)
    (fail-json-file
     'invalid-json-file-record-error
     "Expected a JSON-FILE-WRITE value, received ~S."
     write))
  (let* ((target (json-file-target-pathname root write))
         (temporary (json-file-temporary-pathname target write))
         (content (canonical-json-file-content write))
         (status
           (handler-case
               (if (existing-content-equal-p target content)
                   :unchanged
                   (progn
                     (replace-file-atomically target temporary content)
                     :written))
             (error (condition)
               (fail-json-file
                'json-file-write-error
                "Could not write JSON file ~A: ~A"
                (uiop:native-namestring target)
                condition)))))
    (%make-json-file-result
     :status status
     :collection (json-file-write-collection write)
     :id (json-file-write-id write)
     :path (uiop:native-namestring target))))

(defun json-file-contract-valid-p (contract value)
  (case contract
    (:json-file-write (json-file-write-p value))
    (:json-file-result (json-file-result-p value))
    (otherwise nil)))

(defun make-json-file-writer-actor-definition
    (name root &key service-uri metadata)
  (let ((root-directory (normalize-root-directory root)))
    (starlangruntime:make-native-actor-definition
     name
     (lambda (message state runtime)
       (declare (ignore state runtime))
       (write-json-file-record root-directory message))
     :service-uri service-uri
     :accepts :json-file-write
     :produces :json-file-result
     :input-validator #'json-file-contract-valid-p
     :output-validator #'json-file-contract-valid-p
     :metadata metadata)))

(defun create-json-file-writer-actor
    (runtime name root &key service-uri metadata)
  (starlangruntime:create-actor
   runtime
   (make-json-file-writer-actor-definition
    name
    root
    :service-uri service-uri
    :metadata metadata)))
