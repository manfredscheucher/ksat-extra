package org.bytefred.ksat.playground.ui

import org.bytefred.ksat.playground.core.Example
import org.bytefred.ksat.playground.core.GenerateRequest
import org.bytefred.ksat.playground.core.GenerateResult
import org.bytefred.ksat.playground.core.STARTER_EXAMPLE
import org.bytefred.ksat.playground.core.SolveEvent
import org.bytefred.ksat.playground.core.SolveRequest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Save and "Save changes?" before Load file / an example replaces an edited CNF. */
class UnsavedEditsTest {
    private class NoSolver : SolverService {
        override fun solve(request: SolveRequest, onEvent: (SolveEvent) -> Unit) {}
        override fun cancel() {}
    }

    private class Generator : GeneratorService {
        var onResult: ((GenerateResult) -> Unit)? = null
        override fun generate(request: GenerateRequest, onResult: (GenerateResult) -> Unit) { this.onResult = onResult }
        override fun cancel() {}
    }

    private val generator = Generator()
    private val vm = PlaygroundViewModel(NoSolver(), generator, now = { 0L })

    @Test
    fun theStarterExampleIsNotAnEdit() {
        assertFalse(vm.unsavedEdits)
        var ran = false
        vm.leave { ran = true }
        assertTrue(ran)
        assertNull(vm.pendingLeave)
    }

    @Test
    fun anEditAsksBeforeItIsReplaced() {
        vm.dimacs = "p cnf 1 1\n1 0\n"
        assertTrue(vm.unsavedEdits)
        var ran = false
        vm.leave { ran = true }
        assertFalse(ran)
        assertNotNull(vm.pendingLeave)
        vm.cancelLeave()
        assertFalse(ran)
        assertNull(vm.pendingLeave)

        vm.leave { ran = true }
        vm.discardAndLeave()
        assertTrue(ran)
    }

    @Test
    fun savingMarksTheSavedTextAndGoesOn() {
        vm.dimacs = "p cnf 1 1\n1 0\n"
        var ran = false
        vm.leave { ran = true }
        vm.fileSaved("formula.cnf", vm.dimacs)
        assertTrue(ran)
        assertFalse(vm.unsavedEdits)
        assertEquals("saved formula.cnf", vm.log.last().text)
    }

    @Test
    fun aCancelledSaveCancelsTheLeave() {
        vm.dimacs = "p cnf 1 1\n1 0\n"
        var ran = false
        vm.leave { ran = true }
        vm.fileSaved(null, vm.dimacs)
        assertFalse(ran)
        assertNull(vm.pendingLeave)
        assertTrue(vm.unsavedEdits)
    }

    @Test
    fun anEditDuringTheSaveStaysUnsaved() {
        val saved = "p cnf 1 1\n1 0\n"
        vm.dimacs = saved
        vm.dimacs = saved + "-1 0\n"
        vm.fileSaved("formula.cnf", saved)
        assertTrue(vm.unsavedEdits)
    }

    @Test
    fun loadedAndGeneratedTextIsNotAnEdit() {
        vm.loadDimacs("p cnf 2 1\n1 2 0\n")
        assertFalse(vm.unsavedEdits)
        vm.dimacs = "x"
        vm.generate(Example.entries.first(), vm.selectedTexts) {}
        generator.onResult!!(GenerateResult.Generated("p cnf 1 1\n1 0\n"))
        assertFalse(vm.unsavedEdits)
        assertEquals("p cnf 1 1\n1 0\n", vm.dimacs)
    }

    @Test
    fun goingBackToTheSavedTextIsNoEdit() {
        vm.dimacs = STARTER_EXAMPLE + "c\n"
        vm.dimacs = STARTER_EXAMPLE
        assertFalse(vm.unsavedEdits)
    }
}
