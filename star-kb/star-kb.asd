(defsystem "star-kb"
  :description "Backend-neutral symbolic catalog and graph knowledge-base port for StarLang actors"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-actor-protocol")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "kb")
     (:file "memory"))))
  :in-order-to ((test-op (test-op "star-kb-tests"))))
