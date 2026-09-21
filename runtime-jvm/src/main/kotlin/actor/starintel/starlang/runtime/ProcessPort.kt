package actor.starintel.starlang.runtime

import java.io.BufferedReader
import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.nio.file.Path
import java.util.Collections
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

enum class ProcessOutcome {
    EXITED,
    SIGNALED,
    TIMEOUT,
    CANCELLED,
}

enum class ProcessWaitStatus {
    EXITED,
    TIMEOUT,
}

data class ProcessProvenance(
    val instanceId: String,
    val generation: Long,
    val executable: String,
)

class ProcessCancellationToken {
    private val requested = AtomicBoolean(false)

    fun cancel(): ProcessCancellationToken {
        requested.set(true)
        return this
    }

    val isCancellationRequested: Boolean
        get() = requested.get()
}

class ManagedProcess internal constructor(
    internal val process: Process,
    val instanceId: String,
    val generation: Long,
    val executable: String,
    val charset: Charset,
) {
    val stdin: OutputStream
        get() = process.outputStream

    val stdout: InputStream
        get() = process.inputStream

    val stderr: InputStream
        get() = process.errorStream

    @Volatile
    var isReaped: Boolean = false
        internal set

    @Volatile
    var exitCode: Int? = null
        internal set

    @Volatile
    var signal: Int? = null
        internal set

    val isAlive: Boolean
        get() = !isReaped && process.isAlive

    fun provenance(): ProcessProvenance =
        ProcessProvenance(instanceId, generation, executable)
}

data class ProcessWaitResult(
    val exitCode: Int?,
    val status: ProcessWaitStatus,
    val signal: Int?,
)

class ProcessResult internal constructor(
    val outcome: ProcessOutcome,
    val exitCode: Int?,
    val signal: Int?,
    val stdout: String,
    val stderr: String,
    val stdoutTruncated: Boolean,
    val stderrTruncated: Boolean,
    val instanceId: String,
    val generation: Long,
    val provenance: ProcessProvenance,
) {
    val isSuccess: Boolean
        get() = outcome == ProcessOutcome.EXITED && exitCode == 0
}

object ProcessPort {
    private val instanceSequence = AtomicLong(0)

    @JvmStatic
    @JvmOverloads
    fun launch(
        executable: String,
        arguments: List<*>,
        directory: Path? = null,
        charset: Charset = StandardCharsets.UTF_8,
        generation: Long = 0,
    ): ManagedProcess {
        val command = validateCommand(executable, arguments)
        validateGeneration(generation)
        val instanceId = "process-" + instanceSequence.incrementAndGet()

        val builder = ProcessBuilder(command)
        if (directory != null) {
            builder.directory(directory.toFile())
        }

        val process = try {
            builder.start()
        } catch (condition: IOException) {
            throw ProcessLaunchException(
                "Failed to launch executable " + executable +
                    " with " + arguments.size + " argument(s).",
                condition,
            )
        }

        return ManagedProcess(
            process = process,
            instanceId = instanceId,
            generation = generation,
            executable = executable,
            charset = charset,
        )
    }

    @JvmStatic
    @JvmOverloads
    fun waitProcess(
        process: ManagedProcess,
        timeoutMillis: Long? = null,
        closeStreams: Boolean = true,
    ): ProcessWaitResult = synchronized(process) {
        timeoutMillis?.let { validateDuration("timeoutMillis", it, true) }

        if (process.isReaped) {
            if (closeStreams) closeStreams(process)
            return@synchronized ProcessWaitResult(
                process.exitCode,
                ProcessWaitStatus.EXITED,
                process.signal,
            )
        }

        val exited = if (timeoutMillis == null) {
            process.process.waitFor()
            true
        } else {
            process.process.waitFor(timeoutMillis, TimeUnit.MILLISECONDS)
        }

        if (!exited) {
            return@synchronized ProcessWaitResult(
                null,
                ProcessWaitStatus.TIMEOUT,
                null,
            )
        }

        process.exitCode = process.process.exitValue()
        process.signal = null
        process.isReaped = true
        if (closeStreams) closeStreams(process)
        ProcessWaitResult(
            process.exitCode,
            ProcessWaitStatus.EXITED,
            process.signal,
        )
    }

