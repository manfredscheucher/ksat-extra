package org.bytefred.ksat.playground.core

import org.bytefred.ksat.facade.Solver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

/** Runs [request] to the end and returns its events. */
fun runAll(request: SolveRequest): List<SolveEvent> {
    val events = ArrayList<SolveEvent>()
    PlaygroundSolver.run(request, now = { 0L }, isCancelled = { false }, onEvent = { events += it })
    return events
}

class PlaygroundSolverTest {

    @Test
    fun oneSolutionModeStopsAfterTheFirst() {
        for (solver in Solver.entries) {
            val events = runAll(SolveRequest(solver, Mode.ONE, STARTER_EXAMPLE))
            assertEquals(3, events.size, "$solver: started, solution, finished")
            val started = assertIs<SolveEvent.Started>(events[0])
            assertEquals(3, started.numVars)
            assertEquals(4, started.numClauses)
            val solution = assertIs<SolveEvent.SolutionFound>(events[1])
            assertEquals(1, solution.index)
            assertEquals(1, solution.literals.count { it > 0 }, "$solver: exactly one variable true")
            assertEquals(Outcome.ONE_SOLUTION, assertIs<SolveEvent.Finished>(events[2]).outcome)
        }
    }

    @Test
    fun allSolutionsModeEnumeratesEveryModelWithEverySolver() {
        // incl. MICROSAT and MINISAT (default pre=1), which must use the non-incremental enumeration
        for (solver in Solver.entries) {
            val events = runAll(SolveRequest(solver, Mode.ALL, STARTER_EXAMPLE))
            val solutions = events.filterIsInstance<SolveEvent.SolutionFound>()
            assertEquals(listOf(1, 2, 3), solutions.map { it.index }, "$solver")
            assertEquals(
                setOf(listOf(1, -2, -3), listOf(-1, 2, -3), listOf(-1, -2, 3)),
                solutions.map { it.literals }.toSet(),
                "$solver",
            )
            assertEquals(Outcome.NO_MORE_SOLUTIONS, assertIs<SolveEvent.Finished>(events.last()).outcome)
        }
    }

    @Test
    fun optionsReachTheSolver() {
        // MiniSat pre=0 (core solver, incremental enumeration) and CaDiCaL with options changed
        for ((solver, options) in listOf(
            Solver.MINISAT to mapOf<String, Number>("pre" to 0, "var-decay" to 0.8),
            Solver.MINISAT to mapOf<String, Number>("pre" to 1, "elim" to 0),
            Solver.CADICAL to mapOf<String, Number>("elim" to 0, "seed" to 7),
        )) {
            val events = runAll(SolveRequest(solver, Mode.ALL, STARTER_EXAMPLE, options))
            assertEquals(3, events.count { it is SolveEvent.SolutionFound }, "$solver $options")
            assertEquals(Outcome.NO_MORE_SOLUTIONS, assertIs<SolveEvent.Finished>(events.last()).outcome)
        }
    }

    @Test
    fun invalidOptionsAreRejectedByKsat() {
        for ((solver, options) in listOf(
            Solver.MINISAT to mapOf<String, Number>("bogus" to 1),
            Solver.MINISAT to mapOf<String, Number>("pre" to 0, "elim" to 0),
            Solver.MINISAT to mapOf<String, Number>("var-decay" to 2.0),
            Solver.KISSAT to mapOf<String, Number>("seed" to 1),
        )) for (mode in Mode.entries) {
            assertFailsWith<IllegalArgumentException>("$solver $options $mode") {
                runAll(SolveRequest(solver, mode, STARTER_EXAMPLE, options))
            }
        }
    }

    @Test
    fun unsatInBothModes() {
        for (mode in Mode.entries) {
            val events = runAll(SolveRequest(Solver.CADICAL, mode, "p cnf 1 2\n1 0\n-1 0\n"))
            assertEquals(2, events.size)
            assertEquals(Outcome.UNSAT, assertIs<SolveEvent.Finished>(events.last()).outcome)
        }
    }

    @Test
    fun emptyFormulaHasExactlyTheEmptySolution() {
        for (solver in Solver.entries) {
            val events = runAll(SolveRequest(solver, Mode.ALL, "p cnf 0 0\n"))
            assertEquals(listOf(emptyList()), events.filterIsInstance<SolveEvent.SolutionFound>().map { it.literals }, "$solver")
            assertEquals(Outcome.NO_MORE_SOLUTIONS, assertIs<SolveEvent.Finished>(events.last()).outcome, "$solver")
        }
    }

    @Test
    fun emptyTextHasExactlyTheEmptySolution() {
        val events = runAll(SolveRequest(Solver.MINISAT, Mode.ONE, ""))
        assertEquals(listOf(emptyList()), events.filterIsInstance<SolveEvent.SolutionFound>().map { it.literals })
        assertEquals(Outcome.ONE_SOLUTION, assertIs<SolveEvent.Finished>(events.last()).outcome)
    }

    @Test
    fun parseErrorFailsWithTheLine() {
        val events = runAll(SolveRequest(Solver.MINISAT, Mode.ONE, "p cnf 2 1\n1 x 0\n"))
        val failed = assertIs<SolveEvent.Failed>(events.single())
        assertTrue(failed.message.startsWith("DIMACS parse error at line 2"), failed.message)
    }

    @Test
    fun cancelledAfterTheFirstSolutionEndsWithoutFinished() {
        val events = ArrayList<SolveEvent>()
        PlaygroundSolver.run(
            SolveRequest(Solver.MINISAT, Mode.ALL, STARTER_EXAMPLE),
            now = { 0L },
            isCancelled = { events.any { it is SolveEvent.SolutionFound } },
            onEvent = { events += it },
        )
        assertIs<SolveEvent.Started>(events[0])
        assertIs<SolveEvent.SolutionFound>(events.single { it !is SolveEvent.Started })
    }

    @Test
    fun timeStampsComeFromTheClockWhereTheEventHappens() {
        var t = 100L
        val times = ArrayList<Long>()
        PlaygroundSolver.run(SolveRequest(Solver.KISSAT, Mode.ALL, STARTER_EXAMPLE), now = { t++ },
            isCancelled = { false }, onEvent = { times += it.timeMillis })
        assertEquals((100L until 105L).toList(), times)
    }
}
