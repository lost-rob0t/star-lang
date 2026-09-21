package actor.starintel.starlang.runtime

import java.math.BigInteger
import java.util.Collections
import java.util.TreeMap

object VerificationVocabulary {
    const val SCHEMA = "star.verify.certificate/1"

    const val CLASS_EVIDENCE = "evidence"
    const val CLASS_CHECKED_CONFORMANCE = "checked-conformance"
    const val CLASS_LIFECYCLE_VERIFIED = "lifecycle-verified"
    const val CLASS_MODEL_CHECKED = "model-checked"
    const val CLASS_SOLVER_CERTIFICATE = "solver-certificate"
    const val CLASS_THEOREM_ARTIFACT = "theorem-artifact"

    const val RESULT_VALID = "valid"
    const val RESULT_INVALID = "invalid"
    const val RESULT_INCONCLUSIVE = "inconclusive"

    const val CLAIM_SUBJECT_IDENTITY_BOUND = "star.subject.identity-bound"
    const val CLAIM_DOCUMENT_SCHEMA_CONFORMANT =
        "star.document.schema-conformant"
    const val CLAIM_DOCUMENT_VALID_FOR_DOMAIN =
        "star.document.valid-for-domain"
    const val CLAIM_DOCUMENT_DOMAIN_CONSTRAINT_SATISFIED =
        "star.document.domain-constraint-satisfied"
    const val CLAIM_ACTOR_ACCEPTS_MESSAGE = "star.actor.accepts-message"
    const val CLAIM_ACTOR_EMITS_MESSAGE = "star.actor.emits-message"
    const val CLAIM_ACTOR_PROTOCOL_CONFORMANT =
        "star.actor.protocol-conformant"
    const val CLAIM_LIFECYCLE_TRANSITION_VALID =
        "star.lifecycle.transition-valid"
    const val CLAIM_POISON_TERMINAL_DISPOSITION =
        "star.poison.terminal-disposition"
    const val CLAIM_POISON_ACTIVE_PATH_NONRETURN =
        "star.poison.active-path-nonreturn"
    const val CLAIM_TOPOLOGY_HARD_WAIT_ACYCLIC =
        "star.topology.hard-wait-acyclic"
    const val CLAIM_TOPOLOGY_PROTOCOL_DEADLOCK_FREE =
        "star.topology.protocol-deadlock-free"
    const val CLAIM_TOPOLOGY_PROTOCOL_PROGRESS =
        "star.topology.protocol-progress"

    private val classes = listOf(
        CLASS_EVIDENCE,
        CLASS_CHECKED_CONFORMANCE,
        CLASS_LIFECYCLE_VERIFIED,
        CLASS_MODEL_CHECKED,
        CLASS_SOLVER_CERTIFICATE,
        CLASS_THEOREM_ARTIFACT,
    )
    private val results = listOf(
        RESULT_VALID,
        RESULT_INVALID,
        RESULT_INCONCLUSIVE,
    )
    private val claims = listOf(
        CLAIM_SUBJECT_IDENTITY_BOUND,
        CLAIM_DOCUMENT_SCHEMA_CONFORMANT,
        CLAIM_DOCUMENT_VALID_FOR_DOMAIN,
        CLAIM_DOCUMENT_DOMAIN_CONSTRAINT_SATISFIED,
        CLAIM_ACTOR_ACCEPTS_MESSAGE,
        CLAIM_ACTOR_EMITS_MESSAGE,
        CLAIM_ACTOR_PROTOCOL_CONFORMANT,
        CLAIM_LIFECYCLE_TRANSITION_VALID,
        CLAIM_POISON_TERMINAL_DISPOSITION,
        CLAIM_POISON_ACTIVE_PATH_NONRETURN,
        CLAIM_TOPOLOGY_HARD_WAIT_ACYCLIC,
        CLAIM_TOPOLOGY_PROTOCOL_DEADLOCK_FREE,
        CLAIM_TOPOLOGY_PROTOCOL_PROGRESS,
    )

    @JvmStatic
    fun classes(): List<String> =
        Collections.unmodifiableList(classes.toList())

    @JvmStatic
    fun results(): List<String> =
        Collections.unmodifiableList(results.toList())

    @JvmStatic
    fun claims(): List<String> =
        Collections.unmodifiableList(claims.toList())

    @JvmStatic
    fun isClass(value: String): Boolean = value in classes

    @JvmStatic
    fun isResult(value: String): Boolean = value in results

    @JvmStatic
    fun isClaim(value: String): Boolean = value in claims

    @JvmStatic
    fun isSha256Digest(value: String): Boolean =
        SHA256.matches(value)

    private val SHA256 = Regex("^sha256:[0-9a-f]{64}$")
}

