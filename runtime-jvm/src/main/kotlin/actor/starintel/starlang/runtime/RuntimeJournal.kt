package actor.starintel.starlang.runtime

import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.util.Collections

enum class RuntimeJournalEventKind {
    PENDING,
    ROUTE_RESULT,
    REMOTE_RESULT,
}

data class RuntimeJournalEvent(
    val kind: RuntimeJournalEventKind,
    val dispatcherSequence: Long,
    val dispatcherNow: String,
    val command: LifecycleEnvelope,
    val result: DispatchOutcome? = null,
) {
    fun validate(): RuntimeJournalEvent {
        if (dispatcherSequence < 0) {
            throw JournalException(
                "Runtime journal dispatcher sequence must be a nonnegative integer.",
            )
        }
        if (dispatcherNow.isEmpty()) {
            throw JournalException(
                "Runtime journal dispatcher clock requires a non-empty string.",
            )
        }
        command.validate()
        if (command.kind != EnvelopeKind.COMMAND) {
            throw JournalException(
                "Runtime journal command must be a lifecycle command envelope.",
            )
        }
        when (kind) {
            RuntimeJournalEventKind.PENDING -> {
                if (result != null) {
                    throw JournalException(
                        "Pending runtime journal event may not carry a result.",
                    )
                }
            }
            RuntimeJournalEventKind.ROUTE_RESULT,
            RuntimeJournalEventKind.REMOTE_RESULT,
            -> {
                when (result) {
                    is DispatchOutcome.Complete,
                    is DispatchOutcome.Retry,
                    is DispatchOutcome.Fail,
                    -> Unit
                    DispatchOutcome.Defer -> throw JournalException(
                        "Settled runtime journal result cannot be deferred.",
                    )
                    null -> throw JournalException(
                        "Settled runtime journal event requires a dispatch result.",
                    )
                }
            }
        }
        return this
    }
}

interface RuntimeJournalBackend {
    fun append(event: RuntimeJournalEvent)
    fun replay(): List<RuntimeJournalEvent>
}

class RuntimeJournalPort(
    private val backend: RuntimeJournalBackend,
) {
    @Synchronized
    fun append(event: RuntimeJournalEvent) {
        val owned = snapshotJournalEvent(event).validate()
        try {
            backend.append(owned)
        } catch (condition: JournalException) {
            throw condition
        } catch (condition: Throwable) {
            throw JournalException(
                "Runtime journal append failed: " +
                    (condition.message ?: condition::class.java.name),
                condition,
            )
        }
    }

    @Synchronized
    fun replay(): List<RuntimeJournalEvent> {
        val events = try {
            backend.replay().map(::snapshotJournalEvent)
        } catch (condition: JournalException) {
            throw condition
        } catch (condition: Throwable) {
            throw JournalException(
                "Runtime journal replay failed: " +
                    (condition.message ?: condition::class.java.name),
                condition,
            )
        }
        events.forEach(RuntimeJournalEvent::validate)
        validateJournalOrder(events)
        return Collections.unmodifiableList(events)
    }
}

class MemoryRuntimeJournalBackend : RuntimeJournalBackend {
    private val events = mutableListOf<RuntimeJournalEvent>()

    @Synchronized
    override fun append(event: RuntimeJournalEvent) {
        events += snapshotJournalEvent(event)
    }

    @Synchronized
    override fun replay(): List<RuntimeJournalEvent> =
        events.map(::snapshotJournalEvent)
}

fun interface JournalEncoder {
    fun encode(event: RuntimeJournalEvent): ByteArray
}

fun interface JournalDecoder {
    fun decode(record: ByteArray): RuntimeJournalEvent
}

class RuntimeJournalCodec(
    private val encoder: JournalEncoder,
    private val decoder: JournalDecoder,
) {
    fun encode(event: RuntimeJournalEvent): ByteArray =
        encoder.encode(event).copyOf()

    fun decode(record: ByteArray): RuntimeJournalEvent =
        decoder.decode(record.copyOf())
}

