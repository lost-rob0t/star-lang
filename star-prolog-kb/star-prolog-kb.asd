(defsystem "star-prolog-kb"
  :description "StarLang grammar and Tek9-backed StarIntel Prolog knowledge base"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("starlang-compiler" "star-canonical-json")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "grammar")
     (:file "schema")
     (:file "tek9-store")
     (:file "index-catalog")
     (:file "prolog"))))
  :in-order-to ((test-op (test-op "star-prolog-kb-tests"))))
