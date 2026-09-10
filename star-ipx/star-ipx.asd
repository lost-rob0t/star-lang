(defsystem "star-ipx"
  :description "Lossless passive HTTP evidence actor pipeline for StarLang"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("starlang-runtime")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "ipx"))))
  :in-order-to ((test-op (test-op "star-ipx-tests"))))
