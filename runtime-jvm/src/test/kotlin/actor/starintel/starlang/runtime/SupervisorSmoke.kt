package actor.starintel.starlang.runtime

private fun supervisorCheck(value: Boolean, message: String) {
    if (!value) error(message)
}

private fun fixtureDefinition(
    name: String,
    restartPolicy: RestartPolicy,
): ActorDefinition = ActorDefinition.nativeActor(
    name = name,
    serviceUri = "star://test:local:$name",
    handler = ActorHandler { message, state, _ ->
        if (message == PortableValue.Text("crash")) {
            error("fixture crash")
        }
        ActorTransition(message, StateUpdate.Replace(state))
    },
    restartPolicy = restartPolicy,
    initialStateFactory = InitialStateFactory {
        PortableValue.ObjectValue.of(
            mapOf("count" to PortableValue.Int64(0)),
        )
    },
)

fun main() {
    val runtime = StarRuntime.create()
    val supervisor = StarSupervisor(
        id = "root",
        runtime = runtime,
        specs = listOf(
            RuntimeChildSpec(
                "primary",
                fixtureDefinition("primary", RestartPolicy.PERMANENT),
            ),
            RuntimeChildSpec(
                "sibling",
                fixtureDefinition("sibling", RestartPolicy.PERMANENT),
            ),
        ),
    )
    supervisor.start()

    val oldPrimary = supervisor.childReference("primary")
    val oldSibling = supervisor.childReference("sibling")
    runtime.tell(oldPrimary, PortableValue.Text("crash"))
    supervisorCheck(supervisor.step() == 1, "supervisor processed failure")
    val newPrimary = supervisor.childReference("primary")
    val newSibling = supervisor.childReference("sibling")
    supervisorCheck(newPrimary.generation == 1L, "permanent child restart")
    supervisorCheck(
        newSibling.generation == oldSibling.generation,
        "one-for-one sibling isolation",
    )
    try {
        runtime.resolve(oldPrimary)
        error("stale child reference survived restart")
    } catch (_: ActorStaleReferenceException) {
    }
    supervisorCheck(
        supervisor.handleChildExit(
            "primary",
            ChildExitReason.FAILURE,
            observedGeneration = 0,
        ) == ChildExitDisposition.STALE,
        "stale exit observation",
    )
    supervisorCheck(
        supervisor.childReference("primary").generation == 1L,
        "stale exit changed generation",
    )

    val policyRuntime = StarRuntime.create()
    val policySupervisor = StarSupervisor(
        id = "policy-root",
        runtime = policyRuntime,
        specs = listOf(
            RuntimeChildSpec(
                "transient",
                fixtureDefinition("transient", RestartPolicy.TRANSIENT),
            ),
            RuntimeChildSpec(
                "temporary",
                fixtureDefinition("temporary", RestartPolicy.TEMPORARY),
            ),
        ),
    ).start()

    policyRuntime.tell(
        policySupervisor.childReference("transient"),
        PortableValue.Text("crash"),
    )
    policyRuntime.tell(
        policySupervisor.childReference("temporary"),
        PortableValue.Text("crash"),
    )
    policySupervisor.step()
    supervisorCheck(
        policySupervisor.childReference("transient").generation == 1L,
        "transient did not restart on failure",
    )
    supervisorCheck(
        policySupervisor.childSnapshot("temporary").status ==
            SupervisedChildStatus.STOPPED,
        "temporary child restarted",
    )
    val transient = policySupervisor.childReference("transient")
    policyRuntime.stop(transient)
    policySupervisor.step()
    supervisorCheck(
        policySupervisor.childReference("transient").generation == 1L,
        "transient restarted on normal exit",
    )
    supervisorCheck(
        policySupervisor.childSnapshot("transient").status ==
            SupervisedChildStatus.STOPPED,
        "transient normal exit not stopped",
    )

    val budgetRuntime = StarRuntime.create()
    val unrelated = budgetRuntime.spawn(
        fixtureDefinition("unrelated", RestartPolicy.PERMANENT),
    )
    val budgetSupervisor = StarSupervisor(
        id = "budget-root",
        runtime = budgetRuntime,
        specs = listOf(
            RuntimeChildSpec(
                "budget-primary",
                fixtureDefinition("budget-primary", RestartPolicy.PERMANENT),
            ),
            RuntimeChildSpec(
                "budget-sibling",
                fixtureDefinition("budget-sibling", RestartPolicy.PERMANENT),
            ),
        ),
        maxRestarts = 0,
        restartWindowSeconds = 10.0,
        clock = SupervisorClock { 100.0 },
    ).start()

    budgetRuntime.tell(
        budgetSupervisor.childReference("budget-primary"),
        PortableValue.Text("crash"),
    )
    try {
        budgetSupervisor.step()
        error("restart budget exhaustion did not fail")
    } catch (_: RestartBudgetExhaustedException) {
    }
    supervisorCheck(
        budgetSupervisor.snapshot().status == SupervisorStatus.FAILED,
        "budget exhaustion supervisor status",
    )
    supervisorCheck(
        budgetSupervisor.childSnapshot("budget-primary").status ==
            SupervisedChildStatus.FAILED,
        "budget trigger child status",
    )
    supervisorCheck(
        budgetSupervisor.childSnapshot("budget-sibling").status ==
            SupervisedChildStatus.STOPPED,
        "budget exhaustion left sibling running",
    )
    supervisorCheck(
        budgetRuntime.resolve(unrelated.reference()).isRunning,
        "budget exhaustion stopped unrelated shared-runtime actor",
    )
    budgetSupervisor.shutdown()
    supervisorCheck(
        budgetRuntime.status == RuntimeStatus.RUNNING,
        "supervisor shutdown killed shared runtime",
    )
    supervisorCheck(
        budgetRuntime.resolve(unrelated.reference()).isRunning,
        "supervisor shutdown killed unrelated actor",
    )

    val drainRuntime = StarRuntime.create()
    val drainSupervisor = StarSupervisor(
        id = "drain-root",
        runtime = drainRuntime,
        specs = listOf(
            RuntimeChildSpec(
                "drain-worker",
                fixtureDefinition("drain-worker", RestartPolicy.PERMANENT),
            ),
        ),
    ).start()
    val beforeDrain = drainSupervisor.childReference("drain-worker")
    drainSupervisor.drain()
    supervisorCheck(
        drainSupervisor.snapshot().status == SupervisorStatus.STOPPED,
        "drain status",
    )
    supervisorCheck(
        drainSupervisor.childReference("drain-worker").generation ==
            beforeDrain.generation,
        "drain restarted permanent child",
    )
    supervisorCheck(
        !drainRuntime.resolve(beforeDrain).isRunning,
        "drain left child running",
    )

    println("runtime-jvm supervisor smoke: PASS")
}
