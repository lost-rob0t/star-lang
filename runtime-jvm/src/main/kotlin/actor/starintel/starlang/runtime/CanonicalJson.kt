package actor.starintel.starlang.runtime

import java.math.BigInteger

sealed interface CanonicalJsonValue {
    data object Null : CanonicalJsonValue
    data class Bool(val value: Boolean) : CanonicalJsonValue
    data class Text(val value: String) : CanonicalJsonValue
    data class IntegerValue(val value: BigInteger) : CanonicalJsonValue {
        constructor(value: Long) : this(BigInteger.valueOf(value))
    }
    data class Binary64(val value: Double) : CanonicalJsonValue {
        init {
            if (!value.isFinite()) {
                throw InvalidCanonicalJsonException(
                    "RFC 8785 canonical JSON does not permit NaN or Infinity.",
                )
            }
        }
    }

    class ArrayValue(values: List<CanonicalJsonValue>) : CanonicalJsonValue {
        val values: List<CanonicalJsonValue> = values.toList()
    }

    class ObjectValue(entries: Map<String, CanonicalJsonValue>) :
        CanonicalJsonValue {
        val entries: Map<String, CanonicalJsonValue> = entries.toMap()
    }
}

object CanonicalJson {
    @JvmStatic
    fun encode(value: CanonicalJsonValue): String = buildString {
        writeValue(value, this)
    }

    @JvmStatic
    fun encodePortable(value: PortableValue): String =
        encode(jsonValue(value))

    @JvmStatic
    fun encodeLifecycle(
        manifest: PortableManifest,
        envelope: LifecycleEnvelope,
    ): String {
        envelope.validate(manifest)
        val entries = linkedMapOf<String, CanonicalJsonValue>(
            "starVersion" to CanonicalJsonValue.IntegerValue(1),
            "kind" to CanonicalJsonValue.Text(envelope.kind.wireName()),
            "messageId" to CanonicalJsonValue.Text(envelope.messageId),
            "messageType" to CanonicalJsonValue.Text(envelope.messageType),
            "actor" to CanonicalJsonValue.Text(envelope.actor),
            "correlationId" to CanonicalJsonValue.Text(envelope.correlationId),
            "attempt" to CanonicalJsonValue.IntegerValue(envelope.attempt),
        )
        envelope.sender?.let {
            entries["sender"] = CanonicalJsonValue.Text(it)
        }
        envelope.causationId?.let {
            entries["causationId"] = CanonicalJsonValue.Text(it)
        }
        envelope.idempotencyKey?.let {
            entries["idempotencyKey"] = CanonicalJsonValue.Text(it)
        }
        envelope.dataset?.let {
            entries["dataset"] = CanonicalJsonValue.Text(it)
        }
        envelope.replyTo?.let {
            entries["replyTo"] = CanonicalJsonValue.Text(it)
        }
        envelope.sentAt?.let {
            entries["sentAt"] = CanonicalJsonValue.Text(it)
        }
        envelope.deadline?.let {
            entries["deadline"] = CanonicalJsonValue.Text(it)
        }
        entries["payload"] = lifecyclePayloadJson(manifest, envelope)
        return encode(CanonicalJsonValue.ObjectValue(entries))
    }

    @JvmStatic
    fun binary64(value: Double): String {
        if (!value.isFinite()) {
            throw InvalidCanonicalJsonException(
                "RFC 8785 canonical JSON does not permit NaN or Infinity.",
            )
        }
        val bits = java.lang.Double.doubleToRawLongBits(value)
        val exponent = ((bits ushr 52) and 0x7ffL).toInt()
        val mantissa = bits and 0x000f_ffff_ffff_ffffL
        val negative = bits < 0
        if (exponent == 0 && mantissa == 0L) return "0"

        val shortest = shortestBinary64Decimal(
            BigInteger.valueOf(mantissa),
            exponent,
        )
        return writeShortestDecimal(
            shortest.first,
            shortest.second,
            negative,
        )
    }

