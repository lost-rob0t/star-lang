; TARGET GRAMMAR: referenced by serviceRoot, not inline duplication.
; Omitted :backoff means none.
(supervisor fetchSupervisor
  (:strategy one-for-one
   :restart permanent
   :restart-intensity (3 (seconds 10))
   :shutdown immediate
   :children (fetcher)))
