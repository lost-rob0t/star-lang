package actor.starintel.starlang.runtime

internal data class AskCell(
    val correlationId: String,
    var status: AskStatus = AskStatus.PENDING,
    var value: PortableValue? = null,
    var condition: Throwable? = null,
)

internal enum class AskStatus {
    PENDING,
    REPLIED,
    ERROR,
}

internal data class RuntimeMessage(
    val correlationId: String,
    val payload: PortableValue,
    val replyCell: AskCell?,
)

class ActorInstance internal constructor(
    val definition: ActorDefinition,
    internal var data: PortableValue,
    internal var mailbox: Mailbox<RuntimeMessage>,
) {
    internal var owner: StarRuntime? = null
    var status: ActorStatus = ActorStatus.RUNNING
        internal set
    var generation: Long = 0
        internal set
    internal var completionIncarnation: Long = 0
    var invocationCount: Long = 0
        internal set
    var lastError: Throwable? = null
        internal set
    internal var processing: Boolean = false

    val name: String
        get() = definition.name

    val serviceUri: String
        get() = definition.serviceUri

    val state: PortableValue
        get() = data

    val mailboxDepth: Int
        get() = mailbox.depth

    val isRunning: Boolean
        get() = status == ActorStatus.RUNNING

    fun reference(): ActorReference = ActorReference(
        serviceUri = serviceUri,
        generation = generation,
        protocolRevision = 1,
    )
}

class StarRuntime {
    private val actorsByName = LinkedHashMap<String, ActorInstance>()
    private val actorsByUri = LinkedHashMap<String, ActorInstance>()
    private val actorOrder = mutableListOf<String>()
    private var sequence: Long = 0

    var status: RuntimeStatus = RuntimeStatus.RUNNING
        private set

    val actorCount: Int
        get() = actorsByName.size

    private fun ensureRunning() {
        if (status != RuntimeStatus.RUNNING) {
            throw ActorRuntimeException("StarLang runtime is shut down.")
        }
    }

    fun instantiate(definition: ActorDefinition): ActorInstance = ActorInstance(
        definition = definition,
        data = definition.initialStateFactory.create(),
        mailbox = Mailbox(definition.mailboxCapacity),
    )

    fun register(actor: ActorInstance): ActorInstance {
        ensureRunning()
        val owner = actor.owner
        if (owner != null && owner !== this) {
            throw ActorAlreadyRegisteredException("Actor ${actor.name} is owned by another StarLang runtime.")
        }
        if (actorsByName.containsKey(actor.name) || actorsByUri.containsKey(actor.serviceUri)) {
            throw ActorAlreadyRegisteredException(
                "Actor ${actor.name} (${actor.serviceUri}) is already registered.",
            )
        }
        actor.owner = this
        actorsByName[actor.name] = actor
        actorsByUri[actor.serviceUri] = actor
        actorOrder += actor.name
        return actor
    }

    fun spawn(definition: ActorDefinition): ActorInstance = register(instantiate(definition))

    fun find(nameOrUri: String): ActorInstance? =
        actorsByName[nameOrUri] ?: actorsByUri[nameOrUri]

    fun find(reference: ActorReference): ActorInstance? = actorsByUri[reference.serviceUri]

    fun resolve(nameOrUri: String): ActorInstance =
        find(nameOrUri) ?: throw ActorNotFoundException("No actor registered for target $nameOrUri.")

    fun resolve(reference: ActorReference): ActorInstance {
        val actor = find(reference)
            ?: throw ActorNotFoundException("No actor registered for target ${reference.serviceUri}.")
        if (reference.generation != actor.generation) {
            throw ActorStaleReferenceException(
                "Actor reference ${reference.serviceUri} generation ${reference.generation} is stale; " +
                    "current generation is ${actor.generation}.",
            )
        }
        return actor
    }

    fun unregister(nameOrUri: String): ActorInstance = unregister(resolve(nameOrUri))
    fun unregister(reference: ActorReference): ActorInstance = unregister(resolve(reference))

    fun unregister(actor: ActorInstance): ActorInstance {
        ensureOwned(actor)
        actorsByName.remove(actor.name)
        actorsByUri.remove(actor.serviceUri)
        actorOrder.remove(actor.name)
        actor.completionIncarnation += 1
        return actor
    }

    fun stop(nameOrUri: String): ActorInstance = stop(resolve(nameOrUri))
    fun stop(reference: ActorReference): ActorInstance = stop(resolve(reference))

    fun stop(actor: ActorInstance): ActorInstance {
        ensureOwned(actor)
        actor.status = ActorStatus.STOPPED
        actor.mailbox.close(discard = true)
        return actor
    }

    fun start(nameOrUri: String): ActorInstance = start(resolve(nameOrUri))
    fun start(reference: ActorReference): ActorInstance = start(resolve(reference))

    fun start(actor: ActorInstance): ActorInstance {
        ensureRunning()
        ensureOwned(actor)
        if (actor.status == ActorStatus.RUNNING) return actor
        actor.generation += 1
        actor.mailbox = Mailbox(actor.definition.mailboxCapacity)
        actor.status = ActorStatus.RUNNING
        actor.lastError = null
        return actor
    }

