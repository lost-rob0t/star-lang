(defpackage :starfs
  (:use :cl)
  (:nicknames :star-fs)
  (:export
   ;; Conditions.
   #:star-fs-error
   #:invalid-map-reduce-plan-error
   #:missing-map-operation-error
   #:missing-reduce-operation-error
   #:invalid-fs-port-error

   ;; Data-only plan IR.
   #:map-reduce-plan
   #:map-reduce-plan-p
   #:make-map-reduce-plan
   #:map-reduce-plan-id
   #:map-reduce-plan-source-collection
   #:map-reduce-plan-source-prefix
   #:map-reduce-plan-mapper
   #:map-reduce-plan-reducer
   #:map-reduce-plan-combiner
   #:map-reduce-plan-partitions
   #:map-reduce-plan-output-collection
   #:map-reduce-plan-metadata
   #:map-reduce-plan-plist
   #:map-reduce-plan-from-plist

   ;; Provider-neutral filesystem port.
   #:fs-port
   #:fs-port-p
   #:make-fs-port
   #:fs-port-scan
   #:fs-port-write
   #:fs-record
   #:fs-record-p
   #:make-fs-record
   #:fs-record-key
   #:fs-record-value
   #:fs-record-metadata

   ;; Host operation registry.
   #:operation-registry
   #:operation-registry-p
   #:make-operation-registry
   #:register-map-operation
   #:register-reduce-operation
   #:resolve-map-operation
   #:resolve-reduce-operation

   ;; Deterministic execution.
   #:deterministic-partition
   #:map-reduce-result
   #:map-reduce-result-p
   #:map-reduce-result-plan-id
   #:map-reduce-result-input-count
   #:map-reduce-result-emitted-count
   #:map-reduce-result-partition-count
   #:map-reduce-result-rows
   #:execute-map-reduce

   ;; Actor adapter over the real final runtime.
   #:make-map-reduce-actor-definition
   #:create-map-reduce-actor))
