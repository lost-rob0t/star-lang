; Source-design input using the existing actor declaration grammar.
(actor normalizer
  (:runtime native
   :accepts ()
   :produces ()
   :handler normalizeHandler
   :restart permanent
   :mailbox (bounded 32)))
