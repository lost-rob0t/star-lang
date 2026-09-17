(defsystem "starlang-loader"
  :description "Final digest-locked StarLang specification loader"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "1.0.0"
  :depends-on ("starlang-compiler" "ironclad" "dexador" "quri")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "loader"))))
  :in-order-to ((test-op (test-op "starlang-loader-tests"))))
