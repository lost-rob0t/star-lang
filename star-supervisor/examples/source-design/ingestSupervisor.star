; TARGET GRAMMAR: not accepted by the current supervisor frontend.
; Select this root OR serviceRoot, not both in one activation graph.
(supervisor ingestSupervisor
  (:strategy one-for-one
   :restart permanent
   :restart-intensity (3 (seconds 10))
   :backoff (fixed (milliseconds 250))
   :shutdown (drain (seconds 5))
   :children (fetcher normalizer oneShot)))
