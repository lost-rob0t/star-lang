package actor.starintel.starlang.runtime

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files

private fun journalCheck(value: Boolean, message: String) {
    if (!value) error(message)
}

private fun journalCommand(
    messageId: String,
    idempotencyKey: String,
): LifecycleEnvelope = LifecycleEnvelope.command(
    messageId = messageId,
    messageType = "test/run@1",
    actor = "worker",
    sender = "caller",
    idempotencyKey = idempotencyKey,
    payload = PortableValue.ObjectValue.of(
        mapOf("target" to PortableValue.Text("example.org")),
    ),
)

private fun journalEvent(
    kind: RuntimeJournalEventKind,
    sequence: Long,
    messageId: String,
    result: DispatchOutcome? = null,
): RuntimeJournalEvent = RuntimeJournalEvent(
    kind = kind,
    dispatcherSequence = sequence,
    dispatcherNow = "2026-09-20T22:00:0${sequence}Z",
    command = journalCommand(messageId, "key-$messageId"),
    result = result,
)

private fun testCodec(): RuntimeJournalCodec = RuntimeJournalCodec(
    encoder = JournalEncoder { event ->
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            out.writeUTF(event.kind.name)
            out.writeLong(event.dispatcherSequence)
            out.writeUTF(event.dispatcherNow)
            out.writeUTF(event.command.messageId)
            out.writeUTF(event.command.idempotencyKey!!)
            when (val result = event.result) {
                null -> out.writeByte(0)
                is DispatchOutcome.Complete -> {
                    out.writeByte(1)
                    out.writeUTF(result.messageType ?: "")
                    val value = result.payload as PortableValue.Text
                    out.writeUTF(value.value)
                }
                is DispatchOutcome.Retry -> {
                    out.writeByte(2)
                    out.writeLong(result.retryAfterMs)
                    out.writeUTF(result.reason ?: "")
                }
                is DispatchOutcome.Fail -> {
                    out.writeByte(3)
                    out.writeUTF(result.code)
                    out.writeUTF(result.message)
                    out.writeBoolean(result.retryable)
                }
                DispatchOutcome.Defer -> error("defer is not journal-settled")
            }
        }
        bytes.toByteArray()
    },
    decoder = JournalDecoder { record ->
        DataInputStream(ByteArrayInputStream(record)).use { input ->
            val kind = RuntimeJournalEventKind.valueOf(input.readUTF())
            val sequence = input.readLong()
            val now = input.readUTF()
            val messageId = input.readUTF()
            val idempotencyKey = input.readUTF()
            val result = when (input.readByte().toInt()) {
                0 -> null
                1 -> DispatchOutcome.Complete(
                    messageType = input.readUTF().ifEmpty { null },
                    payload = PortableValue.Text(input.readUTF()),
                )
                2 -> DispatchOutcome.Retry(
                    retryAfterMs = input.readLong(),
                    reason = input.readUTF().ifEmpty { null },
                )
                3 -> DispatchOutcome.Fail(
                    code = input.readUTF(),
                    message = input.readUTF(),
                    retryable = input.readBoolean(),
                )
                else -> error("unknown test journal result")
            }
            RuntimeJournalEvent(
                kind = kind,
                dispatcherSequence = sequence,
                dispatcherNow = now,
                command = journalCommand(messageId, idempotencyKey),
                result = result,
            )
        }
    },
)

fun main() {
    val memory = RuntimeJournalPort(MemoryRuntimeJournalBackend())
    memory.append(
        journalEvent(
            RuntimeJournalEventKind.PENDING,
            1,
            "pending-1",
        ),
    )
    memory.append(
        journalEvent(
            RuntimeJournalEventKind.ROUTE_RESULT,
            2,
            "settled-1",
            DispatchOutcome.Complete(
                "test/result@1",
                PortableValue.Text("ok"),
            ),
        ),
    )
    val replayed = memory.replay()
    journalCheck(replayed.size == 2, "memory replay count")
    journalCheck(
        replayed[1].dispatcherSequence == 2L,
        "memory replay ordering",
    )

    var appendCalls = 0
    val rejectingPort = RuntimeJournalPort(
        object : RuntimeJournalBackend {
            override fun append(event: RuntimeJournalEvent) {
                appendCalls += 1
            }

            override fun replay(): List<RuntimeJournalEvent> = emptyList()
        },
    )
    try {
        rejectingPort.append(
            journalEvent(
                RuntimeJournalEventKind.PENDING,
                1,
                "bad-pending",
                DispatchOutcome.Complete(),
            ),
        )
        error("invalid pending event reached backend")
    } catch (_: JournalException) {
    }
    journalCheck(appendCalls == 0, "invalid append mutated backend")

    val badOrder = RuntimeJournalPort(
        object : RuntimeJournalBackend {
            override fun append(event: RuntimeJournalEvent) = Unit

            override fun replay(): List<RuntimeJournalEvent> = listOf(
                journalEvent(RuntimeJournalEventKind.PENDING, 2, "order-2"),
                journalEvent(RuntimeJournalEventKind.PENDING, 1, "order-1"),
            )
        },
    )
    try {
        badOrder.replay()
        error("backward journal sequence accepted")
    } catch (_: JournalException) {
    }

    val tempDir = Files.createTempDirectory("starlang-journal-smoke")
    val journalPath = tempDir.resolve("runtime.journal")
    try {
        val fileBackend = FileRuntimeJournalBackend(
            journalPath,
            testCodec(),
        )
        val filePort = RuntimeJournalPort(fileBackend)
        filePort.append(
            journalEvent(
                RuntimeJournalEventKind.PENDING,
                1,
                "file-pending",
            ),
        )
        filePort.append(
            journalEvent(
                RuntimeJournalEventKind.REMOTE_RESULT,
                2,
                "file-result",
                DispatchOutcome.Retry(25, "remote retry"),
            ),
        )
        val fileReplay = filePort.replay()
        journalCheck(fileReplay.size == 2, "file replay count")
        journalCheck(
            fileReplay[1].result is DispatchOutcome.Retry,
            "file replay result",
        )

        Files.write(
            journalPath,
            byteArrayOf(0, 0, 0, 5, 1, 2),
        )
        try {
            filePort.replay()
            error("truncated journal body accepted")
        } catch (_: JournalException) {
        }

        val boundedPath = tempDir.resolve("bounded.journal")
        val tiny = RuntimeJournalPort(
            FileRuntimeJournalBackend(
                boundedPath,
                testCodec(),
                FileJournalLimits(
                    maxFileBytes = 64,
                    maxRecords = 2,
                    maxRecordBytes = 16,
                ),
            ),
        )
        try {
            tiny.append(
                journalEvent(
                    RuntimeJournalEventKind.PENDING,
                    1,
                    "record-too-large",
                ),
            )
            error("oversized journal record accepted")
        } catch (_: JournalException) {
        }
        journalCheck(
            !Files.exists(boundedPath) || Files.size(boundedPath) == 0L,
            "rejected record extended file",
        )
    } finally {
        tempDir.toFile().deleteRecursively()
    }

    val objectValue = PortableValue.ObjectValue.of(
        mapOf("owned" to PortableValue.Text("yes")),
    )
    try {
        @Suppress("UNCHECKED_CAST")
        (objectValue.fields as MutableMap<String, PortableValue>)["owned"] =
            PortableValue.Text("mutated")
        error("portable object map remained JVM-mutable")
    } catch (_: UnsupportedOperationException) {
    }

    println("runtime-jvm journal smoke: PASS")
}
