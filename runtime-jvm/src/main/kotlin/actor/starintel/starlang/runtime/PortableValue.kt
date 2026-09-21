package actor.starintel.starlang.runtime

import java.util.Collections
import java.util.TreeMap

sealed interface PortableValue {
    data object Null : PortableValue
    data class Bool(val value: Boolean) : PortableValue
    data class Int64(val value: Long) : PortableValue
    data class Float64(val value: Double) : PortableValue {
        init {
            require(value.isFinite()) { "Portable Float64 values must be finite." }
        }
    }
    data class Decimal(val canonical: String) : PortableValue
    data class Text(val value: String) : PortableValue

    class ListValue private constructor(values: List<PortableValue>) : PortableValue {
        val values: List<PortableValue> = Collections.unmodifiableList(values.toList())

        override fun equals(other: Any?): Boolean =
            other is ListValue && values == other.values

        override fun hashCode(): Int = values.hashCode()

        override fun toString(): String = "ListValue(values=$values)"

        companion object {
            @JvmStatic
            fun of(values: List<PortableValue>): ListValue = ListValue(values)
        }
    }

    class ObjectValue private constructor(fields: Map<String, PortableValue>) : PortableValue {
        val fields: Map<String, PortableValue> = Collections.unmodifiableMap(TreeMap(fields))

        override fun equals(other: Any?): Boolean =
            other is ObjectValue && fields == other.fields

        override fun hashCode(): Int = fields.hashCode()

        override fun toString(): String = "ObjectValue(fields=$fields)"

        companion object {
            @JvmStatic
            fun of(fields: Map<String, PortableValue>): ObjectValue = ObjectValue(fields)
        }
    }
}
