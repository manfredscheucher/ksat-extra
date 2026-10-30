package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.Composable
import kotlinx.browser.document
import org.bytefred.ksat.playground.core.GenerateRequest
import org.bytefred.ksat.playground.core.GenerateResult
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import org.bytefred.ksat.playground.core.nowMillis
import org.w3c.dom.HTMLInputElement
import org.w3c.dom.Worker
import org.w3c.files.FileReader
import org.w3c.files.get

/**
 * Web: the solver runs in a Web Worker (playground-worker.js, built by :playgroundWorker and copied
 * next to index.html), so the page stays responsive. One worker per run; Stop terminates it, which
 * also ends a solve call that is still running.
 *
 * Protocol (SolveProtocol.kt): the request is [SolveRequest.encode], every reply one
 * [SolveEvent.encode] string.
 */
actual fun createSolverService(): SolverService = WorkerSolverService()

/** Web: examples are generated in a Web Worker as well ([GenerateRequest.encode] / [GenerateResult.encode]). */
actual fun createGeneratorService(): GeneratorService = WorkerGeneratorService()

private const val WORKER_SCRIPT = "playground-worker.js"

/**
 * The current worker of a service. [start] terminates the previous one; [onMessage] and
 * [onFailure] are only called for the current worker: a message of a terminated worker may already
 * be queued, and must not reach (or [cancel]) the next one.
 */
private class WorkerSlot {
    private var worker: Worker? = null

    /** Start a worker and post [message] to it; [onFailure] if it cannot start. */
    fun start(message: String, onMessage: (String) -> Unit, onFailure: (String) -> Unit) {
        cancel()
        val w = try {
            Worker(WORKER_SCRIPT).also { worker = it }
        } catch (e: Throwable) {
            onFailure("cannot start the solver worker: ${e.message ?: e.toString()}")
            return
        }
        w.onmessage = { m -> if (worker === w) onMessage(m.data as String) }
        // An uncaught error in the worker (also a stack overflow, or the script failing to load)
        // ends the job, so the UI never waits forever.
        w.onerror = { error ->
            if (worker === w) {
                val detail = error.asDynamic().message as? String
                cancel()
                onFailure("the solver worker failed${detail?.let { ": $it" } ?: ""}")
            }
        }
        w.postMessage(message)
    }

    fun cancel() {
        worker?.terminate()
        worker = null
    }
}

private class WorkerSolverService : SolverService {
    private val slot = WorkerSlot()

    override fun solve(request: SolveRequest, onEvent: (SolveEvent) -> Unit) {
        slot.start(
            request.encode(),
            onMessage = { text ->
                val event = try {
                    SolveEvent.decode(text)
                } catch (e: Throwable) {
                    SolveEvent.Failed(nowMillis(), "unreadable message from the solver worker: ${e.message}")
                }
                if (event is SolveEvent.Finished || event is SolveEvent.Failed) slot.cancel()
                onEvent(event)
            },
            onFailure = { onEvent(SolveEvent.Failed(nowMillis(), it)) },
        )
    }

    override fun cancel() = slot.cancel()
}

private class WorkerGeneratorService : GeneratorService {
    private val slot = WorkerSlot()

    override fun generate(request: GenerateRequest, onResult: (GenerateResult) -> Unit) {
        slot.start(
            request.encode(),
            onMessage = { text ->
                slot.cancel()
                onResult(
                    try {
                        GenerateResult.decode(text)
                    } catch (e: Throwable) {
                        GenerateResult.Failed("unreadable message from the solver worker: ${e.message}")
                    }
                )
            },
            onFailure = { onResult(GenerateResult.Failed(it)) },
        )
    }

    override fun cancel() = slot.cancel()
}

// Browser: load via a hidden <input type=file> + FileReader.
@Composable
actual fun rememberFileLoader(onLoaded: (text: String) -> Unit, onFailed: (message: String) -> Unit): () -> Unit = {
    val input = document.createElement("input") as HTMLInputElement
    input.type = "file"
    input.accept = ".cnf,.dimacs,.txt"
    input.onchange = {
        val file = input.files?.get(0)
        if (file != null) {
            val reader = FileReader()
            reader.onload = {
                val text = reader.result as? String
                if (text != null) onLoaded(text) else onFailed("cannot read ${file.name}: no text content")
            }
            reader.onerror = { onFailed("cannot read ${file.name}: ${reader.error?.asDynamic()?.message ?: "read error"}") }
            reader.readAsText(file)
        }
    }
    input.click()
}
