(defsystem "star-fetch"
  :description "Bounded actor-native generic HTTP fetching with TTL/LRU caching"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-http-port" "starlang-runtime")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "fetch"))))
  :in-order-to ((test-op (test-op "star-fetch-tests"))))
