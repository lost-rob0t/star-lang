package actor.starintel.starlang.runtime

import java.math.BigInteger
import java.util.Collections

sealed interface PortableTypeRef {
    data class Named(val name: String) : PortableTypeRef {
        init {
            require(name.isNotBlank()) { "Portable type name must not be blank." }
        }
    }

    data class ListOf(val element: PortableTypeRef) : PortableTypeRef
    data class Optional(val element: PortableTypeRef) : PortableTypeRef

    companion object {
        @JvmStatic
        fun named(name: String): PortableTypeRef = Named(name)

        @JvmStatic
        fun listOf(element: PortableTypeRef): PortableTypeRef = ListOf(element)

        @JvmStatic
        fun optional(element: PortableTypeRef): PortableTypeRef =
            Optional(element)
    }
}

data class PortableFieldContract(
    val name: String,
    val type: PortableTypeRef,
    val required: Boolean,
) {
    init {
        require(name.isNotBlank()) { "Field contract name must not be blank." }
    }
}

sealed interface PortableTypeContract {
    val name: String
}

data class PortableScalarContract(
    override val name: String,
    val base: PortableTypeRef.Named,
    val minimum: BigInteger? = null,
    val maximum: BigInteger? = null,
    val scale: Int? = null,
) : PortableTypeContract {
    init {
        require(name.isNotBlank()) { "Scalar contract name must not be blank." }
        if (scale != null) require(scale >= 0) {
            "Scalar decimal scale must be nonnegative."
        }
    }
}

class PortableEnumContract(
    override val name: String,
    values: List<String>,
) : PortableTypeContract {
    val values: List<String> =
        Collections.unmodifiableList(values.toList())

    init {
        require(name.isNotBlank()) { "Enum contract name must not be blank." }
        require(this.values.isNotEmpty()) { "Enum contract requires values." }
        require(this.values.none(String::isBlank)) {
            "Enum values must not be blank."
        }
    }
}

class PortableDocumentContract(
    override val name: String,
    val extends: String? = null,
    fields: List<PortableFieldContract>,
) : PortableTypeContract {
    val fields: List<PortableFieldContract> =
        Collections.unmodifiableList(fields.toList())

    init {
        require(name.isNotBlank()) { "Document contract name must not be blank." }
        require(extends == null || extends.isNotBlank()) {
            "Document parent name must not be blank."
        }
    }
}

class PortableMessageContract @JvmOverloads constructor(
    val name: String,
    requiredFields: List<String> = emptyList(),
    fields: List<PortableFieldContract> = emptyList(),
) {
    val requiredFields: List<String> =
        Collections.unmodifiableList(requiredFields.toList())
    val fields: List<PortableFieldContract> =
        Collections.unmodifiableList(
            if (fields.isNotEmpty()) {
                fields.toList()
            } else {
                requiredFields.map {
                    PortableFieldContract(
                        it,
                        PortableTypeRef.Named("any"),
                        true,
                    )
                }
            },
        )

    init {
        require(name.isNotBlank()) { "Message contract name must not be blank." }
        require(this.requiredFields.none(String::isBlank)) {
            "Required message field names must not be blank."
        }
        val names = this.fields.map(PortableFieldContract::name)
        require(names.size == names.toSet().size) {
            "Message field names must be unique."
        }
    }
}

data class PortableActorContract(
    val name: String,
    val serviceUri: String? = null,
    accepts: List<String> = emptyList(),
    produces: List<String> = emptyList(),
) {
    val accepts: List<String> =
        Collections.unmodifiableList(accepts.toList())
    val produces: List<String> =
        Collections.unmodifiableList(produces.toList())

    init {
        require(name.isNotBlank()) { "Actor contract name must not be blank." }
        serviceUri?.let { StarServiceUri.canonicalForActor(name, it) }
    }

    fun accepts(messageType: String): Boolean = messageType in accepts
}