    @JvmStatic
    fun terminate(process: ManagedProcess): ManagedProcess {
        if (process.isAlive) process.process.destroy()
        return process
    }

    @JvmStatic
    fun kill(process: ManagedProcess): ManagedProcess {
        if (process.isAlive) process.process.destroyForcibly()
        return process
    }

    @JvmStatic
    @JvmOverloads
    fun dispose(
        process: ManagedProcess,
        terminateTimeoutMillis: Long = 1_000,
    ): ManagedProcess {
        stopAndReap(
            process,
            terminateTimeoutMillis,
            closeStreams = true,
        )
        return process
    }

    @JvmStatic
    @JvmOverloads
    fun runProcess(
        executable: String,
        arguments: List<*>,
        directory: Path? = null,
        timeoutMillis: Long? = null,
        cancellationToken: ProcessCancellationToken? = null,
        generation: Long = 0,
        stdoutLimit: Int = 65_536,
        stderrLimit: Int = 65_536,
        pollIntervalMillis: Long = 10,
        terminateTimeoutMillis: Long = 1_000,
        charset: Charset = StandardCharsets.UTF_8,
    ): ProcessResult {
        validateLimit("stdoutLimit", stdoutLimit)
        validateLimit("stderrLimit", stderrLimit)
        validateDuration("pollIntervalMillis", pollIntervalMillis, false)
        validateDuration(
            "terminateTimeoutMillis",
            terminateTimeoutMillis,
            true,
        )
        timeoutMillis?.let {
            validateDuration("timeoutMillis", it, true)
        }
        validateGeneration(generation)

        var managed: ManagedProcess? = null
        var stdoutCapture: CaptureState? = null
        var stderrCapture: CaptureState? = null
        var stdoutThread: Thread? = null
        var stderrThread: Thread? = null
        var captureFinished = false

        try {
            val process = launch(
                executable,
                arguments,
                directory,
                charset,
                generation,
            )
            managed = process
            runCatching { process.stdin.close() }

            val stdoutState = CaptureState(stdoutLimit)
            val stderrState = CaptureState(stderrLimit)
            stdoutCapture = stdoutState
            stderrCapture = stderrState

            stdoutThread = captureThread(
                process.stdout,
                process.charset,
                stdoutState,
                "starlang-process stdout drainer",
            )
            stderrThread = captureThread(
                process.stderr,
                process.charset,
                stderrState,
                "starlang-process stderr drainer",
            )

            val deadline = timeoutMillis?.let {
                System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(it)
            }
            var outcome: ProcessOutcome

            while (true) {
                if (cancellationToken?.isCancellationRequested == true) {
                    outcome = ProcessOutcome.CANCELLED
                    break
                }
                if (deadline != null && System.nanoTime() >= deadline) {
                    outcome = ProcessOutcome.TIMEOUT
                    break
                }
                if (!process.isAlive) {
                    outcome = ProcessOutcome.EXITED
                    break
                }
                Thread.sleep(pollIntervalMillis)
            }

            if (
                outcome == ProcessOutcome.TIMEOUT ||
                outcome == ProcessOutcome.CANCELLED
            ) {
                stopAndReap(
                    process,
                    terminateTimeoutMillis,
                    closeStreams = false,
                )
            } else {
                waitProcess(process, closeStreams = false)
            }

            if (
                outcome == ProcessOutcome.EXITED &&
                process.signal != null
            ) {
                outcome = ProcessOutcome.SIGNALED
            }

            finishCapture(
                process,
                stdoutThread,
                stdoutState,
                stderrThread,
                stderrState,
                terminateTimeoutMillis,
            )
            captureFinished = true
            checkCaptureErrors(stdoutState, stderrState)

            return ProcessResult(
                outcome = outcome,
                exitCode = process.exitCode,
                signal = process.signal,
                stdout = stdoutState.content(),
                stderr = stderrState.content(),
                stdoutTruncated = stdoutState.truncated,
                stderrTruncated = stderrState.truncated,
                instanceId = process.instanceId,
                generation = process.generation,
                provenance = process.provenance(),
            )
        } catch (condition: ProcessPortException) {
            throw condition
        } catch (condition: InterruptedException) {
            Thread.currentThread().interrupt()
            throw ProcessDisposalException(
                "Process operation was interrupted.",
                condition,
            )
        } finally {
            val process = managed
            if (process != null) {
                if (!process.isReaped) {
                    runCatching {
                        stopAndReap(
                            process,
                            terminateTimeoutMillis,
                            closeStreams = false,
                        )
                    }
                }
                if (!captureFinished) {
                    val outState = stdoutCapture
                    val errState = stderrCapture
                    if (outState != null && errState != null) {
                        runCatching {
                            finishCapture(
                                process,
                                stdoutThread,
                                outState,
                                stderrThread,
                                errState,
                                terminateTimeoutMillis,
                            )
                        }
                    } else {
                        closeStreams(process)
                    }
                }
            }
        }
    }

