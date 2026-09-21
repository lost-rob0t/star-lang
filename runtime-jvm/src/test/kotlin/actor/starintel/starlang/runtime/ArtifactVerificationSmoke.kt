package actor.starintel.starlang.runtime

import java.math.BigInteger
import java.nio.file.Files

private fun artifactCheck(value: Boolean, message: String) {
    if (!value) error(message)
}

private fun testCanonicalJson(value: PortableValue): String = when (value) {
    PortableValue.Null -> "null"
    is PortableValue.Bool -> if (value.value) "true" else "false"
    is PortableValue.Int64 -> value.value.toString()
    is PortableValue.BigIntegerValue -> value.value.toString()
    is PortableValue.Float64 -> value.value.toString()
    is PortableValue.Decimal -> value.canonical
    is PortableValue.Text -> buildString {
        append('"')
        for (character in value.value) {
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(character)
            }
        }
        append('"')
    }
    is PortableValue.ListValue ->
        value.values.joinToString(prefix = "[", postfix = "]") {
            testCanonicalJson(it)
        }
    is PortableValue.ObjectValue ->
        value.fields.entries.joinToString(prefix = "{", postfix = "}") {
            "${testCanonicalJson(PortableValue.Text(it.key))}:" +
                testCanonicalJson(it.value)
        }
}

fun main() {
    val classes = VerificationVocabulary.classes()
    artifactCheck(
        classes == listOf(
            "evidence",
            "checked-conformance",
            "lifecycle-verified",
            "model-checked",
            "solver-certificate",
            "theorem-artifact",
        ),
        "verification class vocabulary",
    )
    artifactCheck(
        !VerificationVocabulary.isClaim("verified"),
        "generic verification claim accepted",
    )
    artifactCheck(
        VerificationVocabulary.isSha256Digest(
            "sha256:" + "a".repeat(64),
        ),
        "valid digest rejected",
    )
    artifactCheck(
        !VerificationVocabulary.isSha256Digest(
            "sha256:" + "A".repeat(64),
        ),
        "uppercase digest accepted",
    )

    val subject = "sha256:" + "a".repeat(64)
    val specification = "sha256:" + "b".repeat(64)
    val plan = "sha256:" + "c".repeat(64)
    val evidence = "sha256:" + "d".repeat(64)
    val certificate = VerificationCertificate.create(
        certificateId = "verify_01",
        verificationClass = VerificationVocabulary.CLASS_MODEL_CHECKED,
        claim = VerificationVocabulary.CLAIM_TOPOLOGY_PROTOCOL_DEADLOCK_FREE,
        subjectType = "star.actor-topology/1",
        subjectHash = subject,
        specificationDigest = specification,
        planDigest = plan,
        verifier = "star.verify.tlc/1",
        verifierVersion = "TLC2-2.19",
        assumptions = listOf("weak-fair-next"),
        bounds = mapOf(
            "retryLimit" to VerificationBound.Scalar(
                VerificationBoundScalar.IntegerValue(BigInteger.valueOf(2)),
            ),
            "actors" to VerificationBound.Scalar(
                VerificationBoundScalar.IntegerValue(BigInteger.valueOf(2)),
            ),
        ),
        evidence = listOf(evidence),
        result = VerificationVocabulary.RESULT_VALID,
    )
    artifactCheck(
        certificate.fields().keys.toList() ==
            VerificationCertificate.fieldNames(),
        "certificate field order",
    )
    artifactCheck(
        certificate.bounds.keys.toList() == listOf("actors", "retryLimit"),
        "certificate bound normalization",
    )
    val second = VerificationCertificate.create(
        certificateId = "verify_02",
        verificationClass = VerificationVocabulary.CLASS_MODEL_CHECKED,
        claim = VerificationVocabulary.CLAIM_TOPOLOGY_PROTOCOL_DEADLOCK_FREE,
        subjectType = "star.actor-topology/1",
        subjectHash = subject,
        specificationDigest = specification,
        planDigest = plan,
        verifier = "star.verify.tlc/1",
        verifierVersion = "TLC2-2.19",
        assumptions = listOf("weak-fair-next"),
        bounds = certificate.bounds,
        evidence = listOf(evidence),
        result = VerificationVocabulary.RESULT_VALID,
    )
    artifactCheck(
        certificate.semanticIdentity() == second.semanticIdentity(),
        "certificate id changed semantic identity",
    )
    try {
        VerificationCertificate.create(
            certificateId = "bad",
            verificationClass = VerificationVocabulary.CLASS_MODEL_CHECKED,
            claim = VerificationVocabulary.CLAIM_TOPOLOGY_PROTOCOL_DEADLOCK_FREE,
            subjectType = "star.actor-topology/1",
            subjectHash = subject,
            verifier = "test",
            verifierVersion = "1",
            result = VerificationVocabulary.RESULT_VALID,
        )
        error("underscoped model certificate accepted")
    } catch (_: InvalidVerificationCertificateException) {
    }

    val root = Files.createTempDirectory("starlang-artifact-smoke")
    try {
        val writer = JsonFileWriter(root)
        val document = PortableValue.ObjectValue.of(
            mapOf(
                "source" to PortableValue.Text("github"),
                "login" to PortableValue.Text("ada"),
            ),
        )
        val write = JsonFileWrite("github-members", "ada", document)
        val first = writer.write(write)
        artifactCheck(first.status == JsonFileStatus.WRITTEN, "first artifact write")
        artifactCheck(
            Files.readString(root.resolve("github-members/ada.json")) ==
                "{\"login\":\"ada\",\"source\":\"github\"}\n",
            "canonical artifact bytes",
        )
        val secondWrite = writer.write(write)
        artifactCheck(
            secondWrite.status == JsonFileStatus.UNCHANGED,
            "idempotent artifact write",
        )
        writer.write(
            JsonFileWrite(
                "github-members",
                "ada",
                PortableValue.ObjectValue.of(
                    mapOf(
                        "source" to PortableValue.Text("github-api"),
                        "login" to PortableValue.Text("ada"),
                    ),
                ),
            ),
        )
        artifactCheck(
            Files.readString(root.resolve("github-members/ada.json")) ==
                "{\"login\":\"ada\",\"source\":\"github-api\"}\n",
            "artifact replacement",
        )
        try {
            JsonFileWrite("../outside", "ada", document)
            error("path traversal accepted")
        } catch (_: InvalidJsonFileRecordException) {
        }
        try {
            JsonFileWrite("github-members", "..", document)
            error("parent id accepted")
        } catch (_: InvalidJsonFileRecordException) {
        }

        val runtime = StarRuntime.create()
        val actor = runtime.spawn(
            writer.actorDefinition("json-file-writer"),
        )
        val result = runtime.ask(
            actor,
            JsonFileWrite("github-members", "grace", document).toPortable(),
            1,
        )
        val resultFields = (result as PortableValue.ObjectValue).fields
        artifactCheck(
            (resultFields["status"] as PortableValue.Text).value == "written",
            "artifact actor status",
        )
    } finally {
        root.toFile().deleteRecursively()
    }

    println("runtime-jvm artifact/verification smoke: PASS")
}
