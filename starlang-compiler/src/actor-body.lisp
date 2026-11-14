;;;; Native StarLang actor/domain body lowering (issue #69).
;;;;
;;;; A closed first behavior surface lowers to runtime-neutral, data-only
;;;; body IR: state declarations plus typed message handlers. No host READ
;;;; or EVAL ever touches body source: .star bodies arrive as closed-syntax
;;;; objects; trusted host forms (compatibility composition) arrive as
;;;; plain lists. Both normalize to tagged body nodes before lowering so
;;;; identifiers never collapse into string literals.
;;;;
;;;; Body declarations: (state (slot type [:initial literal]
;;;;                              [:persistence class])*)
;;;;                 (on type (message context) expression*)
;;;; Keyed domain handlers bind (key message context).
;;;;
;;;; Expressions: literals, references, (field e name), (let ((n e)*) e*),
;;;; (if c a b), (when c e*), (unless c e*), (construct T (f e)*),
;;;; (reply e), (fail code message), (set slot e), (send t e), (ask t e).

(in-package #:star-lang.compiler.core)

(define-condition invalid-actor-body-error (invalid-actor-error) ())

(defun fail-body (control &rest arguments)
  (apply #'fail 'invalid-actor-body-error control arguments))

(defparameter *state-slot-primitive-types*
  '("integer" "string" "boolean" "decimal"))

(defparameter *state-persistence-classes*
  '(:ephemeral :journaled :owned-document :shared-readonly))

;;; -------------------------------------------------- tagged body nodes

(defun body-node-from-syntax (syntax)
  "Tag one closed-syntax node for body lowering without invoking the host
reader. Identifiers stay distinguishable from string literals."
  (ecase (star-syntax-kind syntax)
    (:identifier (list :name (star-syntax-datum syntax)))
    (:string (list :lit (star-syntax-datum syntax)))
    (:integer (list :lit (star-syntax-datum syntax)))
    (:boolean (list :lit (star-syntax-datum syntax)))
    (:keyword (list :kw (star-syntax-datum syntax)))
    (:list (list :form (mapcar #'body-node (star-syntax-children syntax))))))

(defun body-node (form)
  "Normalize one body form from closed syntax or a trusted host form into a
tagged body node: (:name s) | (:lit v) | (:kw k) | (:form node*)."
  (cond
    ((star-syntax-p form) (body-node-from-syntax form))
    ((consp form) (list :form (mapcar #'body-node form)))
    ((keywordp form) (list :kw form))
    ((symbolp form)
     (if (or (eq form t) (eq form nil))
         (list :lit (if form t nil))
         (list :name (string-downcase (symbol-name form)))))
    ((stringp form) (list :lit form))
    ((integerp form) (list :lit form))
    (t
     (fail-body "Body forms must be closed-syntax objects or trusted host \
lists, received ~S." form))))

(defun body-node-head (node)
  "Return the lowercase head name of a (:form ...) node whose head is an
identifier, or NIL."
  (let ((first (first (second node))))
    (when (and (consp first) (eq (first first) :name))
      (string-downcase (second first)))))

(defun body-identifier-node (node context)
  (unless (and (consp node) (eq (first node) :name))
    (fail-body "~A requires an identifier, received ~S." context (untag-node node)))
  (second node))

(defun body-literal-node (node context)
  (unless (and (consp node) (eq (first node) :lit))
    (fail-body "~A requires a literal, received ~S." context (untag-node node)))
  (let ((value (second node)))
    (unless (or (stringp value) (integerp value) (null value) (eq value t))
      (fail-body "~A requires a string, integer, or boolean literal, received ~S."
                 context value))
    value))

(defun untag-node (node)
  "Render a tagged node back to plain data for diagnostics only."
  (if (consp node)
      (ecase (first node)
        (:name (second node))
        (:lit (second node))
        (:kw (second node))
        (:form (mapcar #'untag-node (second node))))
      node))

;;; --------------------------------------------------- state declarations

(defun state-slot-default-initial (type)
  (cond
    ((string= type "integer") 0)
    ((string= type "string") "")
    ((string= type "boolean") nil)
    ((string= type "decimal") 0)
    (t (fail-body "Unknown state slot primitive type ~S." type))))

(defun state-slot-initial-type-valid-p (type value)
  (cond
    ((string= type "integer") (integerp value))
    ((string= type "string") (stringp value))
    ((string= type "boolean") (null value))
    ((string= type "decimal") (integerp value))
    (t nil)))

(defun persistence-class-keyword (name)
  (cond
    ((string= name "ephemeral") :ephemeral)
    ((string= name "journaled") :journaled)
    ((string= name "ownedDocument") :owned-document)
    ((string= name "sharedReadonly") :shared-readonly)
    (t nil)))

(defun normalize-state-slot (node declared context)
  (unless (and (consp node) (eq (first node) :form)
               (>= (length (second node)) 3))
    (fail-body "~A state slot must be (name type [:initial literal] \
[:persistence class])."
               context))
  (let* ((elements (second node))
         (name (body-identifier-node (first elements)
                                     (format nil "~A state slot" context)))
         (type (body-identifier-node (second elements)
                                     (format nil "State slot ~A type" name))))
    (unless (member type *state-slot-primitive-types* :test #'string=)
      (fail-body "State slot ~A has unknown primitive type ~S." name type))
    (let ((initial-p nil)
          (initial nil)
          (persistence :ephemeral)
          (options (cddr elements)))
      (loop while options
            do (progn
                 (unless (and (consp (first options))
                              (eq (first (first options)) :kw))
                   (fail-body "State slot ~A requires keyword options." name))
                 (let ((key (second (first options))))
                   (unless (member key '(:initial :persistence))
                     (fail-body "State slot ~A has unknown option ~S." name key))
                   (unless (rest options)
                     (fail-body "State slot ~A option ~A requires a value." name key))
                   (case key
                     (:initial
                      (setf initial-p t
                            initial (body-literal-node
                                     (second options)
                                     (format nil "State slot ~A :initial" name))))
                     (:persistence
                      (let* ((class-name
                               (body-identifier-node
                                (second options)
                                (format nil "State slot ~A :persistence" name)))
                             (class (persistence-class-keyword class-name)))
                        (unless class
                          (fail-body
                           "State slot ~A has unknown persistence class ~S."
                           name class-name))
                        (setf persistence class)))))
                 (setf options (cddr options))))
      (unless initial-p
        (setf initial (state-slot-default-initial type)))
      (unless (state-slot-initial-type-valid-p type initial)
        (fail-body "State slot ~A initial value ~S does not match type ~A."
                   name initial type))
      (when (assoc name declared :test #'string=)
        (fail-body "Duplicate state slot ~A." name))
      (cons name
            (list :name name
                  :type type
                  :initial initial
                  :persistence persistence)))))

(defun normalize-state-declaration (node context)
  (unless (string= (or (body-node-head node) "") "state")
    (fail-body "Expected a (state ...) declaration."))
  (let ((declared '()))
    (dolist (slot (rest (second node)))
      (let ((entry (normalize-state-slot slot declared context)))
        (push entry declared)))
    (nreverse declared)))

;;; ------------------------------------------------- handler declarations

(defun normalize-on-declaration (node context)
  (unless (string= (or (body-node-head node) "") "on")
    (fail-body "Expected an (on ...) handler."))
  (let* ((elements (second node)))
    (unless (>= (length elements) 4)
      (fail-body "~A handler must be (on type (vars...) expression...)." context))
    (let ((message-type
            (body-identifier-node (second elements)
                                  (format nil "~A handler type" context)))
          (vars (third elements)))
      (unless (and (consp vars) (eq (first vars) :form))
        (fail-body "~A handler bindings must be a list." context))
      (values message-type
              (mapcar (lambda (var)
                        (body-identifier-node var "handler binding"))
                      (second vars))))))

;;; ---------------------------------------------------- body expressions

(defun body-expression (node state-names bound-vars context)
  "Lower one tagged body expression to data-only body IR. LOCALS are the
in-scope let binding names."
  (labels ((lower (node locals)
             (ecase (first node)
               (:lit (list :const (body-literal-node node context)))
               (:name (lower-reference (second node) locals))
               (:kw (fail-body "~A does not accept keyword ~S in expression \
position." context (second node)))
               (:form (lower-form node locals))))
           (lower-reference (name locals)
             (cond
               ((member name bound-vars :test #'string=)
                (list :context name))
               ((member name locals :test #'string=)
                (list :local name))
               ((member name state-names :test #'string=)
                (list :state-read name))
               (t
                (fail-body "~A references unknown name ~A." context name))))
           (lower-form (node locals)
             (let ((head (body-node-head node)))
               (unless head
                 (fail-body "~A body expression head must be an identifier."
                            context))
               (let ((elements (second node)))
                 (cond
                   ((string= head "field")
                    (require-arity elements 3 "field access")
                    (list :field
                          (lower (second elements) locals)
                          (body-identifier-node (third elements) "field name")))
                   ((string= head "let")
                    (lower-let elements locals))
                   ((string= head "if")
                    (require-arity elements 4 "if")
                    (list :if
                          (lower (second elements) locals)
                          (lower (third elements) locals)
                          (lower (fourth elements) locals)))
                   ((string= head "when")
                    (require-min-arity elements 3 "when")
                    (list :if
                          (lower (second elements) locals)
                          (cons :do (lower-body (cddr elements) locals))
                          (list :const nil)))
                   ((string= head "unless")
                    (require-min-arity elements 3 "unless")
                    (list :if
                          (lower (second elements) locals)
                          (list :const nil)
                          (cons :do (lower-body (cddr elements) locals))))
                   ((string= head "construct")
                    (lower-construct elements locals))
                   ((string= head "reply")
                    (require-arity elements 2 "reply")
                    (list :reply (lower (second elements) locals)))
                   ((string= head "fail")
                    (require-arity elements 3 "fail")
                    (let ((code (body-literal-node (second elements) "fail code"))
                          (message
                            (body-literal-node (third elements) "fail message")))
                      (unless (and (stringp code) (plusp (length code)))
                        (fail-body "~A fail code must be a non-empty string."
                                   context))
                      (unless (stringp message)
                        (fail-body "~A fail message must be a string." context))
                      (list :fail code message)))
                   ((string= head "set")
                    (require-arity elements 3 "state write")
                    (let ((slot (body-identifier-node (second elements)
                                                      "state slot")))
                      (unless (member slot state-names :test #'string=)
                        (fail-body "~A writes unknown state slot ~A."
                                   context slot))
                      (list :state-write
                            slot
                            (lower (third elements) locals))))
                   ((string= head "send")
                    (require-arity elements 3 "send")
                    (list :send
                          (lower (second elements) locals)
                          (lower (third elements) locals)))
                   ((string= head "ask")
                    (require-arity elements 3 "ask")
                    (list :ask
                          (lower (second elements) locals)
                          (lower (third elements) locals)))
                   ((string= head "state")
                    (require-arity elements 2 "state read")
                    (lower (second elements) locals))
                   ((member head '("on" "state") :test #'string=)
                    (fail-body "~A declaration ~A cannot nest inside an \
expression." context head))
                   (t
                    (fail-body "~A body form ~A is outside the closed surface."
                               context head))))))
           (lower-let (elements locals)
             (unless (>= (length elements) 3)
               (fail-body "~A let requires bindings and a body." context))
             (let ((bindings (second elements)))
               (unless (and (consp bindings) (eq (first bindings) :form))
                 (fail-body "~A let bindings must be a list." context))
               (let ((lowered '())
                     (names '()))
                 (dolist (binding (second bindings))
                   (unless (and (consp binding) (eq (first binding) :form)
                                (= (length (second binding)) 2))
                     (fail-body "~A let binding must be (name expression)."
                                context))
                   (let ((name (body-identifier-node (first (second binding))
                                                     "let binding")))
                     (when (member name names :test #'string=)
                       (fail-body "Duplicate let binding ~A." name))
                     (when (or (member name state-names :test #'string=)
                               (member name bound-vars :test #'string=)
                               (member name locals :test #'string=))
                       (fail-body "Let binding ~A shadows an existing name."
                                  name))
                     (push (cons name (lower (second (second binding)) locals))
                           lowered)
                     (push name names)))
                 (list :let (nreverse lowered)
                       (cons :do (lower-body (cddr elements)
                                             (append names locals)))))))
           (lower-construct (elements locals)
             (unless (>= (length elements) 2)
               (fail-body "~A construct requires a type and field pairs."
                          context))
             (let ((type (body-identifier-node (second elements)
                                               "constructed type"))
                   (fields '()))
               (dolist (entry (cddr elements))
                 (unless (and (consp entry) (eq (first entry) :form)
                              (= (length (second entry)) 2))
                   (fail-body "Constructed field must be (name expression)."))
                 (let ((name (body-identifier-node (first (second entry))
                                                   "constructed field")))
                   (when (assoc name fields :test #'string=)
                     (fail-body "Duplicate constructed field ~A." name))
                   (push (cons name (lower (second (second entry)) locals))
                         fields)))
               (list :construct type (nreverse fields))))
           (lower-body (nodes locals)
             (mapcar (lambda (node) (lower node locals)) nodes))
           (require-arity (elements count what)
             (unless (= (length elements) count)
               (fail-body "~A ~A requires ~D elements, received ~D."
                          context what count (length elements))))
           (require-min-arity (elements count what)
             (unless (>= (length elements) count)
               (fail-body "~A ~A requires at least ~D elements, received ~D."
                          context what count (length elements)))))
    (lower node '())))

(defun lower-handler-body (expression-nodes state-names bound-vars context)
  (unless expression-nodes
    (fail-body "~A requires at least one expression." context))
  (cons :do
        (mapcar (lambda (node)
                  (body-expression node state-names bound-vars context))
                expression-nodes)))

(defun compile-body-declarations (forms key-var accepted-types normalize-type context)
  "Lower body declaration forms into (VALUES STATES HANDLERS).
ACCEPTED-TYPES are already-normalized accepted message type names;
NORMALIZE-TYPE maps a declared handler type to its normalized name."
  (let* ((nodes (mapcar #'body-node forms))
         (states '())
         (handlers '())
         (handler-types '()))
    (dolist (node nodes)
      (let ((head (and (consp node) (eq (first node) :form)
                       (body-node-head node))))
        (cond
          ((string= (or head "") "state")
           (when states
             (fail-body "~A supports at most one (state ...) declaration."
                        context))
           (setf states (normalize-state-declaration node context)))
          ((string= (or head "") "on")
           (multiple-value-bind (message-type vars)
               (normalize-on-declaration node context)
             (unless (= (length vars) (if key-var 3 2))
               (fail-body "~A handler for ~A must bind ~A."
                          context message-type
                          (if key-var
                              "(key message context)"
                              "(message context)")))
             (let ((normalized (funcall normalize-type message-type))
                   (bound-vars vars))
               (when (member normalized handler-types :test #'string=)
                 (fail-body "Duplicate ~A handler for ~A."
                            context message-type))
               (unless (member normalized accepted-types :test #'string=)
                 (fail-body "~A handles ~A, which is not an accepted type."
                            context message-type))
               (push normalized handler-types)
               (push
                (append
                 (list :message-type normalized
                       :body (lower-handler-body
                              (cdddr (second node))
                              (mapcar #'car states)
                              bound-vars
                              (format nil "~A handler ~A"
                                      context message-type)))
                 (if key-var
                     (list :key-var (first vars)
                           :message-var (second vars)
                           :context-var (third vars))
                     (list :message-var (first vars)
                           :context-var (second vars))))
                handlers)))))))
    (values (mapcar #'cdr states)
            (nreverse handlers))))

(defun ensure-body-covers-accepted-types (accepted-types handler-types context)
  (dolist (accepted accepted-types)
    (unless (member accepted handler-types :test #'string=)
      (fail-body "~A declares accepted type ~A without a handler."
                 context accepted)))
  (values))