    @JvmStatic
    fun ensureSuccess(result: ProcessResult): ProcessResult {
        if (result.isSuccess) return result

        val message =
            "Process " + result.instanceId +
                " generation " + result.generation +
                " ended with outcome " + result.outcome +
                ", exit " + result.exitCode +
                ", signal " + result.signal + "."

        throw when (result.outcome) {
            ProcessOutcome.TIMEOUT ->
                ProcessTimeoutException(message, result)
            ProcessOutcome.CANCELLED ->
                ProcessCancelledException(message, result)
            else ->
                ProcessExitException(message, result)
        }
    }

    private fun validateCommand(
        executable: String,
        arguments: List<*>,
    ): List<String> {
        if (executable.isEmpty()) {
            throw InvalidProcessCommandException(
                "Executable must be a non-empty string.",
            )
        }
        val command = ArrayList<String>(arguments.size + 1)
        command += executable
        for (argument in arguments) {
            if (argument !is String) {
                throw InvalidProcessCommandException(
                    "ARGV contains a non-string argument.",
                )
            }
            command += argument
        }
        return Collections.unmodifiableList(command)
    }

    private fun validateGeneration(generation: Long) {
        if (generation < 0) {
            throw InvalidProcessCommandException(
                "Process generation must be a non-negative integer.",
            )
        }
    }

    private fun validateLimit(name: String, value: Int) {
        if (value < 0) {
            throw InvalidProcessCommandException(
                name + " must be a non-negative integer.",
            )
        }
    }

    private fun validateDuration(
        name: String,
        value: Long,
        allowZero: Boolean,
    ) {
        if (value < 0 || (!allowZero && value == 0L)) {
            throw InvalidProcessCommandException(
                name + " must be " +
                    (if (allowZero) "non-negative" else "positive") +
                    ".",
            )
        }
    }

    private fun stopAndReap(
        process: ManagedProcess,
        terminateTimeoutMillis: Long,
        closeStreams: Boolean,
    ) {
        validateDuration(
            "terminateTimeoutMillis",
            terminateTimeoutMillis,
            true,
        )
        synchronized(process) {
            if (!process.isReaped) {
                if (process.process.isAlive) {
                    runCatching { process.process.destroy() }
                    if (
                        !process.process.waitFor(
                            terminateTimeoutMillis,
                            TimeUnit.MILLISECONDS,
                        )
                    ) {
                        runCatching { process.process.destroyForcibly() }
                        if (
                            !process.process.waitFor(
                                maxOf(terminateTimeoutMillis, 1L),
                                TimeUnit.MILLISECONDS,
                            )
                        ) {
                            throw ProcessDisposalException(
                                "Failed to reap subprocess after urgent termination.",
                            )
                        }
                    }
                }
                process.exitCode = process.process.exitValue()
                process.signal = null
                process.isReaped = true
            }
            if (closeStreams) closeStreams(process)
        }
    }

    private fun closeStreams(process: ManagedProcess) {
        runCatching { process.stdin.close() }
        runCatching { process.stdout.close() }
        runCatching { process.stderr.close() }
    }

