package org.bytefred.ksat.playground.core

import org.bytefred.ksat.DimacsCnf
import org.bytefred.ksat.DimacsParseException
import org.bytefred.ksat.SatResult
import org.bytefred.ksat.facade.Ksat
import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.facade.enumerateModels

/**
 * Runs one [SolveRequest] synchronously and reports every step as a [SolveEvent]. Called inside the
 * Web Worker on the web and on a background coroutine on JVM/Android.
 */
object PlaygroundSolver {

    /**
     * Parse the DIMACS text, then solve. One-solution mode: a single solve. All-solutions mode:
     * ksat's [enumerateModels] (blocking clauses), incremental where the facade allows it (not for
     * MICROSAT and MINISAT_SIMP), with [isCancelled] checked after each solution: once it is true,
     * the run ends without a [SolveEvent.Finished]. A solve that is already running cannot be
     * interrupted through the ksat facade.
     */
    fun run(request: SolveRequest, now: () -> Long, isCancelled: () -> Boolean, onEvent: (SolveEvent) -> Unit) {
        val cnf = try {
            DimacsCnf.parse(request.dimacs)
        } catch (e: DimacsParseException) {
            onEvent(SolveEvent.Failed(now(), e.message ?: e.toString()))
            return
        }
        onEvent(SolveEvent.Started(now(), cnf.numVars, cnf.clauses.size))
        when (request.mode) {
            Mode.ONE -> {
                val ksat = Ksat(request.solver, numVars = cnf.numVars)
                for (clause in cnf.clauses) ksat.addClause(clause)
                if (ksat.solve() == SatResult.SAT) {
                    onEvent(SolveEvent.SolutionFound(now(), 1, literals(cnf.numVars) { ksat.valueOf(it) }))
                    onEvent(SolveEvent.Finished(now(), Outcome.ONE_SOLUTION))
                } else {
                    onEvent(SolveEvent.Finished(now(), Outcome.UNSAT))
                }
            }
            Mode.ALL -> {
                val incremental = request.solver != Solver.MICROSAT && request.solver != Solver.MINISAT_SIMP
                var count = 0
                for (model in enumerateModels(request.solver, cnf.numVars, cnf.clauses, incremental = incremental)) {
                    count++
                    onEvent(SolveEvent.SolutionFound(now(), count, literals(cnf.numVars) { model[it - 1] }))
                    if (isCancelled()) return
                }
                onEvent(SolveEvent.Finished(now(), if (count == 0) Outcome.UNSAT else Outcome.NO_MORE_SOLUTIONS))
            }
        }
    }

    /** The assignment of variables 1..[numVars] as signed DIMACS literals. */
    private fun literals(numVars: Int, value: (Int) -> Boolean): List<Int> =
        (1..numVars).map { v -> if (value(v)) v else -v }
}
