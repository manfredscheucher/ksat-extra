package org.bytefred.ksat.playground.core

import org.bytefred.ksat.DimacsCnf
import org.bytefred.ksat.facade.Solver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class PigeonholeTest {

    @Test
    fun php1IsTwoPigeonsInOneHole() {
        val cnf = DimacsCnf.parse(pigeonholeDimacs(1))
        assertEquals(2, cnf.numVars)
        assertEquals(listOf(listOf(1), listOf(2), listOf(-1, -2)), cnf.clauses.map { it.toList() })
    }

    @Test
    fun sizesMatchThePigeonholeFormula() {
        for (k in 1..8) {
            val cnf = DimacsCnf.parse(pigeonholeDimacs(k))
            assertEquals((k + 1) * k, cnf.numVars, "variables of PHP($k)")
            // k+1 "pigeon somewhere" clauses + k holes * C(k+1, 2) pairs
            assertEquals((k + 1) + k * (k + 1) * k / 2, cnf.clauses.size, "clauses of PHP($k)")
        }
    }

    @Test
    fun everyPhpIsUnsat() {
        for (k in 1..4) {
            val events = runAll(SolveRequest(Solver.MINISAT, Mode.ONE, pigeonholeDimacs(k)))
            assertEquals(Outcome.UNSAT, assertIs<SolveEvent.Finished>(events.last()).outcome, "PHP($k)")
        }
    }

    @Test
    fun rejectsKBelowOne() {
        assertFailsWith<IllegalArgumentException> { pigeonholeDimacs(0) }
    }
}
