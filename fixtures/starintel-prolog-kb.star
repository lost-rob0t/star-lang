(prolog-kb "org.starintel/prolog-kb@1"
  (:version "1.0.0"
   :runtime tek9
   :persistence persistent
   :protocol "star.logic.prolog/1")

  (schema starintel-core
    (:source "org.starintel/core@1"
     :version "1.0.0"))

  ;; Every StarIntel schema field already receives field/<fieldName>.
  ;; These are additional compound/path indexes declared by the KB.
  (index userByPlatform
    (:source user
     :fields (platform username)
     :kind auto))

  (index externalProvider
    (:source document
     :fields ((externalIds provider))
     :kind multi))

  (prolog graph-rules
    (:source "starintel/graph-rules"
     :kind rules)
    ":- table reachable/2.

reachable(A, B) :-
    star_relation(_, A, _, B).

reachable(A, C) :-
    star_relation(_, A, _, B),
    reachable(B, C)."))