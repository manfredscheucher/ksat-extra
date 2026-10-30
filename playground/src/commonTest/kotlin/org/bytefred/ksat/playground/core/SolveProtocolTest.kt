package org.bytefred.ksat.playground.core

import org.bytefred.ksat.facade.Solver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class SolveProtocolTest {

    @Test
    fun requestRoundTrips() {
        val r = SolveRequest.decode(SolveRequest(Solver.KISSAT, Mode.ALL, STARTER_EXAMPLE).encode())
        assertEquals(Solver.KISSAT, r.solver)
        assertEquals(Mode.ALL, r.mode)
        assertEquals(STARTER_EXAMPLE, r.dimacs)
    }

    @Test
    fun requestWithOptionsRoundTrips() {
        val options = mapOf("pre" to 0, "var-decay" to 0.9, "rfirst" to 50)
        val encoded = SolveRequest(Solver.MINISAT, Mode.ONE, "p cnf 1 1\n1 0\n", options).encode()
        assertEquals("solve MINISAT ONE pre=0 var-decay=0.9 rfirst=50\np cnf 1 1\n1 0\n", encoded)
        val r = SolveRequest.decode(encoded)
        assertEquals(options.mapValues { it.value.toDouble() }, r.options.mapValues { it.value.toDouble() })
        assertEquals("p cnf 1 1\n1 0\n", r.dimacs)
    }

    @Test
    fun generateRoundTrips() {
        val r = GenerateRequest.decode(GenerateRequest(Example.RAMSEY, listOf(6, 3, 3)).encode())
        assertEquals(Example.RAMSEY, r.example)
        assertEquals(listOf(6, 3, 3), r.values)
        assertEquals(emptyList(), GenerateRequest.decode(GenerateRequest(Example.XOR, emptyList()).encode()).values)

        val text = Example.XOR.dimacs(emptyList())
        assertEquals(text, assertIs<GenerateResult.Generated>(GenerateResult.decode(GenerateResult.Generated(text).encode())).dimacs)
        assertEquals("too big", assertIs<GenerateResult.Failed>(GenerateResult.decode(GenerateResult.Failed("too big").encode())).message)
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
        assertFailsWith<IllegalArgumentException> { SolveRequest.decode("solve MINISAT ONE") }
        assertFailsWith<IllegalArgumentException> { SolveRequest.decode("MINISAT ONE\n") }
        assertFailsWith<IllegalArgumentException> { SolveRequest.decode("solve MINISAT ONE pre\n") }
        assertFailsWith<IllegalArgumentException> { GenerateRequest.decode("solve XOR") }
        assertFailsWith<IllegalArgumentException> { GenerateResult.decode("bogus") }
        assertFailsWith<IllegalArgumentException> { SolveEvent.decode("bogus 1 2") }
    }
}
