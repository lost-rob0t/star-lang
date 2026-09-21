package actor.starintel.starlang.runtime

data class PortableMessageContract(
    val name: String,
    requiredFields: List<String> = emptyList(),
) {
    val requiredFields: List<String> = requiredFields.toList()

    init {
        require(name.isNotBlank()) { "Message contract name must not be blank." }
        require(this.requiredFields.none(String::isBlank)) {
            "Required message field names must not be blank."
        }
    }
}

data class PortableActorContract(
    val name: String,
    val serviceUri: String? = null,
    accepts: List<String> = emptyList(),
    produces: List<String> = emptyList(),
) {
    val accepts: List<String> = accepts.toList()
    val produces: List<String> = produces.toList()

    init {
        require(name.isNotBlank()) { "Actor contract name must not be blank." }
        serviceUri?.let { StarServiceUri.canonicalForActor(name, it) }
    }

    fun accepts(messageType: String): Boolean = messageType in accepts
}

data class PortableManifest(
    val wireVersion: Int = 1,
    actors: List<PortableActorContract>,
    messages: List<PortableMessageContract> = emptyList(),
) {
    val actors: List<PortableActorContract> = actors.toList()
    val messages: List<PortableMessageContract> = messages.toList()

    init {
        require(wireVersion == 1) {
            "Portable manifest wireVersion must be 1."
        }
    }

    fun actorContract(target: String): PortableActorContract? =
        if (StarServiceUri.target(target)) {
            val canonical = StarServiceUri.parse(target).toString()
            actors.firstOrNull { it.serviceUri == canonical }
        } else {
            actors.firstOrNull { it.name == target }
        }

    fun messageContract(messageType: String): PortableMessageContract? =
        messages.firstOrNull { it.name == messageType }

    fun validateDataPayload(messageType: String, payload: PortableValue) {
        val contract = messageContract(messageType)
            ?: throw InvalidWireEnvelopeException(
                "Unknown message type $messageType.",
            )
        if (contract.requiredFields.isEmpty()) return
        val fields = (payload as? PortableValue.ObjectValue)?.fields
            ?: throw InvalidWireEnvelopeException(
                "Message $messageType requires an object payload.",
            )
        for (field in contract.requiredFields) {
            if (!fields.containsKey(field)) {
                throw InvalidWireEnvelopeException(
                    "Message $messageType is missing required field $field.",
                )
            }
        }
    }
}
