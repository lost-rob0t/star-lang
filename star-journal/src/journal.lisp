(in-package :starjournal)

(define-condition star-journal-error (error)
  ((message :initarg :message :reader star-journal-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-journal-error-message condition) stream))))

(defun fail-journal (control &rest arguments)
  (error 'star-journal-error
         :message (apply #'format nil control arguments)))

(defun snapshot-journal-value (value context)
  (handler-case
      (staractorprotocol:snapshot-portable-wire-value value)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail-journal "~A contains an invalid portable value: ~A"
                    context condition))))

(defun proper-plist-p (value)
  (loop with rest = value
        do (cond
             ((null rest) (return t))
             ((and (consp rest) (consp (cdr rest)))
              (setf rest (cddr rest)))
             (t (return nil)))))

(defun ensure-journal-plist (value context)
  (unless (proper-plist-p value)
    (fail-journal "~A must be a property list." context))
  value)

(defun journal-plist-has-key-p (plist key)
  (loop for tail on plist by #'cddr
        when (eq (first tail) key)
          do (return t)
        finally (return nil)))

(defun required-nonempty-string (value context)
  (unless (and (stringp value) (> (length value) 0))
    (fail-journal "~A requires a non-empty string." context))
  value)

(defstruct (runtime-journal-port
            (:constructor %make-runtime-journal-port))
  append-fn
  replay-fn)

(defun make-runtime-journal-port (&key append replay)
  (unless (functionp append)
    (fail-journal "Runtime journal append operation must be a function."))
  (unless (functionp replay)
    (fail-journal "Runtime journal replay operation must be a function."))
  (%make-runtime-journal-port
   :append-fn append
   :replay-fn replay))

(defun runtime-journal-event-kind-p (kind)
  (member kind '(:pending :route-result :remote-result) :test #'eq))

(defun validate-runtime-journal-result (event)
  (unless (journal-plist-has-key-p event :result)
    (fail-journal
     "Settled runtime journal event requires a dispatch result."))
  (let ((result (getf event :result)))
    (ensure-journal-plist result "runtime journal dispatch result")
    (unless (member (getf result :outcome)
                    '(:complete :retry :fail)
                    :test #'eq)
      (fail-journal
       "Runtime journal result requires complete, retry, or fail outcome."))
    result))

(defun validate-runtime-journal-command (command)
  (handler-case
      (staractorprotocol:validate-lifecycle-envelope
       command
       :validate-payload nil)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail-journal "Invalid runtime journal command: ~A" condition)))
  (unless (eq (getf command :kind) :command)
    (fail-journal
     "Runtime journal command must be a lifecycle command envelope."))
  command)

(defun validate-runtime-journal-event (event)
  (ensure-journal-plist event "runtime journal event")
  (let ((kind (getf event :kind))
        (sequence (getf event :dispatcher-sequence))
        (now (getf event :dispatcher-now))
        (command (getf event :command)))
    (unless (runtime-journal-event-kind-p kind)
      (fail-journal "Unknown runtime journal event kind ~S." kind))
    (unless (and (integerp sequence) (>= sequence 0))
      (fail-journal
       "Runtime journal dispatcher sequence must be a nonnegative integer."))
    (required-nonempty-string now "runtime journal dispatcher clock")
    (validate-runtime-journal-command command)
    (if (eq kind :pending)
        (when (journal-plist-has-key-p event :result)
          (fail-journal
           "Pending runtime journal event may not carry a result."))
        (validate-runtime-journal-result event))
    event))

(defun validate-runtime-journal-order (events)
  (loop with previous-sequence = nil
        with previous-now = nil
        for event in events
        for sequence = (getf event :dispatcher-sequence)
        for now = (getf event :dispatcher-now)
        do (when (and previous-sequence
                      (< sequence previous-sequence))
             (fail-journal
              "Runtime journal dispatcher sequence moved backward from ~D to ~D."
              previous-sequence sequence))
           (when (and previous-now (string< now previous-now))
             (fail-journal
              "Runtime journal dispatcher clock moved backward from ~A to ~A."
              previous-now now))
           (setf previous-sequence sequence
                 previous-now now))
  events)

(defun runtime-journal-append (port event)
  (unless (runtime-journal-port-p port)
    (fail-journal "Runtime journal append requires a journal port."))
  (handler-case
      (let ((owned-event
              (snapshot-journal-value event "Runtime journal event")))
        (validate-runtime-journal-event owned-event)
        (funcall (runtime-journal-port-append-fn port) owned-event))
    (star-journal-error (condition)
      (error condition))
    (error (condition)
      (fail-journal "Runtime journal append failed: ~A" condition))))

