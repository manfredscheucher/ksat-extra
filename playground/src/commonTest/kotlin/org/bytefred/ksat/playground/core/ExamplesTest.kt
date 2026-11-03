package org.bytefred.ksat.playground.core

import org.bytefred.ksat.DimacsCnf
import org.bytefred.ksat.facade.Solver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

class ExamplesTest {

    private fun binomial(n: Int, k: Int): Int {
        if (k < 0 || k > n) return 0
        var r = 1L
        for (i in 0 until k) r = r * (n - i) / (i + 1)
        return r.toInt()
    }

    /** Number of solutions of [dimacs], by enumerating all of them (CADICAL, incremental). */
    private fun solutions(dimacs: String): Int {
        val events = runAll(SolveRequest(Solver.CADICAL, Mode.ALL, dimacs))
        assertIs<SolveEvent.Finished>(events.last())
        return events.count { it is SolveEvent.SolutionFound }
    }

    @Test
    fun xorHasTwoClausesAndTwoSolutions() {
        val text = Example.XOR.dimacs(emptyList())
        assertTrue(text.startsWith("c ${Example.XOR.title}\nc expected behavior: 2 solutions\np cnf 2 2\n"), text)
        assertEquals(listOf(listOf(1, 2), listOf(-1, -2)), DimacsCnf.parse(text).clauses.map { it.toList() })
        assertEquals(2, solutions(text))
    }

    @Test
    fun headerNamesTheExampleAndItsParameters() {
        val text = Example.RAMSEY.dimacs(listOf(6, 3, 3))
        assertEquals("c ${Example.RAMSEY.title}\nc n=6, k=3, l=3\nc expected behavior: UNSAT\n", text.substringBefore("p cnf"))
    }

    @Test
    fun exactlyKOfNHasTheBinomialCounts() {
        for (n in 0..6) for (k in 0..n) {
            val text = Example.EXACTLY_K_OF_N.dimacs(listOf(k, n))
            val cnf = DimacsCnf.parse(text)
            assertEquals(n, cnf.numVars, "k=$k n=$n")
            val atLeast = if (k >= 1) binomial(n, k - 1) else 0
            assertEquals(binomial(n, k + 1) + atLeast, cnf.clauses.size, "clauses k=$k n=$n")
            assertEquals(binomial(n, k), solutions(text), "solutions k=$k n=$n")
        }
    }

    @Test
    fun exactly2Of4HasSixSolutionsAndKAboveNIsTheEmptyClause() {
        assertEquals(6, solutions(Example.EXACTLY_K_OF_N.dimacs(listOf(2, 4))))
        val cnf = DimacsCnf.parse(Example.EXACTLY_K_OF_N.dimacs(listOf(7, 3)))
        assertEquals(listOf(emptyList()), cnf.clauses.map { it.toList() })
        assertEquals(0, solutions(Example.EXACTLY_K_OF_N.dimacs(listOf(Int.MAX_VALUE, 3))))
    }

    @Test
    fun exactly1OfNHasOneClauseOverAllObjects() {
        val cnf = DimacsCnf.parse(Example.EXACTLY_K_OF_N.dimacs(listOf(1, 3)))
        assertEquals(listOf(1, 2, 3), cnf.clauses.last().toList())
    }

    @Test
    fun pigeonholeSizesAndUnsat() {
        assertEquals(listOf(emptyList()), DimacsCnf.parse(pigeonholeDimacs(0)).clauses.map { it.toList() })
        assertEquals(
            listOf(listOf(1), listOf(2), listOf(-1, -2)),
            DimacsCnf.parse(pigeonholeDimacs(1)).clauses.map { it.toList() },
        )
        for (n in 0..8) {
            val cnf = DimacsCnf.parse(pigeonholeDimacs(n))
            assertEquals((n + 1) * n, cnf.numVars, "variables of n=$n")
            assertEquals((n + 1) + n * binomial(n + 1, 2), cnf.clauses.size, "clauses of n=$n")
        }
        for (n in 0..4) assertEquals(0, solutions(pigeonholeDimacs(n)), "n=$n")
    }

