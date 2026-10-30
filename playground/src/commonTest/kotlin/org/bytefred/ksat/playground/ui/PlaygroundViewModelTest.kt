package org.bytefred.ksat.playground.ui

import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.facade.solverOptions
import org.bytefred.ksat.playground.core.Example
import org.bytefred.ksat.playground.core.GenerateRequest
import org.bytefred.ksat.playground.core.GenerateResult
import org.bytefred.ksat.playground.core.Mode
import org.bytefred.ksat.playground.core.Outcome
import org.bytefred.ksat.playground.core.STARTER_EXAMPLE
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A service the test drives by hand: it records the request and keeps the event callback. */
private class FakeSolverService : SolverService {
    var request: SolveRequest? = null
    var onEvent: ((SolveEvent) -> Unit)? = null
    var cancels = 0

    override fun solve(request: SolveRequest, onEvent: (SolveEvent) -> Unit) {
        this.request = request
        this.onEvent = onEvent
    }

    override fun cancel() {
        cancels++
    }

    fun emit(event: SolveEvent) = onEvent!!(event)
}

private class FakeGeneratorService : GeneratorService {
    var request: GenerateRequest? = null
    var onResult: ((GenerateResult) -> Unit)? = null
    var cancels = 0

    override fun generate(request: GenerateRequest, onResult: (GenerateResult) -> Unit) {
        this.request = request
        this.onResult = onResult
    }

    override fun cancel() {
        cancels++
    }
}

class PlaygroundViewModelTest {
    private val service = FakeSolverService()
    private val generator = FakeGeneratorService()
    private var clock = 1_000L
    private val vm = PlaygroundViewModel(service, generator, now = { clock })

    private fun texts() = vm.log.map { it.text }

    @Test
    fun oneSolutionRunEndsWithTerminatedAfter() {
        vm.solver = Solver.CADICAL
        vm.solve()
        assertTrue(vm.running)
        assertEquals(Solver.CADICAL, service.request!!.solver)
        assertEquals(Mode.ONE, service.request!!.mode)
        assertEquals(emptyMap(), service.request!!.options)

        service.emit(SolveEvent.Started(1_001L, 3, 4))
        service.emit(SolveEvent.SolutionFound(1_002L, 1, listOf(1, -2, -3)))
        service.emit(SolveEvent.Finished(4_412L, Outcome.ONE_SOLUTION))
        assertEquals(
            listOf(
                "start solving: CADICAL, one solution, 3 variables, 4 clauses",
                "solution #1 found",
                "terminated after 3.412s",
            ),
            texts(),
        )
        assertEquals(listOf(1_001L, 1_002L, 4_412L), vm.log.map { it.timeMillis })
        assertEquals(listOf(1, -2, -3), vm.log[1].solution)
        assertFalse(vm.running)
    }

    @Test
    fun allSolutionsRunEndsWithNoMoreSolutions() {
        vm.mode = Mode.ALL
        vm.solve()
        service.emit(SolveEvent.Started(1_000L, 3, 4))
        for (i in 1..3) service.emit(SolveEvent.SolutionFound(1_000L, i, listOf(i)))
        service.emit(SolveEvent.Finished(1_412L, Outcome.NO_MORE_SOLUTIONS))
        assertEquals(
            listOf(
                "start solving: MINISAT, all solutions, 3 variables, 4 clauses",
                "solution #1 found",
                "solution #2 found",
                "solution #3 found",
                "no more solutions.",
                "terminated after 412ms",
            ),
            texts(),
        )
    }

    @Test
    fun unsatEndsWithUnsatAndAnErrorWithTheErrorOnly() {
        vm.solve()
        service.emit(SolveEvent.Finished(1_000L, Outcome.UNSAT))
        assertEquals(listOf("UNSAT.", "terminated after 0s"), texts())
        assertFalse(vm.running)

        vm.solve()
        service.emit(SolveEvent.Failed(2L, "DIMACS parse error at line 2: x"))
        assertEquals(listOf("error: DIMACS parse error at line 2: x"), texts())
        assertFalse(vm.running)
    }

    @Test
    fun stopCancelsAndDropsLaterEvents() {
        vm.mode = Mode.ALL
        vm.solve()
        service.emit(SolveEvent.SolutionFound(1L, 1, listOf(1)))
        clock = 64_412L
        vm.stop()
        assertEquals(1, service.cancels)
        assertFalse(vm.running)
        assertEquals(listOf("solution #1 found", "stopped by user.", "terminated after 1m 3.412s"), texts())
        assertEquals(listOf(64_412L, 64_412L), vm.log.drop(1).map { it.timeMillis })

        service.emit(SolveEvent.SolutionFound(1L, 2, listOf(-1)))
        assertEquals(3, vm.log.size, "events of a stopped run are dropped")
    }

