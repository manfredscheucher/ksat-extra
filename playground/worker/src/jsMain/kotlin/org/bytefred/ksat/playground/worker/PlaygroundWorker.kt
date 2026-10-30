package org.bytefred.ksat.playground.worker

import org.bytefred.ksat.playground.core.GenerateRequest
import org.bytefred.ksat.playground.core.GenerateResult
import org.bytefred.ksat.playground.core.PlaygroundSolver
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import org.bytefred.ksat.playground.core.nowMillis
import org.w3c.dom.DedicatedWorkerGlobalScope

/** The worker's global scope (`self` inside a dedicated Web Worker). */
external val self: DedicatedWorkerGlobalScope

/**
 * Web Worker entry point. Receives one encoded [SolveRequest] or [GenerateRequest] (protocol in
 * :playground's SolveProtocol.kt). A solve runs the synchronous solver and posts every [SolveEvent]
 * back encoded; a generation posts one [GenerateResult]. Stop / Cancel is done by the page
 * terminating this worker.
 */
fun main() {
    self.onmessage = { message ->
        val text = message.data as String
        if (text.startsWith(GenerateRequest.KIND + " ")) {
            val result = try {
                val request = GenerateRequest.decode(text)
                GenerateResult.Generated(request.example.dimacs(request.values))
            } catch (e: Throwable) {
                GenerateResult.Failed(e.message ?: e.toString())
            }
            self.postMessage(result.encode())
        } else {
            fun post(event: SolveEvent) = self.postMessage(event.encode())
            try {
                PlaygroundSolver.run(SolveRequest.decode(text), ::nowMillis, isCancelled = { false }, onEvent = ::post)
            } catch (e: Throwable) {
                post(SolveEvent.Failed(nowMillis(), e.message ?: e.toString()))
            }
        }
    }
}
