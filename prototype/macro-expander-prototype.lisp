(in-package #:star-lang.core-surface.prototype)

(export '(collect-star-macro-environment
          expanded-star-source
          expand-star-syntax-1
          invalid-macro-error
          macro-context-error
          macro-expansion-error
          macro-limit-error
          make-star-expansion-limits
          merge-star-macro-environments
          star-expansion-limits
          star-expansion-trace
          star-macro-dependencies
          star-macro-environment))

(define-condition invalid-macro-error (star-lang-core-error) ())
(define-condition macro-context-error (star-lang-core-error) ())
(define-condition macro-expansion-error (star-lang-core-error) ())
(define-condition macro-limit-error (star-lang-core-error) ())

(defstruct (star-expansion-limits
             (:constructor make-star-expansion-limits
                 (&key
                    (depth 64)
                    (invocations 1000)
                    (generated-nodes 100000)
                    (pattern-steps 100000)
                    (repetition-output 10000)
                    (origin-depth 64)
                    (macro-definitions 1000))))
  depth
  invocations
  generated-nodes
  pattern-steps
  repetition-output
  origin-depth
  macro-definitions)

(defstruct star-macro-rule
  id
  pattern
  template
  span)

(defstruct star-macro-definition
  name
  qualified-name
  format
  context
  literals
  rules
  span
  origin
  library-name
  library-version
  library-digest)

(defstruct (star-macro-environment
             (:constructor %make-star-macro-environment (definitions)))
  (definitions nil :read-only t))

(defvar *declarative-macro-expander-loaded* t)

(defun macro-atom-name (syntax)
  (let ((datum (syntax-atom syntax)))
    (etypecase datum
      (string datum)
      (symbol (string-downcase (symbol-name datum))))))

