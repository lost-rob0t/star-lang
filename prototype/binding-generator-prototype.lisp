(in-package #:star-lang.core-surface.prototype)

(export '(generate-python-bindings generate-typescript-bindings))

(defun generate-python-bindings (manifest)
  "Compatibility wrapper for the final compiler-owned object generator."
  (starlangcompiler:generate-object-bindings manifest :python))

(defun generate-typescript-bindings (manifest)
  "Compatibility wrapper for the final compiler-owned object generator."
  (starlangcompiler:generate-object-bindings manifest :typescript))
