package org.bytefred.ksat.playground.core

import org.bytefred.ksat.facade.Solver

/** Find the first solution only, or enumerate all of them. */
enum class Mode(val label: String) { ONE("one solution"), ALL("all solutions") }

/** One solve: the CNF as DIMACS text, the solver to run and the [Mode]. */
class SolveRequest(val solver: Solver, val mode: Mode, val dimacs: String) {

    /** Text form for the Web Worker: `<SOLVER> <MODE>`, a newline, then the DIMACS text. */
    fun encode(): String = "${solver.name} ${mode.name}\n$dimacs"

    companion object {
        fun decode(text: String): SolveRequest {
            val newline = text.indexOf('\n')
            require(newline >= 0) { "malformed solve request: no newline" }
            val head = text.substring(0, newline).split(' ')
            require(head.size == 2) { "malformed solve request header '${text.substring(0, newline)}'" }
            return SolveRequest(Solver.valueOf(head[0]), Mode.valueOf(head[1]), text.substring(newline + 1))
        }
    }
}

/** How a run ended without being stopped by the user. */
enum class Outcome {
    /** One-solution mode: a solution was found. */
    ONE_SOLUTION,

    /** All-solutions mode: at least one solution, and the enumeration is complete. */
    NO_MORE_SOLUTIONS,

    /** No solution at all. */
    UNSAT,
}

/**
 * What a run reports, in order: [Started], any number of [SolutionFound], then [Finished]; or
 * [Failed] at any point. [timeMillis] (epoch milliseconds) is taken where the event happens, so the
 * console shows when the solver found something, not when the page got the message.
 */
sealed class SolveEvent {
    abstract val timeMillis: Long

    class Started(override val timeMillis: Long, val numVars: Int, val numClauses: Int) : SolveEvent()

    /** Solution number [index] (1-based); [literals] = the assignment as signed DIMACS literals. */
    class SolutionFound(override val timeMillis: Long, val index: Int, val literals: List<Int>) : SolveEvent()

    class Finished(override val timeMillis: Long, val outcome: Outcome) : SolveEvent()

    /** Parse error or solver failure; ends the run. */
    class Failed(override val timeMillis: Long, val message: String) : SolveEvent()

    /** Text form for the Web Worker: `<kind> <timeMillis> <fields...>` on one string. */
    fun encode(): String = when (this) {
        is Started -> "started $timeMillis $numVars $numClauses"
        is SolutionFound -> "solution $timeMillis $index" + literals.joinToString("") { " $it" }
        is Finished -> "finished $timeMillis ${outcome.name}"
        is Failed -> "failed $timeMillis $message"
    }

    companion object {
        fun decode(text: String): SolveEvent {
            val kindEnd = text.indexOf(' ')
            require(kindEnd > 0) { "malformed solve event '$text'" }
            val kind = text.substring(0, kindEnd)
            if (kind == "failed") {
                val timeEnd = text.indexOf(' ', kindEnd + 1)
                require(timeEnd > 0) { "malformed solve event '$text'" }
                return Failed(text.substring(kindEnd + 1, timeEnd).toLong(), text.substring(timeEnd + 1))
            }
            val fields = text.substring(kindEnd + 1).split(' ')
            val time = fields[0].toLong()
            return when (kind) {
                "started" -> Started(time, fields[1].toInt(), fields[2].toInt())
                "solution" -> SolutionFound(time, fields[1].toInt(), fields.drop(2).map { it.toInt() })
                "finished" -> Finished(time, Outcome.valueOf(fields[1]))
                else -> throw IllegalArgumentException("unknown solve event '$kind'")
            }
        }
    }
}
