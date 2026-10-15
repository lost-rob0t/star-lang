(defsystem "star-kb-tek9"
  :description "Tek9/LMDB backend for the StarLang symbolic catalog knowledge-base port"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-kb" "tek9")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "tek9-store"))))
  :in-order-to ((test-op (test-op "star-kb-tek9-tests"))))
