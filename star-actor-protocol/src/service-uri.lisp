(in-package :staractorprotocol)

(define-condition star-actor-protocol-error (error)
  ((message
    :initarg :message
    :reader star-actor-protocol-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-actor-protocol-error-message condition) stream))))

(define-condition invalid-star-service-uri-error
    (star-actor-protocol-error)
  ())

(defun fail-invalid-star-service-uri (control &rest arguments)
  (error 'invalid-star-service-uri-error
         :message (apply #'format nil control arguments)))

(defstruct (star-service-uri
            (:constructor %make-star-service-uri
                (domain address actor-name)))
  (domain "" :type string)
  (address "" :type string)
  (actor-name "" :type string))

(defun valid-star-service-token-character-p (character)
  (or (char<= #\a character #\z)
      (char<= #\0 character #\9)
      (member character '(#\- #\_ #\.) :test #'char=)))

(defun valid-star-service-token-p (value)
  (and (stringp value)
       (plusp (length value))
       (every #'valid-star-service-token-character-p value)))

(defun validate-star-service-token (value label)
  (unless (valid-star-service-token-p value)
    (fail-invalid-star-service-uri
     "STAR service URI ~A must be non-empty lowercase ASCII using only letters, digits, '.', '_', or '-': ~S."
     label
     value))
  value)

(defun make-star-service-uri (domain address actor-name)
  (%make-star-service-uri
   (validate-star-service-token domain "domain")
   (validate-star-service-token address "address")
   (validate-star-service-token actor-name "actor name")))

(defun star-service-uri-string (uri)
  (unless (star-service-uri-p uri)
    (fail-invalid-star-service-uri
     "Expected a STAR service URI object, received ~S."
     uri))
  (format nil "star://~A:~A:~A"
          (star-service-uri-domain uri)
          (star-service-uri-address uri)
          (star-service-uri-actor-name uri)))

(defun star-service-uri-target-p (value)
  (and (stringp value)
       (<= 7 (length value))
       (string= "star://" value :end2 7)))

(defun parse-star-service-uri (value)
  (unless (star-service-uri-target-p value)
    (fail-invalid-star-service-uri
     "STAR service URI must begin with star://, received ~S."
     value))
  (let* ((body (subseq value 7))
         (first-separator (position #\: body))
         (second-separator
           (and first-separator
                (position #\: body :start (1+ first-separator))))
         (third-separator
           (and second-separator
                (position #\: body :start (1+ second-separator)))))
    (unless (and first-separator second-separator (null third-separator))
      (fail-invalid-star-service-uri
       "STAR service URI must have exactly domain:address:actor-name after star://, received ~S."
       value))
    (make-star-service-uri
     (subseq body 0 first-separator)
     (subseq body (1+ first-separator) second-separator)
     (subseq body (1+ second-separator)))))

(defun ensure-star-service-uri (value)
  (cond
    ((star-service-uri-p value) value)
    ((stringp value) (parse-star-service-uri value))
    (t
     (fail-invalid-star-service-uri
      "Expected STAR service URI string or object, received ~S."
      value))))

(defun canonical-star-service-uri-for-actor (actor-name value)
  (let ((uri (ensure-star-service-uri value)))
    (unless (string= actor-name (star-service-uri-actor-name uri))
      (fail-invalid-star-service-uri
       "STAR service URI actor name ~A does not match actor contract ~A."
       (star-service-uri-actor-name uri)
       actor-name))
    (star-service-uri-string uri)))
