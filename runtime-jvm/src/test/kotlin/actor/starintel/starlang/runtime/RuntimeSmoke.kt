package actor.starintel.starlang.runtime

private fun checkThat(value: Boolean, message: String) {
    if (!value) error(message)
}

fun main() {
    val runtime = StarRuntime.create()
    val actor = runtime.spawn(
        ActorDefinition.nativeActor(
            name = "counter",
            serviceUri = "star://local:localhost:counter",
            handler = ActorHandler { message, state, _ ->
                val old = (state as PortableValue.Int64).value
                val increment = (message as PortableValue.Int64).value
                val next = PortableValue.Int64(old + increment)
                ActorTransition(next, StateUpdate.Replace(next))
            },
            mailboxCapacity = 2,
            initialStateFactory = InitialStateFactory {
                PortableValue.Int64(0)
            },
        ),
    )

    checkThat(
        runtime.tell(actor, PortableValue.Int64(1)).status == DeliveryStatus.ACCEPTED,
        "first tell",
    )
    checkThat(
        runtime.tell(actor, PortableValue.Int64(2)).status == DeliveryStatus.ACCEPTED,
        "second tell",
    )
    checkThat(
        runtime.tell(actor, PortableValue.Int64(3)).status == DeliveryStatus.MAILBOX_FULL,
        "mailbox bound",
    )
    checkThat(runtime.runUntilIdle() == 2, "drain count")
    checkThat(actor.state == PortableValue.Int64(3), "state commit")

    val oldRef = actor.reference()
    runtime.restart(actor)
    checkThat(actor.state == PortableValue.Int64(3), "restart preserves state")
    checkThat(actor.generation == 1L, "restart increments generation")
    try {
        runtime.tell(oldRef, PortableValue.Int64(1))
        error("stale reference accepted")
    } catch (_: ActorStaleReferenceException) {
    }

    val answer = runtime.ask(actor, PortableValue.Int64(4), timeoutSteps = 1)
    checkThat(answer == PortableValue.Int64(7), "ask result")

    val selfStopping = runtime.spawn(
        ActorDefinition.nativeActor(
            name = "self-stop",
            serviceUri = "star://local:localhost:self-stop",
            handler = ActorHandler { _, state, rt ->
                rt.stop("self-stop")
                ActorTransition(
                    PortableValue.Text("should-not-commit"),
                    StateUpdate.Replace(state),
                )
            },
        ),
    )
    try {
        runtime.ask(selfStopping, PortableValue.Null, timeoutSteps = 1)
        error("stale completion accepted")
    } catch (_: ActorStaleCompletionException) {
    }

    println("runtime-jvm smoke: PASS")
}
