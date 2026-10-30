package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.facade.SolverOption
import org.bytefred.ksat.facade.solverOptions
import org.bytefred.ksat.playground.core.Example
import org.bytefred.ksat.playground.core.GenerateRequest
import org.bytefred.ksat.playground.core.GenerateResult
import org.bytefred.ksat.playground.core.Mode
import org.bytefred.ksat.playground.core.Outcome
import org.bytefred.ksat.playground.core.STARTER_EXAMPLE
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import org.bytefred.ksat.playground.core.formatDuration
import org.bytefred.ksat.playground.core.formatOptionValue
import org.bytefred.ksat.playground.core.nowMillis

/** One output line. [solution] is set on `solution #i found` lines: the assignment to show below it. */
data class LogLine(val timeMillis: Long, val text: String, val solution: List<Int>? = null)

/**
 * The playground's state: the CNF text, solver, options and mode, the output of the latest run and
 * the running run or example generation. Solve clears the output first.
 */
class PlaygroundViewModel(
    private val service: SolverService = createSolverService(),
    private val generator: GeneratorService = createGeneratorService(),
    private val now: () -> Long = ::nowMillis,
) : ViewModel() {
    var dimacs by mutableStateOf(STARTER_EXAMPLE)
    var solver by mutableStateOf(Solver.MINISAT)
    var mode by mutableStateOf(Mode.ONE)

    val log = mutableStateListOf<LogLine>()

    /** Show the assignments of all solution lines (the Show / Hide solutions toggle). */
    var showSolutions by mutableStateOf(false)

    var running by mutableStateOf(false)
        private set

    /** An example is being generated (the Examples dialog waits for it). */
    var generating by mutableStateOf(false)
        private set

    /**
     * Option texts the user edited, per solver, for the session. Only values that differ from the
     * upstream default are passed to the solver ([changedOptions]).
     */
    private val optionEdits = mutableStateMapOf<Solver, Map<String, String>>()

    private var runId = 0
    private var startedAt = 0L
    private var generationId = 0

    fun solve() {
        if (running) return
        log.clear()
        val options = try {
            changedOptions(solver)
        } catch (e: IllegalArgumentException) {
            logError(e.message ?: e.toString())
            return
        }
        val id = ++runId
        val request = SolveRequest(solver, mode, dimacs, options)
        running = true
        startedAt = now()
        service.solve(request) { event -> if (id == runId && running) onEvent(event, request) }
    }

    fun stop() {
        if (!running) return
        service.cancel()
        end(now(), "stopped by user.")
    }

    /** An error outside a run (e.g. a file that cannot be read), logged as `error: <message>`. */
    fun logError(message: String) {
        log += LogLine(now(), "error: $message")
    }

    /** The text of [option] for [solver]: the user's edit, else the upstream default. */
    fun optionText(solver: Solver, option: SolverOption): String =
        optionEdits[solver]?.get(option.name) ?: formatOptionValue(option.default)

    fun setOptionText(solver: Solver, name: String, text: String) {
        optionEdits[solver] = (optionEdits[solver] ?: emptyMap()) + (name to text)
    }

    fun resetOptions(solver: Solver) {
        optionEdits.remove(solver)
    }

    /**
     * The options of [solver] the user changed: every edited value that differs from the upstream
     * default. Throws IllegalArgumentException for a text that is not a number (range and type are
     * checked by ksat when the run starts).
     */
    fun changedOptions(solver: Solver): Map<String, Number> {
        val edits = optionEdits[solver] ?: return emptyMap()
        val changed = LinkedHashMap<String, Number>()
        for (option in solverOptions(solver)) {
            val text = edits[option.name] ?: continue
            val value = parseOptionValue(text)
                ?: throw IllegalArgumentException("$solver option '${option.name}': '$text' is not a number")
            if (value.toDouble() != option.default.toDouble()) changed[option.name] = value
        }
        return changed
    }

    /**
     * Generate [example] with the parameter texts [values] (each [isParamText]) in the background
     * (Web Worker / background thread); [onFinished] runs when it is done, also when it failed (the
     * error is logged). The DIMACS text replaces the editor's and clears the output.
     */
    fun generate(example: Example, values: List<String>, onFinished: () -> Unit) {
        if (generating) return
        val ints = example.params.zip(values).map { (p, text) ->
            text.trim().toIntOrNull() ?: run {
                logError("cannot generate the example: ${p.name} = ${text.trim()} is larger than ${Int.MAX_VALUE}")
                onFinished()
                return
            }
        }
        val request = GenerateRequest(example, ints)
        val id = ++generationId
        generating = true
        generator.generate(request) { result ->
            if (id == generationId && generating) {
                generating = false
                when (result) {
                    is GenerateResult.Generated -> {
                        log.clear()
                        dimacs = result.dimacs
                    }
                    is GenerateResult.Failed -> logError("cannot generate the example: ${result.message}")
                }
                onFinished()
            }
        }
    }

    fun cancelGeneration() {
        if (!generating) return
        generator.cancel()
        generating = false
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
                Outcome.ONE_SOLUTION -> null
                Outcome.NO_MORE_SOLUTIONS -> "no more solutions."
                Outcome.UNSAT -> "UNSAT."
            })
            is SolveEvent.Failed -> {
                log += LogLine(t, "error: ${event.message}")
                running = false
            }
        }
    }

    /** End the run: [message] (if any), then `terminated after X`, both at [time]. */
    private fun end(time: Long, message: String?) {
        if (message != null) log += LogLine(time, message)
        log += LogLine(time, "terminated after ${formatDuration(time - startedAt)}")
        running = false
    }

    override fun onCleared() {
        service.cancel()
        generator.cancel()
    }
}

/** An option text as a number: an Int if it is one, else a Double; null if it is no number. */
fun parseOptionValue(text: String): Number? = text.trim().let { it.toIntOrNull() ?: it.toDoubleOrNull() }
