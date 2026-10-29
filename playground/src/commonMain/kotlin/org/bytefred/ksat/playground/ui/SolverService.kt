package org.bytefred.ksat.playground.ui

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import org.bytefred.ksat.playground.core.PlaygroundSolver
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import org.bytefred.ksat.playground.core.nowMillis

/**
 * Runs [PlaygroundSolver.run] off the UI thread: a Web Worker on the web, a background coroutine
 * on JVM/Android. Events are delivered on the UI thread, in order.
 */
interface SolverService {
    fun solve(request: SolveRequest, onEvent: (SolveEvent) -> Unit)

    /** Stop the running solve; no further events of it are delivered. */
    fun cancel()
}

/** The platform's solver service. */
expect fun createSolverService(): SolverService

/**
 * JVM/Android: the solver runs on [dispatcher] and its events are posted to Dispatchers.Main.
 * [cancel] cancels the coroutine, which the solver checks after every solution. The ksat facade
 * cannot interrupt a solve call that is already running, so that call finishes in the background
 * and its result is dropped. So pass a [dispatcher] with a thread per run: leftover
 * solves must not occupy every thread and hold up the next run. Any throwable ends the run with a Failed event.
 */
class CoroutineSolverService(dispatcher: CoroutineDispatcher) : SolverService {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var job: Job? = null

    override fun solve(request: SolveRequest, onEvent: (SolveEvent) -> Unit) {
        cancel()
        job = scope.launch {
            val run = coroutineContext.job
            fun deliver(event: SolveEvent) {
                scope.launch(Dispatchers.Main) { if (!run.isCancelled) onEvent(event) }
            }
            try {
                PlaygroundSolver.run(request, ::nowMillis, isCancelled = { !isActive }, onEvent = ::deliver)
            } catch (e: Throwable) {
                // Also OutOfMemoryError / StackOverflowError: the UI must leave "running" in any case.
                deliver(SolveEvent.Failed(nowMillis(), e.message ?: e.toString()))
            }
        }
    }

    override fun cancel() {
        job?.cancel()
        job = null
    }
}
