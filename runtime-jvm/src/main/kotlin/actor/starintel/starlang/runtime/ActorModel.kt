package actor.starintel.starlang.runtime

enum class ActorKind {
    NATIVE,
    EXTERNAL,
}

enum class ActorStatus {
    RUNNING,
    STOPPED,
}

enum class RuntimeStatus {
    RUNNING,
    STOPPED,
}

enum class RestartPolicy {
    PERMANENT,
    TRANSIENT,
    TEMPORARY,
}

data class ActorReference(
    val serviceUri: String,
    val generation: Long,
    val protocolRevision: Int = 1,
)

enum class DeliveryStatus {
    ACCEPTED,
    MAILBOX_FULL,
    STOPPED,
    REJECTED,
}

data class DeliveryResult(
    val status: DeliveryStatus,
    val reference: ActorReference,
    val depth: Int,
    val capacity: Int,
)

enum class DispatchStatus {
    COMPLETED,
    FAILED,
}

data class DispatchResult(
    val status: DispatchStatus,
    val reference: ActorReference,
    val correlationId: String,
    val value: PortableValue? = null,
    val condition: Throwable? = null,
)

sealed interface StateUpdate {
    data object Keep : StateUpdate
    data class Replace(val value: PortableValue) : StateUpdate
}

data class ActorTransition(
    val output: PortableValue,
    val stateUpdate: StateUpdate = StateUpdate.Keep,
)

fun interface ActorHandler {
    fun handle(message: PortableValue, state: PortableValue, runtime: StarRuntime): ActorTransition
}

fun interface ContractValidator {
    fun isValid(contract: List<String>, value: PortableValue): Boolean
}

fun interface InitialStateFactory {
    fun create(): PortableValue
}

data class ActorDefinition(
    val name: String,
    val serviceUri: String,
    val kind: ActorKind,
    val accepts: List<String> = emptyList(),
    val produces: List<String> = emptyList(),
    val restartPolicy: RestartPolicy = RestartPolicy.PERMANENT,
    val mailboxCapacity: Int = 128,
    val capabilities: List<String> = emptyList(),
    val metadata: Map<String, PortableValue> = emptyMap(),
    val protocol: String? = null,
    val endpoint: String? = null,
    val handler: ActorHandler? = null,
    val inputValidator: ContractValidator? = null,
    val outputValidator: ContractValidator? = null,
    val initialStateFactory: InitialStateFactory = InitialStateFactory { PortableValue.Null },
) {
    init {
        require(name.isNotBlank()) { "Actor name must not be blank." }
        require(serviceUri.isNotBlank()) { "Actor service URI must not be blank." }
        StarServiceUri.canonicalForActor(name, serviceUri)
        require(mailboxCapacity > 0) { "Actor mailbox capacity must be a positive integer." }
        require(kind != ActorKind.NATIVE || handler != null) { "Native actor $name requires a handler." }
        require(kind != ActorKind.EXTERNAL || handler == null) { "External actor $name must not define a local handler." }
        require(kind != ActorKind.EXTERNAL || !protocol.isNullOrBlank()) { "External actor $name requires a protocol." }
        require(kind != ActorKind.EXTERNAL || !endpoint.isNullOrBlank()) { "External actor $name requires an endpoint." }
    }

    companion object {
        @JvmStatic
        @JvmOverloads
        fun nativeActor(
            name: String,
            serviceUri: String,
            handler: ActorHandler,
            accepts: List<String> = emptyList(),
            produces: List<String> = emptyList(),
            restartPolicy: RestartPolicy = RestartPolicy.PERMANENT,
            mailboxCapacity: Int = 128,
            capabilities: List<String> = emptyList(),
            metadata: Map<String, PortableValue> = emptyMap(),
            inputValidator: ContractValidator? = null,
            outputValidator: ContractValidator? = null,
            initialStateFactory: InitialStateFactory = InitialStateFactory { PortableValue.Null },
        ): ActorDefinition = ActorDefinition(
            name = name,
            serviceUri = serviceUri,
            kind = ActorKind.NATIVE,
            accepts = accepts.toList(),
            produces = produces.toList(),
            restartPolicy = restartPolicy,
            mailboxCapacity = mailboxCapacity,
            capabilities = capabilities.toList(),
            metadata = metadata.toSortedMap(),
            handler = handler,
            inputValidator = inputValidator,
            outputValidator = outputValidator,
            initialStateFactory = initialStateFactory,
        )

        @JvmStatic
        @JvmOverloads
        fun externalActor(
            name: String,
            serviceUri: String,
            protocol: String,
            endpoint: String,
            accepts: List<String> = emptyList(),
            produces: List<String> = emptyList(),
            restartPolicy: RestartPolicy = RestartPolicy.PERMANENT,
            mailboxCapacity: Int = 128,
            capabilities: List<String> = emptyList(),
            metadata: Map<String, PortableValue> = emptyMap(),
            inputValidator: ContractValidator? = null,
            outputValidator: ContractValidator? = null,
        ): ActorDefinition = ActorDefinition(
            name = name,
            serviceUri = serviceUri,
            kind = ActorKind.EXTERNAL,
            accepts = accepts.toList(),
            produces = produces.toList(),
            restartPolicy = restartPolicy,
            mailboxCapacity = mailboxCapacity,
            capabilities = capabilities.toList(),
            metadata = metadata.toSortedMap(),
            protocol = protocol,
            endpoint = endpoint,
            inputValidator = inputValidator,
            outputValidator = outputValidator,
        )
    }
}

open class ActorRuntimeException(message: String) : RuntimeException(message)
class ActorDefinitionException(message: String) : ActorRuntimeException(message)
class ActorAlreadyRegisteredException(message: String) : ActorRuntimeException(message)
class ActorNotFoundException(message: String) : ActorRuntimeException(message)
class ActorStoppedException(message: String) : ActorRuntimeException(message)
class ActorStaleReferenceException(message: String) : ActorRuntimeException(message)
class ActorStaleCompletionException(message: String) : ActorRuntimeException(message)
class ActorMailboxFullException(message: String) : ActorRuntimeException(message)
class ActorAskTimeoutException(message: String) : ActorRuntimeException(message)
class ActorExternalDispatchRequiredException(message: String) : ActorRuntimeException(message)
class ActorContractException(message: String) : ActorRuntimeException(message)
