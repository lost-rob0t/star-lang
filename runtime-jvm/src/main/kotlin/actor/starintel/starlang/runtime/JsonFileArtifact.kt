package actor.starintel.starlang.runtime

import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.nio.channels.FileChannel
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption

fun interface CanonicalJsonEncoder {
    fun encode(value: PortableValue): String
}

enum class JsonFileStatus {
    WRITTEN,
    UNCHANGED,
}

data class JsonFileWrite(
    val collection: String,
    val id: String,
    val document: PortableValue,
) {
    init {
        requireSafePathSegment(collection, "collection")
        requireSafePathSegment(id, "id")
    }

    fun toPortable(): PortableValue.ObjectValue =
        PortableValue.ObjectValue.of(
            mapOf(
                "collection" to PortableValue.Text(collection),
                "id" to PortableValue.Text(id),
                "document" to document,
            ),
        )

    companion object {
        @JvmStatic
        fun fromPortable(value: PortableValue): JsonFileWrite {
            val fields = (value as? PortableValue.ObjectValue)?.fields
                ?: throw InvalidJsonFileRecordException(
                    "JSON file write requires an object payload.",
                )
            val collection = (fields["collection"] as? PortableValue.Text)?.value
                ?: throw InvalidJsonFileRecordException(
                    "JSON file write requires text collection.",
                )
            val id = (fields["id"] as? PortableValue.Text)?.value
                ?: throw InvalidJsonFileRecordException(
                    "JSON file write requires text id.",
                )
            val document = fields["document"]
                ?: throw InvalidJsonFileRecordException(
                    "JSON file write requires document.",
                )
            return JsonFileWrite(collection, id, document)
        }
    }
}

data class JsonFileResult(
    val status: JsonFileStatus,
    val collection: String,
    val id: String,
    val path: String,
) {
    fun toPortable(): PortableValue.ObjectValue =
        PortableValue.ObjectValue.of(
            mapOf(
                "status" to PortableValue.Text(
                    when (status) {
                        JsonFileStatus.WRITTEN -> "written"
                        JsonFileStatus.UNCHANGED -> "unchanged"
                    },
                ),
                "collection" to PortableValue.Text(collection),
                "id" to PortableValue.Text(id),
                "path" to PortableValue.Text(path),
            ),
        )
}

class JsonFileWriter @JvmOverloads constructor(
    root: Path,
    private val canonicalJson: CanonicalJsonEncoder =
        CanonicalJsonEncoder(CanonicalJson::encodePortable),
) {
    val root: Path = root.toAbsolutePath().normalize()

    @Synchronized
    fun write(record: JsonFileWrite): JsonFileResult {
        val target = targetPath(record)
        val temporary = target.resolveSibling(".${record.id}.json.tmp")
        val content = canonicalContent(record)
        val bytes = content.toByteArray(StandardCharsets.UTF_8)

        try {
            Files.createDirectories(target.parent)
            if (
                Files.exists(target) &&
                Files.readAllBytes(target).contentEquals(bytes)
            ) {
                return JsonFileResult(
                    JsonFileStatus.UNCHANGED,
                    record.collection,
                    record.id,
                    target.toString(),
                )
            }

            try {
                FileChannel.open(
                    temporary,
                    StandardOpenOption.CREATE,
                    StandardOpenOption.TRUNCATE_EXISTING,
                    StandardOpenOption.WRITE,
                ).use { channel ->
                    val buffer = ByteBuffer.wrap(bytes)
                    while (buffer.hasRemaining()) channel.write(buffer)
                    channel.force(true)
                }
                try {
                    Files.move(
                        temporary,
                        target,
                        StandardCopyOption.ATOMIC_MOVE,
                        StandardCopyOption.REPLACE_EXISTING,
                    )
                } catch (_: AtomicMoveNotSupportedException) {
                    Files.move(
                        temporary,
                        target,
                        StandardCopyOption.REPLACE_EXISTING,
                    )
                }
            } finally {
                Files.deleteIfExists(temporary)
            }
        } catch (condition: JsonFileException) {
            throw condition
        } catch (condition: IOException) {
            throw JsonFileWriteException(
                "Could not write JSON file for collection ${record.collection} " +
                    "and id ${record.id}.",
                condition,
            )
        }

        return JsonFileResult(
            JsonFileStatus.WRITTEN,
            record.collection,
            record.id,
            target.toString(),
        )
    }

    fun actorDefinition(
        name: String,
        serviceUri: String = "star://artifact:localhost:$name",
        metadata: Map<String, PortableValue> = emptyMap(),
    ): ActorDefinition = ActorDefinition.nativeActor(
        name = name,
        serviceUri = serviceUri,
        handler = ActorHandler { message, state, _ ->
            ActorTransition(
                output = write(JsonFileWrite.fromPortable(message)).toPortable(),
                stateUpdate = StateUpdate.Replace(state),
            )
        },
        accepts = listOf("star.artifact/json-file-write@1"),
        produces = listOf("star.artifact/json-file-result@1"),
        metadata = metadata,
    )

    private fun targetPath(record: JsonFileWrite): Path {
        val target = root
            .resolve(record.collection)
            .resolve("${record.id}.json")
            .normalize()
        if (!target.startsWith(root)) {
            throw InvalidJsonFileRecordException(
                "JSON file target escapes configured root.",
            )
        }
        return target
    }

    private fun canonicalContent(record: JsonFileWrite): String {
        val encoded = try {
            canonicalJson.encode(record.document)
        } catch (condition: Throwable) {
            throw InvalidJsonFileRecordException(
                "JSON file document is not canonical-JSON serializable.",
                condition,
            )
        }
        return "$encoded\n"
    }

    companion object {
        private val SAFE_SEGMENT = Regex("^[\\p{L}\\p{N}_@.-]+$")

        internal fun requireSafePathSegment(value: String, label: String) {
            if (
                value.isEmpty() ||
                value == "." ||
                value == ".." ||
                !SAFE_SEGMENT.matches(value)
            ) {
                throw InvalidJsonFileRecordException(
                    "JSON file $label must be a non-empty path-safe segment.",
                )
            }
        }
    }
}

private fun requireSafePathSegment(value: String, label: String) =
    JsonFileWriter.requireSafePathSegment(value, label)

open class JsonFileException(
    message: String,
    cause: Throwable? = null,
) : ActorRuntimeException(message) {
    init {
        if (cause != null) initCause(cause)
    }
}

class InvalidJsonFileRecordException(
    message: String,
    cause: Throwable? = null,
) : JsonFileException(message, cause)

class JsonFileWriteException(
    message: String,
    cause: Throwable? = null,
) : JsonFileException(message, cause)