(defun macro-pattern-variable-name (syntax)
  (when (and (star-syntax-p syntax)
             (eq (star-syntax-kind syntax) :identifier))
    (let ((name (star-syntax-datum syntax)))
      (when (and (> (length name) 1) (char= (char name 0) #\?))
        name))))

(defun macro-ellipsis-p (syntax)
  (and (star-syntax-p syntax)
       (eq (star-syntax-kind syntax) :identifier)
       (string= (star-syntax-datum syntax) "...")))

(defun macro-option (options key &optional required-p)
  (unless (syntax-list-p options)
    (fail 'invalid-macro-error "Macro options must be a property list."))
  (let ((children (star-syntax-children options)))
    (unless (evenp (length children))
      (fail 'invalid-macro-error "Macro options must be a property list."))
    (loop for (candidate value) on children by #'cddr
          when (and (eq (star-syntax-kind candidate) :keyword)
                    (eq (star-syntax-datum candidate) key))
            return value
          finally
             (when required-p
               (fail 'invalid-macro-error
                     "Macro declaration requires option ~S." key)))))

(defun macro-root-parts (syntax)
  (let ((children (syntax-elements syntax)))
    (if (string= (or (syntax-head-name syntax) "") "spec-library")
        (values (subseq children 0 (min 3 (length children)))
                (nthcdr 3 children)
                :spec-library)
        (values nil children :program))))

(defun macro-library-metadata (syntax root-kind)
  (if (eq root-kind :spec-library)
      (let* ((children (syntax-elements syntax))
             (name-node (second children))
             (options (third children))
             (version (macro-option options :version t))
             (digest (macro-option options :digest nil)))
        (values (syntax-atom name-node)
                (syntax-atom version)
                (and digest (syntax-atom digest))))
      (values "<program>" "1" nil)))

(defun macro-pattern-variables (syntax)
  (let ((variables '()))
    (labels ((walk (node)
               (let ((name (macro-pattern-variable-name node)))
                 (when name (pushnew name variables :test #'string=)))
               (when (syntax-list-p node)
                 (dolist (child (star-syntax-children node))
                   (walk child)))))
      (walk syntax))
    (nreverse variables)))

(defun validate-macro-ellipsis-shape (syntax context)
  (when (syntax-list-p syntax)
    (let ((children (star-syntax-children syntax)))
      (loop for child in children
            for position from 0
            when (macro-ellipsis-p child)
              do (unless (and (> position 0)
                              (= position (1- (length children))))
                   (fail 'invalid-macro-error
                         "~A repetition uses ... only after the final list item."
                         context)))
      (dolist (child children)
        (validate-macro-ellipsis-shape child context)))))

(defun parse-star-macro-rule (syntax ordinal)
  (with-star-source-position (syntax)
    (unless (and (syntax-list-p syntax)
                 (= (length (star-syntax-children syntax)) 2))
      (fail 'invalid-macro-error
            "Each macro rule must contain exactly one pattern and one template."))
    (let* ((pattern (first (star-syntax-children syntax)))
           (template (second (star-syntax-children syntax)))
           (pattern-variables (macro-pattern-variables pattern)))
      (unless (syntax-list-p pattern)
        (fail 'invalid-macro-error "Macro rule patterns must be lists."))
      (validate-macro-ellipsis-shape pattern "Macro pattern")
      (validate-macro-ellipsis-shape template "Macro template")
      (dolist (variable (macro-pattern-variables template))
        (unless (member variable pattern-variables :test #'string=)
          (fail 'invalid-macro-error
                "Macro template references unbound pattern variable ~A."
                variable)))
      (make-star-macro-rule
       :id (format nil "rule-~D" ordinal)
       :pattern pattern
       :template template
       :span (star-syntax-span syntax)))))

(defun parse-star-macro-definition (syntax library-name library-version
                                    library-digest)
  (with-star-source-position (syntax)
    (unless (and (syntax-list-p syntax)
                 (= (length (star-syntax-children syntax)) 3)
                 (string= (or (syntax-head-name syntax) "") "macro"))
      (fail 'invalid-macro-error
            "Macro declarations use (macro name (:context declaration :rules ...))."))
    (destructuring-bind (operator name-node options)
        (star-syntax-children syntax)
      (declare (ignore operator))
      (let* ((name (macro-atom-name name-node))
             (format-node (macro-option options :format nil))
             (format (if format-node (syntax-atom format-node) 1))
             (context-node (macro-option options :context t))
             (context-name (macro-atom-name context-node))
             (rules-node (macro-option options :rules t))
             (literals-node (macro-option options :literals nil)))
        (unless (and (integerp format) (= format 1))
          (fail 'invalid-macro-error
                "Macro ~A requires declarative macro format 1." name))
        (unless (string= context-name "declaration")
          (fail 'invalid-macro-error
                "Macro ~A uses unsupported context ~A; V1 supports declaration only."
                name context-name))
        (unless (and (syntax-list-p rules-node)
                     (star-syntax-children rules-node))
          (fail 'invalid-macro-error "Macro ~A requires at least one rule." name))
        (when (and literals-node (not (syntax-list-p literals-node)))
          (fail 'invalid-macro-error "Macro literals must be a list."))
        (make-star-macro-definition
         :name name
         :qualified-name (format nil "~A/~A" library-name name)
         :format format
         :context :declaration
         :literals
         (if literals-node
             (mapcar #'macro-atom-name (star-syntax-children literals-node))
             '())
         :rules
         (loop for rule in (star-syntax-children rules-node)
               for ordinal from 1
               collect (parse-star-macro-rule rule ordinal))
         :span (star-syntax-span syntax)
         :origin (star-syntax-origin syntax)
         :library-name library-name
         :library-version library-version
         :library-digest library-digest)))))

(defun merge-star-macro-environments (&rest environments)
  (let ((definitions '()))
    (dolist (environment environments)
      (when environment
        (dolist (definition (star-macro-environment-definitions environment))
          (let ((existing
                  (find (star-macro-definition-name definition) definitions
                        :key #'star-macro-definition-name :test #'string=)))
            (when existing
              (if (and
                   (string=
                    (star-macro-definition-qualified-name existing)
                    (star-macro-definition-qualified-name definition))
                   (equal (star-macro-definition-library-digest existing)
                          (star-macro-definition-library-digest definition)))
                  (setf definition nil)
                  (let ((*star-current-syntax* nil)
                        (*star-current-phase* :expand))
                    (fail 'invalid-macro-error
                          "Macro name collision for ~A between ~A and ~A."
                          (star-macro-definition-name definition)
                          (star-macro-definition-qualified-name existing)
                          (star-macro-definition-qualified-name definition)))))
            (when definition
              (setf definitions (append definitions (list definition))))))))
    (%make-star-macro-environment definitions)))

(defun collect-star-macro-environment
    (syntax &key environment limits
                  ((:library-name locked-library-name) nil library-name-p)
                  ((:library-version locked-library-version) nil library-version-p)
                  ((:library-digest locked-library-digest) nil library-digest-p))
  (unless (star-syntax-p syntax)
    (fail 'invalid-macro-error
          "Macro collection requires a StarLang syntax object."))
  (multiple-value-bind (prefix declarations root-kind)
      (macro-root-parts syntax)
    (declare (ignore prefix))
    (multiple-value-bind (library-name library-version library-digest)
        (macro-library-metadata syntax root-kind)
      (when library-name-p (setf library-name locked-library-name))
      (when library-version-p (setf library-version locked-library-version))
      (when library-digest-p (setf library-digest locked-library-digest))
      (let ((definitions
              (loop for declaration in declarations
                    when (string= (or (syntax-head-name declaration) "") "macro")
                      collect
                      (parse-star-macro-definition
                       declaration library-name library-version library-digest))))
        (when (> (length definitions)
                 (star-expansion-limits-macro-definitions
                  (or limits (make-star-expansion-limits))))
          (fail 'macro-limit-error
                "Macro definition count exceeds the configured limit."))
        (merge-star-macro-environments
         environment (%make-star-macro-environment definitions))))))

(defun macro-syntax-equal-p (left right)
  (equal (star-syntax-to-datum left) (star-syntax-to-datum right)))

(defun macro-binding (name bindings)
  (assoc name bindings :test #'string=))

(defun bind-macro-variable (name value bindings)
  (let ((existing (macro-binding name bindings)))
    (cond
      ((null existing) (values t (acons name value bindings)))
      ((and (star-syntax-p (cdr existing))
            (macro-syntax-equal-p (cdr existing) value))
       (values t bindings))
      (t (values nil bindings)))))

(defun merge-repeated-bindings (bindings local variables)
  (dolist (variable variables bindings)
    (let* ((entry (macro-binding variable local))
           (value (and entry (cdr entry)))
           (existing (macro-binding variable bindings)))
      (cond
        ((and existing (star-syntax-p (cdr existing)))
         (fail 'invalid-macro-error
               "Pattern variable ~A appears in both repeated and non-repeated positions."
               variable))
        (existing
         (setf (cdr existing) (append (cdr existing) (list value))))
        (t
         (push (cons variable (list value)) bindings))))))

(defun match-macro-pattern (pattern input bindings state)
  (incf (getf state :pattern-steps))
  (when (> (getf state :pattern-steps)
           (star-expansion-limits-pattern-steps (getf state :limits)))
    (fail 'macro-limit-error
          "Macro pattern matching exceeds the configured work limit."))
  (let ((variable (macro-pattern-variable-name pattern)))
    (cond
      (variable (bind-macro-variable variable input bindings))
      ((and (syntax-list-p pattern) (syntax-list-p input))
       (match-macro-pattern-list
        (star-syntax-children pattern) (star-syntax-children input)
        bindings state))
      ((or (syntax-list-p pattern) (syntax-list-p input))
       (values nil bindings))
      ((and (eq (star-syntax-kind pattern) (star-syntax-kind input))
            (equal (star-syntax-datum pattern) (star-syntax-datum input)))
       (values t bindings))
      (t (values nil bindings)))))

(defun match-macro-pattern-list (patterns inputs bindings state)
  (let* ((count (length patterns))
         (repeated-p (and (>= count 2)
                          (macro-ellipsis-p (nth (1- count) patterns))))
         (prefix-count (if repeated-p (- count 2) count)))
    (when (if repeated-p
              (< (length inputs) prefix-count)
              (/= (length inputs) count))
      (return-from match-macro-pattern-list (values nil bindings)))
    (loop for index below prefix-count
          do (multiple-value-bind (matched updated)
                 (match-macro-pattern (nth index patterns) (nth index inputs)
                                      bindings state)
               (unless matched
                 (return-from match-macro-pattern-list
                   (values nil bindings)))
               (setf bindings updated)))
    (when repeated-p
      (let* ((fragment (nth prefix-count patterns))
             (variables (macro-pattern-variables fragment)))
        (dolist (variable variables)
          (unless (macro-binding variable bindings)
            (push (cons variable nil) bindings)))
        (dolist (input (nthcdr prefix-count inputs))
          (multiple-value-bind (matched local)
              (match-macro-pattern fragment input nil state)
            (unless matched
              (return-from match-macro-pattern-list (values nil bindings)))
            (setf bindings
                  (merge-repeated-bindings bindings local variables))))))
    (values t bindings)))

(defun select-macro-rule (definition invocation state)
  (let ((matches '()))
    (dolist (rule (star-macro-definition-rules definition))
      (multiple-value-bind (matched bindings)
          (match-macro-pattern
           (star-macro-rule-pattern rule) invocation nil state)
        (when matched (push (cons rule bindings) matches))))
    (setf matches (nreverse matches))
    (cond
      ((null matches)
       (fail 'macro-expansion-error
             "No rule of macro ~A matches this invocation."
             (star-macro-definition-qualified-name definition)))
      ((rest matches)
       (fail 'macro-expansion-error
             "Macro ~A invocation ambiguously matches rules ~{~A~^, ~}."
             (star-macro-definition-qualified-name definition)
             (mapcar (lambda (match)
                       (star-macro-rule-id (car match)))
                     matches)))
      (t (values (caar matches) (cdar matches))))))

(defun repeated-template-count (fragment bindings)
  (let ((counts
          (loop for variable in (macro-pattern-variables fragment)
                for entry = (macro-binding variable bindings)
                when (and entry (listp (cdr entry)))
                  collect (length (cdr entry)))))
    (unless counts
      (fail 'invalid-macro-error
            "Repeated macro template fragment has no repeated pattern variable."))
    (unless (every (lambda (count) (= count (first counts))) (rest counts))
      (fail 'macro-expansion-error
            "Repeated macro template variables have different lengths."))
    (first counts)))

(defun make-macro-origin (definition rule invocation ordinal)
  (make-star-origin-frame
   :kind :macro-expansion
   :source-id
   (let ((span (star-syntax-span invocation)))
     (and span (star-source-span-source-id span)))
   :library-name (star-macro-definition-library-name definition)
   :library-version (star-macro-definition-library-version definition)
   :library-digest (star-macro-definition-library-digest definition)
   :macro-name (star-macro-definition-qualified-name definition)
   :rule-id (star-macro-rule-id rule)
   :definition-span (star-macro-definition-span definition)
   :invocation-span (star-syntax-span invocation)
   :expansion-ordinal ordinal
   :output-context (star-macro-definition-context definition)
   :parent (star-syntax-origin invocation)))

(defun instantiate-macro-template (template bindings definition rule invocation
                                   ordinal scope state &optional repeat-index)
  (let ((variable (macro-pattern-variable-name template)))
    (when variable
      (let ((entry (macro-binding variable bindings)))
        (unless entry
          (fail 'invalid-macro-error
                "Macro template variable ~A is not bound." variable))
        (let ((value (cdr entry)))
          (cond
            ((star-syntax-p value) (return-from instantiate-macro-template value))
            ((and (listp value) (integerp repeat-index))
             (return-from instantiate-macro-template (nth repeat-index value)))
            (t
             (fail 'invalid-macro-error
                   "Repeated macro variable ~A must appear under ...." variable)))))))
  (incf (getf state :generated-nodes))
  (when (> (getf state :generated-nodes)
           (star-expansion-limits-generated-nodes (getf state :limits)))
    (fail 'macro-limit-error
          "Macro expansion exceeds the configured generated-node limit."))
  (let ((origin (make-macro-origin definition rule invocation ordinal)))
    (if (syntax-list-p template)
        (let ((children (star-syntax-children template))
              (expanded '()))
          (loop for tail on children
                for child = (first tail)
                do (cond
                     ((macro-ellipsis-p child)
                      (fail 'invalid-macro-error
                            "Macro template contains an unattached ...."))
                     ((and (second tail) (macro-ellipsis-p (second tail)))
                      (let ((count (repeated-template-count child bindings)))
                        (incf (getf state :repetition-output) count)
                        (when (> (getf state :repetition-output)
                                 (star-expansion-limits-repetition-output
                                  (getf state :limits)))
                          (fail 'macro-limit-error
                                "Macro expansion exceeds the repetition-output limit."))
                        (dotimes (index count)
                          (push
                           (instantiate-macro-template
                            child bindings definition rule invocation ordinal
                            scope state index)
                           expanded)))
                      (setf tail (rest tail)))
                     (t
                      (push
                       (instantiate-macro-template
                        child bindings definition rule invocation ordinal scope
                        state repeat-index)
                       expanded))))
          (make-star-syntax
           :kind :list
           :children (nreverse expanded)
           :span (star-syntax-span invocation)
           :scopes (copy-list (star-syntax-scopes template))
           :origin origin
           :introduced-by (star-macro-definition-qualified-name definition)))
        (make-star-syntax
         :kind (star-syntax-kind template)
         :datum (star-syntax-datum template)
         :span (star-syntax-span invocation)
         :scopes
         (if (eq (star-syntax-kind template) :identifier)
             (cons scope (remove scope (star-syntax-scopes template)
                                 :test #'string=))
             (copy-list (star-syntax-scopes template)))
         :origin origin
         :introduced-by (star-macro-definition-qualified-name definition)))))

(defun macro-definition-for-head (head environment)
  (and head environment
       (find head (star-macro-environment-definitions environment)
             :key #'star-macro-definition-name :test #'string=)))

(defun macro-definition-form-p (syntax)
  (string= (or (syntax-head-name syntax) "") "macro"))

(defun macro-dependency-map (definition)
  (list :name (star-macro-definition-qualified-name definition)
        :format (star-macro-definition-format definition)
        :library-name (star-macro-definition-library-name definition)
        :library-version (star-macro-definition-library-version definition)
        :library-digest (star-macro-definition-library-digest definition)))

(defun copy-expanded-root (syntax children trace dependencies)
  (make-star-syntax
   :kind :list
   :children children
   :span (star-syntax-span syntax)
   :scopes (copy-list (star-syntax-scopes syntax))
   :origin (star-syntax-origin syntax)
   :introduced-by (star-syntax-introduced-by syntax)
   :expansion-trace trace
   :macro-dependencies dependencies))

(defun expand-star-syntax (syntax &key environment limits expansion-limits)
  "Expand bounded declarative format-1 macros into declaration-context core.

Macro definitions are compile-time data. Pattern arguments retain their
use-site syntax objects; identifiers copied from templates receive a fresh,
deterministic introduction scope and a source-located macro origin frame."
  (unless (star-syntax-p syntax)
    (fail 'invalid-declaration-error
          "Expansion requires a StarLang syntax object."))
  (let* ((parser-limits
           (if (star-parser-limits-p limits) limits (make-star-parser-limits)))
         (effective-limits
           (or expansion-limits
               (and (star-expansion-limits-p limits) limits)
               (make-star-expansion-limits)))
         (*star-current-phase* :expand)
         (state (list :limits effective-limits
                      :pattern-steps 0 :generated-nodes 0
                      :repetition-output 0))
         (local-environment
           (collect-star-macro-environment
            syntax :environment environment :limits effective-limits))
         (trace '())
         (used '())
         (invocations 0)
         (input-nodes 0))
    (labels
        ((check-input (node depth)
           (incf input-nodes)
           (when (> input-nodes (star-parser-limits-node-count parser-limits))
             (fail 'macro-limit-error
                   "Expansion input exceeds the configured syntax-node limit."))
           (when (> depth (star-parser-limits-nesting-depth parser-limits))
             (fail 'macro-limit-error
                   "Expansion input exceeds the configured nesting-depth limit."))
           (when (syntax-list-p node)
             (dolist (child (star-syntax-children node))
               (check-input child (1+ depth)))))
         (reject-nested-macro (node)
           (when (and (syntax-list-p node)
                      (macro-definition-for-head
                       (syntax-head-name node) local-environment))
             (with-star-source-position (node)
               (fail 'macro-context-error
                     "Macro ~A is declaration-context only."
                     (syntax-head-name node))))
           (when (and (eq (star-syntax-kind node) :identifier)
                      (macro-pattern-variable-name node))
             (with-star-source-position (node)
               (fail 'invalid-macro-error
                     "Pattern variable ~A remains outside a macro definition."
                     (star-syntax-datum node))))
           (when (syntax-list-p node)
             (dolist (child (star-syntax-children node))
               (reject-nested-macro child))))
         (expand-declaration (declaration depth stack)
           (when (> depth (star-expansion-limits-depth effective-limits))
             (with-star-source-position (declaration)
               (fail 'macro-limit-error
                     "Macro expansion exceeds the configured depth limit.")))
           (let ((definition
                   (macro-definition-for-head
                    (syntax-head-name declaration) local-environment)))
             (if (null definition)
                 (progn (reject-nested-macro declaration) declaration)
                 (let ((qualified
                         (star-macro-definition-qualified-name definition)))
                   (when (member qualified stack :test #'string=)
                     (with-star-source-position (declaration)
                       (fail 'macro-expansion-error
                             "Recursive macro cycle: ~{~A~^ -> ~} -> ~A."
                             (reverse stack) qualified)))
                   (incf invocations)
                   (when (> invocations
                            (star-expansion-limits-invocations effective-limits))
                     (with-star-source-position (declaration)
                       (fail 'macro-limit-error
                             "Macro expansion exceeds the invocation limit.")))
                   (with-star-source-position (declaration)
                     (multiple-value-bind (rule bindings)
                         (select-macro-rule definition declaration state)
                       (let* ((scope (format nil "macro/~A/~D"
                                            qualified invocations))
                              (expanded
                                (instantiate-macro-template
                                 (star-macro-rule-template rule) bindings
                                 definition rule declaration invocations scope
                                 state)))
                         (pushnew definition used
                                  :key #'star-macro-definition-qualified-name
                                  :test #'string=)
                         (push
                          (list :expansion invocations
                                :macro qualified
                                :rule (star-macro-rule-id rule)
                                :scope scope
                                :context :declaration
                                :definition-span
                                (star-source-span-map
                                 (star-macro-definition-span definition))
                                :invocation-span
                                (star-source-span-map
                                 (star-syntax-span declaration)))
                          trace)
                         (expand-declaration
                          expanded (1+ depth) (cons qualified stack))))))))))
      (check-input syntax 1)
      (multiple-value-bind (prefix declarations root-kind)
          (macro-root-parts syntax)
        (declare (ignore root-kind))
        (let* ((core-declarations
                 (remove-if #'macro-definition-form-p declarations))
               (expanded-declarations
                 (mapcar (lambda (declaration)
                           (expand-declaration declaration 1 nil))
                         core-declarations))
               (ordered-trace (nreverse trace))
               (dependencies
                 (mapcar #'macro-dependency-map (nreverse used)))
               (expanded-root
                 (if (and (= (length core-declarations)
                             (length declarations))
                          (every #'eq core-declarations expanded-declarations)
                          (null ordered-trace))
                     syntax
                     (copy-expanded-root
                      syntax (append prefix expanded-declarations)
                      ordered-trace dependencies))))
          (values expanded-root ordered-trace dependencies))))))

(defun expand-star-syntax-1 (syntax &key environment limits expansion-limits)
  "Perform exactly one declaration-context macro expansion step."
  (let* ((effective-limits
           (or expansion-limits
               (and (star-expansion-limits-p limits) limits)
               (make-star-expansion-limits)))
         (*star-current-phase* :expand)
         (macro-environment
           (if (macro-definition-for-head (syntax-head-name syntax) environment)
               environment
               (collect-star-macro-environment
                syntax :environment environment :limits effective-limits)))
         (state (list :limits effective-limits
                      :pattern-steps 0 :generated-nodes 0
                      :repetition-output 0)))
    (labels ((expand-once (invocation definition)
               (with-star-source-position (invocation)
                 (multiple-value-bind (rule bindings)
                     (select-macro-rule definition invocation state)
                   (let* ((scope
                            (format nil "macro/~A/1"
                                    (star-macro-definition-qualified-name
                                     definition)))
                          (expanded
                            (instantiate-macro-template
                             (star-macro-rule-template rule) bindings definition
                             rule invocation 1 scope state))
                          (record
                            (list :expansion 1
                                  :macro
                                  (star-macro-definition-qualified-name definition)
                                  :rule (star-macro-rule-id rule)
                                  :scope scope
                                  :context :declaration
                                  :definition-span
                                  (star-source-span-map
                                   (star-macro-definition-span definition))
                                  :invocation-span
                                  (star-source-span-map
                                   (star-syntax-span invocation))))
                          (dependency (macro-dependency-map definition)))
                     (values expanded record (list dependency)))))))
      (let ((direct
              (macro-definition-for-head
               (syntax-head-name syntax) macro-environment)))
        (when direct
          (return-from expand-star-syntax-1 (expand-once syntax direct))))
      (multiple-value-bind (prefix declarations root-kind)
          (macro-root-parts syntax)
        (declare (ignore root-kind))
        (loop for declaration in declarations
              for index from 0
              for definition =
                (macro-definition-for-head
                 (syntax-head-name declaration) macro-environment)
              when definition
                do (multiple-value-bind (expanded record dependencies)
                       (expand-once declaration definition)
                     (let ((children (append prefix (copy-list declarations))))
                       (setf (nth (+ (length prefix) index) children) expanded)
                       (return-from expand-star-syntax-1
                         (values
                          (copy-expanded-root syntax children (list record)
                                              dependencies)
                          record dependencies)))))
        (values syntax nil nil)))))

(defun star-expansion-trace (syntax &key environment limits expansion-limits)
  (multiple-value-bind (expanded trace)
      (expand-star-syntax syntax :environment environment :limits limits
                         :expansion-limits expansion-limits)
    (declare (ignore expanded))
    trace))

(defun star-macro-dependencies (syntax &key environment limits expansion-limits)
  (if (star-syntax-macro-dependencies syntax)
      (copy-tree (star-syntax-macro-dependencies syntax))
      (multiple-value-bind (expanded trace dependencies)
          (expand-star-syntax syntax :environment environment :limits limits
                             :expansion-limits expansion-limits)
        (declare (ignore expanded trace))
        dependencies)))

(defun write-expanded-star-syntax (syntax stream)
  (case (star-syntax-kind syntax)
    (:list
     (write-char #\( stream)
     (loop for child in (star-syntax-children syntax)
           for first-p = t then nil
           do (unless first-p (write-char #\Space stream))
              (write-expanded-star-syntax child stream))
     (write-char #\) stream))
    (:string
     (write-char #\" stream)
     (loop for character across (star-syntax-datum syntax)
           do (case character
                (#\" (write-string "\\\"" stream))
                (#\\ (write-string "\\\\" stream))
                (#\Newline (write-string "\\n" stream))
                (#\Return (write-string "\\r" stream))
                (#\Tab (write-string "\\t" stream))
                (otherwise (write-char character stream))))
     (write-char #\" stream))
    (:keyword
     (format stream ":~(~A~)" (symbol-name (star-syntax-datum syntax))))
    (:boolean (write-string (if (star-syntax-datum syntax) "true" "false") stream))
    (otherwise (princ (star-syntax-datum syntax) stream))))

(defun expanded-star-source (syntax &key environment limits expansion-limits)
  (let ((expanded
          (expand-star-syntax syntax :environment environment :limits limits
                             :expansion-limits expansion-limits)))
    (with-output-to-string (stream)
      (write-expanded-star-syntax expanded stream))))
