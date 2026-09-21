package actor.starintel.starlang.runtime

import java.math.BigInteger

private fun canonicalCheck(value: Boolean, message: String) {
    if (!value) error(message)
}

private fun doubleFromHex(hex: String): Double =
    Double.fromBits(java.lang.Long.parseUnsignedLong(hex, 16))

fun main() {
    canonicalCheck(
        CanonicalJson.encode(
            CanonicalJsonValue.ObjectValue(
                linkedMapOf(
                    "z" to CanonicalJsonValue.IntegerValue(2),
                    "a" to CanonicalJsonValue.IntegerValue(1),
                ),
            ),
        ) == "{\"a\":1,\"z\":2}",
        "canonical object sorting",
    )

    canonicalCheck(
        CanonicalJson.encode(
            CanonicalJsonValue.ArrayValue(
                listOf(
                    CanonicalJsonValue.Text("x"),
                    CanonicalJsonValue.Bool(true),
                    CanonicalJsonValue.Bool(false),
                    CanonicalJsonValue.Null,
                    CanonicalJsonValue.IntegerValue(-7),
                ),
            ),
        ) == "[\"x\",true,false,null,-7]",
        "canonical scalar array",
    )

    val escaped = "\"\\\n\t\u0001"
    canonicalCheck(
        CanonicalJson.encode(CanonicalJsonValue.Text(escaped)) ==
            "\"\\\"\\\\\\n\\t\\u0001\"",
        "canonical escaping",
    )

    val vectors = listOf(
        "0000000000000000" to "0",
        "8000000000000000" to "0",
        "0000000000000001" to "5e-324",
        "8000000000000001" to "-5e-324",
        "7fefffffffffffff" to "1.7976931348623157e+308",
        "ffefffffffffffff" to "-1.7976931348623157e+308",
        "4340000000000000" to "9007199254740992",
        "c340000000000000" to "-9007199254740992",
        "4430000000000000" to "295147905179352830000",
        "44b52d02c7e14af5" to "9.999999999999997e+22",
        "44b52d02c7e14af6" to "1e+23",
        "44b52d02c7e14af7" to "1.0000000000000001e+23",
        "444b1ae4d6e2ef4e" to "999999999999999700000",
        "444b1ae4d6e2ef4f" to "999999999999999900000",
        "444b1ae4d6e2ef50" to "1e+21",
        "3eb0c6f7a0b5ed8c" to "9.999999999999997e-7",
        "3eb0c6f7a0b5ed8d" to "0.000001",
        "41b3de4355555553" to "333333333.3333332",
        "41b3de4355555554" to "333333333.33333325",
        "41b3de4355555555" to "333333333.3333333",
        "41b3de4355555556" to "333333333.3333334",
        "41b3de4355555557" to "333333333.33333343",
        "becbf647612f3696" to "-0.0000033333333333333333",
        "43143ff3c1cb0959" to "1424953923781206.2",
        "4363c0c7485b9a7e" to "44479893619921900",
    )
    for ((hex, expected) in vectors) {
        val actual = CanonicalJson.binary64(doubleFromHex(hex))
        canonicalCheck(
            actual == expected,
            "binary64 $hex expected $expected, got $actual",
        )
    }
    for (value in listOf(
        Double.POSITIVE_INFINITY,
        Double.NEGATIVE_INFINITY,
        Double.NaN,
    )) {
        try {
            CanonicalJson.binary64(value)
            error("non-finite binary64 accepted")
        } catch (_: InvalidCanonicalJsonException) {
        }
    }

    canonicalCheck(
        CanonicalJson.encodePortable(
            PortableValue.BigIntegerValue(
                BigInteger("123456789012345678901234567890"),
            ),
        ) == "123456789012345678901234567890",
        "arbitrary precision integer JSON",
    )

    val manifest = PortableManifest(
        actors = listOf(
            PortableActorContract(
                name = "worker",
                serviceUri = "star://test:localhost:worker",
                accepts = listOf("test/run@1"),
                produces = listOf("test/result@1"),
            ),
        ),
        types = listOf(
            PortableScalarContract(
                name = "rating",
                base = PortableTypeRef.Named("integer"),
                minimum = BigInteger.ONE,
                maximum = BigInteger.valueOf(5),
            ),
            PortableScalarContract(
                name = "money",
                base = PortableTypeRef.Named("decimal"),
                scale = 2,
            ),
            PortableEnumContract(
                "status",
                listOf("new", "done"),
            ),
            PortableDocumentContract(
                name = "baseDoc",
                fields = listOf(
                    PortableFieldContract(
                        "id",
                        PortableTypeRef.Named("string"),
                        true,
                    ),
                ),
            ),
            PortableDocumentContract(
                name = "jobDoc",
                extends = "baseDoc",
                fields = listOf(
                    PortableFieldContract(
                        "status",
                        PortableTypeRef.Named("status"),
                        true,
                    ),
                    PortableFieldContract(
                        "rating",
                        PortableTypeRef.Named("rating"),
                        true,
                    ),
                    PortableFieldContract(
                        "amount",
                        PortableTypeRef.Named("money"),
                        true,
                    ),
                ),
            ),
        ),
        messages = listOf(
            PortableMessageContract(
                name = "test/run@1",
                fields = listOf(
                    PortableFieldContract(
                        "job",
                        PortableTypeRef.Named("jobDoc"),
                        true,
                    ),
                    PortableFieldContract(
                        "tags",
                        PortableTypeRef.ListOf(
                            PortableTypeRef.Named("string"),
                        ),
                        true,
                    ),
                    PortableFieldContract(
                        "enabled",
                        PortableTypeRef.Optional(
                            PortableTypeRef.Named("boolean"),
                        ),
                        false,
                    ),
                ),
            ),
            PortableMessageContract(
                name = "test/result@1",
                fields = listOf(
                    PortableFieldContract(
                        "ok",
                        PortableTypeRef.Named("boolean"),
                        true,
                    ),
                ),
            ),
        ),
    )

    val payload = PortableValue.ObjectValue.of(
        mapOf(
            "job" to PortableValue.ObjectValue.of(
                mapOf(
                    "id" to PortableValue.Text("job-1"),
                    "status" to PortableValue.Text("new"),
                    "rating" to PortableValue.BigIntegerValue(
                        BigInteger("5"),
                    ),
                    "amount" to PortableValue.Decimal("12.50"),
                ),
            ),
            "tags" to PortableValue.ListValue.of(
                listOf(
                    PortableValue.Text("alpha"),
                    PortableValue.Text("beta"),
                ),
            ),
            "enabled" to PortableValue.Bool(true),
        ),
    )
    manifest.validateDataPayload("test/run@1", payload)

    val command = LifecycleEnvelope.command(
        messageId = "cmd-1",
        messageType = "test/run@1",
        actor = "worker",
        sender = "caller",
        idempotencyKey = "idem-1",
        payload = payload,
    )
    canonicalCheck(
        CanonicalJson.encodeLifecycle(manifest, command) ==
            "{\"actor\":\"worker\",\"attempt\":1," +
            "\"correlationId\":\"cmd-1\",\"idempotencyKey\":\"idem-1\"," +
            "\"kind\":\"command\",\"messageId\":\"cmd-1\"," +
            "\"messageType\":\"test/run@1\",\"payload\":{" +
            "\"enabled\":true,\"job\":{" +
            "\"amount\":\"12.50\",\"id\":\"job-1\"," +
            "\"rating\":5,\"status\":\"new\"}," +
            "\"tags\":[\"alpha\",\"beta\"]}," +
            "\"sender\":\"caller\",\"starVersion\":1}",
        "canonical lifecycle bytes",
    )

    fun rejected(value: PortableValue): Boolean =
        try {
            manifest.validateDataPayload("test/run@1", value)
            false
        } catch (_: InvalidWireEnvelopeException) {
            true
        }

    canonicalCheck(
        rejected(
            PortableValue.ObjectValue.of(
                (payload.fields + (
                    "unknown" to PortableValue.Text("x")
                )),
            ),
        ),
        "unknown field accepted",
    )

    val badRating = PortableValue.ObjectValue.of(
        payload.fields + (
            "job" to PortableValue.ObjectValue.of(
                (payload.fields["job"] as PortableValue.ObjectValue)
                    .fields + (
                    "rating" to PortableValue.Int64(6)
                ),
            )
        ),
    )
    canonicalCheck(rejected(badRating), "scalar maximum ignored")

    val badDecimal = PortableValue.ObjectValue.of(
        payload.fields + (
            "job" to PortableValue.ObjectValue.of(
                (payload.fields["job"] as PortableValue.ObjectValue)
                    .fields + (
                    "amount" to PortableValue.Decimal("12.500")
                ),
            )
        ),
    )
    canonicalCheck(
        rejected(badDecimal),
        "decimal scalar scale ignored",
    )

    val mapManifest = PortableManifest(
        actors = emptyList(),
        messages = listOf(
            PortableMessageContract(
                "map/test@1",
                fields = listOf(
                    PortableFieldContract(
                        "data",
                        PortableTypeRef.Named("map"),
                        true,
                    ),
                ),
            ),
        ),
    )
    canonicalCheck(
        try {
            mapManifest.validateDataPayload(
                "map/test@1",
                PortableValue.ObjectValue.of(
                    mapOf(
                        "data" to PortableValue.ObjectValue.of(
                            mapOf("bad" to PortableValue.Float64(1.5)),
                        ),
                    ),
                ),
            )
            false
        } catch (_: InvalidWireEnvelopeException) {
            true
        },
        "generic float leaked into portable map",
    )

    println("runtime-jvm canonical JSON/protocol smoke: PASS")
}
