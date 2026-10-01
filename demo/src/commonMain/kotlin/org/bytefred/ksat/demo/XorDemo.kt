package org.bytefred.ksat.demo

import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.facade.enumerateModels

/**
 * A tiny, self-contained SAT demo shared across ALL Kotlin Multiplatform targets
 * (JVM, Android, JS, Wasm, Linux, Windows, macOS, iOS): the SAME code below runs
 * everywhere, because the ksat solver is pure Kotlin common code.
 *
 * It solves XOR(x1, x2) — "exactly one of x1, x2 is true" — and enumerates ALL
 * models, then shows the search running out (UNSAT). In CNF:
 *
 *     (x1 OR x2) AND (NOT x1 OR NOT x2)
 *
 * Enumeration uses the shared [enumerateModels] helper from the ksat facade (solve,
 * block the model found, solve again, until UNSAT).
 */
object XorDemo {

    private const val N_VARS = 2

    // XOR(x1, x2) as CNF. Literals are signed DIMACS: +v = "v true", -v = "v false".
    private val cnf: List<IntArray> = listOf(
        intArrayOf(1, 2),   // x1 OR x2
        intArrayOf(-1, -2), // NOT x1 OR NOT x2
    )

    /** The full demo report as one string — the entry point every target calls. */
    fun report(solver: Solver = Solver.MINISAT): String = run(solver).joinToString("\n")

    /** Run the demo with the given solver and return the report as lines of text. */
    fun run(solver: Solver = Solver.MINISAT): List<String> {
        val out = ArrayList<String>()
        out += "CNF:  (x1 OR x2) AND (NOT x1 OR NOT x2)      // XOR(x1, x2)"
        out += "start solver: ksat / $solver"
        out += ""

        val models = enumerateModels(solver, numVars = N_VARS, cnf = cnf)
        models.forEachIndexed { i, model -> out += "solution ${i + 1}: ${format(model)}" }
        out += if (models.isEmpty()) "UNSAT: no solutions." else "no other solutions (UNSAT)."
        return out
    }

    private fun format(model: List<Boolean>): String =
        model.mapIndexed { i, v -> "x${i + 1}=$v" }.joinToString(", ")
}