    private fun captureThread(
        stream: InputStream,
        charset: Charset,
        state: CaptureState,
        name: String,
    ): Thread = Thread(
        {
            try {
                BufferedReader(InputStreamReader(stream, charset)).use { reader ->
                    val buffer = CharArray(4096)
                    while (true) {
                        val count = reader.read(buffer)
                        if (count < 0) break
                        state.append(buffer, count)
                    }
                }
            } catch (condition: Throwable) {
                if (!state.forcedStop) state.error = condition
            }
        },
        name,
    ).apply {
        isDaemon = true
        start()
    }

    private fun finishCapture(
        process: ManagedProcess,
        stdoutThread: Thread?,
        stdoutState: CaptureState,
        stderrThread: Thread?,
        stderrState: CaptureState,
        timeoutMillis: Long,
    ) {
        val deadline =
            System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis)

        quiesceCapture(
            stdoutThread,
            stdoutState,
            process.stdout,
            deadline,
        )
        quiesceCapture(
            stderrThread,
            stderrState,
            process.stderr,
            deadline,
        )
        closeStreams(process)

        if (stdoutThread?.isAlive == true) {
            stdoutState.error = IOException(
                "Stdout capture thread remained alive after bounded cleanup.",
            )
        }
        if (stderrThread?.isAlive == true) {
            stderrState.error = IOException(
                "Stderr capture thread remained alive after bounded cleanup.",
            )
        }
    }

    private fun quiesceCapture(
        thread: Thread?,
        state: CaptureState,
        stream: InputStream,
        deadlineNanos: Long,
    ) {
        if (thread == null || !thread.isAlive) {
            thread?.join(0)
            return
        }

        val remainingNanos = deadlineNanos - System.nanoTime()
        if (remainingNanos > 0) {
            val millis = TimeUnit.NANOSECONDS.toMillis(remainingNanos)
            val nanos = (
                remainingNanos -
                    TimeUnit.MILLISECONDS.toNanos(millis)
                ).coerceIn(0, 999_999).toInt()
            thread.join(millis, nanos)
        }

        if (thread.isAlive) {
            state.truncated = true
            state.forcedStop = true
            runCatching { stream.close() }
            thread.interrupt()
            thread.join(10)
        }
    }

    private fun checkCaptureErrors(
        stdoutState: CaptureState,
        stderrState: CaptureState,
    ) {
        val cause = stdoutState.error ?: stderrState.error
        if (cause != null) {
            throw ProcessOutputException(
                "Failed while draining subprocess output.",
                cause,
            )
        }
    }

    private class CaptureState(
        private val limit: Int,
    ) {
        private val builder = StringBuilder()

        @Volatile
        var truncated: Boolean = false

        @Volatile
        var forcedStop: Boolean = false

        @Volatile
        var error: Throwable? = null

        @Synchronized
        fun append(chars: CharArray, count: Int) {
            val room = limit - builder.length
            if (room > 0) {
                val keep = minOf(room, count)
                builder.append(chars, 0, keep)
            }
            if (count > room.coerceAtLeast(0)) {
                truncated = true
            }
        }

        @Synchronized
        fun content(): String = builder.toString()
    }
}

open class ProcessPortException(
    message: String,
    cause: Throwable? = null,
) : ActorRuntimeException(message) {
    init {
        if (cause != null) initCause(cause)
    }
}

class InvalidProcessCommandException(message: String) :
    ProcessPortException(message)

class ProcessLaunchException(
    message: String,
    cause: Throwable? = null,
) : ProcessPortException(message, cause)

class ProcessDisposalException(
    message: String,
    cause: Throwable? = null,
) : ProcessPortException(message, cause)

open class ProcessResultException(
    message: String,
    val result: ProcessResult,
) : ProcessPortException(message)

class ProcessExitException(
    message: String,
    result: ProcessResult,
) : ProcessResultException(message, result)

class ProcessTimeoutException(
    message: String,
    result: ProcessResult,
) : ProcessResultException(message, result)

class ProcessCancelledException(
    message: String,
    result: ProcessResult,
) : ProcessResultException(message, result)

class ProcessOutputException(
    message: String,
    cause: Throwable? = null,
) : ProcessPortException(message, cause)
