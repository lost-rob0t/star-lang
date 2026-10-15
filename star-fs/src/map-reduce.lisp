(in-package :starfs)

(define-condition star-fs-error (error)
  ((message :initarg :message :reader star-fs-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-fs-error-message condition) stream))))

(define-condition invalid-map-reduce-plan-error (star-fs-error) ())
(define-condition missing-map-operation-error (star-fs-error) ())
(define-condition missing-reduce-operation-error (star-fs-error) ())
(define-condition invalid-fs-port-error (star-fs-error) ())

(defun fail-fs (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun non-empty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun operation-name-p (value)
  (and (non-empty-string-p value)
       (every
        (lambda (character)
          (or (alphanumericp character)
              (find character "._/-:" :test #'char=)))
        value)))

(defun ensure-operation-name (value label)
  (unless (operation-name-p value)
    (fail-fs
     'invalid-map-reduce-plan-error
     "~A must be a non-empty portable operation name, received ~S."
     label value))
  value)

(defun ensure-optional-operation-name (value label)
  (when value
    (ensure-operation-name value label))
  value)

(defun data-only-value-p (value)
  "Conservative recursive predicate for plan metadata.

Functions, hash tables, streams, pathnames, packages, and implementation
objects are rejected so a plan can cross a process/provider boundary without
smuggling executable host state."
  (labels ((walk (item depth)
             (when (> depth 64)
               (return-from walk nil))
             (cond
               ((or (null item)
                    (stringp item)
                    (integerp item)
                    (rationalp item)
                    (floatp item)
                    (characterp item)
                    (eq item t))
                t)
               ((consp item)
                (and (walk (car item) (1+ depth))
                     (walk (cdr item) (1+ depth))))
               ((vectorp item)
                (loop for element across item
                      always (walk element (1+ depth))))
               (t nil))))
    (walk value 0)))

(defstruct (map-reduce-plan
            (:constructor %make-map-reduce-plan
                (&key id source-collection source-prefix mapper reducer
                      combiner partitions output-collection metadata)))
  (id "" :type string)
  (source-collection "" :type string)
  (source-prefix "" :type string)
  (mapper "" :type string)
  reducer
  combiner
  (partitions 1 :type integer)
  output-collection
  metadata)

(defun make-map-reduce-plan
    (&key id source-collection (source-prefix "") mapper reducer combiner
          (partitions 1) output-collection metadata)
  "Build a data-only StarFS map/reduce plan.

MAPPER, REDUCER, and COMBINER are portable names, never Lisp function objects.
The execution host resolves them against an explicit operation registry."
  (dolist (pair
           (list (cons id "id")
                 (cons source-collection "source-collection")
                 (cons source-prefix "source-prefix")))
    (unless (stringp (car pair))
      (fail-fs
       'invalid-map-reduce-plan-error
       "~A must be a string, received ~S."
       (cdr pair) (car pair))))
  (unless (non-empty-string-p id)
    (fail-fs 'invalid-map-reduce-plan-error "Plan id must not be empty."))
  (unless (non-empty-string-p source-collection)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Source collection must not be empty."))
  (ensure-operation-name mapper "mapper")
  (ensure-optional-operation-name reducer "reducer")
  (ensure-optional-operation-name combiner "combiner")
  (when (and combiner (null reducer))
    (fail-fs
     'invalid-map-reduce-plan-error
     "A combiner requires a reducer."))
  (unless (and (integerp partitions) (<= 1 partitions 4096))
    (fail-fs
     'invalid-map-reduce-plan-error
     "Partition count must be an integer in [1,4096], received ~S."
     partitions))
  (when (and output-collection
             (not (non-empty-string-p output-collection)))
    (fail-fs
     'invalid-map-reduce-plan-error
     "Output collection must be NIL or a non-empty string, received ~S."
     output-collection))
  (unless (data-only-value-p metadata)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Plan metadata must contain data only, received ~S."
     metadata))
  (%make-map-reduce-plan
   :id id
   :source-collection source-collection
   :source-prefix source-prefix
   :mapper mapper
   :reducer reducer
   :combiner combiner
   :partitions partitions
   :output-collection output-collection
   :metadata (copy-tree metadata)))

(defun map-reduce-plan-plist (plan)
  (unless (map-reduce-plan-p plan)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Expected MAP-REDUCE-PLAN, received ~S."
     plan))
  (list
   :id (map-reduce-plan-id plan)
   :source-collection (map-reduce-plan-source-collection plan)
   :source-prefix (map-reduce-plan-source-prefix plan)
   :mapper (map-reduce-plan-mapper plan)
   :reducer (map-reduce-plan-reducer plan)
   :combiner (map-reduce-plan-combiner plan)
   :partitions (map-reduce-plan-partitions plan)
   :output-collection (map-reduce-plan-output-collection plan)
   :metadata (copy-tree (map-reduce-plan-metadata plan))))

(defun map-reduce-plan-from-plist (plist)
  (unless (listp plist)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Plan representation must be a plist, received ~S."
     plist))
  (make-map-reduce-plan
   :id (getf plist :id)
   :source-collection (getf plist :source-collection)
   :source-prefix (or (getf plist :source-prefix) "")
   :mapper (getf plist :mapper)
   :reducer (getf plist :reducer)
   :combiner (getf plist :combiner)
   :partitions (or (getf plist :partitions) 1)
   :output-collection (getf plist :output-collection)
   :metadata (getf plist :metadata)))

(defstruct (fs-record
            (:constructor %make-fs-record (&key key value metadata)))
  (key "" :type string)
  value
  metadata)

(defun make-fs-record (key value &key metadata)
  (unless (non-empty-string-p key)
    (fail-fs
     'invalid-fs-port-error
     "Filesystem record key must be a non-empty string, received ~S."
     key))
  (%make-fs-record :key key :value value :metadata metadata))

(defstruct (fs-port
            (:constructor %make-fs-port (&key scan write)))
  scan
  write)

(defun make-fs-port (&key scan write)
  "Construct a provider-neutral filesystem port.

SCAN receives (collection prefix) and returns FS-RECORD values. WRITE, when
present, receives (collection rows plan). Credentials and provider objects
remain behind these callbacks and are never part of a map/reduce plan."
  (unless (functionp scan)
    (fail-fs
     'invalid-fs-port-error
     "Filesystem scan operation must be a function."))
  (when (and write (not (functionp write)))
    (fail-fs
     'invalid-fs-port-error
     "Filesystem write operation must be NIL or a function."))
  (%make-fs-port :scan scan :write write))

(defstruct (operation-registry
            (:constructor %make-operation-registry (&key maps reduces)))
  maps
  reduces)

(defun make-operation-registry ()
  (%make-operation-registry
   :maps (make-hash-table :test #'equal)
   :reduces (make-hash-table :test #'equal)))

(defun register-operation (table name function condition-type kind)
  (ensure-operation-name name kind)
  (unless (functionp function)
    (fail-fs
     condition-type
     "~A operation ~S must be a function."
     kind name))
  (multiple-value-bind (existing present-p)
      (gethash name table)
    (when (and present-p (not (eq existing function)))
      (fail-fs
       condition-type
       "~A operation ~S is already registered."
       kind name))
    (setf (gethash name table) function))
  name)

(defun register-map-operation (registry name function)
  (unless (operation-registry-p registry)
    (fail-fs
     'missing-map-operation-error
     "Expected an operation registry, received ~S."
     registry))
  (register-operation
   (operation-registry-maps registry)
   name function
   'missing-map-operation-error
   "Map"))

(defun register-reduce-operation (registry name function)
  (unless (operation-registry-p registry)
    (fail-fs
     'missing-reduce-operation-error
     "Expected an operation registry, received ~S."
     registry))
  (register-operation
   (operation-registry-reduces registry)
   name function
   'missing-reduce-operation-error
   "Reduce"))

(defun resolve-map-operation (registry name)
  (let ((function
          (and (operation-registry-p registry)
               (gethash name (operation-registry-maps registry)))))
    (or function
        (fail-fs
         'missing-map-operation-error
         "Map operation ~S is not registered."
         name))))

(defun resolve-reduce-operation (registry name)
  (let ((function
          (and (operation-registry-p registry)
               (gethash name (operation-registry-reduces registry)))))
    (or function
        (fail-fs
         'missing-reduce-operation-error
         "Reduce operation ~S is not registered."
         name))))

(defun fnv1a-64 (octets)
  (let ((hash #xcbf29ce484222325))
    (loop for octet across octets
          do (setf hash
                   (ldb (byte 64 0)
                        (* (logxor hash octet)
                           #x100000001b3))))
    hash))

(defun deterministic-partition (key partition-count)
  "Return a stable partition for UTF-8 KEY independent of Lisp SXHASH."
  (unless (non-empty-string-p key)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Partition key must be a non-empty string, received ~S."
     key))
  (unless (and (integerp partition-count)
               (plusp partition-count))
    (fail-fs
     'invalid-map-reduce-plan-error
     "Partition count must be positive, received ~S."
     partition-count))
  (mod
   (fnv1a-64 (babel:string-to-octets key :encoding :utf-8))
   partition-count))

(defstruct emission
  (key "" :type string)
  value
  (partition 0 :type integer)
  (input-ordinal 0 :type integer)
  (emission-ordinal 0 :type integer))

(defun emission< (left right)
  (or (< (emission-partition left)
         (emission-partition right))
      (and (= (emission-partition left)
              (emission-partition right))
           (or (string< (emission-key left)
                        (emission-key right))
               (and (string= (emission-key left)
                             (emission-key right))
                    (or (< (emission-input-ordinal left)
                           (emission-input-ordinal right))
                        (and (= (emission-input-ordinal left)
                                (emission-input-ordinal right))
                             (< (emission-emission-ordinal left)
                                (emission-emission-ordinal right)))))))))

(defun ensure-record-list (records)
  (unless (and (listp records) (every #'fs-record-p records))
    (fail-fs
     'invalid-fs-port-error
     "Filesystem scan must return a list of FS-RECORD values."))
  records)

(defun sorted-input-records (records)
  (stable-sort
   (copy-list (ensure-record-list records))
   #'string<
   :key #'fs-record-key))

(defun map-records (records mapper partitions)
  (let ((emissions nil))
    (loop for record in records
          for input-ordinal from 0
          do
             (let ((emission-ordinal 0))
               (funcall
                mapper
                record
                (lambda (key value)
                  (unless (non-empty-string-p key)
                    (fail-fs
                     'invalid-map-reduce-plan-error
                     "Mapper emitted invalid key ~S."
                     key))
                  (push
                   (make-emission
                    :key key
                    :value value
                    :partition
                    (deterministic-partition key partitions)
                    :input-ordinal input-ordinal
                    :emission-ordinal emission-ordinal)
                   emissions)
                  (incf emission-ordinal)))))
    (stable-sort emissions #'emission<)))

(defun contiguous-emission-groups (emissions &key include-partition)
  (let ((groups nil)
        (current nil)
        (current-key nil)
        (current-partition nil))
    (labels ((flush ()
               (when current
                 (push
                  (list :key current-key
                        :partition current-partition
                        :emissions (nreverse current))
                  groups)
                 (setf current nil))))
      (dolist (item emissions)
        (let ((key (emission-key item))
              (partition (emission-partition item)))
          (unless (and current
                       (string= key current-key)
                       (or (not include-partition)
                           (= partition current-partition)))
            (flush)
            (setf current-key key
                  current-partition partition))
          (push item current)))
      (flush))
    (nreverse groups)))

(defun combine-emissions (emissions combiner)
  (if (null combiner)
      emissions
      (let ((combined nil))
        (dolist
            (group
             (contiguous-emission-groups
              emissions :include-partition t))
          (let* ((items (getf group :emissions))
                 (first (first items))
                 (value
                   (funcall
                    combiner
                    (getf group :key)
                    (mapcar #'emission-value items))))
            (push
             (make-emission
              :key (getf group :key)
              :value value
              :partition (getf group :partition)
              :input-ordinal (emission-input-ordinal first)
              :emission-ordinal 0)
             combined)))
        (stable-sort combined #'emission<))))

(defun reduce-emissions (emissions reducer)
  (if (null reducer)
      (mapcar
       (lambda (item)
         (make-fs-record
          (emission-key item)
          (emission-value item)
          :metadata
          (list :partition (emission-partition item))))
       emissions)
      (let ((rows nil)
            (by-key
              (stable-sort
               (copy-list emissions)
               #'string<
               :key #'emission-key)))
        (dolist
            (group
             (contiguous-emission-groups
              by-key :include-partition nil))
          (push
           (make-fs-record
            (getf group :key)
            (funcall
             reducer
             (getf group :key)
             (mapcar #'emission-value
                     (getf group :emissions))))
           rows))
        (nreverse rows))))

(defstruct (map-reduce-result
            (:constructor %make-map-reduce-result
                (&key plan-id input-count emitted-count partition-count rows)))
  (plan-id "" :type string)
  (input-count 0 :type integer)
  (emitted-count 0 :type integer)
  (partition-count 1 :type integer)
  rows)

(defun execute-map-reduce (port registry plan)
  "Execute PLAN through PORT with deterministic map/shuffle/reduce semantics."
  (unless (fs-port-p port)
    (fail-fs 'invalid-fs-port-error "Expected FS-PORT, received ~S." port))
  (unless (operation-registry-p registry)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Expected OPERATION-REGISTRY, received ~S."
     registry))
  (unless (map-reduce-plan-p plan)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Expected MAP-REDUCE-PLAN, received ~S."
     plan))
  (let* ((records
           (sorted-input-records
            (funcall
             (fs-port-scan port)
             (map-reduce-plan-source-collection plan)
             (map-reduce-plan-source-prefix plan))))
         (mapper
           (resolve-map-operation
            registry (map-reduce-plan-mapper plan)))
         (reducer-name (map-reduce-plan-reducer plan))
         (combiner-name (map-reduce-plan-combiner plan))
         (reducer
           (and reducer-name
                (resolve-reduce-operation registry reducer-name)))
         (combiner
           (and combiner-name
                (resolve-reduce-operation registry combiner-name)))
         (mapped
           (map-records
            records mapper (map-reduce-plan-partitions plan)))
         (combined (combine-emissions mapped combiner))
         (rows (reduce-emissions combined reducer))
         (output (map-reduce-plan-output-collection plan)))
    (when output
      (unless (functionp (fs-port-write port))
        (fail-fs
         'invalid-fs-port-error
         "Plan ~A declares output collection ~S but the filesystem port has no writer."
         (map-reduce-plan-id plan) output))
      (funcall (fs-port-write port) output rows plan))
    (%make-map-reduce-result
     :plan-id (map-reduce-plan-id plan)
     :input-count (length records)
     :emitted-count (length mapped)
     :partition-count (map-reduce-plan-partitions plan)
     :rows rows)))

(defun map-reduce-contract-valid-p (contract value)
  (case contract
    (:map-reduce-plan (map-reduce-plan-p value))
    (:map-reduce-result (map-reduce-result-p value))
    (otherwise nil)))

(defun make-map-reduce-actor-definition
    (name port registry &key service-uri metadata)
  "Adapt StarFS execution to the real final StarLang actor runtime."
  (unless (fs-port-p port)
    (fail-fs 'invalid-fs-port-error "Expected FS-PORT, received ~S." port))
  (unless (operation-registry-p registry)
    (fail-fs
     'invalid-map-reduce-plan-error
     "Expected OPERATION-REGISTRY, received ~S."
     registry))
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (declare (ignore state runtime))
     (execute-map-reduce port registry message))
   :service-uri service-uri
   :accepts :map-reduce-plan
   :produces :map-reduce-result
   :input-validator #'map-reduce-contract-valid-p
   :output-validator #'map-reduce-contract-valid-p
   :metadata metadata))

(defun create-map-reduce-actor
    (runtime name port registry &key service-uri metadata)
  (starlangruntime:create-actor
   runtime
   (make-map-reduce-actor-definition
    name port registry
    :service-uri service-uri
    :metadata metadata)))
