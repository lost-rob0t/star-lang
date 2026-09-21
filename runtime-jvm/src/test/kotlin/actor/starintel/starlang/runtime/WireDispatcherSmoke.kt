package actor.starintel.starlang.runtime

private fun wireCheck(value: Boolean, message: String) {
    if (!value) error(message)
}

private fun dispatcherManifest(): PortableManifest = PortableManifest(
    actors = listOf(
        PortableActorContract(
            name = "worker",
            serviceUri = "star://test:localhost:worker",
            accepts = listOf("test/run@1"),
            produces = listOf("test/result@1"),
        ),
    ),
    messages = listOf(
        PortableMessageContract(
            name = "test/run@1",
            requiredFields = listOf("target"),
        ),
        PortableMessageContract(
            name = "test/result@1",
            requiredFields = listOf("value"),
        ),
    ),
)

private fun command(
    messageId: String = "cmd-1",
    idempotencyKey: String = "scope-1",
    attempt: Long = 1,
    causationId: String? = null,
    target: String = "example.org",
    deadline: String? = null,
): LifecycleEnvelope = LifecycleEnvelope.command(
    messageId = messageId,
    messageType = "test/run@1",
    actor = "worker",
    sender = "caller",
    idempotencyKey = idempotencyKey,
    causationId = causationId,
    attempt = attempt,
    deadline = deadline,
    payload = PortableValue.ObjectValue.of(
        mapOf("target" to PortableValue.Text(target)),
    ),
)

private fun emittedKinds(items: List<LifecycleEnvelope>): List<EnvelopeKind> =
    items.map(LifecycleEnvelope::kind)

