package actor.starintel.starlang.runtime

enum class CommandRecordStatus {
    IN_PROGRESS,
    RETRY,
    TERMINAL,
}

enum class WireProcessStatus {
    COMPLETED,
    RETRY,
    FAILED,
    DEFERRED,
    DUPLICATE,
    IN_PROGRESS,
    CANCELLED,
    DEADLINE_EXCEEDED,
}

sealed interface DispatchOutcome {
    data class Complete(
        val messageType: String? = null,
        val payload: PortableValue = PortableValue.Null,
    ) : DispatchOutcome

    data class Retry(
        val retryAfterMs: Long,
        val reason: String? = null,
    ) : DispatchOutcome {
        init {
            require(retryAfterMs > 0) {
                "dispatch retry-after-ms requires a positive integer."
            }
        }
    }

    data class Fail(
        val code: String,
        val message: String,
        val retryable: Boolean,
        val details: PortableValue? = null,
    ) : DispatchOutcome {
        init {
            require(code.isNotBlank()) { "dispatch error code requires a non-empty string." }
            require(message.isNotBlank()) { "dispatch error message requires a non-empty string." }
        }
    }

    data object Defer : DispatchOutcome
}

fun interface DispatchHandler {
    fun handle(
        dispatcher: DeterministicDispatcher,
        command: LifecycleEnvelope,
    ): DispatchOutcome
}

private data class CommandIdentity(
    val starVersion: Int,
    val kind: EnvelopeKind,
    val messageType: String,
    val actor: String,
    val sender: String?,
    val correlationId: String,
    val idempotencyKey: String?,
    val dataset: String?,
    val replyTo: String?,
    val deadline: String?,
    val payload: LifecyclePayload,
)

private data class CommandRecord(
    val status: CommandRecordStatus,
    val command: LifecycleEnvelope,
    val outcomes: List<LifecycleEnvelope>,
)

