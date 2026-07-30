(defsystem "star-xlsx"
  :description "XLSX reading and writing for structured ingest"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.0.0"
  :depends-on ()
  :components
  ((:module "src"
    :components
    ((:file "packages"))))
  :in-order-to ((test-op (test-op "star-xlsx-tests"))))