data class FileJournalLimits(
    val maxFileBytes: Long = 64L * 1024L * 1024L,
    val maxRecords: Int = 50_000,
    val maxRecordBytes: Int = 8 * 1024 * 1024,
) {
    init {
        require(maxFileBytes > 0) { "maxFileBytes must be positive." }
        require(maxRecords > 0) { "maxRecords must be positive." }
        require(maxRecordBytes > 0) { "maxRecordBytes must be positive." }
        require(maxRecordBytes.toLong() <= maxFileBytes) {
            "maxRecordBytes may not exceed maxFileBytes."
        }
    }
}

/**
 * Durable append-only framing for language-neutral journal records.
 *
 * Each record is:
 *   4-byte signed JVM int constrained to non-negative lengths, big endian
 *   exactly N codec bytes
 *
 * The codec is injected deliberately. The production codec is expected to be
 * canonical StarLang interchange (tracked with the canonical-JSON port), not
 * Java/Kotlin object serialization.
 */
class FileRuntimeJournalBackend(
    private val path: Path,
    private val codec: RuntimeJournalCodec,
    private val limits: FileJournalLimits = FileJournalLimits(),
) : RuntimeJournalBackend {
    @Synchronized
    override fun append(event: RuntimeJournalEvent) {
        val encoded = codec.encode(snapshotJournalEvent(event).validate())
        if (encoded.size > limits.maxRecordBytes) {
            throw JournalException(
                "File journal record exceeds the ${limits.maxRecordBytes}-byte limit.",
            )
        }

        val parent = path.parent
        if (parent != null) Files.createDirectories(parent)

        val currentSize = if (Files.exists(path)) Files.size(path) else 0L
        val appendedSize = 4L + encoded.size.toLong()
        if (currentSize > limits.maxFileBytes - appendedSize) {
            throw JournalException(
                "File journal would exceed the ${limits.maxFileBytes}-byte limit.",
            )
        }

        try {
            FileChannel.open(
                path,
                StandardOpenOption.CREATE,
                StandardOpenOption.WRITE,
                StandardOpenOption.APPEND,
            ).use { channel ->
                val header = ByteBuffer.allocate(4)
                    .order(ByteOrder.BIG_ENDIAN)
                    .putInt(encoded.size)
                header.flip()
                writeFully(channel, header)
                writeFully(channel, ByteBuffer.wrap(encoded))
                channel.force(true)
            }
        } catch (condition: IOException) {
            throw JournalException("File journal append failed.", condition)
        }
    }

    @Synchronized
    override fun replay(): List<RuntimeJournalEvent> {
        if (!Files.exists(path)) return emptyList()

        val observedSize = try {
            Files.size(path)
        } catch (condition: IOException) {
            throw JournalException("File journal size check failed.", condition)
        }
        if (observedSize > limits.maxFileBytes) {
            throw JournalException(
                "File journal exceeds the ${limits.maxFileBytes}-byte limit.",
            )
        }
        if (observedSize > Int.MAX_VALUE) {
            throw JournalException("File journal is too large for bounded replay.")
        }

        val snapshot = ByteArray(observedSize.toInt())
        try {
            FileChannel.open(path, StandardOpenOption.READ).use { channel ->
                val buffer = ByteBuffer.wrap(snapshot)
                while (buffer.hasRemaining()) {
                    val count = channel.read(buffer)
                    if (count < 0) {
                        throw JournalException(
                            "File journal changed or truncated during replay.",
                        )
                    }
                }
                val extra = ByteBuffer.allocate(1)
                if (channel.read(extra) >= 0) {
                    throw JournalException(
                        "File journal changed or grew during replay.",
                    )
                }
            }
            if (Files.size(path) != observedSize) {
                throw JournalException(
                    "File journal changed during replay.",
                )
            }
        } catch (condition: JournalException) {
            throw condition
        } catch (condition: IOException) {
            throw JournalException("File journal replay failed.", condition)
        }

        val buffer = ByteBuffer.wrap(snapshot).order(ByteOrder.BIG_ENDIAN)
        val events = mutableListOf<RuntimeJournalEvent>()
        while (buffer.hasRemaining()) {
            if (buffer.remaining() < 4) {
                throw JournalException(
                    "File journal contains a truncated record header.",
                )
            }
            val length = buffer.int
            if (length < 0 || length > limits.maxRecordBytes) {
                throw JournalException(
                    "File journal record length $length is outside the admitted range.",
                )
            }
            if (length > buffer.remaining()) {
                throw JournalException(
                    "File journal contains a truncated record body.",
                )
            }
            if (events.size >= limits.maxRecords) {
                throw JournalException(
                    "File journal record count exceeds ${limits.maxRecords}.",
                )
            }
            val record = ByteArray(length)
            buffer.get(record)
            val decoded = try {
                codec.decode(record)
            } catch (condition: JournalException) {
                throw condition
            } catch (condition: Throwable) {
                throw JournalException(
                    "File journal codec rejected a record.",
                    condition,
                )
            }
            events += snapshotJournalEvent(decoded).validate()
        }
        validateJournalOrder(events)
        return Collections.unmodifiableList(events)
    }

    private fun writeFully(channel: FileChannel, buffer: ByteBuffer) {
        while (buffer.hasRemaining()) {
            channel.write(buffer)
        }
    }
}

