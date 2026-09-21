package actor.starintel.starlang.runtime

enum class SupervisorStatus {
    NEW,
    RUNNING,
    DRAINING,
    STOPPED,
    FAILED,
}

enum class SupervisedChildStatus {
    NEW,
    RUNNING,
    STOPPED,
    FAILED,
}

enum class ChildExitReason {
    NORMAL,
    FAILURE,
}

enum class ChildExitDisposition {
    RESTARTED,
    STOPPED,
    SUPPRESSED,
    STALE,
}

fun interface SupervisorClock {
    fun nowSeconds(): Double
}

data class RuntimeChildSpec(
    val id: String,
    val definition: ActorDefinition,
) {
    init {
        require(id.isNotBlank()) { "Child id must be a non-empty string." }
    }

    val restartClass: RestartPolicy
        get() = definition.restartPolicy
}

data class SupervisedChildSnapshot(
    val id: String,
    val status: SupervisedChildStatus,
    val restartClass: RestartPolicy,
    val generation: Long,
    val lastExit: ChildExitReason?,
    val lastCondition: Throwable?,
)

data class SupervisorSnapshot(
    val id: String,
    val status: SupervisorStatus,
    val restartCount: Int,
    val children: List<SupervisedChildSnapshot>,
    val terminalCondition: Throwable?,
)

private class SupervisedChild(
    val spec: RuntimeChildSpec,
) {
    var reference: ActorReference? = null
    var generation: Long = 0
    var status: SupervisedChildStatus = SupervisedChildStatus.NEW
    var lastExit: ChildExitReason? = null
    var lastCondition: Throwable? = null
}

