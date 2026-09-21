package actor.starintel.starlang.runtime

import java.util.Collections

enum class HttpMethod {
    GET,
    HEAD,
    OPTIONS,
    PUT,
    POST,
    DELETE,
    PATCH,
}

data class HttpRequestSpec @JvmOverloads constructor(
    val url: String,
    val method: HttpMethod = HttpMethod.GET,
    headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
    val connectTimeoutSeconds: Int = 10,
    val readTimeoutSeconds: Int = 10,
    val maxRedirects: Int = 5,
) {
    val headers: Map<String, String> =
        Collections.unmodifiableMap(LinkedHashMap(headers))
    val bodyBytes: ByteArray? = body?.copyOf()

    init {
        if (url.isEmpty()) {
            throw HttpRequestException("HTTP URL must be a non-empty string.")
        }
        if (connectTimeoutSeconds <= 0) {
            throw HttpRequestException(
                "Connect timeout must be a positive integer.",
            )
        }
        if (readTimeoutSeconds <= 0) {
            throw HttpRequestException(
                "Read timeout must be a positive integer.",
            )
        }
        if (maxRedirects < 0) {
            throw HttpRequestException(
                "Max redirects must be a nonnegative integer.",
            )
        }
    }

    override fun equals(other: Any?): Boolean =
        other is HttpRequestSpec &&
            url == other.url &&
            method == other.method &&
            headers == other.headers &&
            bodyBytes.contentEqualsNullable(other.bodyBytes) &&
            connectTimeoutSeconds == other.connectTimeoutSeconds &&
            readTimeoutSeconds == other.readTimeoutSeconds &&
            maxRedirects == other.maxRedirects

    override fun hashCode(): Int {
        var result = url.hashCode()
        result = 31 * result + method.hashCode()
        result = 31 * result + headers.hashCode()
        result = 31 * result + (bodyBytes?.contentHashCode() ?: 0)
        result = 31 * result + connectTimeoutSeconds
        result = 31 * result + readTimeoutSeconds
        result = 31 * result + maxRedirects
        return result
    }
}

data class HttpResponseSpec(
    val body: ByteArray,
    val status: Int,
    headers: Map<String, String> = emptyMap(),
    val finalUrl: String,
) {
    val bodyBytes: ByteArray = body.copyOf()
    val headers: Map<String, String> =
        Collections.unmodifiableMap(LinkedHashMap(headers))

    init {
        if (status !in 0..999) {
            throw HttpRequestException(
                "HTTP response status must be between 0 and 999.",
            )
        }
    }

    val isSuccess: Boolean
        get() = status in 200..299

    override fun equals(other: Any?): Boolean =
        other is HttpResponseSpec &&
            bodyBytes.contentEquals(other.bodyBytes) &&
            status == other.status &&
            headers == other.headers &&
            finalUrl == other.finalUrl

    override fun hashCode(): Int {
        var result = bodyBytes.contentHashCode()
        result = 31 * result + status
        result = 31 * result + headers.hashCode()
        result = 31 * result + finalUrl.hashCode()
        return result
    }
}

fun interface HttpRequestOperation {
    fun perform(request: HttpRequestSpec): HttpResponseSpec
}

class HttpClientPort(
    val name: String,
    private val requestOperation: HttpRequestOperation,
) {
    init {
        if (name.isEmpty()) {
            throw HttpRequestException(
                "HTTP client name must be a non-empty string.",
            )
        }
    }

    fun perform(request: HttpRequestSpec): HttpResponseSpec =
        try {
            requestOperation.perform(request)
        } catch (condition: HttpPortException) {
            throw condition
        } catch (condition: Throwable) {
            throw HttpTransportException(
                "HTTP client $name transport operation failed.",
                condition,
            )
        }

    @JvmOverloads
    fun get(
        url: String,
        headers: Map<String, String> = emptyMap(),
        connectTimeoutSeconds: Int = 10,
        readTimeoutSeconds: Int = 10,
        maxRedirects: Int = 5,
    ): HttpResponseSpec = perform(
        HttpRequestSpec(
            url = url,
            method = HttpMethod.GET,
            headers = headers,
            connectTimeoutSeconds = connectTimeoutSeconds,
            readTimeoutSeconds = readTimeoutSeconds,
            maxRedirects = maxRedirects,
        ),
    )
}

private fun ByteArray?.contentEqualsNullable(other: ByteArray?): Boolean =
    when {
        this == null && other == null -> true
        this == null || other == null -> false
        else -> contentEquals(other)
    }

open class HttpPortException(
    message: String,
    cause: Throwable? = null,
) : ActorRuntimeException(message) {
    init {
        if (cause != null) initCause(cause)
    }
}

class HttpBackendUnavailableException(message: String) :
    HttpPortException(message)

class HttpRequestException(
    message: String,
    cause: Throwable? = null,
) : HttpPortException(message, cause)

class HttpTransportException(
    message: String,
    cause: Throwable? = null,
) : HttpRequestException(message, cause)