    fun restart(nameOrUri: String): ActorInstance = restart(resolve(nameOrUri))
    fun restart(reference: ActorReference): ActorInstance = restart(resolve(reference))

    fun restart(actor: ActorInstance): ActorInstance {
        ensureRunning()
        stop(actor)
        return start(actor)
    }

    fun shutdown(): RuntimeStatus {
        if (status == RuntimeStatus.RUNNING) {
            actorOrder.toList().forEach { name -> actorsByName[name]?.let(::stop) }
            status = RuntimeStatus.STOPPED
        }
        return status
    }

    fun tell(nameOrUri: String, message: PortableValue): DeliveryResult =
        tell(resolve(nameOrUri), message)

    fun tell(reference: ActorReference, message: PortableValue): DeliveryResult =
        tell(resolve(reference), message)

    fun tell(actor: ActorInstance, message: PortableValue): DeliveryResult {
        ensureOwned(actor)
        if (!actor.isRunning) {
            return DeliveryResult(
                status = DeliveryStatus.STOPPED,
                reference = actor.reference(),
                depth = actor.mailbox.depth,
                capacity = actor.definition.mailboxCapacity,
            )
        }
        ensureLocal(actor)
        return enqueue(
            actor,
            RuntimeMessage(
                correlationId = nextCorrelationId(),
                payload = message,
                replyCell = null,
            ),
        )
    }

    @JvmOverloads
    fun ask(nameOrUri: String, message: PortableValue, timeoutSteps: Int = 1000): PortableValue =
        ask(resolve(nameOrUri), message, timeoutSteps)

    @JvmOverloads
    fun ask(reference: ActorReference, message: PortableValue, timeoutSteps: Int = 1000): PortableValue =
        ask(resolve(reference), message, timeoutSteps)

    @JvmOverloads
    fun ask(actor: ActorInstance, message: PortableValue, timeoutSteps: Int = 1000): PortableValue {
        require(timeoutSteps >= 0) {
            "ASK timeoutSteps must be non-negative, received $timeoutSteps."
        }
        ensureOwned(actor)
        if (!actor.isRunning) {
            throw ActorStoppedException("Actor ${actor.name} is stopped.")
        }
        ensureLocal(actor)

        val correlationId = nextCorrelationId()
        val cell = AskCell(correlationId)
        val delivery = enqueue(actor, RuntimeMessage(correlationId, message, cell))
        when (delivery.status) {
            DeliveryStatus.ACCEPTED -> Unit
            DeliveryStatus.MAILBOX_FULL -> throw ActorMailboxFullException(
                "Actor ${actor.name} mailbox is full (${delivery.depth}/${delivery.capacity}).",
            )
            DeliveryStatus.STOPPED -> throw ActorStoppedException("Actor ${actor.name} is stopped.")
            DeliveryStatus.REJECTED -> throw ActorRuntimeException(
                "Actor ${actor.name} rejected delivery.",
            )
        }

        repeat(timeoutSteps) {
            if (cell.status != AskStatus.PENDING) return@repeat
            dispatchNext(actor)
        }

        return when (cell.status) {
            AskStatus.REPLIED -> cell.value!!
            AskStatus.ERROR -> throw cell.condition!!
            AskStatus.PENDING -> throw ActorAskTimeoutException(
                "ASK to actor ${actor.name} timed out after $timeoutSteps deterministic " +
                    "dispatch steps (correlation $correlationId).",
            )
        }
    }

    fun dispatchNext(nameOrUri: String): DispatchResult? = dispatchNext(resolve(nameOrUri))
    fun dispatchNext(reference: ActorReference): DispatchResult? = dispatchNext(resolve(reference))

    fun dispatchNext(actor: ActorInstance): DispatchResult? {
        ensureOwned(actor)
        if (!actor.isRunning || actor.processing) return null
        val envelope = actor.mailbox.poll() ?: return null
        actor.processing = true
        return try {
            dispatchEnvelope(actor, envelope)
        } finally {
            actor.processing = false
        }
    }

    fun runUntilIdle(): Int {
        var processed = 0
        while (true) {
            var progressed = false
            for (name in actorOrder.toList()) {
                val actor = actorsByName[name] ?: continue
                if (actor.isRunning && dispatchNext(actor) != null) {
                    processed += 1
                    progressed = true
                }
            }
            if (!progressed) return processed
        }
    }

    fun invoke(nameOrUri: String, message: PortableValue): PortableValue =
        ask(nameOrUri, message)

    fun invoke(reference: ActorReference, message: PortableValue): PortableValue =
        ask(reference, message)

    private fun nextCorrelationId(): String {
        sequence += 1
        return "runtime-correlation-%08d".format(sequence)
    }

    private fun ensureOwned(actor: ActorInstance) {
        if (
            actor.owner !== this ||
            actorsByName[actor.name] !== actor ||
            actorsByUri[actor.serviceUri] !== actor
        ) {
            throw ActorNotFoundException(
                "Actor ${actor.name} is not registered in this runtime.",
            )
        }
    }

