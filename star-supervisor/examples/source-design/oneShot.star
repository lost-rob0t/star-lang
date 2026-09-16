; Source-design input: this child never automatically restarts.
(actor oneShot
  (:runtime native
   :accepts ()
   :produces ()
   :handler oneShotHandler
   :restart temporary
   :mailbox (bounded 8)))
