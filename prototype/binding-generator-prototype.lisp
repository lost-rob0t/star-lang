;;;; Compatibility re-export only.
;;;; Portable binding generation is final-owned by starlang-compiler.

(in-package #:star-lang.core-surface.prototype)

(export '(generate-python-bindings generate-typescript-bindings))

;; core-surface-prototype imports these exact final compiler symbols. Defining
;; forwarding functions here would replace their implementations with recursive
;; calls to themselves. The imported definitions already provide compatibility.