class DeterministicDispatcher(
    val manifest: PortableManifest,
    now: String = "1970-01-01T00:00:00Z",
) {
    private val actors = LinkedHashMap<String, DispatchHandler>()
    private val queue = ArrayDeque<LifecycleEnvelope>()
    private val emitted = mutableListOf<LifecycleEnvelope>()
    private val idempotency = LinkedHashMap<IdempotencyScope, CommandRecord>()
    private val cancelledMessages = LinkedHashSet<String>()
    private val cancelledCorrelations = LinkedHashSet<String>()
    private val handlerCounts = LinkedHashMap<String, Long>()
    private var sequence: Long = 0

    var now: String = requireNonEmpty(now, "dispatcher clock")
        private set

    init {
        if (manifest.wireVersion != 1) {
            throw WireDispatcherException(
                "Deterministic dispatcher requires a version-one portable manifest.",
            )
        }
    }

    val queueDepth: Int
        get() = queue.size

    fun emittedSnapshot(): List<LifecycleEnvelope> = emitted.toList()

    fun handlerCount(actorName: String): Long = handlerCounts[actorName] ?: 0L

    fun advanceClock(value: String): String {
        val next = requireNonEmpty(value, "dispatcher clock")
        if (next < now) {
            throw WireDispatcherException(
                "Deterministic dispatcher clock cannot move backward.",
            )
        }
        now = next
        return next
    }

    fun nextMessageId(prefix: String): String {
        requireNonEmpty(prefix, "message id prefix")
        sequence += 1
        return "%s-%06d".format(prefix, sequence)
    }

    fun registerActor(actorName: String, handler: DispatchHandler): String {
        requireNonEmpty(actorName, "actor name")
        val contract = manifest.actorContract(actorName)
            ?: throw WireDispatcherInvalidActorException(
                "Actor $actorName is absent from the portable manifest.",
            )
        actors[contract.name] = handler
        return contract.name
    }

    fun drainEmitted(): List<LifecycleEnvelope> =
        emitted.toList().also { emitted.clear() }

    fun submit(envelope: LifecycleEnvelope): Any {
        validate(envelope)
        return when (envelope.kind) {
            EnvelopeKind.COMMAND -> {
                queue.addLast(envelope)
                envelope
            }
            EnvelopeKind.CANCEL -> applyCancel(envelope)
            else -> throw WireDispatcherException(
                "Deterministic dispatcher accepts command and cancel inputs, " +
                    "received ${envelope.kind}.",
            )
        }
    }

    fun runNext(): WireProcessStatus? {
        val envelope = if (queue.isEmpty()) null else queue.removeFirst()
        return envelope?.let(::processCommand)
    }

    fun run(): List<WireProcessStatus> {
        val statuses = mutableListOf<WireProcessStatus>()
        while (queue.isNotEmpty()) {
            statuses += processCommand(queue.removeFirst())
        }
        return statuses
    }

    @JvmOverloads
    fun redeliver(
        command: LifecycleEnvelope,
        messageId: String = nextMessageId("redelivery"),
    ): LifecycleEnvelope {
        validate(command)
        if (command.kind != EnvelopeKind.COMMAND) {
            throw WireDispatcherException("Only commands may be redelivered.")
        }
        return command.copy(
            messageId = messageId,
            causationId = command.messageId,
            attempt = command.attempt + 1,
        ).validate(manifest)
    }

    fun deferredStatus(command: LifecycleEnvelope): CommandRecordStatus? =
        idempotency[command.idempotencyScope()]?.status

    fun finishDeferred(
        command: LifecycleEnvelope,
        result: DispatchOutcome,
    ): WireProcessStatus {
        validate(command)
        val record = idempotency[command.idempotencyScope()]
            ?: throw WireDispatcherException(
                "Deferred completion has no idempotency record for command " +
                    "${command.messageId}.",
            )
        ensureIdentityCompatible(record, command)
        ensureActiveAttempt(record, command)

        return when (record.status) {
            CommandRecordStatus.TERMINAL -> WireProcessStatus.DUPLICATE
            CommandRecordStatus.RETRY -> throw WireDispatcherException(
                "Command ${command.messageId} is not awaiting deferred completion; " +
                    "status is RETRY.",
            )
            CommandRecordStatus.IN_PROGRESS -> when (result) {
                is DispatchOutcome.Complete -> completeCommand(command, result)
                is DispatchOutcome.Retry -> retryCommand(command, result)
                is DispatchOutcome.Fail -> failCommand(command, result)
                DispatchOutcome.Defer -> throw WireDispatcherException(
                    "A deferred actor result cannot defer the same command again.",
                )
            }
        }
    }

    private fun processCommand(command: LifecycleEnvelope): WireProcessStatus {
        validate(command)
        val scope = command.idempotencyScope()
        val existing = idempotency[scope]
        if (existing != null) {
            ensureIdentityCompatible(existing, command)
            when (existing.status) {
                CommandRecordStatus.TERMINAL -> {
                    replay(existing.outcomes)
                    return WireProcessStatus.DUPLICATE
                }
                CommandRecordStatus.IN_PROGRESS -> {
                    ensureActiveAttempt(existing, command)
                    emit(
                        makeAck(
                            command,
                            AckStatus.ACCEPTED,
                            reason = "Command is already in progress.",
                        ),
                    )
                    return WireProcessStatus.IN_PROGRESS
                }
                CommandRecordStatus.RETRY -> {
                    ensureNextAttempt(existing, command)
                }
            }
        }

        if (isCancelled(command)) return cancelCommand(command)
        if (deadlineExpired(command)) return expireCommand(command)

        val handler = validateRoute(command)
        val accepted = makeAck(command, AckStatus.ACCEPTED)
        emit(accepted)
        idempotency[scope] = CommandRecord(
            CommandRecordStatus.IN_PROGRESS,
            command,
            listOf(accepted),
        )
        handlerCounts[command.actor] = handlerCount(command.actor) + 1

        return try {
            when (val result = handler.handle(this, command)) {
                is DispatchOutcome.Complete -> completeCommand(command, result)
                is DispatchOutcome.Retry -> retryCommand(command, result)
                is DispatchOutcome.Fail -> failCommand(command, result)
                DispatchOutcome.Defer -> WireProcessStatus.DEFERRED
            }
        } catch (_: Throwable) {
            settleHandlerFailure(command)
        }
    }

    private fun validate(envelope: LifecycleEnvelope) {
        try {
            envelope.validate(manifest)
        } catch (condition: InvalidWireEnvelopeException) {
            throw WireDispatcherException(condition.message ?: "Invalid wire envelope.")
        }
    }

    private fun validateRoute(command: LifecycleEnvelope): DispatchHandler {
        val contract = manifest.actorContract(command.actor)
            ?: throw WireDispatcherInvalidActorException(
                "Command targets unknown actor or STAR service ${command.actor}.",
            )
        if (!contract.accepts(command.messageType)) {
            throw WireDispatcherInvalidActorException(
                "Actor ${command.actor} does not accept message type " +
                    "${command.messageType}.",
            )
        }
        return actors[contract.name]
            ?: throw WireDispatcherInvalidActorException(
                "Actor ${contract.name} has no registered deterministic handler.",
            )
    }

    private fun completeCommand(
        command: LifecycleEnvelope,
        result: DispatchOutcome.Complete,
    ): WireProcessStatus {
        val outcomes = mutableListOf<LifecycleEnvelope>()
        if (result.messageType != null) {
            val reply = LifecycleEnvelope.reply(
                source = command,
                messageId = nextMessageId("reply"),
                messageType = result.messageType,
                actor = command.sender ?: "star.dispatcher",
                sender = command.actor,
                payload = result.payload,
                sentAt = now,
            )
            validate(reply)
            emit(reply)
            outcomes += reply
        }
        val completed = makeAck(command, AckStatus.COMPLETED)
        emit(completed)
        outcomes += completed
        idempotency[command.idempotencyScope()] = CommandRecord(
            CommandRecordStatus.TERMINAL,
            command,
            outcomes.toList(),
        )
        return WireProcessStatus.COMPLETED
    }

    private fun retryCommand(
        command: LifecycleEnvelope,
        result: DispatchOutcome.Retry,
    ): WireProcessStatus {
        val retry = makeAck(
            command,
            AckStatus.RETRY,
            reason = result.reason,
            retryAfterMs = result.retryAfterMs,
        )
        emit(retry)
        idempotency[command.idempotencyScope()] = CommandRecord(
            CommandRecordStatus.RETRY,
            command,
            listOf(retry),
        )
        return WireProcessStatus.RETRY
    }

    private fun failCommand(
        command: LifecycleEnvelope,
        result: DispatchOutcome.Fail,
    ): WireProcessStatus {
        val failure = makeError(
            command,
            result.code,
            result.message,
            result.retryable,
            result.details,
        )
        emit(failure)
        idempotency[command.idempotencyScope()] = CommandRecord(
            if (result.retryable) {
                CommandRecordStatus.RETRY
            } else {
                CommandRecordStatus.TERMINAL
            },
            command,
            listOf(failure),
        )
        return if (result.retryable) {
            WireProcessStatus.RETRY
        } else {
            WireProcessStatus.FAILED
        }
    }

    private fun settleHandlerFailure(command: LifecycleEnvelope): WireProcessStatus {
        val record = idempotency[command.idempotencyScope()]
        return when (record?.status) {
            CommandRecordStatus.IN_PROGRESS -> failCommand(
                command,
                DispatchOutcome.Fail(
                    code = "star.native-handler-error",
                    message = "Native actor handler failed before producing a valid result.",
                    retryable = false,
                ),
            )
            CommandRecordStatus.TERMINAL -> WireProcessStatus.FAILED
            CommandRecordStatus.RETRY -> WireProcessStatus.RETRY
            null -> throw WireDispatcherException(
                "Cannot settle command ${command.messageId} after handler failure; " +
                    "idempotency record is absent.",
            )
        }
    }

    private fun cancelCommand(command: LifecycleEnvelope): WireProcessStatus {
        val failure = makeError(
            command,
            "star.cancelled",
            "Command was cancelled before completion.",
            false,
            null,
        )
        emit(failure)
        idempotency[command.idempotencyScope()] = CommandRecord(
            CommandRecordStatus.TERMINAL,
            command,
            listOf(failure),
        )
        return WireProcessStatus.CANCELLED
    }

    private fun expireCommand(command: LifecycleEnvelope): WireProcessStatus {
        val details = PortableValue.ObjectValue.of(
            mapOf(
                "deadline" to PortableValue.Text(command.deadline!!),
                "dispatcherNow" to PortableValue.Text(now),
            ),
        )
        val failure = makeError(
            command,
            "star.deadline-exceeded",
            "Command deadline expired before completion.",
            false,
            details,
        )
        emit(failure)
        idempotency[command.idempotencyScope()] = CommandRecord(
            CommandRecordStatus.TERMINAL,
            command,
            listOf(failure),
        )
        return WireProcessStatus.DEADLINE_EXCEEDED
    }

    private fun applyCancel(cancel: LifecycleEnvelope): WireProcessStatus {
        val payload = cancel.payload as? LifecyclePayload.Cancel
            ?: throw WireDispatcherException("Cancel envelope has invalid payload.")
        cancelledMessages += payload.targetMessageId
        cancelledCorrelations += payload.targetCorrelationId

        val active = idempotency.values
            .filter { it.status in setOf(CommandRecordStatus.IN_PROGRESS, CommandRecordStatus.RETRY) }
            .filter {
                it.command.messageId == payload.targetMessageId ||
                    it.command.correlationId == payload.targetCorrelationId
            }
            .toList()
        active.forEach { cancelCommand(it.command) }
        return WireProcessStatus.CANCELLED
    }

    private fun isCancelled(command: LifecycleEnvelope): Boolean =
        command.messageId in cancelledMessages ||
            command.correlationId in cancelledCorrelations

    private fun deadlineExpired(command: LifecycleEnvelope): Boolean =
        command.deadline?.let { now >= it } ?: false

    private fun makeAck(
        command: LifecycleEnvelope,
        status: AckStatus,
        reason: String? = null,
        retryAfterMs: Long? = null,
    ): LifecycleEnvelope = LifecycleEnvelope.ack(
        source = command,
        messageId = nextMessageId("ack"),
        actor = command.sender ?: "star.dispatcher",
        sender = command.actor,
        status = status,
        reason = reason,
        retryAfterMs = retryAfterMs,
        sentAt = now,
    )

    private fun makeError(
        command: LifecycleEnvelope,
        code: String,
        message: String,
        retryable: Boolean,
        details: PortableValue?,
    ): LifecycleEnvelope = LifecycleEnvelope.error(
        source = command,
        messageId = nextMessageId("error"),
        actor = command.sender ?: "star.dispatcher",
        sender = command.actor,
        code = code,
        message = message,
        retryable = retryable,
        details = details,
        sentAt = now,
    )

    private fun emit(envelope: LifecycleEnvelope): LifecycleEnvelope {
        emitted += envelope
        return envelope
    }

    private fun replay(outcomes: List<LifecycleEnvelope>) {
        emitted += outcomes
    }

    private fun identity(command: LifecycleEnvelope): CommandIdentity =
        CommandIdentity(
            starVersion = command.starVersion,
            kind = command.kind,
            messageType = command.messageType,
            actor = command.actor,
            sender = command.sender,
            correlationId = command.correlationId,
            idempotencyKey = command.idempotencyKey,
            dataset = command.dataset,
            replyTo = command.replyTo,
            deadline = command.deadline,
            payload = command.payload,
        )

    private fun ensureIdentityCompatible(
        record: CommandRecord,
        command: LifecycleEnvelope,
    ) {
        if (identity(record.command) != identity(command)) {
            throw WireDispatcherIdempotencyConflictException(
                "Idempotency key ${command.idempotencyKey} for actor " +
                    "${command.actor} is already bound to a different command identity.",
            )
        }
    }

    private fun ensureActiveAttempt(
        record: CommandRecord,
        command: LifecycleEnvelope,
    ) {
        if (
            record.command.attempt != command.attempt ||
            record.command.messageId != command.messageId
        ) {
            throw WireDispatcherStaleCompletionException(
                "Command ${command.messageId} attempt ${command.attempt} is stale; " +
                    "active command is ${record.command.messageId} attempt " +
                    "${record.command.attempt}.",
            )
        }
    }

    private fun ensureNextAttempt(
        record: CommandRecord,
        command: LifecycleEnvelope,
    ) {
        val expected = record.command.attempt + 1
        if (command.attempt != expected) {
            throw WireDispatcherAttemptException(
                "Command ${command.messageId} attempt ${command.attempt} is not " +
                    "the next retry attempt $expected.",
            )
        }
        if (command.causationId != record.command.messageId) {
            throw WireDispatcherAttemptException(
                "Retry command ${command.messageId} must name prior message " +
                    "${record.command.messageId} as causationId.",
            )
        }
    }

    private fun requireNonEmpty(value: String, context: String): String {
        if (value.isEmpty()) {
            throw WireDispatcherException("$context requires a non-empty string.")
        }
        return value
    }
}

open class WireDispatcherException(message: String) :
    ActorRuntimeException(message)

class WireDispatcherInvalidActorException(message: String) :
    WireDispatcherException(message)

class WireDispatcherIdempotencyConflictException(message: String) :
    WireDispatcherException(message)

class WireDispatcherAttemptException(message: String) :
    WireDispatcherException(message)

class WireDispatcherStaleCompletionException(message: String) :
    WireDispatcherException(message)
