(defsystem "star-github"
  :description "GitHub target actor backed by StarIntel target documents and JSON artifact persistence"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-artifact"
               "star-canonical-json"
               "starlang-runtime"
               "uiop"
               "yason")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "github-actor")
     (:file "github-graph"))))
  :in-order-to ((test-op (test-op "star-github-tests"))))
