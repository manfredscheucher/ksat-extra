package org.bytefred.ksat.playground.ui

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import org.bytefred.ksat.playground.core.GenerateRequest
import org.bytefred.ksat.playground.core.GenerateResult
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

/**
 * Generates an example's DIMACS text off the UI thread: a Web Worker on the web, a background
 * coroutine on JVM/Android. The result is delivered on the UI thread.
 */
interface GeneratorService {
    fun generate(request: GenerateRequest, onResult: (GenerateResult) -> Unit)

    /** Stop the running generation; its result is not delivered. */
    fun cancel()
}

/** The platform's generator service. */
expect fun createGeneratorService(): GeneratorService

/**
 * JVM/Android: the generation runs on [dispatcher] and checks for cancellation once per clause;
 * its result is posted to Dispatchers.Main. Any throwable (also OutOfMemoryError for a huge
 * instance) is delivered as [GenerateResult.Failed].
 */
class CoroutineGeneratorService(dispatcher: CoroutineDispatcher) : GeneratorService {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var job: Job? = null

    override fun generate(request: GenerateRequest, onResult: (GenerateResult) -> Unit) {
        cancel()
        job = scope.launch {
            val result = try {
                GenerateResult.Generated(request.example.dimacs(request.values, checkCancelled = { ensureActive() }))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                GenerateResult.Failed(e.message ?: e.toString())
            }
            val run = coroutineContext.job
            scope.launch(Dispatchers.Main) { if (!run.isCancelled) onResult(result) }
        }
    }

    override fun cancel() {
        job?.cancel()
        job = null
    }
}
