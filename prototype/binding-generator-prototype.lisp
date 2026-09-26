;;;; Compatibility forwarding only.
;;;; Portable binding generation is final-owned by starlang-compiler.

(in-package #:star-lang.core-surface.prototype)

(export '(generate-python-bindings generate-typescript-bindings))

(defun generate-python-bindings (manifest)
  (starlangcompiler:generate-python-bindings manifest))

(defun generate-typescript-bindings (manifest)
  (starlangcompiler:generate-typescript-bindings manifest))
