package actor.starintel.starlang.runtime

import java.nio.charset.StandardCharsets

private fun effectCheck(value: Boolean, message: String) {
    if (!value) error(message)
}

private fun shell(vararg command: String): ProcessResult =
    ProcessPort.runProcess(
        executable = "/bin/sh",
        arguments = listOf("-c", command[0]) + command.drop(1),
        timeoutMillis = 10_000,
        terminateTimeoutMillis = 100,
    )

fun main() {
    var seen: HttpRequestSpec? = null
    val client = HttpClientPort(
        "fixture",
        HttpRequestOperation { request ->
            seen = request
            HttpResponseSpec(
                body = "<html><title>Star</title></html>"
                    .toByteArray(StandardCharsets.UTF_8),
                status = 200,
                headers = mapOf("content-type" to "text/html"),
                finalUrl = request.url,
            )
        },
    )
    val response = client.get(
        "https://example.test/page",
        headers = mapOf("user-agent" to "StarLang-Test"),
        connectTimeoutSeconds = 3,
        readTimeoutSeconds = 7,
        maxRedirects = 2,
    )
    effectCheck(seen?.method == HttpMethod.GET, "HTTP GET method")
    effectCheck(seen?.connectTimeoutSeconds == 3, "HTTP connect timeout")
    effectCheck(seen?.readTimeoutSeconds == 7, "HTTP read timeout")
    effectCheck(seen?.maxRedirects == 2, "HTTP redirect bound")
    effectCheck(response.status == 200 && response.isSuccess, "HTTP success")
    effectCheck(
        String(response.bodyBytes, StandardCharsets.UTF_8) ==
            "<html><title>Star</title></html>",
        "HTTP response body",
    )
    try {
        HttpRequestSpec("")
        error("empty URL accepted")
    } catch (_: HttpRequestException) {
    }
    try {
        HttpRequestSpec("https://example.test", readTimeoutSeconds = 0)
        error("zero HTTP timeout accepted")
    } catch (_: HttpRequestException) {
    }

    try {
        ProcessPort.launch(
            "/definitely/not/launched",
            listOf("ok", 42),
        )
        error("non-string argv accepted")
    } catch (_: InvalidProcessCommandException) {
    }
    try {
        ProcessPort.launch("", emptyList<String>())
        error("empty executable accepted")
    } catch (_: InvalidProcessCommandException) {
    }

    val secret = "STARLANG-PROCESS-SECRET-DO-NOT-RENDER"
    try {
        ProcessPort.launch(
            "/definitely/not/a/star-process-port-program",
            listOf(secret),
        )
        error("missing executable launched")
    } catch (condition: ProcessLaunchException) {
        effectCheck(
            !condition.message.orEmpty().contains(secret),
            "launch error rendered secret argv",
        )
    }

    val literal = "\$HOME;\$(printf hacked);*;space value"
    val exact = shell(
        "printf '%s' \"\$1\"",
        "_",
        literal,
    )
    effectCheck(exact.isSuccess, "exact argv process")
    effectCheck(exact.stdout == literal, "argv was shell-expanded")

    val bounded = shell(
        "i=0; while [ \$i -lt 70000 ]; do " +
            "printf x; printf y >&2; i=\$((i+1)); done",
    )
    val boundedAgain = ProcessPort.runProcess(
        "/bin/sh",
        listOf(
            "-c",
            "i=0; while [ \$i -lt 70000 ]; do " +
                "printf x; printf y >&2; i=\$((i+1)); done",
        ),
        stdoutLimit = 31,
        stderrLimit = 17,
        timeoutMillis = 10_000,
        terminateTimeoutMillis = 100,
    )
    effectCheck(bounded.isSuccess, "unbounded fixture sanity")
    effectCheck(boundedAgain.stdout.length == 31, "stdout retain bound")
    effectCheck(boundedAgain.stderr.length == 17, "stderr retain bound")
    effectCheck(boundedAgain.stdoutTruncated, "stdout truncation flag")
    effectCheck(boundedAgain.stderrTruncated, "stderr truncation flag")

    val nonzero = shell("exit 7")
    effectCheck(
        nonzero.outcome == ProcessOutcome.EXITED &&
            nonzero.exitCode == 7 &&
            !nonzero.isSuccess,
        "nonzero exit result",
    )
    try {
        ProcessPort.ensureSuccess(nonzero)
        error("nonzero exit accepted")
    } catch (_: ProcessExitException) {
    }

    val timeout = ProcessPort.runProcess(
        "/bin/sh",
        listOf(
            "-c",
            "trap '' TERM; while :; do sleep 1; done",
        ),
        timeoutMillis = 50,
        terminateTimeoutMillis = 25,
    )
    effectCheck(timeout.outcome == ProcessOutcome.TIMEOUT, "timeout outcome")
    try {
        ProcessPort.ensureSuccess(timeout)
        error("timeout accepted")
    } catch (_: ProcessTimeoutException) {
    }

    val token = ProcessCancellationToken()
    val canceller = Thread {
        Thread.sleep(50)
        token.cancel()
    }.apply { start() }
    val cancelled = ProcessPort.runProcess(
        "/bin/sh",
        listOf("-c", "while :; do sleep 1; done"),
        cancellationToken = token,
        terminateTimeoutMillis = 50,
    )
    canceller.join()
    effectCheck(
        cancelled.outcome == ProcessOutcome.CANCELLED,
        "cancellation outcome",
    )

    val started = System.nanoTime()
    val descendant = ProcessPort.runProcess(
        "/bin/sh",
        listOf("-c", "(sleep 2) & exit 0"),
        terminateTimeoutMillis = 50,
    )
    val elapsedMillis =
        (System.nanoTime() - started) / 1_000_000L
    effectCheck(
        descendant.outcome == ProcessOutcome.EXITED &&
            descendant.exitCode == 0,
        "descendant-held-pipe root result",
    )
    effectCheck(
        elapsedMillis < 750,
        "descendant-held pipe blocked bounded cleanup: " +
            elapsedMillis + "ms",
    )

    val generated = ProcessPort.runProcess(
        "/bin/sh",
        listOf("-c", "printf ok"),
        generation = 9,
    )
    effectCheck(generated.generation == 9L, "process generation")
    effectCheck(
        generated.provenance.executable == "/bin/sh" &&
            generated.provenance.generation == 9L,
        "process provenance",
    )
    effectCheck(
        !generated.provenance.toString().contains("printf ok"),
        "process provenance leaked argv",
    )

    println("runtime-jvm HTTP/process ports smoke: PASS")
}
