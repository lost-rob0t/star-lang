package actor.starintel.starlang.runtime

fun interface LeaseClock {
    fun nowMillis(): Long
}

class HeartbeatLease @JvmOverloads constructor(
    val timeoutMillis: Long = 15_000,
    private val clock: LeaseClock =
        LeaseClock { System.nanoTime() / 1_000_000L },
) {
    private val lastSeen = LinkedHashMap<Any, Long>()

    init {
        require(timeoutMillis > 0) {
            "Heartbeat lease timeout must be a positive integer."
        }
    }

    @Synchronized
    fun now(): Long {
        val value = clock.nowMillis()
        if (value < 0) {
            throw LeaseException(
                "Heartbeat lease clock must return a nonnegative integer, " +
                    "received $value.",
            )
        }
        return value
    }

    @Synchronized
    fun noteSeen(key: Any): Any {
        lastSeen[key] = now()
        return key
    }

    @Synchronized
    fun lastSeenAt(key: Any): Long? = lastSeen[key]

    @JvmOverloads
    @Synchronized
    fun expired(key: Any, atMillis: Long = now()): Boolean {
        if (atMillis < 0) {
            throw LeaseException(
                "Heartbeat lease expiry time must be a nonnegative integer, " +
                    "received $atMillis.",
            )
        }
        val seen = lastSeen[key] ?: return false
        return atMillis - seen >= timeoutMillis
    }
}

open class LeaseException(message: String) : ActorRuntimeException(message)
