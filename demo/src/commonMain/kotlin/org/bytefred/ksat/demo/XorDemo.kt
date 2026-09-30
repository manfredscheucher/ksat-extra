package org.bytefred.ksat.demo

import org.bytefred.ksat.SatResult
import org.bytefred.ksat.facade.Ksat
import org.bytefred.ksat.facade.Solver

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
 * Enumeration works by blocking: solve, print the model, add a clause that forbids
 * exactly that assignment, solve again — until the solver reports UNSAT, i.e. there
 * are no more models. (These ports don't accept new clauses mid-instance, so each
 * round uses a fresh solver replaying the CNF plus the blocking clauses so far.)
 */
object XorDemo {

    private const val N_VARS = 2

    // XOR(x1, x2) as CNF. Literals are signed DIMACS: +v = "v true", -v = "v false".
    private val cnf: List<IntArray> = listOf(
        intArrayOf(1, 2),   // x1 OR x2
        intArrayOf(-1, -2), // NOT x1 OR NOT x2
    )

    /** Run the demo with the given solver and return the report as lines of text. */
    fun run(solver: Solver = Solver.MINISAT): List<String> {
        val out = ArrayList<String>()
        out += "CNF:  (x1 OR x2) AND (NOT x1 OR NOT x2)      // XOR(x1, x2)"
        out += "start solver: ksat / $solver"
        out += ""

        val blocks = ArrayList<IntArray>()
        var n = 0
        while (true) {
            val k = Ksat(solver, numVars = N_VARS)
            for (c in cnf) k.addClause(c)
            for (b in blocks) k.addClause(b)

            if (k.solve() != SatResult.SAT) {
                out += if (n == 0) "UNSAT: no solutions." else "no other solutions (UNSAT)."
                break
            }

            val model = (1..N_VARS).map { k.valueOf(it) }
            n++
            out += "solution $n: ${format(model)}"

            // block this exact assignment: OR of the negated literals of the model
            blocks += IntArray(N_VARS) { i -> if (model[i]) -(i + 1) else (i + 1) }
        }
        return out
    }

    private fun format(model: List<Boolean>): String =
        model.mapIndexed { i, v -> "x${i + 1}=${if (v) "true" else "false"}" }.joinToString(", ")
}
