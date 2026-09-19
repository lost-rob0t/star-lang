(spec-library "org.starintel/lifecycle-fixtures@1" (:version "1.0.0")
  (document person (:persistence persistent)
    (name string :required)
    (age integer :optional))
  (lifecycle person-lifecycle
    (:applies org.starintel/person@1
     :version 2
     :initial draft
     :states (draft active archived redacted deleted)
     :retention (evidence (years 7))
     :storage (tier warm replication regional)
     :ttl (days 90)
     :indexing (mode full-text)
     :encryption (class sealed)
     :hold (legal "litigation-2026")
     :events (submitted archived redacted tombstoned)
     :transitions (
       (:from draft :on submitted :to active
        :guard submit-guard :emit submitted)
       (:from active :on archived :to archived
        :action archive :emit archived)
       (:from archived :on redacted :to redacted :action redact)
       (:from redacted :on tombstoned :to deleted
        :action tombstone :supersedes org.starintel/person@0)))))
