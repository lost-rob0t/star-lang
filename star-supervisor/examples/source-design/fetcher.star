; Source-design input; handler binding is supplied by the host, not evaluated.
(actor fetcher
  (:runtime native
   :accepts ()
   :produces ()
   :handler fetchHandler
   :restart transient
   :mailbox (bounded 32)))