class PortableManifest @JvmOverloads constructor(
    val wireVersion: Int = 1,
    actors: List<PortableActorContract>,
    messages: List<PortableMessageContract> = emptyList(),
    types: List<PortableTypeContract> = emptyList(),
) {
    val actors: List<PortableActorContract> =
        Collections.unmodifiableList(actors.toList())
    val messages: List<PortableMessageContract> =
        Collections.unmodifiableList(messages.toList())
    val types: List<PortableTypeContract> =
        Collections.unmodifiableList(types.toList())

    init {
        require(wireVersion == 1) {
            "Portable manifest wireVersion must be 1."
        }
        require(types.map(PortableTypeContract::name).distinct().size == types.size) {
            "Portable manifest type names must be unique."
        }
        require(messages.map(PortableMessageContract::name).distinct().size ==
            messages.size) {
            "Portable manifest message names must be unique."
        }
        require(actors.map(PortableActorContract::name).distinct().size ==
            actors.size) {
            "Portable manifest actor names must be unique."
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

    fun typeContract(name: String): PortableTypeContract? =
        types.firstOrNull { it.name == name }

    fun validateDataPayload(
        messageType: String,
        payload: PortableValue,
    ) {
        val contract = messageContract(messageType)
            ?: throw InvalidWireEnvelopeException(
                "Unknown message type $messageType.",
            )
        validateFields(
            contract.fields,
            payload,
            "Message $messageType",
            emptySet(),
        )
    }

    internal fun jsonValueForMessage(
        messageType: String,
        payload: PortableValue,
    ): CanonicalJsonValue {
        val contract = messageContract(messageType)
            ?: throw InvalidWireEnvelopeException(
                "Unknown message type $messageType.",
            )
        validateFields(
            contract.fields,
            payload,
            "Message $messageType",
            emptySet(),
        )
        return jsonFields(
            contract.fields,
            payload as PortableValue.ObjectValue,
            "Message $messageType",
            emptySet(),
        )
    }

    fun validateValue(
        type: PortableTypeRef,
        value: PortableValue,
        context: String = "wire value",
    ) {
        validateValue(type, value, context, emptySet())
    }

    private fun validateValue(
        type: PortableTypeRef,
        value: PortableValue,
        context: String,
        visitingDocuments: Set<String>,
    ) {
        when (type) {
            is PortableTypeRef.ListOf -> {
                val list = value as? PortableValue.ListValue
                    ?: invalid("$context requires a list.")
                list.values.forEach {
                    validateValue(
                        type.element,
                        it,
                        context,
                        visitingDocuments,
                    )
                }
            }
            is PortableTypeRef.Optional -> {
                if (value != PortableValue.Null) {
                    validateValue(
                        type.element,
                        value,
                        context,
                        visitingDocuments,
                    )
                }
            }
            is PortableTypeRef.Named -> validateNamed(
                type.name,
                value,
                context,
                visitingDocuments,
            )
        }
    }

    private fun validateNamed(
        type: String,
        value: PortableValue,
        context: String,
        visitingDocuments: Set<String>,
    ) {
        when (type) {
            "any" -> validateGeneric(value, context)
            "string", "symbol", "iso-date", "iso-datetime" ->
                if (value !is PortableValue.Text) {
                    invalid("$context requires $type.")
                }
            "integer" ->
                if (
                    value !is PortableValue.Int64 &&
                    value !is PortableValue.BigIntegerValue
                ) {
                    invalid("$context requires an integer.")
                }
            "boolean" ->
                if (value !is PortableValue.Bool) {
                    invalid("$context requires a boolean.")
                }
            "decimal" -> {
                val text = decimalString(value)
                    ?: invalid(
                        "$context requires a decimal string to preserve wire precision.",
                    )
                if (!DECIMAL.matches(text)) {
                    invalid(
                        "$context requires a decimal string to preserve wire precision.",
                    )
                }
            }
            "map" -> validateMap(value, context)
            "reference" -> validateReference(value, context)
            else -> {
                val contract = typeContract(type)
                    ?: invalid("$context references unknown type $type.")
                when (contract) {
                    is PortableScalarContract -> {
                        validateValue(
                            contract.base,
                            value,
                            context,
                            visitingDocuments,
                        )
                        validateScalar(contract, value, context)
                    }
                    is PortableEnumContract -> {
                        val text = (value as? PortableValue.Text)?.value
                            ?: invalid(
                                "$context requires one of ${contract.values}.",
                            )
                        if (text !in contract.values) {
                            invalid(
                                "$context requires one of ${contract.values}, " +
                                    "received $text.",
                            )
                        }
                    }
                    is PortableDocumentContract -> {
                        val fields = documentFields(
                            contract,
                            visitingDocuments,
                        )
                        validateFields(
                            fields,
                            value,
                            context,
                            visitingDocuments + contract.name,
                        )
                    }
                }
            }
        }
    }

    private fun validateScalar(
        contract: PortableScalarContract,
        value: PortableValue,
        context: String,
    ) {
        val integer = integerValue(value)
        if (
            contract.minimum != null &&
            integer != null &&
            integer < contract.minimum
        ) {
            invalid("$context is below scalar minimum ${contract.minimum}.")
        }
        if (
            contract.maximum != null &&
            integer != null &&
            integer > contract.maximum
        ) {
            invalid("$context exceeds scalar maximum ${contract.maximum}.")
        }
        val scale = contract.scale
        if (scale != null) {
            val decimal = decimalString(value)
                ?: invalid(
                    "$context requires a decimal string with at most " +
                        "$scale fractional digits.",
                )
            val fractionDigits =
                decimal.substringAfter('.', "").length
            if (!DECIMAL.matches(decimal) || fractionDigits > scale) {
                invalid(
                    "$context requires a decimal string with at most " +
                        "$scale fractional digits.",
                )
            }
        }
    }

    private fun validateFields(
        contracts: List<PortableFieldContract>,
        value: PortableValue,
        context: String,
        visitingDocuments: Set<String>,
    ) {
        val fields = (value as? PortableValue.ObjectValue)?.fields
            ?: invalid("$context requires an object payload.")
        val known = contracts.map(PortableFieldContract::name).toSet()
        for (name in fields.keys) {
            if (name !in known) {
                invalid("$context contains unknown field $name.")
            }
        }
        for (field in contracts) {
            val item = fields[field.name]
            if (item == null) {
                if (field.required) {
                    invalid("$context is missing required field ${field.name}.")
                }
            } else {
                validateValue(
                    field.type,
                    item,
                    "$context field ${field.name}",
                    visitingDocuments,
                )
            }
        }
    }

    private fun documentFields(
        contract: PortableDocumentContract,
        visitingDocuments: Set<String>,
    ): List<PortableFieldContract> {
        if (contract.name in visitingDocuments) {
            invalid(
                "Document inheritance contains a cycle at ${contract.name}.",
            )
        }
        val parentName = contract.extends ?: return contract.fields
        val parent = typeContract(parentName) as? PortableDocumentContract
            ?: invalid(
                "Cannot resolve document parent $parentName while validating wire data.",
            )
        return documentFields(
            parent,
            visitingDocuments + contract.name,
        ) + contract.fields
    }

    private fun validateGeneric(
        value: PortableValue,
        context: String,
    ) {
        when (value) {
            PortableValue.Null,
            is PortableValue.Bool,
            is PortableValue.Int64,
            is PortableValue.BigIntegerValue,
            is PortableValue.Decimal,
            is PortableValue.Text,
            -> Unit
            is PortableValue.ListValue ->
                value.values.forEach {
                    validateGeneric(it, context)
                }
            is PortableValue.ObjectValue ->
                value.fields.values.forEach {
                    validateGeneric(it, context)
                }
            is PortableValue.Float64 ->
                invalid("$context contains unsupported generic float.")
        }
    }

    private fun validateMap(
        value: PortableValue,
        context: String,
    ) {
        val map = value as? PortableValue.ObjectValue
            ?: invalid("$context requires an object/map value.")
        map.fields.values.forEach {
            validateGeneric(it, context)
        }
    }

    private fun validateReference(
        value: PortableValue,
        context: String,
    ) {
        val map = value as? PortableValue.ObjectValue
            ?: invalid("$context requires reference fields schema and id.")
        if (
            map.fields["schema"] !is PortableValue.Text ||
            map.fields["id"] !is PortableValue.Text
        ) {
            invalid(
                "$context requires reference fields schema and id as strings.",
            )
        }
        validateMap(value, context)
    }

    private fun jsonFields(
        contracts: List<PortableFieldContract>,
        value: PortableValue.ObjectValue,
        context: String,
        visitingDocuments: Set<String>,
    ): CanonicalJsonValue.ObjectValue {
        val entries = linkedMapOf<String, CanonicalJsonValue>()
        for (field in contracts) {
            val item = value.fields[field.name] ?: continue
            entries[field.name] = jsonValueForType(
                field.type,
                item,
                "$context field ${field.name}",
                visitingDocuments,
            )
        }
        return CanonicalJsonValue.ObjectValue(entries)
    }

    private fun jsonValueForType(
        type: PortableTypeRef,
        value: PortableValue,
        context: String,
        visitingDocuments: Set<String>,
    ): CanonicalJsonValue {
        validateValue(type, value, context, visitingDocuments)
        return when (type) {
            is PortableTypeRef.ListOf ->
                CanonicalJsonValue.ArrayValue(
                    (value as PortableValue.ListValue).values.map {
                        jsonValueForType(
                            type.element,
                            it,
                            context,
                            visitingDocuments,
                        )
                    },
                )
            is PortableTypeRef.Optional ->
                if (value == PortableValue.Null) {
                    CanonicalJsonValue.Null
                } else {
                    jsonValueForType(
                        type.element,
                        value,
                        context,
                        visitingDocuments,
                    )
                }
            is PortableTypeRef.Named -> when (type.name) {
                "any", "map", "reference" ->
                    CanonicalJson.jsonValue(value)
                "string", "symbol", "iso-date", "iso-datetime" ->
                    CanonicalJsonValue.Text(
                        (value as PortableValue.Text).value,
                    )
                "integer" -> CanonicalJsonValue.IntegerValue(
                    integerValue(value)!!,
                )
                "boolean" -> CanonicalJsonValue.Bool(
                    (value as PortableValue.Bool).value,
                )
                "decimal" -> CanonicalJsonValue.Text(
                    decimalString(value)!!,
                )
                else -> when (val contract = typeContract(type.name)!!) {
                    is PortableScalarContract ->
                        jsonValueForType(
                            contract.base,
                            value,
                            context,
                            visitingDocuments,
                        )
                    is PortableEnumContract ->
                        CanonicalJsonValue.Text(
                            (value as PortableValue.Text).value,
                        )
                    is PortableDocumentContract -> {
                        val fields = documentFields(
                            contract,
                            visitingDocuments,
                        )
                        jsonFields(
                            fields,
                            value as PortableValue.ObjectValue,
                            context,
                            visitingDocuments + contract.name,
                        )
                    }
                }
            }
        }
    }

    private fun integerValue(value: PortableValue): BigInteger? =
        when (value) {
            is PortableValue.Int64 -> BigInteger.valueOf(value.value)
            is PortableValue.BigIntegerValue -> value.value
            else -> null
        }

    private fun decimalString(value: PortableValue): String? =
        when (value) {
            is PortableValue.Decimal -> value.canonical
            is PortableValue.Text -> value.value
            else -> null
        }

    private fun invalid(message: String): Nothing =
        throw InvalidWireEnvelopeException(message)

    companion object {
        private val DECIMAL = Regex("^[+-]?[0-9]+(?:\\.[0-9]+)?$")
    }
}
