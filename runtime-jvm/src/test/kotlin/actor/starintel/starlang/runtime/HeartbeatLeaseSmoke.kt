package actor.starintel.starlang.runtime

private fun leaseCheck(value: Boolean, message: String) {
    if (!value) error(message)
}

fun main() {
    var now = 1_000L
    val lease = HeartbeatLease(
        timeoutMillis = 250,
        clock = LeaseClock { now },
    )

    leaseCheck(!lease.expired("worker"), "unseen key expired")
    lease.noteSeen("worker")
    leaseCheck(lease.lastSeenAt("worker") == 1_000L, "last seen time")
    leaseCheck(!lease.expired("worker", 1_249L), "lease expired early")
    leaseCheck(lease.expired("worker", 1_250L), "lease failed boundary expiry")

    now = 1_200L
    lease.noteSeen("worker")
    leaseCheck(!lease.expired("worker", 1_449L), "renewed lease expired early")
    leaseCheck(lease.expired("worker", 1_450L), "renewed lease boundary")

    leaseCheck(!lease.expired("worker", 1_100L), "backward observation expired")
    try {
        lease.expired("worker", -1L)
        error("negative expiry time accepted")
    } catch (_: LeaseException) {
    }

    val badClock = HeartbeatLease(
        timeoutMillis = 1,
        clock = LeaseClock { -1L },
    )
    try {
        badClock.noteSeen("bad")
        error("negative lease clock accepted")
    } catch (_: LeaseException) {
    }

    println("runtime-jvm heartbeat lease smoke: PASS")
}