    private fun writeValue(
        value: CanonicalJsonValue,
        out: StringBuilder,
    ) {
        when (value) {
            CanonicalJsonValue.Null -> out.append("null")
            is CanonicalJsonValue.Bool ->
                out.append(if (value.value) "true" else "false")
            is CanonicalJsonValue.Text ->
                writeEscaped(value.value, out)
            is CanonicalJsonValue.IntegerValue ->
                out.append(value.value.toString())
            is CanonicalJsonValue.Binary64 ->
                out.append(binary64(value.value))
            is CanonicalJsonValue.ArrayValue -> {
                out.append('[')
                value.values.forEachIndexed { index, item ->
                    if (index > 0) out.append(',')
                    writeValue(item, out)
                }
                out.append(']')
            }
            is CanonicalJsonValue.ObjectValue -> {
                out.append('{')
                value.entries.entries
                    .sortedWith { left, right ->
                        compareByCodePoint(left.key, right.key)
                    }
                    .forEachIndexed { index, entry ->
                        if (index > 0) out.append(',')
                        writeEscaped(entry.key, out)
                        out.append(':')
                        writeValue(entry.value, out)
                    }
                out.append('}')
            }
        }
    }

    private fun writeEscaped(value: String, out: StringBuilder) {
        out.append('"')
        for (character in value) {
            when (character) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\b' -> out.append("\\b")
                '\u000c' -> out.append("\\f")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                else -> {
                    if (character.code < 32) {
                        out.append("\\u")
                        out.append(
                            character.code
                                .toString(16)
                                .uppercase()
                                .padStart(4, '0'),
                        )
                    } else {
                        out.append(character)
                    }
                }
            }
        }
        out.append('"')
    }

    internal fun jsonValue(value: PortableValue): CanonicalJsonValue =
        when (value) {
            PortableValue.Null -> CanonicalJsonValue.Null
            is PortableValue.Bool -> CanonicalJsonValue.Bool(value.value)
            is PortableValue.Int64 ->
                CanonicalJsonValue.IntegerValue(value.value)
            is PortableValue.BigIntegerValue ->
                CanonicalJsonValue.IntegerValue(value.value)
            is PortableValue.Float64 ->
                CanonicalJsonValue.Binary64(value.value)
            is PortableValue.Decimal ->
                CanonicalJsonValue.Text(value.canonical)
            is PortableValue.Text ->
                CanonicalJsonValue.Text(value.value)
            is PortableValue.ListValue ->
                CanonicalJsonValue.ArrayValue(
                    value.values.map(::jsonValue),
                )
            is PortableValue.ObjectValue ->
                CanonicalJsonValue.ObjectValue(
                    value.fields.mapValues { (_, item) ->
                        jsonValue(item)
                    },
                )
        }

    private fun lifecyclePayloadJson(
        manifest: PortableManifest,
        envelope: LifecycleEnvelope,
    ): CanonicalJsonValue = when (val payload = envelope.payload) {
        is LifecyclePayload.Data -> manifest.jsonValueForMessage(
            envelope.messageType,
            payload.value,
        )
        is LifecyclePayload.Ack -> {
            val entries = linkedMapOf<String, CanonicalJsonValue>(
                "status" to CanonicalJsonValue.Text(
                    payload.status.wireName(),
                ),
                "forMessageId" to CanonicalJsonValue.Text(
                    payload.forMessageId,
                ),
            )
            payload.reason?.let {
                entries["reason"] = CanonicalJsonValue.Text(it)
            }
            payload.retryAfterMs?.let {
                entries["retryAfterMs"] =
                    CanonicalJsonValue.IntegerValue(it)
            }
            CanonicalJsonValue.ObjectValue(entries)
        }
        is LifecyclePayload.Error -> {
            val entries = linkedMapOf<String, CanonicalJsonValue>(
                "forMessageId" to
                    CanonicalJsonValue.Text(payload.forMessageId),
                "code" to CanonicalJsonValue.Text(payload.code),
                "message" to CanonicalJsonValue.Text(payload.message),
                "retryable" to CanonicalJsonValue.Bool(payload.retryable),
            )
            payload.details?.let {
                entries["details"] = jsonValue(it)
            }
            CanonicalJsonValue.ObjectValue(entries)
        }
        is LifecyclePayload.Cancel -> {
            val entries = linkedMapOf<String, CanonicalJsonValue>(
                "targetMessageId" to
                    CanonicalJsonValue.Text(payload.targetMessageId),
                "targetCorrelationId" to
                    CanonicalJsonValue.Text(payload.targetCorrelationId),
            )
            payload.reason?.let {
                entries["reason"] = CanonicalJsonValue.Text(it)
            }
            CanonicalJsonValue.ObjectValue(entries)
        }
    }

    private fun EnvelopeKind.wireName(): String =
        name.lowercase().replace('_', '-')

    private fun AckStatus.wireName(): String =
        name.lowercase().replace('_', '-')

    private fun compareByCodePoint(left: String, right: String): Int {
        var li = 0
        var ri = 0
        while (li < left.length && ri < right.length) {
            val l = left.codePointAt(li)
            val r = right.codePointAt(ri)
            if (l != r) return l.compareTo(r)
            li += Character.charCount(l)
            ri += Character.charCount(r)
        }
        return (left.length - li).compareTo(right.length - ri)
    }

    private fun shortestBinary64Decimal(
        ieeeMantissa: BigInteger,
        ieeeExponent: Int,
    ): Pair<BigInteger, Int> {
        val e2 =
            if (ieeeExponent == 0) {
                1 - 1023 - 52 - 2
            } else {
                ieeeExponent - 1023 - 52 - 2
            }
        val m2 =
            if (ieeeExponent == 0) {
                ieeeMantissa
            } else {
                BigInteger.ONE.shiftLeft(52).or(ieeeMantissa)
            }
        val acceptBounds = !m2.testBit(0)
        var mv = m2.shiftLeft(2)
        var mp = mv + TWO
        val mmShift =
            if (ieeeMantissa.signum() != 0 || ieeeExponent <= 1) 1 else 0
        var mm = mv - BigInteger.ONE - BigInteger.valueOf(mmShift.toLong())

        var vr: BigInteger
        var vp: BigInteger
        var vm: BigInteger
        val e10: Int
        var vmTrailingZero = false
        var vrTrailingZero = false

        if (e2 >= 0) {
            val q = log10PowerOfTwo(e2) - if (e2 > 3) 1 else 0
            val denominator = BigInteger.TEN.pow(q)
            vr = mv.shiftLeft(e2) / denominator
            vp = mp.shiftLeft(e2) / denominator
            vm = mm.shiftLeft(e2) / denominator
            e10 = q
            if (q <= 21) {
                when {
                    mv.mod(FIVE) == BigInteger.ZERO ->
                        vrTrailingZero = multipleOfPower(mv, FIVE, q)
                    acceptBounds ->
                        vmTrailingZero = multipleOfPower(mm, FIVE, q)
                    multipleOfPower(mp, FIVE, q) ->
                        vp -= BigInteger.ONE
                }
            }
        } else {
            val negativeE2 = -e2
            val q =
                log10PowerOfFive(negativeE2) -
                    if (negativeE2 > 1) 1 else 0
            val denominator = BigInteger.TEN.pow(q)
            val scale = FIVE.pow(negativeE2)
            vr = mv * scale / denominator
            vp = mp * scale / denominator
            vm = mm * scale / denominator
            e10 = q + e2
            when {
                q <= 1 -> {
                    vrTrailingZero = true
                    if (acceptBounds) {
                        vmTrailingZero = mmShift == 1
                    } else {
                        vp -= BigInteger.ONE
                    }
                }
                q < 63 ->
                    vrTrailingZero = multipleOfPower(
                        mv,
                        TWO,
                        q,
                    )
            }
        }

        var removed = 0
        var lastRemovedDigit = 0
        val output: BigInteger

        if (vmTrailingZero || vrTrailingZero) {
            while (vp / TEN > vm / TEN) {
                vmTrailingZero =
                    vmTrailingZero && vm.mod(TEN) == BigInteger.ZERO
                vrTrailingZero =
                    vrTrailingZero && lastRemovedDigit == 0
                lastRemovedDigit = vr.mod(TEN).toInt()
                vp /= TEN
                vr /= TEN
                vm /= TEN
                removed += 1
            }
            while (vmTrailingZero && vm.mod(TEN) == BigInteger.ZERO) {
                vrTrailingZero =
                    vrTrailingZero && lastRemovedDigit == 0
                lastRemovedDigit = vr.mod(TEN).toInt()
                vp /= TEN
                vr /= TEN
                vm /= TEN
                removed += 1
            }
            if (
                vrTrailingZero &&
                lastRemovedDigit == 5 &&
                !vr.testBit(0)
            ) {
                lastRemovedDigit = 4
            }
            output =
                vr +
                    if (
                        (vr == vm &&
                            (!acceptBounds || !vmTrailingZero)) ||
                        lastRemovedDigit >= 5
                    ) {
                        BigInteger.ONE
                    } else {
                        BigInteger.ZERO
                    }
        } else {
            var roundUp = false
            while (vp / TEN > vm / TEN) {
                roundUp = vr.mod(TEN).toInt() >= 5
                vp /= TEN
                vr /= TEN
                vm /= TEN
                removed += 1
            }
            output =
                vr +
                    if (vr == vm || roundUp) {
                        BigInteger.ONE
                    } else {
                        BigInteger.ZERO
                    }
        }
        return output to (e10 + removed)
    }

    private fun writeShortestDecimal(
        mantissa: BigInteger,
        exponent: Int,
        negative: Boolean,
    ): String {
        val digits = mantissa.toString()
        val digitCount = digits.length
        val decimalPoint = digitCount + exponent

        return buildString {
            if (negative) append('-')
            when {
                decimalPoint > 0 && decimalPoint <= 21 -> {
                    if (decimalPoint >= digitCount) {
                        append(digits)
                        repeat(decimalPoint - digitCount) {
                            append('0')
                        }
                    } else {
                        append(digits, 0, decimalPoint)
                        append('.')
                        append(digits, decimalPoint, digitCount)
                    }
                }
                decimalPoint <= 0 && decimalPoint > -6 -> {
                    append("0.")
                    repeat(-decimalPoint) {
                        append('0')
                    }
                    append(digits)
                }
                else -> {
                    append(digits[0])
                    if (digitCount > 1) {
                        append('.')
                        append(digits, 1, digitCount)
                    }
                    append('e')
                    val scientificExponent = decimalPoint - 1
                    if (scientificExponent >= 0) append('+')
                    append(scientificExponent)
                }
            }
        }
    }

    private fun log10PowerOfTwo(exponent: Int): Int =
        ((exponent.toLong() * 78_913L) shr 18).toInt()

    private fun log10PowerOfFive(exponent: Int): Int =
        ((exponent.toLong() * 732_923L) shr 20).toInt()

    private fun multipleOfPower(
        value: BigInteger,
        base: BigInteger,
        exponent: Int,
    ): Boolean =
        exponent == 0 ||
            value.mod(base.pow(exponent)) == BigInteger.ZERO

    private val TWO = BigInteger.valueOf(2)
    private val FIVE = BigInteger.valueOf(5)
    private val TEN = BigInteger.TEN
}

open class CanonicalJsonException(message: String) :
    ActorRuntimeException(message)

class InvalidCanonicalJsonException(message: String) :
    CanonicalJsonException(message)