    private fun ensureLocal(actor: ActorInstance) {
        if (actor.definition.kind == ActorKind.EXTERNAL) {
            throw ActorExternalDispatchRequiredException(
                "Actor ${actor.name} is external at ${actor.serviceUri}; " +
                    "a transport dispatcher is required.",
            )
        }
    }

    private fun enqueue(actor: ActorInstance, message: RuntimeMessage): DeliveryResult {
        val mailboxResult = actor.mailbox.offer(message)
        val deliveryStatus = when (mailboxResult.status) {
            MailboxDeliveryStatus.ACCEPTED -> DeliveryStatus.ACCEPTED
            MailboxDeliveryStatus.FULL -> DeliveryStatus.MAILBOX_FULL
            MailboxDeliveryStatus.CLOSED -> DeliveryStatus.STOPPED
        }
        return DeliveryResult(
            deliveryStatus,
            actor.reference(),
            mailboxResult.depth,
            mailboxResult.capacity,
        )
    }

    private fun dispatchIncarnationCurrent(
        actor: ActorInstance,
        reference: ActorReference,
        completionIncarnation: Long,
    ): Boolean =
        status == RuntimeStatus.RUNNING &&
            actor.isRunning &&
            actor.generation == reference.generation &&
            actor.completionIncarnation == completionIncarnation &&
            actorsByName[actor.name] === actor &&
            actorsByUri[actor.serviceUri] === actor

    private fun staleCompletion(
        actor: ActorInstance,
        reference: ActorReference,
    ): ActorStaleCompletionException =
        ActorStaleCompletionException(
            "Actor ${actor.name} dispatch from generation ${reference.generation} " +
                "completed after its dispatch incarnation became stale.",
        )

    private fun ensureDispatchIncarnationCurrent(
        actor: ActorInstance,
        reference: ActorReference,
        completionIncarnation: Long,
    ) {
        if (!dispatchIncarnationCurrent(actor, reference, completionIncarnation)) {
            throw staleCompletion(actor, reference)
        }
    }

    private fun validateContract(
        label: String,
        validator: ContractValidator?,
        contract: List<String>,
        value: PortableValue,
        actor: ActorInstance,
    ) {
        if (validator != null && !validator.isValid(contract, value)) {
            throw ActorContractException(
                "Actor ${actor.name} rejected its $label contract $contract for value $value.",
            )
        }
    }

    private fun invokeNativeTransition(
        actor: ActorInstance,
        message: PortableValue,
        reference: ActorReference,
        completionIncarnation: Long,
    ): PortableValue {
        val definition = actor.definition
        val handler = definition.handler
            ?: throw ActorDefinitionException(
                "Native actor ${actor.name} has no callable handler.",
            )
        val transition = handler.handle(message, actor.data, this)
        ensureDispatchIncarnationCurrent(actor, reference, completionIncarnation)
        validateContract(
            "output",
            definition.outputValidator,
            definition.produces,
            transition.output,
            actor,
        )
        ensureDispatchIncarnationCurrent(actor, reference, completionIncarnation)
        when (val update = transition.stateUpdate) {
            StateUpdate.Keep -> Unit
            is StateUpdate.Replace -> actor.data = update.value
        }
        actor.invocationCount += 1
        actor.lastError = null
        return transition.output
    }

    private fun dispatchEnvelope(
        actor: ActorInstance,
        envelope: RuntimeMessage,
    ): DispatchResult {
        val reference = actor.reference()
        val completionIncarnation = actor.completionIncarnation
        return try {
            validateContract(
                "input",
                actor.definition.inputValidator,
                actor.definition.accepts,
                envelope.payload,
                actor,
            )
            ensureDispatchIncarnationCurrent(
                actor,
                reference,
                completionIncarnation,
            )
            val result = invokeNativeTransition(
                actor,
                envelope.payload,
                reference,
                completionIncarnation,
            )
            envelope.replyCell?.apply {
                value = result
                condition = null
                status = AskStatus.REPLIED
            }
            DispatchResult(
                status = DispatchStatus.COMPLETED,
                reference = reference,
                correlationId = envelope.correlationId,
                value = result,
            )
        } catch (condition: Throwable) {
            val current = dispatchIncarnationCurrent(
                actor,
                reference,
                completionIncarnation,
            )
            val effectiveCondition = when {
                current -> condition
                condition is ActorStaleCompletionException -> condition
                else -> staleCompletion(actor, reference)
            }
            if (current) actor.lastError = effectiveCondition
            envelope.replyCell?.apply {
                value = null
                this.condition = effectiveCondition
                status = AskStatus.ERROR
            }
            DispatchResult(
                status = DispatchStatus.FAILED,
                reference = reference,
                correlationId = envelope.correlationId,
                condition = effectiveCondition,
            )
        }
    }

    companion object {
        @JvmStatic
        fun create(): StarRuntime = StarRuntime()
    }
}