class StarSupervisor @JvmOverloads constructor(
    val id: String,
    private val runtime: StarRuntime,
    specs: List<RuntimeChildSpec>,
    val maxRestarts: Int = 3,
    val restartWindowSeconds: Double = 5.0,
    private val clock: SupervisorClock =
        SupervisorClock { System.nanoTime().toDouble() / 1_000_000_000.0 },
) {
    private val children = LinkedHashMap<String, SupervisedChild>()
    private val childOrder = mutableListOf<String>()
    private val restartTimes = mutableListOf<Double>()

    var status: SupervisorStatus = SupervisorStatus.NEW
        private set

    var terminalCondition: Throwable? = null
        private set

    init {
        require(id.isNotBlank()) { "Supervisor id must be a non-empty string." }
        require(maxRestarts >= 0) {
            "maxRestarts must be a non-negative integer."
        }
        require(restartWindowSeconds > 0.0 && restartWindowSeconds.isFinite()) {
            "restartWindowSeconds must be a positive finite number."
        }
        for (spec in specs) {
            if (children.containsKey(spec.id)) {
                throw InvalidSupervisorException(
                    "Duplicate supervisor child id ${spec.id}.",
                )
            }
            children[spec.id] = SupervisedChild(spec)
            childOrder += spec.id
        }
    }

    fun start(): StarSupervisor = when (status) {
        SupervisorStatus.RUNNING -> this
        SupervisorStatus.NEW -> {
            try {
                childOrder.forEach { spawnChild(child(it)) }
                status = SupervisorStatus.RUNNING
                this
            } catch (condition: Throwable) {
                childOrder.forEach { childId ->
                    val child = child(childId)
                    if (child.status == SupervisedChildStatus.RUNNING) {
                        runCatching { stopChild(child) }
                    }
                }
                status = SupervisorStatus.FAILED
                terminalCondition = condition
                throw condition
            }
        }
        else -> throw InvalidSupervisorException(
            "Supervisor $id is terminal in state $status and cannot be started.",
        )
    }

    fun step(): Int {
        if (status != SupervisorStatus.RUNNING) return 0
        var processed = 0
        for (childId in childOrder) {
            val child = child(childId)
            if (child.status != SupervisedChildStatus.RUNNING) continue
            val reference = child.reference
                ?: throw InvalidSupervisorException(
                    "Running child $childId has no actor reference.",
                )
            val observedGeneration = child.generation
            val actor = runtime.resolve(reference)
            if (actor.isRunning) {
                val result = runtime.dispatchNext(reference)
                if (result != null) {
                    processed += 1
                    if (result.status == DispatchStatus.FAILED) {
                        handleChildExit(
                            childId,
                            ChildExitReason.FAILURE,
                            condition = result.condition,
                            observedGeneration = observedGeneration,
                        )
                    }
                }
            } else {
                handleChildExit(
                    childId,
                    ChildExitReason.NORMAL,
                    observedGeneration = observedGeneration,
                )
            }
        }
        return processed
    }

    @JvmOverloads
    fun handleChildExit(
        childId: String,
        reason: ChildExitReason,
        condition: Throwable? = null,
        observedGeneration: Long,
    ): ChildExitDisposition {
        if (observedGeneration < 0) {
            throw InvalidSupervisorException(
                "Observed child generation must be non-negative.",
            )
        }
        val child = child(childId)
        if (observedGeneration != child.generation) {
            return ChildExitDisposition.STALE
        }

        child.lastExit = reason
        child.lastCondition = condition

        if (status != SupervisorStatus.RUNNING) {
            stopChild(child)
            return ChildExitDisposition.SUPPRESSED
        }

        return if (restartRequired(child.spec.restartClass, reason)) {
            restartChild(child)
            ChildExitDisposition.RESTARTED
        } else {
            stopChild(child)
            ChildExitDisposition.STOPPED
        }
    }

    fun childReference(childId: String): ActorReference =
        child(childId).reference
            ?: throw InvalidSupervisorException(
                "Supervisor $id child $childId has no actor reference.",
            )

    fun childSnapshot(childId: String): SupervisedChildSnapshot {
        val child = child(childId)
        return SupervisedChildSnapshot(
            id = child.spec.id,
            status = child.status,
            restartClass = child.spec.restartClass,
            generation = child.generation,
            lastExit = child.lastExit,
            lastCondition = child.lastCondition,
        )
    }

    fun snapshot(): SupervisorSnapshot = SupervisorSnapshot(
        id = id,
        status = status,
        restartCount = restartTimes.size,
        children = childOrder.map(::childSnapshot),
        terminalCondition = terminalCondition,
    )

    fun drain(): StarSupervisor {
        if (status !in setOf(SupervisorStatus.STOPPED, SupervisorStatus.FAILED)) {
            status = SupervisorStatus.DRAINING
            childOrder.forEach { childId ->
                val child = child(childId)
                if (child.status == SupervisedChildStatus.RUNNING) {
                    stopChild(child)
                }
            }
            status = SupervisorStatus.STOPPED
        }
        return this
    }

    fun shutdown(): SupervisorStatus {
        if (status == SupervisorStatus.FAILED) {
            childOrder.forEach { childId ->
                val child = child(childId)
                if (child.status == SupervisedChildStatus.RUNNING) {
                    stopChild(child)
                }
            }
        } else {
            drain()
        }
        status = SupervisorStatus.STOPPED
        return status
    }

    private fun child(childId: String): SupervisedChild =
        children[childId]
            ?: throw InvalidSupervisorException(
                "Supervisor $id has no child $childId.",
            )

    private fun spawnChild(child: SupervisedChild) {
        val actor = runtime.spawn(child.spec.definition)
        child.reference = actor.reference()
        child.generation = actor.generation
        child.status = SupervisedChildStatus.RUNNING
        child.lastExit = null
        child.lastCondition = null
    }

    private fun stopChild(child: SupervisedChild) {
        val reference = child.reference
        if (reference != null) {
            val actor = runCatching { runtime.resolve(reference) }.getOrNull()
            if (actor != null && actor.isRunning) runtime.stop(reference)
        }
        child.status = SupervisedChildStatus.STOPPED
    }

    private fun restartChild(child: SupervisedChild) {
        consumeRestartBudget(child)
        val reference = child.reference
            ?: throw InvalidSupervisorException(
                "Child ${child.spec.id} has no actor reference to restart.",
            )
        val actor = runtime.restart(reference)
        child.reference = actor.reference()
        child.generation = actor.generation
        child.status = SupervisedChildStatus.RUNNING
    }

    private fun consumeRestartBudget(child: SupervisedChild) {
        val now = clock.nowSeconds()
        if (!now.isFinite()) {
            throw InvalidSupervisorException(
                "Supervisor clock returned non-finite value $now.",
            )
        }
        restartTimes.removeAll { timestamp ->
            now - timestamp >= restartWindowSeconds
        }
        if (restartTimes.size >= maxRestarts) {
            markBudgetExhausted(child)
        }
        restartTimes += now
    }

    private fun markBudgetExhausted(child: SupervisedChild): Nothing {
        val condition = RestartBudgetExhaustedException(
            supervisorId = id,
            childId = child.spec.id,
            maxRestarts = maxRestarts,
            restartWindowSeconds = restartWindowSeconds,
        )
        status = SupervisorStatus.FAILED
        terminalCondition = condition
        childOrder.forEach { childId ->
            val owned = child(childId)
            if (owned.status == SupervisedChildStatus.RUNNING) {
                stopChild(owned)
            }
        }
        child.status = SupervisedChildStatus.FAILED
        throw condition
    }

    private fun restartRequired(
        restartClass: RestartPolicy,
        reason: ChildExitReason,
    ): Boolean = when (restartClass) {
        RestartPolicy.PERMANENT -> true
        RestartPolicy.TRANSIENT -> reason == ChildExitReason.FAILURE
        RestartPolicy.TEMPORARY -> false
    }
}

open class SupervisorException(message: String) : ActorRuntimeException(message)

class InvalidSupervisorException(message: String) : SupervisorException(message)

class RestartBudgetExhaustedException(
    val supervisorId: String,
    val childId: String,
    val maxRestarts: Int,
    val restartWindowSeconds: Double,
) : SupervisorException(
    "Supervisor $supervisorId exhausted restart budget " +
        "($maxRestarts restarts in $restartWindowSeconds seconds) " +
        "while restarting child $childId.",
)
