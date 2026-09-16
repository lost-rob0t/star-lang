(defpackage :starjournal-review-repair-tests
  (:use :cl)
  (:export #:run-tests))

(defpackage :starjournal-rejected-input-sentinel
  (:use))

(in-package :starjournal-review-repair-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun temporary-journal-pathname (label)
  (pathname
   (format nil "/tmp/star-journal-review-repair-~A-~D-~D.sexp"
           label
           (get-universal-time)
           (random 1000000000))))

(defun test-command (&key message-id payload)
  (staractorprotocol:make-command-envelope
   :message-id message-id
   :message-type "test/journal@1/command"
   :actor "journal-test"
   :idempotency-key (format nil "~A-key" message-id)
   :payload payload))

(defun pending-event (message-id &key (sequence 1) payload)
  (list :kind :pending
        :dispatcher-sequence sequence
        :dispatcher-now "1970-01-01T00:00:00Z"
        :command (test-command :message-id message-id :payload payload)))

(defun write-raw-journal (path contents)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string contents stream)
    (finish-output stream)))

(defun replay-path (path)
  (starjournal:runtime-journal-replay
   (starjournal:make-file-runtime-journal-port path)))

(defun test-file-journal-shared-acyclic-replays-by-value ()
  (let* ((path (temporary-journal-pathname "shared-acyclic"))
         (shared (list (copy-seq "alpha")))
         (payload (list (cons "left" shared)
                        (cons "right" shared)))
         (event (pending-event "shared-acyclic" :payload payload)))
    (unwind-protect
         (let ((journal (starjournal:make-file-runtime-journal-port path)))
           (check (eq :appended
                      (starjournal:runtime-journal-append journal event))
                  "Shared acyclic file event was not appended.")
           (let* ((replayed (first (starjournal:runtime-journal-replay journal)))
                  (replayed-payload
                    (getf (getf replayed :command) :payload))
                  (left (cdr (assoc "left" replayed-payload :test #'string=)))
                  (right (cdr (assoc "right" replayed-payload :test #'string=))))
             (check (equal '("alpha") left)
                    "Shared acyclic left branch changed during file replay: ~S"
                    left)
             (check (equal '("alpha") right)
                    "Shared acyclic right branch changed during file replay: ~S"
                    right)
             (check (not (eq left right))
                    "File replay unexpectedly preserved mutable alias identity.")
             (setf (char (first left) 0) #\X)
             (check (string= "alpha" (first right))
                    "Mutating one replayed shared branch changed the other branch.")))
      (when (probe-file path)
        (delete-file path)))))

(defun check-rejected-input-does-not-intern
    (label package-designator token-format)
  (let* ((path (temporary-journal-pathname label))
         (package (find-package package-designator))
         (name (symbol-name (gensym "STARLANG-JOURNAL-POLLUTION-")))
         (token (format nil token-format name)))
    (check package "Missing test package ~A." package-designator)
    (multiple-value-bind (symbol status) (find-symbol name package)
      (declare (ignore symbol))
      (check (null status)
             "Novel symbol test precondition failed for ~A::~A."
             (package-name package) name))
    (unwind-protect
         (progn
           (write-raw-journal path token)
           (check (signals-p 'starjournal:star-journal-error
                             (lambda () (replay-path path)))
                  "Rejected symbol fixture ~A did not signal STAR-JOURNAL-ERROR."
                  label)
           (multiple-value-bind (symbol status) (find-symbol name package)
             (declare (ignore symbol))
             (check (null status)
                    "Rejected journal input interned ~A::~A."
                    (package-name package) name)))
      (multiple-value-bind (symbol status) (find-symbol name package)
        (when status
          (unintern symbol package)))
      (when (probe-file path)
        (delete-file path)))))

(defun test-rejected-package-qualified-symbol-does-not-intern ()
  (check-rejected-input-does-not-intern
   "package-qualified-symbol"
   "STARJOURNAL-REJECTED-INPUT-SENTINEL"
   "STARJOURNAL-REJECTED-INPUT-SENTINEL::~A"))

(defun test-rejected-unqualified-symbol-does-not-intern ()
  (check-rejected-input-does-not-intern
   "unqualified-symbol"
   "CL-USER"
   "~A"))

(defun test-unrelated-common-lisp-symbols-are-quarantined-before-read ()
  (dolist (token '("&REST" "&ALLOW-OTHER-KEYS"))
    (multiple-value-bind (sanitized placeholders)
        (starjournal::sanitize-file-journal-source token)
      (check (= 1 (hash-table-count placeholders))
             "Existing COMMON-LISP marker ~A bypassed journal token quarantine."
             token)
      (check (null (search token sanitized :test #'char-equal))
             "Existing COMMON-LISP marker ~A remained visible to READ: ~S"
             token sanitized)
      (let ((original nil))
        (maphash
         (lambda (placeholder value)
           (declare (ignore placeholder))
           (setf original value))
         placeholders)
        (check (string= token original)
               "Quarantine did not retain the original marker token ~A: ~S"
               token original)))))

#+sbcl
(defun test-file-journal-short-snapshot-read-is-rejected ()
  (let* ((path (temporary-journal-pathname "short-read"))
         (journal (starjournal:make-file-runtime-journal-port path))
         (first-event (pending-event "short-read-1" :sequence 1))
         (second-event (pending-event "short-read-2" :sequence 2))
         (original-file-length (symbol-function 'cl:file-length))
         (triggered nil)
         (first-record nil))
    (unwind-protect
         (progn
           (starjournal:runtime-journal-append journal first-event)
           (starjournal:runtime-journal-append journal second-event)
           (with-open-file (stream path :direction :input)
             (setf first-record (read-line stream nil nil)))
           (check first-record "Short-read fixture did not contain a first record.")
           (sb-ext:without-package-locks
             (setf (symbol-function 'cl:file-length)
                   (lambda (stream)
                     (let ((size (funcall original-file-length stream)))
                       (unless triggered
                         (setf triggered t)
                         (write-raw-journal
                          path
                          (format nil "~A~%" first-record)))
                       size))))
           (check (signals-p 'starjournal:star-journal-error
                             (lambda () (replay-path path)))
                  "A file truncated after snapshot size observation replayed a valid prefix instead of failing typed.")
           (check triggered
                  "Short-read fixture did not intercept the journal size observation."))
      (sb-ext:without-package-locks
        (setf (symbol-function 'cl:file-length) original-file-length))
      (when (probe-file path)
        (delete-file path)))))

#-sbcl
(defun test-file-journal-short-snapshot-read-is-rejected ()
  (error "The deterministic short-read acceptance fixture currently requires the pinned SBCL test host."))

(defun run-tests ()
  (test-file-journal-shared-acyclic-replays-by-value)
  (test-rejected-package-qualified-symbol-does-not-intern)
  (test-rejected-unqualified-symbol-does-not-intern)
  (test-unrelated-common-lisp-symbols-are-quarantined-before-read)
  (test-file-journal-short-snapshot-read-is-rejected)
  (format t "~&star-journal review repair tests passed~%")
  t)