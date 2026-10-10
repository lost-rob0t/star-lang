  ;; Proposed successor: a fixed WGS84 bbox with typed coordinate bounds.
  ;; SS11/SS13 alone perform authorized GeoCouch query execution.
  ;; Candidate 0.10.2 only: page size is a bounded wire value, not
  ;; an authorization or storage policy.
  (scalar spatial-query-page-size
    (:base integer
     :minimum 1
     :maximum 1000))

  (document spatial-bounds
    (:persistence transient)
    (west longitude :required)
    (south latitude :required)
    (east longitude :required)
    (north latitude :required))

  (message query-spatial-bbox
    (:fields
     ((dataset string :required)
      (bounds spatial-bounds :required)
      (dtype string :optional)
      (filters map :optional)
      (atTime unix-time :optional)
      (limit spatial-query-page-size :optional)
      (cursor string :optional))))