private fun validateJournalOrder(events: List<RuntimeJournalEvent>) {
    var previousSequence: Long? = null
    var previousNow: String? = null
    for (event in events) {
        val priorSequence = previousSequence
        if (priorSequence != null && event.dispatcherSequence < priorSequence) {
            throw JournalException(
                "Runtime journal dispatcher sequence moved backward from " +
                    "$priorSequence to ${event.dispatcherSequence}.",
            )
        }
        val priorNow = previousNow
        if (priorNow != null && event.dispatcherNow < priorNow) {
            throw JournalException(
                "Runtime journal dispatcher clock moved backward from " +
                    "$priorNow to ${event.dispatcherNow}.",
            )
        }
        previousSequence = event.dispatcherSequence
        previousNow = event.dispatcherNow
    }
}

private fun snapshotJournalEvent(event: RuntimeJournalEvent): RuntimeJournalEvent =
    RuntimeJournalEvent(
        kind = event.kind,
        dispatcherSequence = event.dispatcherSequence,
        dispatcherNow = event.dispatcherNow,
        command = snapshotLifecycleEnvelope(event.command),
        result = snapshotDispatchOutcome(event.result),
    )

private fun snapshotDispatchOutcome(
    outcome: DispatchOutcome?,
): DispatchOutcome? = when (outcome) {
    null -> null
    is DispatchOutcome.Complete -> DispatchOutcome.Complete(
        messageType = outcome.messageType,
        payload = snapshotPortableValue(outcome.payload),
    )
    is DispatchOutcome.Retry -> outcome.copy()
    is DispatchOutcome.Fail -> DispatchOutcome.Fail(
        code = outcome.code,
        message = outcome.message,
        retryable = outcome.retryable,
        details = outcome.details?.let(::snapshotPortableValue),
    )
    DispatchOutcome.Defer -> DispatchOutcome.Defer
}

private fun snapshotLifecycleEnvelope(
    envelope: LifecycleEnvelope,
): LifecycleEnvelope = envelope.copy(
    payload = when (val payload = envelope.payload) {
        is LifecyclePayload.Data ->
            LifecyclePayload.Data(snapshotPortableValue(payload.value))
        is LifecyclePayload.Ack -> payload.copy()
        is LifecyclePayload.Error -> payload.copy(
            details = payload.details?.let(::snapshotPortableValue),
        )
        is LifecyclePayload.Cancel -> payload.copy()
    },
)

private fun snapshotPortableValue(value: PortableValue): PortableValue = when (value) {
    PortableValue.Null -> PortableValue.Null
    is PortableValue.Bool -> value.copy()
    is PortableValue.Int64 -> value.copy()
    is PortableValue.BigIntegerValue -> value.copy()
    is PortableValue.Float64 -> value.copy()
    is PortableValue.Decimal -> value.copy()
    is PortableValue.Text -> value.copy()
    is PortableValue.ListValue ->
        PortableValue.ListValue.of(value.values.map(::snapshotPortableValue))
    is PortableValue.ObjectValue ->
        PortableValue.ObjectValue.of(
            value.fields.mapValues { (_, item) -> snapshotPortableValue(item) },
        )
}

open class JournalException(
    message: String,
    cause: Throwable? = null,
) : ActorRuntimeException(message) {
    init {
        if (cause != null) initCause(cause)
    }
}
