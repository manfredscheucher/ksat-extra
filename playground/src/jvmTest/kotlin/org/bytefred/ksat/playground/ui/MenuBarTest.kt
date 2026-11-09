package org.bytefred.ksat.playground.ui

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.bytefred.ksat.facade.Solver

@OptIn(ExperimentalTestApi::class)
class MenuBarTest {
    @Test
    fun theMenuBarSpansTheTop() = runDesktopComposeUiTest(1000, 600) {
        setContent { App() }
        val file = onNodeWithTag("menu-File").fetchSemanticsNode().boundsInRoot
        assertTrue(file.top < 20f, "menu at the top: $file")
        onNodeWithText("ksat playground", substring = true).assertExists()
    }

    @Test
    fun theSolverMenuShowsAndPicksTheSolver() = runDesktopComposeUiTest(1000, 600) {
        val vm = PlaygroundViewModel()
        setContent { PlaygroundScreen(vm) }
        onNodeWithText("Solver: ${vm.solver.name}").performClick()
        waitForIdle()
        onNodeWithText("✓ ${vm.solver.name}").assertExists()
        onNodeWithText("   ${Solver.KISSAT.name}").performClick()
        waitForIdle()
        assertEquals(Solver.KISSAT, vm.solver)
        onNodeWithText("Solver: KISSAT").assertExists()
    }

    @Test
    fun fileOpensTheExamplesAndHelpTheAbout() = runDesktopComposeUiTest(1000, 600) {
        setContent { PlaygroundScreen(PlaygroundViewModel()) }
        onNodeWithTag("menu-File").performClick()
        waitForIdle()
        onNodeWithText("Examples…").performClick()
        waitForIdle()
        onNodeWithText("Examples").assertExists()
    }

    @Test
    fun helpOpensTheAbout() = runDesktopComposeUiTest(1000, 600) {
        setContent { PlaygroundScreen(PlaygroundViewModel()) }
        onNodeWithTag("menu-Help").performClick()
        waitForIdle()
        onNodeWithText("About ksat playground").performClick()
        waitForIdle()
        onNodeWithText("Feedback is very welcome", substring = true).assertExists()
    }
}