fun main() {
    val dispatcher = DeterministicDispatcher(dispatcherManifest())
    dispatcher.registerActor(
        "worker",
        DispatchHandler { _, _ ->
            DispatchOutcome.Complete(
                messageType = "test/result@1",
                payload = PortableValue.ObjectValue.of(
                    mapOf("value" to PortableValue.Text("ok")),
                ),
            )
        },
    )

    val first = command()
    dispatcher.submit(first)
    wireCheck(
        dispatcher.runNext() == WireProcessStatus.COMPLETED,
        "command completion",
    )
    wireCheck(dispatcher.handlerCount("worker") == 1L, "handler count")
    wireCheck(
        emittedKinds(dispatcher.drainEmitted()) ==
            listOf(EnvelopeKind.ACK, EnvelopeKind.REPLY, EnvelopeKind.ACK),
        "completion lifecycle",
    )

    val duplicate = dispatcher.redeliver(first, "cmd-2")
    dispatcher.submit(duplicate)
    wireCheck(
        dispatcher.runNext() == WireProcessStatus.DUPLICATE,
        "terminal replay",
    )
    wireCheck(dispatcher.handlerCount("worker") == 1L, "duplicate reran handler")
    wireCheck(
        emittedKinds(dispatcher.drainEmitted()) ==
            listOf(EnvelopeKind.REPLY, EnvelopeKind.ACK),
        "terminal replay outcomes",
    )

    val conflict = command(
        messageId = "cmd-conflict",
        target = "different.example.org",
    )
    dispatcher.submit(conflict)
    try {
        dispatcher.runNext()
        error("idempotency identity conflict accepted")
    } catch (_: WireDispatcherIdempotencyConflictException) {
    }
    wireCheck(dispatcher.drainEmitted().isEmpty(), "identity conflict emitted")

    val retryDispatcher = DeterministicDispatcher(dispatcherManifest())
    retryDispatcher.registerActor(
        "worker",
        DispatchHandler { _, envelope ->
            if (envelope.attempt == 1L) {
                DispatchOutcome.Retry(25, "retry")
            } else {
                DispatchOutcome.Complete(
                    "test/result@1",
                    PortableValue.ObjectValue.of(
                        mapOf("value" to PortableValue.Text("retried")),
                    ),
                )
            }
        },
    )
    val retry1 = command(messageId = "retry-1", idempotencyKey = "retry-scope")
    retryDispatcher.submit(retry1)
    wireCheck(retryDispatcher.runNext() == WireProcessStatus.RETRY, "retry outcome")
    retryDispatcher.drainEmitted()
    val retry2 = retryDispatcher.redeliver(retry1, "retry-2")
    retryDispatcher.submit(retry2)
    wireCheck(
        retryDispatcher.runNext() == WireProcessStatus.COMPLETED,
        "retry redelivery",
    )

    val deferred = DeterministicDispatcher(dispatcherManifest())
    deferred.registerActor(
        "worker",
        DispatchHandler { _, _ -> DispatchOutcome.Defer },
    )
    val attempt1 = command(messageId = "defer-1", idempotencyKey = "defer-scope")
    deferred.submit(attempt1)
    wireCheck(deferred.runNext() == WireProcessStatus.DEFERRED, "defer attempt 1")
    deferred.drainEmitted()
    wireCheck(
        deferred.finishDeferred(attempt1, DispatchOutcome.Retry(10)) ==
            WireProcessStatus.RETRY,
        "deferred retry settlement",
    )
    deferred.drainEmitted()

    val attempt2 = deferred.redeliver(attempt1, "defer-2")
    deferred.submit(attempt2)
    wireCheck(deferred.runNext() == WireProcessStatus.DEFERRED, "defer attempt 2")
    deferred.drainEmitted()
    try {
        deferred.finishDeferred(
            attempt1,
            DispatchOutcome.Complete(
                "test/result@1",
                PortableValue.ObjectValue.of(
                    mapOf("value" to PortableValue.Text("stale")),
                ),
            ),
        )
        error("stale deferred attempt settled active attempt")
    } catch (_: WireDispatcherStaleCompletionException) {
    }
    wireCheck(deferred.drainEmitted().isEmpty(), "stale completion emitted")

    val finish = DispatchOutcome.Complete(
        "test/result@1",
        PortableValue.ObjectValue.of(
            mapOf("value" to PortableValue.Text("done")),
        ),
    )
    wireCheck(
        deferred.finishDeferred(attempt2, finish) == WireProcessStatus.COMPLETED,
        "active deferred completion",
    )
    deferred.drainEmitted()
    wireCheck(
        deferred.finishDeferred(attempt2, finish) == WireProcessStatus.DUPLICATE,
        "late terminal duplicate",
    )
    wireCheck(deferred.drainEmitted().isEmpty(), "late terminal emitted")

    val deadline = DeterministicDispatcher(
        dispatcherManifest(),
        now = "2026-08-15T10:00:00Z",
    )
    var deadlineCalls = 0
    deadline.registerActor(
        "worker",
        DispatchHandler { _, _ ->
            deadlineCalls += 1
            DispatchOutcome.Complete()
        },
    )
    deadline.submit(
        command(
            messageId = "expired-1",
            idempotencyKey = "expired-scope",
            deadline = "2026-08-15T09:59:59Z",
        ),
    )
    wireCheck(
        deadline.runNext() == WireProcessStatus.DEADLINE_EXCEEDED,
        "deadline outcome",
    )
    wireCheck(deadlineCalls == 0, "expired command invoked handler")
    val deadlineOutcomes = deadline.drainEmitted()
    val deadlineError = deadlineOutcomes.single().payload as LifecyclePayload.Error
    wireCheck(
        deadlineError.code == "star.deadline-exceeded",
        "deadline error code",
    )

    val failure = DeterministicDispatcher(dispatcherManifest())
    failure.registerActor(
        "worker",
        DispatchHandler { _, _ -> error("do not serialize this exception") },
    )
    failure.submit(command(messageId = "boom-1", idempotencyKey = "boom-scope"))
    wireCheck(
        failure.runNext() == WireProcessStatus.FAILED,
        "handler failure settlement",
    )
    val failureOutcomes = failure.drainEmitted()
    wireCheck(
        emittedKinds(failureOutcomes) ==
            listOf(EnvelopeKind.ACK, EnvelopeKind.ERROR),
        "handler failure lifecycle",
    )
    val failureError = failureOutcomes.last().payload as LifecyclePayload.Error
    wireCheck(
        failureError.code == "star.native-handler-error" &&
            failureError.message ==
                "Native actor handler failed before producing a valid result.",
        "handler failure diagnostic",
    )

    println("runtime-jvm wire dispatcher smoke: PASS")
}
