(in-package :staractorprotocol)

(defconstant +portable-snapshot-default-max-depth+ 64)
(defconstant +portable-snapshot-default-max-nodes+ 100000)
(defconstant +portable-snapshot-default-max-string-length+ 1048576)
(defconstant +portable-snapshot-default-max-vector-length+ 65536)

(defun ensure-portable-snapshot-limit (value name)
  (unless (and (integerp value) (> value 0))
    (fail-invalid-wire-envelope
     "Portable wire snapshot ~A must be a positive integer, received ~S."
     name value))
  value)

(defun snapshot-portable-wire-value
    (value
     &key
       (max-depth +portable-snapshot-default-max-depth+)
       (max-nodes +portable-snapshot-default-max-nodes+)
       (max-string-length +portable-snapshot-default-max-string-length+)
       (max-vector-length +portable-snapshot-default-max-vector-length+))
  "Return an owned, bounded snapshot of a portable StarLang wire value.

Strings, cons structure, and vectors are copied recursively. Immutable wire
atoms are retained. Cycles and unsupported host objects are rejected instead of
being retained by identity. Shared-but-acyclic input is accepted and copied by
value, so callers cannot mutate a later snapshot through an earlier alias."
  (ensure-portable-snapshot-limit max-depth "max-depth")
  (ensure-portable-snapshot-limit max-nodes "max-nodes")
  (ensure-portable-snapshot-limit max-string-length "max-string-length")
  (ensure-portable-snapshot-limit max-vector-length "max-vector-length")
  (let ((nodes 0)
        (visiting (make-hash-table :test #'eq)))
    (labels
        ((claim-node (depth)
           (incf nodes)
           (when (> nodes max-nodes)
             (fail-invalid-wire-envelope
              "Portable wire snapshot exceeded the ~D-node limit."
              max-nodes))
           (when (> depth max-depth)
             (fail-invalid-wire-envelope
              "Portable wire snapshot exceeded the depth limit ~D."
              max-depth)))
         (enter-composite (item)
           (when (gethash item visiting)
             (fail-invalid-wire-envelope
              "Portable wire snapshot contains a cycle."))
           (setf (gethash item visiting) t))
         (copy-vector-value (item depth)
           (let ((length (length item)))
             (when (> length max-vector-length)
               (fail-invalid-wire-envelope
                "Portable wire snapshot vector length ~D exceeds the limit ~D."
                length max-vector-length))
             (enter-composite item)
             (unwind-protect
                  (let ((snapshot
                          (make-array length
                                      :element-type
                                      (array-element-type item))))
                    (dotimes (index length snapshot)
                      (setf (aref snapshot index)
                            (copy-value (aref item index) (1+ depth)))))
               (remhash item visiting))))
         (copy-cons-value (item depth)
           (enter-composite item)
           (unwind-protect
                (cons (copy-value (car item) (1+ depth))
                      (copy-value (cdr item) (1+ depth)))
             (remhash item visiting)))
         (copy-value (item depth)
           (claim-node depth)
           (cond
             ((null item) nil)
             ((eq item t) t)
             ((integerp item) item)
             ((symbolp item) item)
             ((stringp item)
              (when (> (length item) max-string-length)
                (fail-invalid-wire-envelope
                 "Portable wire snapshot string length ~D exceeds the limit ~D."
                 (length item) max-string-length))
              (copy-seq item))
             ((consp item)
              (copy-cons-value item depth))
             ((vectorp item)
              (copy-vector-value item depth))
             (t
              (fail-invalid-wire-envelope
               "Unsupported portable wire snapshot value ~S."
               (type-of item))))))
      (copy-value value 0))))
