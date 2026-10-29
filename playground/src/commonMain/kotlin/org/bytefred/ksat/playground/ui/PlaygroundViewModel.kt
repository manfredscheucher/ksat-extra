package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.playground.core.Mode
import org.bytefred.ksat.playground.core.Outcome
import org.bytefred.ksat.playground.core.STARTER_EXAMPLE
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import org.bytefred.ksat.playground.core.nowMillis

/**
 * One console line. [solution] is set on `solution #i found` lines; a click toggles [expanded],
 * which shows the assignment below the line.
 */
data class LogLine(
    val timeMillis: Long,
    val message: String,
    val solution: List<Int>? = null,
    val expanded: Boolean = false,
) {
    /** The text after the time stamp, incl. the click hint of a solution line. */
    val text: String
        get() = if (solution == null) message else "$message (click to ${if (expanded) "hide" else "show"})"
}

/**
 * The playground's state: the CNF text, solver and mode, the console log and the running run.
 * The log keeps every run (like a console) until [clearLog].
 */
class PlaygroundViewModel(
    private val service: SolverService = createSolverService(),
    private val now: () -> Long = ::nowMillis,
) : ViewModel() {
    var dimacs by mutableStateOf(STARTER_EXAMPLE)
    var solver by mutableStateOf(Solver.MINISAT)
    var mode by mutableStateOf(Mode.ONE)

    val log = mutableStateListOf<LogLine>()

    var running by mutableStateOf(false)
        private set

    /** Start and end of the latest run (epoch ms), for the elapsed-time display. */
    var startedAt by mutableStateOf<Long?>(null)
        private set
    var endedAt by mutableStateOf<Long?>(null)
        private set

    private var runId = 0

    fun solve() {
        if (running) return
        val id = ++runId
        val request = SolveRequest(solver, mode, dimacs)
        running = true
        startedAt = now()
        endedAt = null
        service.solve(request) { event -> if (id == runId && running) onEvent(event, request) }
    }

    fun stop() {
        if (!running) return
        service.cancel()
        end(now(), "stopped by user.")
    }

    fun toggleSolution(index: Int) {
        val line = log[index]
        if (line.solution != null) log[index] = line.copy(expanded = !line.expanded)
    }

    fun clearLog() = log.clear()

    /** An error outside a run (e.g. a file that cannot be read), logged as `error: <message>`. */
    fun logError(message: String) {
        log += LogLine(now(), "error: $message")
    }

    private fun onEvent(event: SolveEvent, request: SolveRequest) {
        val t = event.timeMillis
        when (event) {
            is SolveEvent.Started -> log += LogLine(
                t,
                "start solving: ${request.solver.name}, ${request.mode.label}, " +
                    "${event.numVars} variables, ${event.numClauses} clauses",
            )
            is SolveEvent.SolutionFound -> log += LogLine(t, "solution #${event.index} found", event.literals)
            is SolveEvent.Finished -> end(t, when (event.outcome) {
                Outcome.ONE_SOLUTION -> "stop."
                Outcome.NO_MORE_SOLUTIONS -> "no more solutions. stop."
                Outcome.UNSAT -> "UNSAT. stop."
            })
            is SolveEvent.Failed -> end(t, "error: ${event.message}")
        }
    }

    private fun end(time: Long, message: String) {
        log += LogLine(time, message)
        running = false
        endedAt = time
    }

    override fun onCleared() = service.cancel()
}