    @Test
    fun ramseyCounts() {
        for (n in 0..6) for (k in 0..4) for (l in 0..4) {
            val cnf = DimacsCnf.parse(Example.RAMSEY.dimacs(listOf(n, k, l)))
            assertEquals(binomial(n, 2), cnf.numVars, "n=$n")
            assertEquals(binomial(n, k) + binomial(n, l), cnf.clauses.size, "n=$n k=$k l=$l")
        }
        assertEquals(12, solutions(Example.RAMSEY.dimacs(listOf(5, 3, 3))))
        assertEquals(0, solutions(Example.RAMSEY.dimacs(listOf(6, 3, 3))))
        // k = 1: every single vertex is a 1-subset without edges, so its clause is empty
        assertEquals(0, solutions(Example.RAMSEY.dimacs(listOf(3, 1, 5))))
        // k, l > n: no clause at all, every graph on 3 vertices
        assertEquals(8, solutions(Example.RAMSEY.dimacs(listOf(3, 4, 4))))
    }

    @Test
    fun tooManyVariablesAndNegativeValuesFailLoudly() {
        assertFailsWith<IllegalArgumentException> { Example.RAMSEY.dimacs(listOf(100_000, 3, 3)) }
        assertFailsWith<IllegalArgumentException> { Example.PIGEONHOLE.dimacs(listOf(-1)) }
        assertFailsWith<IllegalArgumentException> { Example.XOR.dimacs(listOf(1)) }
    }

    @Test
    fun cancelStopsTheGeneration() {
        var calls = 0
        assertFailsWith<IllegalStateException> {
            Example.PIGEONHOLE.dimacs(listOf(50)) { if (++calls == 10) throw IllegalStateException("cancelled") }
        }
        assertEquals(10, calls)
    }

    @Test
    fun presetsAreTheListedOnes() {
        assertEquals(
            listOf(
                listOf("R(3,3) > 5", "R(3,3) > 6"), listOf("R(3,4) > 8", "R(3,4) > 9"),
                listOf("R(3,5) > 13", "R(3,5) > 14"), listOf("R(4,4) > 17", "R(4,4) > 18"),
            ),
            Example.RAMSEY.presets.map { row -> row.map { it.label } },
        )
        assertEquals(listOf(6, 3, 3), Example.RAMSEY.presets[0][1].values)
        assertEquals(listOf(18, 4, 4), Example.RAMSEY.presets[3][1].values)
        assertEquals((3..9).map { "n=$it" }, Example.PIGEONHOLE.presets.flatten().map { it.label })
        assertEquals((3..9).map { listOf(it) }, Example.PIGEONHOLE.presets.flatten().map { it.values })
        assertTrue(Example.XOR.presets.isEmpty() && Example.EXACTLY_K_OF_N.presets.isEmpty())
    }

    @Test
    fun expectedBehavior() {
        assertEquals("C(4,2) = 6 solutions", Example.EXACTLY_K_OF_N.expected(listOf(2, 4)))
        assertEquals("C(3,5) = 0 solutions", Example.EXACTLY_K_OF_N.expected(listOf(5, 3)))
        assertEquals("C(1000,500) solutions", Example.EXACTLY_K_OF_N.expected(listOf(500, 1000)))
        assertEquals("UNSAT", Example.PIGEONHOLE.expected(listOf(5)))
        assertEquals("SAT", Example.RAMSEY.expected(listOf(13, 3, 5)))
        assertEquals("UNSAT", Example.RAMSEY.expected(listOf(14, 5, 3)))
        assertEquals("SAT if and only if R(5,5) > 42", Example.RAMSEY.expected(listOf(42, 5, 5)))
    }

    /** R(k,l) > n is SAT below the Ramsey number and UNSAT at it (small cases only). */
    @Test
    fun smallRamseyPresetsAreSatThenUnsat() {
        for (row in Example.RAMSEY.presets.take(2)) {
            val (below, at) = row.map { p ->
                val events = runAll(SolveRequest(Solver.CADICAL, Mode.ONE, Example.RAMSEY.dimacs(p.values)))
                events.any { it is SolveEvent.SolutionFound }
            }
            assertTrue(below, row[0].label)
            assertFalse(at, row[1].label)
        }
    }

    @Test
    fun paramTextIsANonNegativeInteger() {
        for (ok in listOf("0", "5", " 12 ", "+3", "-0", "99999999999999999999")) assertTrue(isParamText(ok), ok)
        for (bad in listOf("", " ", "-1", "1.5", "abc", "1e3", "--2")) assertFalse(isParamText(bad), bad)
    }
}
