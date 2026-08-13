(defsystem "star-scrape"
  :description "Actor-native HTML scraping plans and optional Common Lisp backends"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-http-port" "starlang-runtime")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "scrape"))))
  :in-order-to ((test-op (test-op "star-scrape-tests"))))