    @Test
    fun eventsOfAnEarlierRunAreDropped() {
        vm.solve()
        val firstRun = service.onEvent!!
        vm.stop()
        vm.solve()
        firstRun(SolveEvent.Finished(1L, Outcome.UNSAT))
        assertTrue(vm.running, "a late event of the stopped run must not end the new one")
    }

    @Test
    fun solveWhileRunningIsIgnored() {
        vm.solve()
        val first = service.request
        vm.solve()
        assertTrue(first === service.request)
    }

    @Test
    fun solveClearsTheOutput() {
        vm.logError("cannot read x.cnf: denied")
        vm.solve()
        assertTrue(vm.log.isEmpty())
        service.emit(SolveEvent.Finished(1_000L, Outcome.UNSAT))
        vm.solve()
        assertTrue(vm.log.isEmpty())
    }

    @Test
    fun showSolutionsIsOneToggleForAllLines() {
        assertFalse(vm.showSolutions)
        vm.showSolutions = true
        vm.solve()
        assertTrue(vm.showSolutions, "a new run keeps the toggle")
    }

    @Test
    fun fileErrorIsLoggedWithoutARun() {
        vm.logError("cannot read x.cnf: denied")
        assertEquals(listOf("error: cannot read x.cnf: denied"), texts())
        assertFalse(vm.running)
    }

    @Test
    fun onlyOptionsThatDifferFromTheDefaultArePassed() {
        val pre = solverOptions(Solver.MINISAT).first { it.name == "pre" }
        assertEquals("1", vm.optionText(Solver.MINISAT, pre))
        vm.setOptionText(Solver.MINISAT, "pre", "0")
        vm.setOptionText(Solver.MINISAT, "var-decay", "0.95")   // = default: not passed
        vm.setOptionText(Solver.MINISAT, "rfirst", " 50 ")
        vm.setOptionText(Solver.CADICAL, "seed", "3")
        assertEquals("0", vm.optionText(Solver.MINISAT, pre))
        vm.solve()
        assertEquals(mapOf<String, Number>("pre" to 0, "rfirst" to 50), service.request!!.options)

        vm.resetOptions(Solver.MINISAT)
        assertEquals("1", vm.optionText(Solver.MINISAT, pre))
        assertEquals(emptyMap(), vm.changedOptions(Solver.MINISAT))
        assertEquals(mapOf<String, Number>("seed" to 3), vm.changedOptions(Solver.CADICAL), "kept per solver")
    }

    @Test
    fun anOptionThatIsNoNumberIsAnErrorAndNoRun() {
        vm.setOptionText(Solver.MINISAT, "rfirst", "abc")
        vm.solve()
        assertNull(service.request)
        assertFalse(vm.running)
        assertEquals(listOf("error: MINISAT option 'rfirst': 'abc' is not a number"), texts())
    }

    @Test
    fun generateReplacesTheEditorText() {
        var finished = 0
        vm.generate(Example.RAMSEY, listOf("6", "+3", " 3 "), onFinished = { finished++ })
        assertTrue(vm.generating)
        assertEquals(Example.RAMSEY, generator.request!!.example)
        assertEquals(listOf(6, 3, 3), generator.request!!.values)
        generator.onResult!!(GenerateResult.Generated("p cnf 0 0\n"))
        assertFalse(vm.generating)
        assertEquals("p cnf 0 0\n", vm.dimacs)
        assertEquals(1, finished)
    }

    @Test
    fun failedOrTooLargeGenerationIsLogged() {
        var finished = 0
        vm.generate(Example.PIGEONHOLE, listOf("5"), onFinished = { finished++ })
        generator.onResult!!(GenerateResult.Failed("out of memory"))
        assertEquals(STARTER_EXAMPLE, vm.dimacs)
        assertEquals(listOf("error: cannot generate the example: out of memory"), texts())

        vm.generate(Example.PIGEONHOLE, listOf("99999999999"), onFinished = { finished++ })
        assertFalse(vm.generating)
        assertEquals("error: cannot generate the example: n = 99999999999 is larger than 2147483647", texts().last())
        assertEquals(2, finished)
    }

    @Test
    fun cancelledGenerationDropsItsResult() {
        var finished = 0
        vm.generate(Example.XOR, emptyList(), onFinished = { finished++ })
        val result = generator.onResult!!
        vm.cancelGeneration()
        assertEquals(1, generator.cancels)
        assertFalse(vm.generating)
        result(GenerateResult.Generated("p cnf 2 0\n"))
        assertEquals(STARTER_EXAMPLE, vm.dimacs)
        assertEquals(0, finished)
    }
}
