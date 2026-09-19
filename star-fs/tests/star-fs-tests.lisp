(defpackage :starfs-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starfs-tests)

(def-suite star-fs-suite)
(in-suite star-fs-suite)

(defun rows->alist (rows)
  (mapcar
   (lambda (row)
     (cons (starfs:fs-record-key row)
           (starfs:fs-record-value row)))
   rows))

(defun fixture-registry ()
  (let ((registry (starfs:make-operation-registry)))
    (starfs:register-map-operation
     registry
     "words"
     (lambda (record emit)
       (dolist (word (starfs:fs-record-value record))
         (funcall emit word 1))))
    (starfs:register-reduce-operation
     registry
     "sum"
     (lambda (_key values)
       (declare (ignore _key))
       (reduce #'+ values :initial-value 0)))
    registry))

(defun fixture-plan (&key (output "word-counts"))
  (starfs:make-map-reduce-plan
   :id "word-count"
   :source-collection "documents"
   :source-prefix "notes/"
   :mapper "words"
   :combiner "sum"
   :reducer "sum"
   :partitions 4
   :output-collection output
   :metadata '(("purpose" . "test"))))

(test plan-is-data-only-and-round-trips
  (let* ((plan (fixture-plan))
         (copy
           (starfs:map-reduce-plan-from-plist
            (starfs:map-reduce-plan-plist plan))))
    (is (string= "word-count" (starfs:map-reduce-plan-id copy)))
    (is (string= "documents"
                 (starfs:map-reduce-plan-source-collection copy)))
    (is (= 4 (starfs:map-reduce-plan-partitions copy))))
  (signals starfs:invalid-map-reduce-plan-error
    (starfs:make-map-reduce-plan
     :id "bad"
     :source-collection "docs"
     :mapper "map"
     :metadata (list #'identity)))
  (signals starfs:invalid-map-reduce-plan-error
    (starfs:make-map-reduce-plan
     :id "bad-combiner"
     :source-collection "docs"
     :mapper "map"
     :combiner "sum")))

(test partitioning-is-stable-and-bounded
  (loop for key in '("alpha" "beta" "γamma" "path/to/item")
        for first = (starfs:deterministic-partition key 17)
        do
           (is (= first
                  (starfs:deterministic-partition key 17)))
           (is (<= 0 first))
           (is (< first 17))))

(test executes-map-combine-reduce-through-port
  (let ((scan-arguments nil)
        (write-arguments nil)
        (records
          (list
           (starfs:make-fs-record "notes/c"
                                  '("beta" "alpha"))
           (starfs:make-fs-record "notes/a"
                                  '("alpha" "beta"))
           (starfs:make-fs-record "notes/b"
                                  '("beta")))))
    (let* ((port
             (starfs:make-fs-port
              :scan
              (lambda (collection prefix)
                (setf scan-arguments (list collection prefix))
                records)
              :write
              (lambda (collection rows plan)
                (setf write-arguments
                      (list collection (rows->alist rows)
                            (starfs:map-reduce-plan-id plan))))))
           (result
             (starfs:execute-map-reduce
              port (fixture-registry) (fixture-plan))))
      (is (equal '("documents" "notes/") scan-arguments))
      (is (= 3 (starfs:map-reduce-result-input-count result)))
      (is (= 5 (starfs:map-reduce-result-emitted-count result)))
      (is (= 4 (starfs:map-reduce-result-partition-count result)))
      (is (equal '(("alpha" . 2) ("beta" . 3))
                 (rows->alist
                  (starfs:map-reduce-result-rows result))))
      (is (equal
           '("word-counts"
             (("alpha" . 2) ("beta" . 3))
             "word-count")
           write-arguments)))))

(test missing-operation-fails-closed
  (let ((port
          (starfs:make-fs-port
           :scan (lambda (_collection _prefix)
                   (declare (ignore _collection _prefix))
                   nil)))
        (registry (starfs:make-operation-registry)))
    (signals starfs:missing-map-operation-error
      (starfs:execute-map-reduce
       port registry
       (starfs:make-map-reduce-plan
        :id "missing"
        :source-collection "docs"
        :mapper "does-not-exist")))))

(test output-requires-writer
  (let ((port
          (starfs:make-fs-port
           :scan
           (lambda (_collection _prefix)
             (declare (ignore _collection _prefix))
             nil))))
    (signals starfs:invalid-fs-port-error
      (starfs:execute-map-reduce
       port (fixture-registry) (fixture-plan)))))

(test real-runtime-actor-executes-plan
  (let* ((runtime (starlangruntime:make-runtime))
         (port
           (starfs:make-fs-port
            :scan
            (lambda (_collection _prefix)
              (declare (ignore _collection _prefix))
              (list
               (starfs:make-fs-record
                "one" '("alpha" "alpha" "beta"))))))
         (actor
           (starfs:create-map-reduce-actor
            runtime
            "star-fs-worker"
            port
            (fixture-registry))))
    (unwind-protect
         (let ((result
                 (starlangruntime:ask
                  runtime
                  actor
                  (fixture-plan :output nil))))
           (is (starfs:map-reduce-result-p result))
           (is (equal
                '(("alpha" . 2) ("beta" . 1))
                (rows->alist
                 (starfs:map-reduce-result-rows result))))
           (is (= 1
                  (starlangruntime:actor-instance-invocation-count
                   actor))))
      (starlangruntime:shutdown-runtime runtime))))

(defun run-tests ()
  (let ((result (run! 'star-fs-suite)))
    (unless (results-status result)
      (error "star-fs tests failed"))
    t))
