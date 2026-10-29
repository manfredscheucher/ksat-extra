package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.Composable
import kotlinx.browser.document
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

private class WorkerSolverService : SolverService {
    private var worker: Worker? = null

    override fun solve(request: SolveRequest, onEvent: (SolveEvent) -> Unit) {
        cancel()
        val w = try {
            Worker(WORKER_SCRIPT).also { worker = it }
        } catch (e: Throwable) {
            onEvent(SolveEvent.Failed(nowMillis(), "cannot start the solver worker: ${e.message ?: e.toString()}"))
            return
        }
        // Both handlers ignore a worker that is no longer the current one: a message of a stopped
        // worker may already be queued, and its cancel() must not terminate the next run's worker.
        w.onmessage = { message ->
            if (worker === w) {
                val event = try {
                    SolveEvent.decode(message.data as String)
                } catch (e: Throwable) {
                    SolveEvent.Failed(nowMillis(), "unreadable message from the solver worker: ${e.message}")
                }
                if (event is SolveEvent.Finished || event is SolveEvent.Failed) cancel()
                onEvent(event)
            }
        }
        // An uncaught error in the worker (also a stack overflow, or the script failing to load)
        // ends the run, so the UI never waits forever.
        w.onerror = { error ->
            if (worker === w) {
                val detail = error.asDynamic().message as? String
                cancel()
                onEvent(SolveEvent.Failed(nowMillis(), "the solver worker failed${detail?.let { ": $it" } ?: ""}"))
            }
        }
        w.postMessage(request.encode())
    }

    override fun cancel() {
        worker?.terminate()
        worker = null
    }

    private companion object {
        const val WORKER_SCRIPT = "playground-worker.js"
    }
}

/** On GitHub Pages the XOR demo is served under xor-demo/ next to the playground. */
actual val xorDemoLink: String? = "xor-demo/"

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
