(defsystem "star-http-dexador"
  :description "Synchronous Dexador backend for the StarLang HTTP port"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-http-port"
               "dexador"
               "usocket"
               "cl+ssl"
               "fast-http")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "dexador-client"))))
  :in-order-to ((test-op (test-op "star-http-dexador-tests"))))