(defun runtime-journal-replay (port)
  (unless (runtime-journal-port-p port)
    (fail-journal "Runtime journal replay requires a journal port."))
  (handler-case
      (let* ((events (funcall (runtime-journal-port-replay-fn port)))
             (owned-events
               (snapshot-journal-value events "Runtime journal replay")))
        (unless (listp owned-events)
          (fail-journal "Runtime journal replay must return a list."))
        (dolist (event owned-events)
          (validate-runtime-journal-event event))
        (validate-runtime-journal-order owned-events)
        owned-events)
    (star-journal-error (condition)
      (error condition))
    (error (condition)
      (fail-journal "Runtime journal replay failed: ~A" condition))))

(defun make-memory-runtime-journal-port ()
  (let ((events '()))
    (make-runtime-journal-port
     :append
     (lambda (event)
       (setf events (append events (list event)))
       :appended)
     :replay
     (lambda () events))))

(defconstant +file-journal-max-bytes+ (* 64 1024 1024))
(defconstant +file-journal-max-reader-depth+ 64)
(defconstant +file-journal-max-reader-tokens+ 50000)
(defconstant +file-journal-max-records+ 50000)
(defconstant +file-journal-max-string-length+ 1048576)
(defconstant +file-journal-max-total-string-length+ 8388608)
(defconstant +file-journal-max-bit-vector-length+ 65536)

(defun file-journal-whitespace-p (character)
  (member character '(#\Space #\Tab #\Newline #\Return #\Page)
          :test #'char=))

(defun file-journal-token-delimiter-p (character)
  (or (file-journal-whitespace-p character)
      (member character
              '(#\( #\) #\" #\; #\' #\` #\,)
              :test #'char=)))

(defun validate-file-journal-source (source)
  "Reject reader forms that can outrun final journal ownership bounds.

The on-disk format remains the readable representation emitted by this package:
ordinary atoms, strings, proper/dotted lists, vectors, bounded array syntax,
bit-vectors, keywords, package-qualified symbols, and uninterned symbols. Reader
evaluation, graph labels, numeric dispatch prefixes, and other dispatch
extensions are not emitted by the writer and are rejected before invoking READ.
The second return value contains source spans for symbol/atom tokens so replay
can quarantine novel symbols before the host reader sees live packages."
  (let ((length (length source))
        (index 0)
        (depth 0)
        (tokens 0)
        (total-string-length 0)
        (symbol-spans '()))
    (labels
        ((claim-token ()
           (incf tokens)
           (when (> tokens +file-journal-max-reader-tokens+)
             (fail-journal
              "File journal reader token budget exceeded ~D."
              +file-journal-max-reader-tokens+)))
         (scan-string ()
           (claim-token)
           (incf index)
           (let ((string-length 0)
                 (escaped nil))
             (loop while (< index length)
                   for character = (char source index)
                   do (incf index)
                      (cond
                        (escaped
                         (setf escaped nil)
                         (incf string-length))
                        ((char= character #\\)
                         (setf escaped t))
                        ((char= character #\")
                         (incf total-string-length string-length)
                         (when (> string-length
                                  +file-journal-max-string-length+)
                           (fail-journal
                            "File journal string exceeds the ~D-character limit."
                            +file-journal-max-string-length+))
                         (when (> total-string-length
                                  +file-journal-max-total-string-length+)
                           (fail-journal
                            "File journal aggregate string data exceeds the ~D-character limit."
                            +file-journal-max-total-string-length+))
                         (return-from scan-string nil))
                        (t
                         (incf string-length))))
             (fail-journal "File journal contains a truncated string.")))
         (scan-symbol-token (&optional (token-start index))
           (claim-token)
           (let ((barred nil)
                 (escaped nil))
             (loop while (< index length)
                   for character = (char source index)
                   do (cond
                        (escaped
                         (setf escaped nil)
                         (incf index))
                        ((char= character #\\)
                         (setf escaped t)
                         (incf index))
                        ((char= character #\|)
                         (setf barred (not barred))
                         (incf index))
                        ((and (not barred)
                              (file-journal-token-delimiter-p character))
                         (return))
                        (t
                         (incf index))))
             (when escaped
               (fail-journal "File journal contains a truncated symbol escape."))
             (when barred
               (fail-journal "File journal contains an unterminated escaped symbol."))
             (push (cons token-start index) symbol-spans)))
         (scan-line-comment ()
           (loop while (< index length)
                 for character = (char source index)
                 do (incf index)
                 until (char= character #\Newline)))
         (scan-bit-vector ()
           (claim-token)
           (incf index 2)
           (let ((bits 0))
             (loop while (< index length)
                   for character = (char source index)
                   while (or (char= character #\0)
                             (char= character #\1))
                   do (incf bits)
                      (incf index)
                      (when (> bits +file-journal-max-bit-vector-length+)
                        (fail-journal
                         "File journal bit-vector exceeds the ~D-bit limit."
                         +file-journal-max-bit-vector-length+)))
             (when (= bits 0)
               (fail-journal "File journal contains an empty bit-vector reader token."))))
         (scan-dispatch ()
           (when (= (1+ index) length)
             (fail-journal "File journal contains a truncated # dispatch token."))
           (let ((next (char source (1+ index))))
             (cond
               ((digit-char-p next)
                (fail-journal
                 "File journal numeric # dispatch prefixes are not admitted."))
               ((char= next #\()
                (incf index))
               ((char= next #\*)
                (scan-bit-vector))
               ((char= next #\:)
                (let ((token-start index))
                  (incf index 2)
                  (when (or (= index length)
                            (file-journal-token-delimiter-p
                             (char source index)))
                    (fail-journal
                     "File journal contains an incomplete uninterned symbol."))
                  (scan-symbol-token token-start)))
               ((char-equal next #\A)
                (incf index 2))
               (t
                (fail-journal
                 "File journal reader dispatch #~C is not admitted."
                 next))))))
      (loop while (< index length)
            for character = (char source index)
            do (cond
                 ((file-journal-whitespace-p character)
                  (incf index))
                 ((char= character #\;)
                  (scan-line-comment))
                 ((char= character #\")
                  (scan-string))
                 ((char= character #\()
                  (claim-token)
                  (incf depth)
                  (when (> depth +file-journal-max-reader-depth+)
                    (fail-journal
                     "File journal reader depth exceeds ~D."
                     +file-journal-max-reader-depth+))
                  (incf index))
                 ((char= character #\))
                  (decf depth)
                  (when (< depth 0)
                    (fail-journal
                     "File journal contains an unmatched closing parenthesis."))
                  (incf index))
                 ((char= character #\#)
                  (scan-dispatch))
                 ((member character '(#\' #\` #\,) :test #'char=)
                  (fail-journal
                   "File journal reader abbreviation ~C is not admitted."
                   character))
                 (t
                  (scan-symbol-token))))
      (unless (zerop depth)
        (fail-journal "File journal contains an unterminated list or vector."))
      (values source (nreverse symbol-spans)))))

(defun file-journal-decimal-integer-token-p (token)
  (let* ((length (length token))
         (start (if (and (> length 0)
                         (member (char token 0) '(#\+ #\-) :test #'char=))
                    1
                    0)))
    (and (< start length)
         (loop for index from start below length
               always (digit-char-p (char token index))))))

(defun file-journal-symbol-token (symbol)
  (with-standard-io-syntax
    (let ((*print-readably* t)
          (*print-pretty* nil)
          (*print-circle* nil))
      (write-to-string symbol))))

(defun file-journal-existing-symbol-token-table ()
  (let ((table (make-hash-table :test #'equal))
        (keyword-package (find-package :keyword)))
    (do-all-symbols (symbol table)
      (when (or (eq symbol nil)
                (eq symbol t)
                (eq (symbol-package symbol) keyword-package))
        (setf (gethash (file-journal-symbol-token symbol) table) symbol)))))

(defun sanitize-file-journal-source (source)
  (multiple-value-bind (validated symbol-spans)
      (validate-file-journal-source source)
    (let ((existing (file-journal-existing-symbol-token-table))
          (placeholders (make-hash-table :test #'equal))
          (cursor 0)
          (counter 0))
      (values
       (with-output-to-string (stream)
         (dolist (span symbol-spans)
           (let* ((start (car span))
                  (end (cdr span))
                  (token (subseq validated start end)))
             (write-string validated stream :start cursor :end start)
             (cond
               ((or (string= token ".")
                    (file-journal-decimal-integer-token-p token)
                    (gethash token existing))
                (write-string token stream))
               (t
                (let ((name (format nil "STAR-JOURNAL-RAW-TOKEN-~D"
                                    (incf counter))))
                  (setf (gethash name placeholders) token)
                  (format stream "#:~A" name))))
             (setf cursor end)))
         (write-string validated stream :start cursor))
       placeholders))))

(defun validate-safe-file-journal-events (events)
  (let ((owned-events
          (snapshot-journal-value events "File journal replay")))
    (unless (listp owned-events)
      (fail-journal "File journal replay must contain a list of events."))
    (dolist (event owned-events)
      (validate-runtime-journal-event event))
    (validate-runtime-journal-order owned-events)
    owned-events))

(defun file-journal-standard-reader-package ()
  (with-standard-io-syntax *package*))

(defun file-journal-package-marker (token)
  (let ((barred nil)
        (escaped nil)
        (marker-start nil)
        (marker-count 0)
        (last-colon nil))
    (loop for index from 0 below (length token)
          for character = (char token index)
          do (cond
               (escaped
                (setf escaped nil))
               ((char= character #\\)
                (setf escaped t))
               ((char= character #\|)
                (setf barred (not barred)))
               ((and (not barred) (char= character #\:))
                (cond
                  ((null marker-start)
                   (setf marker-start index
                         marker-count 1
                         last-colon index))
                  ((= index (1+ last-colon))
                   (incf marker-count)
                   (setf last-colon index))
                  (t
                   (fail-journal
                    "File journal symbol token contains multiple package markers."))))))
    (when (> marker-count 2)
      (fail-journal "File journal symbol token has an invalid package marker."))
    (values marker-start marker-count)))

(defun decode-file-journal-symbol-component (text decoder-package)
  (when (= (length text) 0)
    (fail-journal "File journal symbol token contains an empty name."))
  (handler-case
      (with-standard-io-syntax
        (let ((*package* decoder-package)
              (*read-eval* nil))
          (multiple-value-bind (value position)
              (read-from-string text nil nil)
            (unless (and (symbolp value)
                         (= position (length text)))
              (fail-journal
               "File journal token is not a readable symbol name."))
            (symbol-name value))))
    (star-journal-error (condition)
      (error condition))
    (error ()
      (fail-journal "File journal contains an invalid symbol token."))))

(defun plan-file-journal-symbol-resolution (token decoder-package)
  (labels ((intern-plan (package name)
             #+sbcl
             (when (and (not (eq package (find-package :keyword)))
                        (sb-ext:package-locked-p package))
               (multiple-value-bind (existing status)
                   (find-symbol name package)
                 (declare (ignore existing))
                 (unless status
                   (fail-journal
                    "File journal symbol targets a locked package."))))
             (list :intern package name)))
    (if (and (>= (length token) 2)
             (char= (char token 0) #\#)
             (char= (char token 1) #\:))
        (list :make-symbol
              (decode-file-journal-symbol-component
               (subseq token 2) decoder-package))
        (multiple-value-bind (marker-start marker-count)
            (file-journal-package-marker token)
          (cond
            ((null marker-start)
             (intern-plan
              (file-journal-standard-reader-package)
              (decode-file-journal-symbol-component token decoder-package)))
            ((and (= marker-start 0) (= marker-count 1))
             (intern-plan
              (find-package :keyword)
              (decode-file-journal-symbol-component
               (subseq token 1) decoder-package)))
            ((= marker-start 0)
             (fail-journal "File journal symbol token has no package name."))
            (t
             (let* ((package-name
                      (decode-file-journal-symbol-component
                       (subseq token 0 marker-start) decoder-package))
                    (symbol-start (+ marker-start marker-count))
                    (symbol-name
                      (decode-file-journal-symbol-component
                       (subseq token symbol-start) decoder-package))
                    (package (find-package package-name)))
               (unless package
                 (fail-journal
                  "File journal symbol names an unavailable package."))
               (ecase marker-count
                 (1
                  (multiple-value-bind (symbol status)
                      (find-symbol symbol-name package)
                    (unless (eq status :external)
                      (fail-journal
                       "File journal symbol names a non-external package symbol."))
                    (list :existing symbol)))
                 (2
                  (multiple-value-bind (symbol status)
                      (find-symbol symbol-name package)
                    (if status
                        (list :existing symbol)
                        (intern-plan package symbol-name))))))))))))

(defun collect-file-journal-symbol-plans (value placeholders decoder-package)
  (let ((plans (make-hash-table :test #'eq)))
    (labels ((walk (item depth)
               (when (> depth +file-journal-max-reader-depth+)
                 (fail-journal "File journal symbol-resolution depth exceeded."))
               (cond
                 ((symbolp item)
                  (let ((token (gethash (symbol-name item) placeholders)))
                    (when token
                      (setf (gethash item plans)
                            (plan-file-journal-symbol-resolution
                             token decoder-package)))))
                 ((consp item)
                  (loop with current = item
                        while (consp current)
                        do (walk (car current) (1+ depth))
                           (setf current (cdr current))
                        finally (unless (null current)
                                  (walk current (1+ depth)))))
                 ((and (vectorp item) (not (stringp item)))
                  (dotimes (index (length item))
                    (walk (aref item index) (1+ depth)))))))
      (walk value 0))
    plans))

(defun realize-file-journal-symbol-plan (plan)
  (ecase (first plan)
    (:existing (second plan))
    (:make-symbol (make-symbol (second plan)))
    (:intern (intern (third plan) (second plan)))))

(defun resolve-file-journal-symbol-placeholders (value plans)
  (labels ((resolve (item depth)
             (when (> depth +file-journal-max-reader-depth+)
               (fail-journal "File journal symbol-resolution depth exceeded."))
             (cond
               ((symbolp item)
                (let ((plan (gethash item plans)))
                  (if plan
                      (realize-file-journal-symbol-plan plan)
                      item)))
               ((consp item)
                (loop with current = item
                      while (consp current)
                      do (setf (car current)
                               (resolve (car current) (1+ depth)))
                         (if (consp (cdr current))
                             (setf current (cdr current))
                             (progn
                               (setf (cdr current)
                                     (resolve (cdr current) (1+ depth)))
                               (return item)))))
               ((and (vectorp item) (not (stringp item)))
                (dotimes (index (length item) item)
                  (setf (aref item index)
                        (resolve (aref item index) (1+ depth)))))
               (t item))))
    (resolve value 0)))

(defun resolve-file-journal-symbols (events placeholders)
  (let ((decoder-package
          (make-package
           (format nil "STARJOURNAL-READER-~A" (gensym))
           :use '())))
    (unwind-protect
         (let ((plans
                 (collect-file-journal-symbol-plans
                  events placeholders decoder-package)))
           (resolve-file-journal-symbol-placeholders events plans))
      (delete-package decoder-package))))

(defun read-bounded-file-journal-source (stream)
  (let ((size (file-length stream)))
    (unless (and (integerp size) (>= size 0))
      (fail-journal "File journal size is unavailable."))
    (when (> size +file-journal-max-bytes+)
      (fail-journal
       "File journal size ~D exceeds the ~D-byte replay limit."
       size +file-journal-max-bytes+))
    (let ((buffer (make-string size)))
      (let ((count (read-sequence buffer stream)))
        (unless (= count size)
          (fail-journal "File journal changed while replay was reading it."))
        (when (read-char stream nil nil)
          (fail-journal "File journal changed while replay was reading it."))
        buffer))))

(defun parse-file-journal-source (source)
  (multiple-value-bind (sanitized placeholders)
      (sanitize-file-journal-source source)
    (handler-case
        (let ((events
                (with-input-from-string (stream sanitized)
                  (with-standard-io-syntax
                    (let ((*read-eval* nil)
                          (eof (gensym "EOF"))
                          (record-count 0))
                      (loop for event = (read stream nil eof)
                            until (eq event eof)
                            do (incf record-count)
                               (when (> record-count +file-journal-max-records+)
                                 (fail-journal
                                  "File journal record count exceeds ~D."
                                  +file-journal-max-records+))
                            collect event))))))
          (let* ((safe-events
                   (validate-safe-file-journal-events events))
                 (resolved
                   (resolve-file-journal-symbols safe-events placeholders)))
            (validate-safe-file-journal-events resolved)))
      (star-journal-error (condition)
        (error condition))
      (error ()
        (fail-journal "File journal contains invalid readable data.")))))

(defun read-file-runtime-journal-events (path)
  (handler-case
      (with-open-file (stream path :direction :input)
        (parse-file-journal-source
         (read-bounded-file-journal-source stream)))
    (star-journal-error (condition)
      (error condition))
    (error ()
      (fail-journal "File journal replay could not read bounded journal data."))))

(defun make-file-runtime-journal-port (pathname)
  (let ((path (pathname pathname)))
    (make-runtime-journal-port
     :append
     (lambda (event)
       (ensure-directories-exist path)
       (with-open-file
           (stream path
                   :direction :output
                   :if-exists :append
                   :if-does-not-exist :create)
         (with-standard-io-syntax
           (let ((*print-readably* t)
                 (*print-pretty* nil)
                 (*print-circle* nil))
             (write event :stream stream)
             (terpri stream)
             (finish-output stream))))
       :appended)
     :replay
     (lambda ()
       (if (probe-file path)
           (read-file-runtime-journal-events path)
           '())))))
