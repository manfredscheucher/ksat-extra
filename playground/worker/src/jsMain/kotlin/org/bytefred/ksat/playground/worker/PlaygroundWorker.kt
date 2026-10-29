package org.bytefred.ksat.playground.worker

import org.bytefred.ksat.playground.core.PlaygroundSolver
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import org.bytefred.ksat.playground.core.nowMillis
import org.w3c.dom.DedicatedWorkerGlobalScope

/** The worker's global scope (`self` inside a dedicated Web Worker). */
external val self: DedicatedWorkerGlobalScope

/**
 * Web Worker entry point. Receives one encoded [SolveRequest], runs the synchronous solver and
 * posts every [SolveEvent] back encoded (protocol in :playground's SolveProtocol.kt). Stop is done
 * by the page terminating this worker.
 */
fun main() {
    self.onmessage = { message ->
        fun post(event: SolveEvent) = self.postMessage(event.encode())
        try {
            PlaygroundSolver.run(SolveRequest.decode(message.data as String), ::nowMillis, isCancelled = { false }, onEvent = ::post)
        } catch (e: Throwable) {
            post(SolveEvent.Failed(nowMillis(), e.message ?: e.toString()))
        }
    }
}
