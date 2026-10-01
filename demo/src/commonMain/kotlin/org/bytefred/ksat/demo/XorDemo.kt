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

    /**
     * The full demo report as one string — the entry point every target calls. Shows the CNF
     * once, then one block per solver (all four), blocks separated by a blank line.
     */
    fun report(): String {
        val out = ArrayList<String>()
        out += "CNF:  (x1 OR x2) AND (NOT x1 OR NOT x2)      // XOR(x1, x2)"
        for (solver in Solver.entries) {
            out += "" // blank line between the CNF / previous block and this one
            out += run(solver)
        }
        return out.joinToString("\n")
    }

    /** One solver's block: "start solver ...", the solutions, then the UNSAT line. */
    fun run(solver: Solver): List<String> {
        val out = ArrayList<String>()
        out += "start solver: ksat / $solver"
        // enumerateModels is lazy; this small CNF has few models, so collect them all.
        val models = enumerateModels(solver, numVars = N_VARS, cnf = cnf).toList()
        models.forEachIndexed { i, model -> out += "solution ${i + 1}: ${format(model)}" }
        out += if (models.isEmpty()) "UNSAT: no solutions." else "no other solutions (UNSAT)."
        return out
    }

    private fun format(model: List<Boolean>): String =
        model.mapIndexed { i, v -> "x${i + 1}=$v" }.joinToString(", ")
}
