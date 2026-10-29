package org.bytefred.ksat.playground.core

import org.bytefred.ksat.facade.Solver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class SolveProtocolTest {

    @Test
    fun requestRoundTrips() {
        val r = SolveRequest.decode(SolveRequest(Solver.MINISAT_SIMP, Mode.ALL, STARTER_EXAMPLE).encode())
        assertEquals(Solver.MINISAT_SIMP, r.solver)
        assertEquals(Mode.ALL, r.mode)
        assertEquals(STARTER_EXAMPLE, r.dimacs)
    }

    @Test
    fun eventsRoundTrip() {
        val started = assertIs<SolveEvent.Started>(SolveEvent.decode(SolveEvent.Started(12L, 3, 4).encode()))
        assertEquals(listOf(12L, 3L, 4L), listOf(started.timeMillis, started.numVars.toLong(), started.numClauses.toLong()))

        val solution = assertIs<SolveEvent.SolutionFound>(
            SolveEvent.decode(SolveEvent.SolutionFound(13L, 2, listOf(1, -2, 3)).encode()))
        assertEquals(13L, solution.timeMillis)
        assertEquals(2, solution.index)
        assertEquals(listOf(1, -2, 3), solution.literals)

        val empty = assertIs<SolveEvent.SolutionFound>(SolveEvent.decode(SolveEvent.SolutionFound(1L, 1, emptyList()).encode()))
        assertEquals(emptyList(), empty.literals)

        val finished = assertIs<SolveEvent.Finished>(SolveEvent.decode(SolveEvent.Finished(14L, Outcome.UNSAT).encode()))
        assertEquals(Outcome.UNSAT, finished.outcome)

        val failed = assertIs<SolveEvent.Failed>(SolveEvent.decode(SolveEvent.Failed(15L, "bad input\nline 2").encode()))
        assertEquals(15L, failed.timeMillis)
        assertEquals("bad input\nline 2", failed.message)
    }

    @Test
    fun malformedTextFailsLoudly() {
        assertFailsWith<IllegalArgumentException> { SolveRequest.decode("MINISAT ONE") }
        assertFailsWith<IllegalArgumentException> { SolveEvent.decode("bogus 1 2") }
    }
}
