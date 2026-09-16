; TARGET GRAMMAR: named nested tree; current prototype remains flat.
; Child order determines rest-for-one recovery order.
(supervisor serviceRoot
  (:strategy rest-for-one
   :restart permanent
   :restart-intensity (2 (minutes 1))
   :shutdown (drain (seconds 10))
   :children (fetchSupervisor normalizer oneShot)))
