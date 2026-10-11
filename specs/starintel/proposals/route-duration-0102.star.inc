  ;; 0.10.2 ONLY: this source replaces the frozen route document in-memory.
  ;; RED stage intentionally retains unrestricted route duration fields.
  (scalar route-duration-seconds
    (:base integer
     :minimum 0))
  (document route
    (:extends document
     :persistence persistent)
    (name string :optional)
    (geometry reference :required)
    (origin reference :optional)
    (destination reference :optional)
    (waypoints (list reference) :optional)
    (mode route-mode :optional)
    (distanceMeters distance-meters :optional)
    (estimatedDurationSeconds integer :optional)
    (actualDurationSeconds integer :optional)
    (plannedAt unix-time :optional)
    (startedAt unix-time :optional)
    (endedAt unix-time :optional)
    (routingProvider string :optional)
    (constraints map :optional))
