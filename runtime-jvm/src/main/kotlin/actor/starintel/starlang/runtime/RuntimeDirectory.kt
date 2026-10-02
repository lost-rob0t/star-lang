package actor.starintel.starlang.runtime

import java.util.Collections

enum class RuntimeAlive {
    ALIVE,
    DEAD,
    UNKNOWN,
}

class RuntimeDirectoryEntry(
    val name: String,
    val runtime: String,
    val alive: RuntimeAlive,
    capabilities: List<String> = emptyList(),
    serviceUri: String? = null,
    val domain: String? = null,
    val address: String? = null,
) {
    val capabilities: List<String> = Collections.unmodifiableList(capabilities.toList())

    val serviceUri: String? = serviceUri?.let { raw ->
        val uri = StarServiceUri.parse(raw)
        if (uri.actorName != name) {
            throw RuntimeDirectoryException(
                "Runtime directory actor $name does not match STAR service URI " +
                    "actor name ${uri.actorName}.",
            )
        }
        if (domain != null && domain != uri.domain) {
            throw RuntimeDirectoryException(
                "Runtime directory service domain $domain does not match URI " +
                    "domain ${uri.domain}.",
            )
        }
        if (address != null && address != uri.address) {
            throw RuntimeDirectoryException(
                "Runtime directory service address $address does not match URI " +
                    "address ${uri.address}.",
            )
        }
        uri.toString()
    }

    init {
        if (name.isEmpty()) {
            throw RuntimeDirectoryException(
                "Runtime directory actor name requires a non-empty string.",
            )
        }
        if (runtime.isEmpty()) {
            throw RuntimeDirectoryException(
                "Runtime directory actor $name requires a non-empty runtime.",
            )
        }
        if (capabilities.any(String::isEmpty)) {
            throw RuntimeDirectoryException(
                "Runtime directory actor $name capabilities must be non-empty strings.",
            )
        }
    }

    fun copyEntry(): RuntimeDirectoryEntry = RuntimeDirectoryEntry(
        name = name,
        runtime = runtime,
        alive = alive,
        capabilities = capabilities,
        serviceUri = serviceUri,
        domain = domain,
        address = address,
    )
}

fun interface RuntimeDirectorySnapshot {
    fun snapshot(context: PortableValue?): List<RuntimeDirectoryEntry>
}

class RuntimeDirectoryPort(
    private val snapshot: RuntimeDirectorySnapshot,
) {
    @JvmOverloads
    fun snapshot(context: PortableValue? = null): List<RuntimeDirectoryEntry> =
        try {
            snapshot.snapshot(context).map(RuntimeDirectoryEntry::copyEntry)
        } catch (condition: RuntimeDirectoryException) {
            throw condition
        } catch (condition: InvalidStarServiceUriException) {
            throw condition
        } catch (condition: Throwable) {
            throw RuntimeDirectoryException(
                "Runtime directory snapshot failed: ${condition.message ?: condition::class.java.name}",
                condition,
            )
        }

    @JvmOverloads
    fun resolve(
        uriValue: String,
        context: PortableValue? = null,
    ): RuntimeDirectoryEntry {
        val canonical = StarServiceUri.parse(uriValue).toString()
        val matches = snapshot(context).filter { it.serviceUri == canonical }
        return when {
            matches.isEmpty() -> throw RuntimeDirectoryServiceNotFoundException(
                "STAR service $canonical is not registered in the runtime directory.",
            )
            matches.size > 1 -> throw RuntimeDirectoryException(
                "STAR service $canonical has duplicate runtime-directory registrations.",
            )
            matches.single().alive == RuntimeAlive.DEAD ->
                throw RuntimeDirectoryServiceUnavailableException(
                    "STAR service $canonical is registered but not alive.",
                )
            else -> matches.single().copyEntry()
        }
    }
}

open class RuntimeDirectoryException(
    message: String,
    cause: Throwable? = null,
) : ActorRuntimeException(message) {
    init {
        if (cause != null) initCause(cause)
    }
}

class RuntimeDirectoryServiceNotFoundException(message: String) :
    RuntimeDirectoryException(message)

class RuntimeDirectoryServiceUnavailableException(message: String) :
    RuntimeDirectoryException(message)
