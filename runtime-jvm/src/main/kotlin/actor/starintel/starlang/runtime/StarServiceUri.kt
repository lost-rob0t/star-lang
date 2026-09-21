package actor.starintel.starlang.runtime

data class StarServiceUri(
    val domain: String,
    val address: String,
    val actorName: String,
) {
    init {
        validateToken(domain, "domain")
        validateToken(address, "address")
        validateToken(actorName, "actor name")
    }

    override fun toString(): String =
        "star://$domain:$address:$actorName"

    companion object {
        private val token = Regex("[a-z0-9._-]+")

        private fun validateToken(value: String, label: String) {
            if (value.isEmpty() || !token.matches(value)) {
                throw InvalidStarServiceUriException(
                    "STAR service URI $label must be non-empty lowercase ASCII " +
                        "using only letters, digits, '.', '_', or '-': $value.",
                )
            }
        }

        @JvmStatic
        fun parse(value: String): StarServiceUri {
            if (!value.startsWith("star://")) {
                throw InvalidStarServiceUriException(
                    "STAR service URI must begin with star://, received $value.",
                )
            }
            val body = value.removePrefix("star://")
            val parts = body.split(':')
            if (parts.size != 3) {
                throw InvalidStarServiceUriException(
                    "STAR service URI must have exactly domain:address:actor-name " +
                        "after star://, received $value.",
                )
            }
            return StarServiceUri(parts[0], parts[1], parts[2])
        }

        @JvmStatic
        fun canonicalForActor(actorName: String, value: String): String {
            val uri = parse(value)
            if (uri.actorName != actorName) {
                throw InvalidStarServiceUriException(
                    "STAR service URI actor name ${uri.actorName} does not match " +
                        "actor contract $actorName.",
                )
            }
            return uri.toString()
        }

        @JvmStatic
        fun target(value: String): Boolean = value.startsWith("star://")
    }
}

class InvalidStarServiceUriException(message: String) :
    ActorRuntimeException(message)
