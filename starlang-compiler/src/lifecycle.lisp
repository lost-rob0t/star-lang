;;;; Document lifecycle DSL: lower a closed .star `lifecycle` declaration to
;;;; data-only IR and emit a deterministic, server-consumable lifecycle
;;;; manifest and transition table (issue star-lang#142; fixtures feed the
;;;; LATER server lifecycle executor slice starintel-server#240).
;;;;
;;;; Lifecycle policy is declarative closed-vocabulary data: every option,
;;;; action, class, and unit is drawn from a fixed vocabulary, so no arbitrary
;;;; host evaluation can enter lifecycle policy. Storage backend choice is
;;;; policy input only (tier/replication class) and never enters the document
;;;; schema. Destructive deletion that would erase provenance or event history
;;;; is rejected while evidence retention or a legal hold applies.

(in-package #:star-lang.compiler.core)

(defparameter +lifecycle-option-keys+
  '(:applies :version :initial :states :retention :storage :ttl :indexing
    :encryption :hold :events :transitions))

(defparameter +lifecycle-transition-option-keys+
  '(:from :on :to :guard :action :emit :supersedes))

(defparameter +lifecycle-actions+ '(:keep :archive :redact :tombstone :destroy))

(defparameter +lifecycle-storage-tiers+ '(:hot :warm :cold))

(defparameter +lifecycle-replication-classes+ '(:local :regional :global))

(defparameter +lifecycle-indexing-modes+ '(:none :metadata :full-text))

(defparameter +lifecycle-encryption-classes+ '(:open :standard :sealed))

(defparameter +lifecycle-hold-classes+ '(:legal))

(defun validate-lifecycle-option-keys (options allowed-keys context)
  "Require unique lifecycle option keys drawn from ALLOWED-KEYS."
  (let ((seen '()))
    (loop for tail on (plist-elements options) by #'cddr
          for key = (first tail)
          do (unless (and (star-syntax-p key)
                          (eq (star-syntax-kind key) :keyword))
               (fail 'invalid-declaration-error
                     "Lifecycle ~A option keys must be keyword occurrences."
                     context))
             (let ((normalized-key (syntax-atom key)))
               (unless (member normalized-key allowed-keys :test #'eq)
                 (fail 'invalid-declaration-error
                       "Lifecycle ~A option ~S is not part of the closed vocabulary."
                       context normalized-key))
               (when (member normalized-key seen :test #'eq)
                 (fail 'invalid-declaration-error
                       "Lifecycle ~A declares ~S more than once."
                       context normalized-key))
             (push normalized-key seen)))))

(defun lifecycle-closed-keyword (value allowed what)
  (let ((key (identifier-key value)))
    (or (find (intern (string-upcase key) :keyword) allowed :test #'eq)
        (fail 'invalid-declaration-error
              "Lifecycle ~A must be one of ~S, received ~S." what allowed key))))

(defun lifecycle-duration-days (value what)
  (let* ((elements (syntax-elements value))
         (count (and (= (length elements) 2)
                     (syntax-atom (second elements)))))
    (unless (and count (integerp count) (plusp count))
      (fail 'invalid-declaration-error
            "Lifecycle ~A must be (days N), (months N), or (years N) with a positive integer N."
            what))
    (let ((unit (identifier-key (first elements))))
      (cond
        ((string= unit "days") count)
        ((string= unit "months") (* 30 count))
        ((string= unit "years") (* 365 count))
        (t
         (fail 'invalid-declaration-error
               "Lifecycle ~A unit must be days, months, or years, received ~S."
               what unit))))))

(defun lifecycle-sub-options (value what)
  "Parse a closed positional sub-form such as (tier warm replication regional)
into a plist of keyword keys and raw values."
  (let ((elements (syntax-elements value)))
    (when (oddp (length elements))
      (fail 'invalid-declaration-error
            "Lifecycle ~A must alternate closed keys and values." what))
    (let ((seen '()))
      (loop for (key value) on elements by #'cddr
            collect (let ((normalized-key
                            (intern (string-upcase (identifier-key key))
                                    :keyword)))
                      (when (member normalized-key seen :test #'eq)
                        (fail 'invalid-declaration-error
                              "Lifecycle ~A declares ~S more than once."
                              what normalized-key))
                      (push normalized-key seen)
                      (cons normalized-key value))
              into pairs
          finally (return (mapcan (lambda (pair) (list (car pair) (cdr pair)))
                                  pairs))))))

(defun lifecycle-required-sub-value (sub key what)
  (or (getf sub key)
      (fail 'invalid-declaration-error
            "Lifecycle ~A requires ~S." what key)))

(defun compile-lifecycle-transition (row states events library-name local-types)
  (with-star-source-position (row)
    (ensure-plist row "lifecycle transition")
    (validate-lifecycle-option-keys
     row +lifecycle-transition-option-keys+ "transition")
    (flet ((declared-state (value)
             (let ((name (identifier-string value)))
               (if (member name states :test #'string=)
                   name
                   (fail 'invalid-declaration-error
                         "Lifecycle transition references undeclared state ~S."
                         name))))
           (declared-event (value)
             (let ((name (identifier-string value)))
               (if (member name events :test #'string=)
                   name
                   (fail 'invalid-declaration-error
                         "Lifecycle transition references undeclared event ~S."
                         name)))))
      (let* ((guard (optional-option row :guard))
             (action-value (optional-option row :action))
             (emit (optional-option row :emit))
             (supersedes (optional-option row :supersedes)))
        (append (list :from (declared-state (required-option row :from
                                                           "lifecycle transition"))
                      :on (declared-event (required-option row :on
                                                           "lifecycle transition"))
                      :to (declared-state (required-option row :to
                                                           "lifecycle transition")))
                (when guard
                  (list :guard (identifier-string guard)))
                (list :action (if action-value
                                  (lifecycle-closed-keyword
                                   action-value +lifecycle-actions+
                                   "transition action")
                                  :keep))
                (when emit
                  (list :emit (declared-event emit)))
                (when supersedes
                  (list :supersedes
                        (normalize-type-expression
                         supersedes library-name local-types))))))))

(defun compile-lifecycle (declaration library-name local-types)
  (destructuring-bind (operator name options &rest trailing)
      (syntax-elements declaration)
    (declare (ignore operator))
    (when trailing
      (fail 'invalid-declaration-error
            "Expected (lifecycle name (...options...))."))
    (ensure-plist options "lifecycle")
    (validate-lifecycle-option-keys options +lifecycle-option-keys+ "policy")
    (let* ((lifecycle-name (identifier-string name))
           (version-value (syntax-atom
                           (required-option options :version "lifecycle")))
           (applies (normalize-type-expression
                     (required-option options :applies "lifecycle")
                     library-name local-types))
           (states
             (mapcar #'identifier-string
                     (syntax-elements
                      (required-option options :states "lifecycle"))))
           (initial (identifier-string
                     (required-option options :initial "lifecycle")))
           (events
             (mapcar #'identifier-string
                     (syntax-elements
                      (required-option options :events "lifecycle"))))
           (transitions-value (required-option options :transitions "lifecycle"))
           (retention-value (optional-option options :retention))
           (storage-value (optional-option options :storage))
           (ttl-value (optional-option options :ttl))
           (indexing-value (optional-option options :indexing))
           (encryption-value (optional-option options :encryption))
           (hold-value (optional-option options :hold)))
      (unless (and (integerp version-value) (plusp version-value))
        (fail 'invalid-declaration-error
              "Lifecycle version must be a positive integer, received ~S."
              version-value))
      (unless (member initial states :test #'string=)
        (fail 'invalid-declaration-error
              "Lifecycle initial state ~S is not a declared state." initial))
      (when retention-value
        (let ((elements (syntax-elements retention-value)))
          (unless (and (= (length elements) 2)
                       (string= (identifier-key (first elements)) "evidence"))
            (fail 'invalid-declaration-error
                  "Lifecycle retention must be (evidence <duration>)."))))
      (let ((storage
              (and storage-value
                   (let ((sub (lifecycle-sub-options storage-value
                                                     "storage")))
                     (list :tier (lifecycle-closed-keyword
                                  (lifecycle-required-sub-value sub :tier
                                                                "storage")
                                  +lifecycle-storage-tiers+
                                  "storage tier")
                           :replication
                           (lifecycle-closed-keyword
                            (lifecycle-required-sub-value sub :replication
                                                          "storage")
                            +lifecycle-replication-classes+
                            "storage replication class")))))
            (indexing
              (and indexing-value
                   (let ((sub (lifecycle-sub-options indexing-value
                                                     "indexing")))
                     (list :mode
                           (lifecycle-closed-keyword
                            (lifecycle-required-sub-value sub :mode
                                                          "indexing")
                            +lifecycle-indexing-modes+
                            "indexing mode")))))
            (encryption
              (and encryption-value
                   (let ((sub (lifecycle-sub-options encryption-value
                                                     "encryption")))
                     (list :class
                           (lifecycle-closed-keyword
                            (lifecycle-required-sub-value sub :class
                                                          "encryption")
                            +lifecycle-encryption-classes+
                            "encryption class")))))
            (hold
              (and hold-value
                   (let ((elements (syntax-elements hold-value)))
                     (unless (= (length elements) 2)
                       (fail 'invalid-declaration-error
                             "Lifecycle hold must be (<class> \"<reason>\")."))
                     (let ((reason (syntax-atom (second elements))))
                       (unless (stringp reason)
                         (fail 'invalid-declaration-error
                               "Lifecycle hold reason must be a string."))
                       (list :class
                             (lifecycle-closed-keyword
                              (first elements) +lifecycle-hold-classes+
                              "hold class")
                             :reason reason))))))
        (let ((transitions
                (mapcar (lambda (row)
                          (compile-lifecycle-transition
                           row states events library-name local-types))
                        (syntax-elements transitions-value))))
          (validate-lifecycle-graph transitions states initial)
          (dolist (row transitions)
            (when (and (eq (getf row :action) :destroy)
                       (or retention-value hold-value))
              (with-star-source-position (declaration)
                (fail 'invalid-declaration-error
                      "Lifecycle transition from ~S on ~S is unsafe: action destroy erases provenance and event history while evidence retention or a legal hold applies; use redact or tombstone."
                      (getf row :from) (getf row :on)))))
          (let ((lifecycle
                  (list :kind :lifecycle
                        :name lifecycle-name
                        :qualified-name (qualify-name library-name
                                                      lifecycle-name)
                        :applies applies
                        :version version-value
                        :initial initial
                        :states states
                        :events events
                        :transitions transitions)))
            (when retention-value
              (setf lifecycle
                    (append lifecycle
                            (list :retention
                                  (list :evidence-days
                                        (lifecycle-duration-days
                                         (second (syntax-elements
                                                  retention-value))
                                         "retention"))))))
            (when ttl-value
              (setf lifecycle
                    (append lifecycle
                            (list :ttl-days
                                  (lifecycle-duration-days ttl-value "ttl")))))
            (when storage
              (setf lifecycle (append lifecycle (list :storage storage))))
            (when indexing
              (setf lifecycle (append lifecycle (list :indexing indexing))))
            (when encryption
              (setf lifecycle (append lifecycle (list :encryption encryption))))
            (when hold
              (setf lifecycle (append lifecycle (list :hold hold))))
            lifecycle))))))

(defun validate-lifecycle-graph (transitions states initial)
  "Reject ambiguous (from, event) pairs and states unreachable from the
initial state; every declared state must be reachable so the transition table
is a total replay function over its event vocabulary."
  (let ((seen '()))
    (dolist (row transitions)
      (let ((key (cons (getf row :from) (getf row :on))))
        (when (member key seen :test #'equal)
          (fail 'invalid-declaration-error
                "Lifecycle is ambiguous: transition from ~S on ~S is declared more than once."
                (getf row :from) (getf row :on)))
        (push key seen))))
  (labels ((successors (state)
             (loop for row in transitions
                   when (string= (getf row :from) state)
                     collect (getf row :to)))
           (walk (state visited)
             (if (member state visited :test #'string=)
                 visited
                 (reduce (lambda (acc next) (walk next acc))
                         (successors state)
                         :initial-value (cons state visited)))))
    (let ((reachable (walk initial '())))
      (dolist (state states)
        (unless (member state reachable :test #'string=)
          (fail 'invalid-declaration-error
                "Lifecycle state ~S is unreachable from initial state ~S."
                state initial))))))

(defun emit-lifecycle-manifest (lifecycle)
  "Emit the deterministic, server-consumable lifecycle manifest for compiled
lifecycle IR. The manifest is runtime-neutral wire data: no handler
identities, no backend bindings, no wall-clock values."
  (unless (and (listp lifecycle) (eq (getf lifecycle :kind) :lifecycle))
    (fail 'invalid-declaration-error
          "Lifecycle manifest requires compiled lifecycle IR."))
  (list :wire-version 1 :lifecycle lifecycle))

(defun lifecycle-transition-table (lifecycle)
  "Return the deterministic transition table of compiled lifecycle IR: one
fully resolved row per declared transition in declared order."
  (unless (and (listp lifecycle) (eq (getf lifecycle :kind) :lifecycle))
    (fail 'invalid-declaration-error
          "Lifecycle transition table requires compiled lifecycle IR."))
  (copy-tree (getf lifecycle :transitions)))