sealed interface VerificationBoundScalar {
    data class IntegerValue(val value: BigInteger) : VerificationBoundScalar {
        init {
            require(value.signum() >= 0) {
                "Verification bound integers must be nonnegative."
            }
        }

        constructor(value: Long) : this(BigInteger.valueOf(value))
    }

    data class TextValue(val value: String) : VerificationBoundScalar {
        init {
            require(value.isNotEmpty()) {
                "Verification bound strings must be non-empty."
            }
        }
    }
}

sealed interface VerificationBound {
    data class Scalar(val value: VerificationBoundScalar) : VerificationBound

    class Values(values: List<VerificationBoundScalar>) : VerificationBound {
        val values: List<VerificationBoundScalar> =
            Collections.unmodifiableList(values.toList())

        override fun equals(other: Any?): Boolean =
            other is Values && values == other.values

        override fun hashCode(): Int = values.hashCode()
    }
}

class VerificationCertificate private constructor(
    val certificateId: String,
    val verificationClass: String,
    val claim: String,
    val subjectType: String,
    val subjectHash: String,
    val specificationDigest: String?,
    val planDigest: String?,
    val verifier: String,
    val verifierVersion: String,
    assumptions: List<String>,
    bounds: Map<String, VerificationBound>,
    evidence: List<String>,
    val result: String,
) {
    val schema: String = VerificationVocabulary.SCHEMA
    val assumptions: List<String> =
        Collections.unmodifiableList(assumptions.toList())
    val bounds: Map<String, VerificationBound> =
        Collections.unmodifiableMap(TreeMap(bounds))
    val evidence: List<String> =
        Collections.unmodifiableList(evidence.toList())

    fun fields(): Map<String, Any?> = orderedMap(
        "schema" to schema,
        "certificateId" to certificateId,
        "class" to verificationClass,
        "claim" to claim,
        "subjectType" to subjectType,
        "subjectHash" to subjectHash,
        "specificationDigest" to specificationDigest,
        "planDigest" to planDigest,
        "verifier" to verifier,
        "verifierVersion" to verifierVersion,
        "assumptions" to assumptions,
        "bounds" to bounds,
        "evidence" to evidence,
        "result" to result,
    )

    fun semanticIdentity(): Map<String, Any?> = orderedMap(
        "claim" to claim,
        "subjectHash" to subjectHash,
        "specificationDigest" to specificationDigest,
        "planDigest" to planDigest,
        "verifier" to verifier,
        "verifierVersion" to verifierVersion,
        "assumptions" to assumptions,
        "bounds" to bounds,
        "evidence" to evidence,
        "result" to result,
    )

    companion object {
        @JvmStatic
        fun fieldNames(): List<String> = Collections.unmodifiableList(
            listOf(
                "schema",
                "certificateId",
                "class",
                "claim",
                "subjectType",
                "subjectHash",
                "specificationDigest",
                "planDigest",
                "verifier",
                "verifierVersion",
                "assumptions",
                "bounds",
                "evidence",
                "result",
            ),
        )

        @JvmStatic
        @JvmOverloads
        fun create(
            certificateId: String,
            verificationClass: String,
            claim: String,
            subjectType: String,
            subjectHash: String,
            verifier: String,
            verifierVersion: String,
            result: String,
            specificationDigest: String? = null,
            planDigest: String? = null,
            assumptions: List<String> = emptyList(),
            bounds: Map<String, VerificationBound> = emptyMap(),
            evidence: List<String> = emptyList(),
        ): VerificationCertificate {
            requireNonEmpty(certificateId, "Certificate id")
            requireNonEmpty(subjectType, "Certificate subject type")
            requireDigest(subjectHash, "Certificate subject hash")
            specificationDigest?.let {
                requireDigest(it, "Certificate specification digest")
            }
            planDigest?.let {
                requireDigest(it, "Certificate plan digest")
            }
            requireNonEmpty(verifier, "Certificate verifier")
            requireNonEmpty(verifierVersion, "Certificate verifier version")
            if (!VerificationVocabulary.isClass(verificationClass)) {
                throw InvalidVerificationCertificateException(
                    "Unknown verification class $verificationClass.",
                )
            }
            if (!VerificationVocabulary.isClaim(claim)) {
                throw InvalidVerificationCertificateException(
                    "Unknown verification claim $claim.",
                )
            }
            if (!VerificationVocabulary.isResult(result)) {
                throw InvalidVerificationCertificateException(
                    "Unknown verification result $result.",
                )
            }
            assumptions.forEach {
                requireNonEmpty(it, "Certificate assumption")
            }
            evidence.forEach {
                requireDigest(it, "Certificate evidence hash")
            }
            bounds.keys.forEach {
                requireNonEmpty(it, "Certificate bound key")
            }

            validateScope(
                verificationClass,
                claim,
                specificationDigest,
                planDigest,
                bounds,
                evidence,
            )

            return VerificationCertificate(
                certificateId = certificateId,
                verificationClass = verificationClass,
                claim = claim,
                subjectType = subjectType,
                subjectHash = subjectHash,
                specificationDigest = specificationDigest,
                planDigest = planDigest,
                verifier = verifier,
                verifierVersion = verifierVersion,
                assumptions = assumptions,
                bounds = bounds,
                evidence = evidence,
                result = result,
            )
        }

        private fun validateScope(
            verificationClass: String,
            claim: String,
            specificationDigest: String?,
            planDigest: String?,
            bounds: Map<String, VerificationBound>,
            evidence: List<String>,
        ) {
            if (
                claim in specificationClaims &&
                specificationDigest == null
            ) {
                throw InvalidVerificationCertificateException(
                    "Verification claim $claim requires specificationDigest.",
                )
            }
            if (
                (claim in planClaims ||
                    verificationClass in planClasses) &&
                planDigest == null
            ) {
                throw InvalidVerificationCertificateException(
                    "Verification class/claim combination " +
                        "$verificationClass / $claim requires planDigest.",
                )
            }
            if (
                verificationClass ==
                    VerificationVocabulary.CLASS_MODEL_CHECKED &&
                bounds.isEmpty()
            ) {
                throw InvalidVerificationCertificateException(
                    "Verification class model-checked requires explicit " +
                        "non-empty bounds.",
                )
            }
            if (
                verificationClass in evidenceClasses &&
                evidence.isEmpty()
            ) {
                throw InvalidVerificationCertificateException(
                    "Verification class $verificationClass requires at least " +
                        "one evidence hash.",
                )
            }
        }

        private fun requireNonEmpty(value: String, context: String) {
            if (value.isEmpty()) {
                throw InvalidVerificationCertificateException(
                    "$context must be a non-empty string.",
                )
            }
        }

        private fun requireDigest(value: String, context: String) {
            if (!VerificationVocabulary.isSha256Digest(value)) {
                throw InvalidVerificationCertificateException(
                    "$context must be a lowercase sha256: digest with " +
                        "64 hexadecimal digits.",
                )
            }
        }

        private val specificationClaims = setOf(
            VerificationVocabulary.CLAIM_DOCUMENT_SCHEMA_CONFORMANT,
            VerificationVocabulary.CLAIM_DOCUMENT_VALID_FOR_DOMAIN,
            VerificationVocabulary.CLAIM_DOCUMENT_DOMAIN_CONSTRAINT_SATISFIED,
            VerificationVocabulary.CLAIM_ACTOR_ACCEPTS_MESSAGE,
            VerificationVocabulary.CLAIM_ACTOR_EMITS_MESSAGE,
            VerificationVocabulary.CLAIM_ACTOR_PROTOCOL_CONFORMANT,
            VerificationVocabulary.CLAIM_POISON_TERMINAL_DISPOSITION,
        )

        private val planClaims = setOf(
            VerificationVocabulary.CLAIM_DOCUMENT_VALID_FOR_DOMAIN,
            VerificationVocabulary.CLAIM_POISON_TERMINAL_DISPOSITION,
            VerificationVocabulary.CLAIM_POISON_ACTIVE_PATH_NONRETURN,
            VerificationVocabulary.CLAIM_TOPOLOGY_HARD_WAIT_ACYCLIC,
            VerificationVocabulary.CLAIM_TOPOLOGY_PROTOCOL_DEADLOCK_FREE,
            VerificationVocabulary.CLAIM_TOPOLOGY_PROTOCOL_PROGRESS,
        )

        private val planClasses = setOf(
            VerificationVocabulary.CLASS_MODEL_CHECKED,
            VerificationVocabulary.CLASS_SOLVER_CERTIFICATE,
        )

        private val evidenceClasses = setOf(
            VerificationVocabulary.CLASS_EVIDENCE,
            VerificationVocabulary.CLASS_MODEL_CHECKED,
            VerificationVocabulary.CLASS_SOLVER_CERTIFICATE,
            VerificationVocabulary.CLASS_THEOREM_ARTIFACT,
        )

        private fun orderedMap(
            vararg pairs: Pair<String, Any?>,
        ): Map<String, Any?> =
            Collections.unmodifiableMap(linkedMapOf(*pairs))
    }
}

open class VerificationException(message: String) :
    ActorRuntimeException(message)

class InvalidVerificationCertificateException(message: String) :
    VerificationException(message)
