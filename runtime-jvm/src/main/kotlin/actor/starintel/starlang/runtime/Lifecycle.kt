package actor.starintel.starlang.runtime

enum class EnvelopeKind {
    COMMAND,
    EVENT,
    REPLY,
    ACK,
    ERROR,
    CANCEL,
}

enum class AckStatus {
    ACCEPTED,
    COMPLETED,
    REJECTED,
    RETRY,
}

sealed interface LifecyclePayload {
    data class Data(val value: PortableValue) : LifecyclePayload

    data class Ack(
        val status: AckStatus,
        val forMessageId: String,
        val reason: String? = null,
        val retryAfterMs: Long? = null,
    ) : LifecyclePayload

    data class Error(
        val forMessageId: String,
        val code: String,
        val message: String,
        val retryable: Boolean,
        val details: PortableValue? = null,
    ) : LifecyclePayload

    data class Cancel(
        val targetMessageId: String,
        val targetCorrelationId: String,
        val reason: String? = null,
    ) : LifecyclePayload
}

data class LifecycleEnvelope(
    val starVersion: Int = 1,
    val kind: EnvelopeKind,
    val messageId: String,
    val messageType: String,
    val actor: String,
    val sender: String? = null,
    val correlationId: String,
    val causationId: String? = null,
    val attempt: Long = 1,
    val idempotencyKey: String? = null,
    val dataset: String? = null,
    val replyTo: String? = null,
    val sentAt: String? = null,
    val deadline: String? = null,
    val payload: LifecyclePayload,
) {
    fun validate(manifest: PortableManifest? = null): LifecycleEnvelope {
        if (starVersion != 1) {
            throw InvalidWireEnvelopeException("Unsupported lifecycle wire version.")
        }
        requireNonEmpty(messageId, "messageId")
        requireNonEmpty(messageType, "message-type")
        requireNonEmpty(actor, "actor")
        requireNonEmpty(correlationId, "correlationId")
        if (attempt <= 0) {
            throw InvalidWireEnvelopeException("attempt requires a positive integer.")
        }
        if (kind in setOf(
                EnvelopeKind.REPLY,
                EnvelopeKind.ACK,
                EnvelopeKind.ERROR,
                EnvelopeKind.CANCEL,
            )
        ) {
            requireNonEmpty(causationId, "causationId")
        }
        if (kind == EnvelopeKind.COMMAND) {
            requireNonEmpty(idempotencyKey, "command idempotency-key")
        }
        when (kind) {
            EnvelopeKind.COMMAND,
            EnvelopeKind.EVENT,
            EnvelopeKind.REPLY,
            -> {
                if (payload !is LifecyclePayload.Data) {
                    throw InvalidWireEnvelopeException(
                        "$kind requires a data payload.",
                    )
                }
                manifest?.validateDataPayload(messageType, payload.value)
            }
            EnvelopeKind.ACK -> {
                val ack = validateAckPayload(payload)
                if (ack.forMessageId != causationId) {
                    throw InvalidWireEnvelopeException(
                        "ack payload for-message-id must match envelope causationId.",
                    )
                }
            }
            EnvelopeKind.ERROR -> {
                val error = validateErrorPayload(payload)
                if (error.forMessageId != causationId) {
                    throw InvalidWireEnvelopeException(
                        "error payload for-message-id must match envelope causationId.",
                    )
                }
            }
            EnvelopeKind.CANCEL -> {
                val cancel = validateCancelPayload(payload)
                if (cancel.targetMessageId != causationId) {
                    throw InvalidWireEnvelopeException(
                        "cancel target-message-id must match envelope causationId.",
                    )
                }
                if (cancel.targetCorrelationId != correlationId) {
                    throw InvalidWireEnvelopeException(
                        "cancel target-correlation-id must match envelope correlationId.",
                    )
                }
            }
        }
        return this
    }

    fun idempotencyScope(): IdempotencyScope {
        if (kind != EnvelopeKind.COMMAND) {
            throw InvalidWireEnvelopeException(
                "Idempotency scope keys are defined for command envelopes.",
            )
        }
        return IdempotencyScope(
            actor,
            messageType,
            requireNonEmpty(idempotencyKey, "command idempotency-key"),
        )
    }

    fun deliveryOutcome(): DeliveryOutcome = when (kind) {
        EnvelopeKind.ACK -> when ((payload as LifecyclePayload.Ack).status) {
            AckStatus.ACCEPTED -> DeliveryOutcome.ACCEPTED
            AckStatus.COMPLETED -> DeliveryOutcome.COMPLETED
            AckStatus.REJECTED -> DeliveryOutcome.REJECTED
            AckStatus.RETRY -> DeliveryOutcome.RETRY
        }
        EnvelopeKind.ERROR ->
            if ((payload as LifecyclePayload.Error).retryable) {
                DeliveryOutcome.RETRY
            } else {
                DeliveryOutcome.FAILED
            }
        EnvelopeKind.CANCEL -> DeliveryOutcome.CANCEL_REQUESTED
        else -> DeliveryOutcome.PENDING
    }

    fun isTerminal(): Boolean =
        deliveryOutcome() in setOf(
            DeliveryOutcome.COMPLETED,
            DeliveryOutcome.REJECTED,
            DeliveryOutcome.FAILED,
        )

    companion object {
        const val ACK_MESSAGE_TYPE: String = "star.protocol/ack@1"
        const val ERROR_MESSAGE_TYPE: String = "star.protocol/error@1"
        const val CANCEL_MESSAGE_TYPE: String = "star.protocol/cancel@1"

        @JvmStatic
        @JvmOverloads
        fun command(
            messageId: String,
            messageType: String,
            actor: String,
            idempotencyKey: String,
            payload: PortableValue,
            sender: String? = null,
            correlationId: String = messageId,
            causationId: String? = null,
            dataset: String? = null,
            replyTo: String? = null,
            sentAt: String? = null,
            deadline: String? = null,
            attempt: Long = 1,
        ): LifecycleEnvelope = LifecycleEnvelope(
            kind = EnvelopeKind.COMMAND,
            messageId = messageId,
            messageType = messageType,
            actor = actor,
            sender = sender,
            correlationId = correlationId,
            causationId = causationId,
            attempt = attempt,
            idempotencyKey = idempotencyKey,
            dataset = dataset,
            replyTo = replyTo,
            sentAt = sentAt,
            deadline = deadline,
            payload = LifecyclePayload.Data(payload),
        ).validate()

        @JvmStatic
        fun reply(
            source: LifecycleEnvelope,
            messageId: String,
            messageType: String,
            actor: String,
            sender: String?,
            payload: PortableValue,
            sentAt: String?,
        ): LifecycleEnvelope {
            source.validate()
            return LifecycleEnvelope(
                kind = EnvelopeKind.REPLY,
                messageId = messageId,
                messageType = messageType,
                actor = actor,
                sender = sender,
                correlationId = source.correlationId,
                causationId = source.messageId,
                dataset = source.dataset,
                sentAt = sentAt,
                deadline = source.deadline,
                payload = LifecyclePayload.Data(payload),
            ).validate()
        }

        @JvmStatic
        fun ack(
            source: LifecycleEnvelope,
            messageId: String,
            actor: String,
            sender: String?,
            status: AckStatus,
            reason: String? = null,
            retryAfterMs: Long? = null,
            sentAt: String? = null,
        ): LifecycleEnvelope {
            source.validate()
            if (status == AckStatus.RETRY && (retryAfterMs == null || retryAfterMs <= 0)) {
                throw InvalidWireEnvelopeException(
                    "retry-after-ms requires a positive integer.",
                )
            }
            if (status != AckStatus.RETRY && retryAfterMs != null) {
                throw InvalidWireEnvelopeException(
                    "retry-after-ms is valid only for retry acknowledgements.",
                )
            }
            return LifecycleEnvelope(
                kind = EnvelopeKind.ACK,
                messageId = messageId,
                messageType = ACK_MESSAGE_TYPE,
                actor = actor,
                sender = sender,
                correlationId = source.correlationId,
                causationId = source.messageId,
                dataset = source.dataset,
                sentAt = sentAt,
                payload = LifecyclePayload.Ack(
                    status = status,
                    forMessageId = source.messageId,
                    reason = reason,
                    retryAfterMs = retryAfterMs,
                ),
            ).validate()
        }

        @JvmStatic
        fun error(
            source: LifecycleEnvelope,
            messageId: String,
            actor: String,
            sender: String?,
            code: String,
            message: String,
            retryable: Boolean,
            details: PortableValue? = null,
            sentAt: String? = null,
        ): LifecycleEnvelope {
            source.validate()
            return LifecycleEnvelope(
                kind = EnvelopeKind.ERROR,
                messageId = messageId,
                messageType = ERROR_MESSAGE_TYPE,
                actor = actor,
                sender = sender,
                correlationId = source.correlationId,
                causationId = source.messageId,
                dataset = source.dataset,
                sentAt = sentAt,
                payload = LifecyclePayload.Error(
                    forMessageId = source.messageId,
                    code = requireNonEmpty(code, "error code"),
                    message = requireNonEmpty(message, "error message"),
                    retryable = retryable,
                    details = details,
                ),
            ).validate()
        }

        @JvmStatic
        fun cancel(
            source: LifecycleEnvelope,
            messageId: String,
            actor: String,
            sender: String?,
            reason: String? = null,
            sentAt: String? = null,
        ): LifecycleEnvelope {
            source.validate()
            return LifecycleEnvelope(
                kind = EnvelopeKind.CANCEL,
                messageId = messageId,
                messageType = CANCEL_MESSAGE_TYPE,
                actor = actor,
                sender = sender,
                correlationId = source.correlationId,
                causationId = source.messageId,
                dataset = source.dataset,
                sentAt = sentAt,
                payload = LifecyclePayload.Cancel(
                    targetMessageId = source.messageId,
                    targetCorrelationId = source.correlationId,
                    reason = reason,
                ),
            ).validate()
        }

        private fun validateAckPayload(payload: LifecyclePayload): LifecyclePayload.Ack {
            val ack = payload as? LifecyclePayload.Ack
                ?: throw InvalidWireEnvelopeException("ACK requires an acknowledgement payload.")
            requireNonEmpty(ack.forMessageId, "ack for-message-id")
            if (ack.status == AckStatus.RETRY && (ack.retryAfterMs == null || ack.retryAfterMs <= 0)) {
                throw InvalidWireEnvelopeException(
                    "ack retry-after-ms requires a positive integer.",
                )
            }
            if (ack.status != AckStatus.RETRY && ack.retryAfterMs != null) {
                throw InvalidWireEnvelopeException(
                    "Only retry acknowledgements may carry retry-after-ms.",
                )
            }
            return ack
        }

        private fun validateErrorPayload(payload: LifecyclePayload): LifecyclePayload.Error {
            val error = payload as? LifecyclePayload.Error
                ?: throw InvalidWireEnvelopeException("ERROR requires an error payload.")
            requireNonEmpty(error.forMessageId, "error for-message-id")
            requireNonEmpty(error.code, "error code")
            requireNonEmpty(error.message, "error message")
            return error
        }

        private fun validateCancelPayload(payload: LifecyclePayload): LifecyclePayload.Cancel {
            val cancel = payload as? LifecyclePayload.Cancel
                ?: throw InvalidWireEnvelopeException("CANCEL requires a cancellation payload.")
            requireNonEmpty(cancel.targetMessageId, "cancel target-message-id")
            requireNonEmpty(cancel.targetCorrelationId, "cancel target-correlation-id")
            return cancel
        }

        internal fun requireNonEmpty(value: String?, context: String): String {
            if (value.isNullOrEmpty()) {
                throw InvalidWireEnvelopeException("$context requires a non-empty string.")
            }
            return value
        }
    }
}

data class IdempotencyScope(
    val actor: String,
    val messageType: String,
    val idempotencyKey: String,
)

enum class DeliveryOutcome {
    PENDING,
    ACCEPTED,
    COMPLETED,
    REJECTED,
    RETRY,
    FAILED,
    CANCEL_REQUESTED,
}

class InvalidWireEnvelopeException(message: String) :
    ActorRuntimeException(message)
