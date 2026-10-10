  ;; Proposed successor: a fixed WGS84 bbox with typed coordinate bounds.
  ;; SS11/SS13 alone perform authorized GeoCouch query execution.
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
      (limit integer :optional)
      (cursor string :optional))))
