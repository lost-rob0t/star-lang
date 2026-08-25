(in-package #:star-lang.core-surface.prototype)

(export '(generate-python-lifecycle-bindings
          generate-typescript-lifecycle-bindings))

(defun generate-python-lifecycle-bindings ()
  (starlangcompiler:generate-python-lifecycle-bindings))

(defun generate-typescript-lifecycle-bindings ()
  (starlangcompiler:generate-typescript-lifecycle-bindings))
