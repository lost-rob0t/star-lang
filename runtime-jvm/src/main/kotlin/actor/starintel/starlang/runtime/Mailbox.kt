package actor.starintel.starlang.runtime

enum class MailboxDeliveryStatus {
    ACCEPTED,
    FULL,
    CLOSED,
}

data class MailboxDelivery(
    val status: MailboxDeliveryStatus,
    val depth: Int,
    val capacity: Int,
)

class Mailbox<T>(val capacity: Int) {
    private val queue = ArrayDeque<T>()
    var isClosed: Boolean = false
        private set

    init {
        require(capacity > 0) { "Mailbox capacity must be a positive integer, received $capacity." }
    }

    val depth: Int
        get() = queue.size

    val isEmpty: Boolean
        get() = queue.isEmpty()

    val isFull: Boolean
        get() = queue.size >= capacity

    fun offer(message: T): MailboxDelivery = when {
        isClosed -> MailboxDelivery(MailboxDeliveryStatus.CLOSED, depth, capacity)
        isFull -> MailboxDelivery(MailboxDeliveryStatus.FULL, depth, capacity)
        else -> {
            queue.add(message)
            MailboxDelivery(MailboxDeliveryStatus.ACCEPTED, depth, capacity)
        }
    }

    fun poll(): T? = if (queue.isEmpty()) null else queue.removeFirst()

    fun snapshot(): List<T> = queue.toList()

    fun clear() {
        queue.clear()
    }

    @JvmOverloads
    fun close(discard: Boolean = false) {
        isClosed = true
        if (discard) clear()
    }
}
