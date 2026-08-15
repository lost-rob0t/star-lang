(in-package :starcanonicaljson)

(define-condition star-canonical-json-error (error)
  ((message :initarg :message :reader star-canonical-json-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-canonical-json-error-message condition) stream))))

(define-condition invalid-canonical-json-error (star-canonical-json-error) ())

(defun fail-canonical-json (control &rest arguments)
  (error 'invalid-canonical-json-error
         :message (apply #'format nil control arguments)))

(defstruct (json-object (:constructor make-json-object (entries)))
  entries)

(defstruct (json-array (:constructor make-json-array (values)))
  values)

(defparameter +json-true+ (gensym "JSON-TRUE"))
(defparameter +json-false+ (gensym "JSON-FALSE"))
(defparameter +json-null+ (gensym "JSON-NULL"))

(defun write-json-escaped-string (value stream)
  (write-char #\" stream)
  (loop for character across value
        for code = (char-code character)
        do (case character
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Backspace (write-string "\\b" stream))
             (#\Page (write-string "\\f" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (otherwise
              (if (< code 32)
                  (format stream "\\u~4,'0X" code)
                  (write-char character stream)))))
  (write-char #\" stream))

(defun write-canonical-json (value stream)
  (cond
    ((eq value +json-true+)
     (write-string "true" stream))
    ((eq value +json-false+)
     (write-string "false" stream))
    ((eq value +json-null+)
     (write-string "null" stream))
    ((stringp value)
     (write-json-escaped-string value stream))
    ((integerp value)
     (format stream "~D" value))
    ((json-array-p value)
     (write-char #\[ stream)
     (loop for item in (json-array-values value)
           for first-p = t then nil
           do (unless first-p
                (write-char #\, stream))
              (write-canonical-json item stream))
     (write-char #\] stream))
    ((json-object-p value)
     (write-char #\{ stream)
     (loop for entry in (sort (copy-list (json-object-entries value))
                              #'string<
                              :key #'car)
           for first-p = t then nil
           do (unless first-p
                (write-char #\, stream))
              (write-json-escaped-string (car entry) stream)
              (write-char #\: stream)
              (write-canonical-json (cdr entry) stream))
     (write-char #\} stream))
    (t
     (fail-canonical-json
      "Unsupported canonical JSON node ~S."
      value))))

(defun canonical-json-string (value)
  (with-output-to-string (stream)
    (write-canonical-json value stream)))
