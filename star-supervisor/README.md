# star-supervisor

`star-supervisor` owns the bounded StarLang supervision policy. The first final
slice implements one-for-one child lifecycle only; it deliberately does not own
application retries, durable replay, scheduling, registry behavior, or a second
Sento restart policy.

## One-for-one contract

A supervisor has an explicit id and a closed child set. Each child is classified
as `:permanent`, `:transient`, or `:temporary`.

- `:permanent` restarts after normal or failed exit.
- `:transient` restarts only after failed exit.
- `:temporary` never restarts.
- only the exited child is replaced; siblings retain their generation during
  ordinary one-for-one recovery.
- each replacement advances the child generation.
- final StarLang runtime children reuse the runtime's actor reference generation,
  so old references fail with `actor-stale-reference-error`.
- every reported child exit must include the observed child generation.
  Notifications from an older generation are stale and cannot restart the
  replacement, consume restart budget, or mutate current child state.
- restart admission is bounded by `:max-restarts` inside `:restart-window`.
  Exhaustion raises `restart-budget-exhausted-error`, fails the supervisor, and
  terminally stops every child owned by that supervisor so no managed sibling is
  left live and unmanaged. This terminal cleanup is not one-for-all restart.
- `drain-supervisor` intentionally stops owned children without restarting them.
- caller-supplied runtime and Sento contexts are shared in this slice.
  `shutdown-supervisor` stops only children owned by the supervisor and leaves
  unrelated actors/backend context usable. Exclusive backend-system ownership
  belongs to later topology/materialization work.
- snapshots expose supervision metadata only; actor business state is not copied
  into the supervisor.

The Common Lisp final runtime remains the portable lifecycle authority.
`star-sento-compat` remains the concrete Sento operation port; this system uses
that port rather than private Sento actor APIs or a duplicate policy engine.

## Runtime example

```lisp
(let* ((runtime (starlangruntime:make-runtime))
       (definition
         (starlangruntime:make-native-actor-definition
          "worker"
          (lambda (message state runtime)
            (declare (ignore runtime))
            (values message state))
          :restart-policy :permanent))
       (child (starsupervisor:make-runtime-child-spec "worker" definition))
       (supervisor
         (starsupervisor:make-runtime-supervisor
          "root" runtime (list child)
          :max-restarts 3
          :restart-window 10)))
  (starsupervisor:start-supervisor supervisor)
  (starsupervisor:supervisor-child-reference supervisor "worker"))
```

`supervisor-step` executes at most one queued final-runtime message per running
child and translates a failed dispatch into the approved child-exit policy. A
normal stop is likewise observed on the next step. Sento lifecycle adapters
report an observed exit with `supervisor-handle-child-exit`, including the
`:observed-generation` captured for the actor incarnation that produced the exit.

## Deliberate non-goals of this slice

One-for-all and rest-for-one strategies, durable restart history, replay/leases,
topology materialization and exclusive backend ownership, readiness graphs,
backoff/jitter, provider retry, process readiness, effectful actor bodies, and
scheduling remain outside this implementation.
