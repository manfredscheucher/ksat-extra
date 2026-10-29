package org.bytefred.ksat.playground.ui

import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.playground.core.Mode
import org.bytefred.ksat.playground.core.Outcome
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
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

class PlaygroundViewModelTest {
    private val service = FakeSolverService()
    private var clock = 1_000L
    private val vm = PlaygroundViewModel(service, now = { clock })

    private fun texts() = vm.log.map { it.text }

    @Test
    fun oneSolutionRunLogsStartSolutionAndStop() {
        vm.solver = Solver.CADICAL
        vm.solve()
        assertTrue(vm.running)
        assertEquals(Solver.CADICAL, service.request!!.solver)
        assertEquals(Mode.ONE, service.request!!.mode)
        assertEquals(1_000L, vm.startedAt)

        service.emit(SolveEvent.Started(1_001L, 3, 4))
        service.emit(SolveEvent.SolutionFound(1_002L, 1, listOf(1, -2, -3)))
        service.emit(SolveEvent.Finished(1_003L, Outcome.ONE_SOLUTION))
        assertEquals(
            listOf(
                "start solving: CADICAL, one solution, 3 variables, 4 clauses",
                "solution #1 found (click to show)",
                "stop.",
            ),
            texts(),
        )
        assertEquals(listOf(1_001L, 1_002L, 1_003L), vm.log.map { it.timeMillis })
        assertFalse(vm.running)
        assertEquals(1_003L, vm.endedAt)
    }

    @Test
    fun allSolutionsRunEndsWithNoMoreSolutions() {
        vm.mode = Mode.ALL
        vm.solve()
        service.emit(SolveEvent.Started(1L, 3, 4))
        for (i in 1..3) service.emit(SolveEvent.SolutionFound(1L, i, listOf(i)))
        service.emit(SolveEvent.Finished(1L, Outcome.NO_MORE_SOLUTIONS))
        assertEquals(
            listOf(
                "start solving: MINISAT, all solutions, 3 variables, 4 clauses",
                "solution #1 found (click to show)",
                "solution #2 found (click to show)",
                "solution #3 found (click to show)",
                "no more solutions. stop.",
            ),
            texts(),
        )
    }

    @Test
    fun unsatAndErrorEndTheRun() {
        vm.solve()
        service.emit(SolveEvent.Finished(1L, Outcome.UNSAT))
        assertEquals("UNSAT. stop.", texts().last())
        assertFalse(vm.running)

        vm.solve()
        service.emit(SolveEvent.Failed(2L, "DIMACS parse error at line 2: x"))
        assertEquals("error: DIMACS parse error at line 2: x", texts().last())
        assertFalse(vm.running)
    }

    @Test
    fun stopCancelsAndDropsLaterEvents() {
        vm.mode = Mode.ALL
        vm.solve()
        service.emit(SolveEvent.SolutionFound(1L, 1, listOf(1)))
        clock = 5_000L
        vm.stop()
        assertEquals(1, service.cancels)
        assertFalse(vm.running)
        assertEquals(5_000L, vm.endedAt)
        assertEquals(listOf("solution #1 found (click to show)", "stopped by user."), texts())

        service.emit(SolveEvent.SolutionFound(1L, 2, listOf(-1)))
        assertEquals(2, vm.log.size, "events of a stopped run are dropped")
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
    fun clickingASolutionLineTogglesIt() {
        vm.solve()
        service.emit(SolveEvent.SolutionFound(1L, 1, listOf(1, -2)))
        vm.toggleSolution(0)
        assertTrue(vm.log[0].expanded)
        assertEquals("solution #1 found (click to hide)", vm.log[0].text)
        assertEquals(listOf(1, -2), vm.log[0].solution)
        vm.toggleSolution(0)
        assertFalse(vm.log[0].expanded)
    }

    @Test
    fun logKeepsEarlierRunsUntilCleared() {
        vm.solve()
        service.emit(SolveEvent.Finished(1L, Outcome.UNSAT))
        vm.solve()
        service.emit(SolveEvent.Finished(2L, Outcome.UNSAT))
        assertEquals(2, vm.log.size)
        vm.clearLog()
        assertTrue(vm.log.isEmpty())
    }

    @Test
    fun fileErrorIsLoggedWithoutARun() {
        vm.logError("cannot read x.cnf: denied")
        assertEquals(listOf("error: cannot read x.cnf: denied"), texts())
        assertFalse(vm.running)
    }
}
