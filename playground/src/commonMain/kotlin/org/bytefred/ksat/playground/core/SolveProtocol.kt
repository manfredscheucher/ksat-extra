package org.bytefred.ksat.playground.core

import org.bytefred.ksat.facade.Solver

/** Find the first solution only, or enumerate all of them. */
enum class Mode(val label: String) { ONE("one solution"), ALL("all solutions") }

/**
 * One solve: the CNF as DIMACS text, the solver to run, the [Mode] and the solver [options] the
 * user changed (upstream name -> value, see ksat's `solverOptions`; empty = all upstream defaults).
 */
class SolveRequest(
    val solver: Solver,
    val mode: Mode,
    val dimacs: String,
    val options: Map<String, Number> = emptyMap(),
) {

    /**
     * Text form for the Web Worker: `solve <SOLVER> <MODE>`, then ` <name>=<value>` per option, a
     * newline, then the DIMACS text.
     */
    fun encode(): String =
        "$KIND ${solver.name} ${mode.name}" + options.entries.joinToString("") { (k, v) -> " $k=$v" } + "\n$dimacs"

    companion object {
        const val KIND = "solve"

        fun decode(text: String): SolveRequest {
            val newline = text.indexOf('\n')
            require(newline >= 0) { "malformed solve request: no newline" }
            val head = text.substring(0, newline).split(' ')
            require(head.size >= 3 && head[0] == KIND) { "malformed solve request header '${text.substring(0, newline)}'" }
            val options = head.drop(3).associate { option ->
                val eq = option.indexOf('=')
                require(eq > 0) { "malformed solver option '$option'" }
                option.substring(0, eq) to decodeNumber(option.substring(eq + 1))
            }
            return SolveRequest(Solver.valueOf(head[1]), Mode.valueOf(head[2]), text.substring(newline + 1), options)
        }

        /** An Int if the text is one, else a Double (`3` and `3.0` both reach ksat as integral). */
        private fun decodeNumber(text: String): Number =
            text.toIntOrNull() ?: text.toDoubleOrNull() ?: throw IllegalArgumentException("malformed option value '$text'")
    }
}

/** Generate an [Example] with the parameter [values] (in the order of [Example.params]). */
class GenerateRequest(val example: Example, val values: List<Int>) {

    /** Text form for the Web Worker: `generate <EXAMPLE>`, then ` <value>` per parameter. */
    fun encode(): String = "$KIND ${example.name}" + values.joinToString("") { " $it" }

    companion object {
        const val KIND = "generate"

        fun decode(text: String): GenerateRequest {
            val fields = text.split(' ')
            require(fields.size >= 2 && fields[0] == KIND) { "malformed generate request '$text'" }
            return GenerateRequest(Example.valueOf(fields[1]), fields.drop(2).map { it.toInt() })
        }
    }
}

/** The result of a [GenerateRequest]: the DIMACS text, or why the generation failed. */
sealed class GenerateResult {
    class Generated(val dimacs: String) : GenerateResult()

    class Failed(val message: String) : GenerateResult()

    /** Text form for the Web Worker: `generated` + newline + the DIMACS text, or `failed <message>`. */
    fun encode(): String = when (this) {
        is Generated -> "generated\n$dimacs"
        is Failed -> "failed $message"
    }

    companion object {
        fun decode(text: String): GenerateResult = when {
            text.startsWith("generated\n") -> Generated(text.substring("generated\n".length))
            text.startsWith("failed ") -> Failed(text.substring("failed ".length))
            else -> throw IllegalArgumentException("malformed generate result '${text.take(40)}'")
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
 * output shows when the solver found something, not when the page got the message.
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
