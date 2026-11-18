package org.bytefred.ksat.playground.ui

import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.dp
import org.bytefred.ksat.facade.solverOptions
import org.bytefred.ksat.playground.core.Example
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The compact number fields of the Examples and Options dialogs (real clicks and typing). */
@OptIn(ExperimentalTestApi::class)
class NumberFieldTest {
    private fun ComposeUiTest.open(menu: String, item: String) {
        onNodeWithTag("menu-$menu").performClick()
        waitForIdle()
        onNodeWithText(item).performClick()
        waitForIdle()
    }

    @Test
    fun exampleParameterStepsAndTypes() = runDesktopComposeUiTest(1000, 800) {
        val vm = PlaygroundViewModel()
        vm.selectedExample = Example.PIGEONHOLE
        setContent { PlaygroundScreen(vm) }
        open("File", "Examples…")
        onNodeWithText("custom").performScrollTo().performClick()
        val field = onNodeWithTag("param-n").performScrollTo()
        // as high as a button, 10 digits wide (Material's text field is 280 x 56 dp)
        val b = field.getUnclippedBoundsInRoot()
        assertEquals(40.dp, b.bottom - b.top)
        assertTrue(b.right - b.left < 110.dp, "width ${b.right - b.left}")

        assertEquals(listOf("5"), vm.selectedTexts)
        onNodeWithTag("param-n-plus").performClick()
        onNodeWithTag("param-n-plus").performClick()
        waitForIdle()
        assertEquals(listOf("7"), vm.selectedTexts)
        onNodeWithTag("param-n-minus").performClick()
        waitForIdle()
        assertEquals(listOf("6"), vm.selectedTexts)
        field.performTextReplacement("0")
        onNodeWithTag("param-n-minus").assertIsNotEnabled()
        onNodeWithTag("param-n-plus").performClick()
        waitForIdle()
        assertEquals(listOf("1"), vm.selectedTexts)
        // not a parameter: Generate off as before; + steps back into the range
        field.performTextReplacement("-3")
        onNodeWithText("Generate").assertIsNotEnabled()
        onNodeWithTag("param-n-plus").performClick()
        waitForIdle()
        assertEquals(listOf("0"), vm.selectedTexts)
        field.performTextReplacement("x")
        onNodeWithText("Generate").assertIsNotEnabled()
        onNodeWithTag("param-n-plus").assertIsNotEnabled()
        field.performTextReplacement("4")
        onNodeWithText("Generate").assertIsEnabled()
        assertEquals(listOf("4"), vm.selectedTexts)
    }

    @Test
    fun solverOptionFieldIsCompactAndTakesTyping() = runDesktopComposeUiTest(1000, 800) {
        val vm = PlaygroundViewModel()
        setContent { PlaygroundScreen(vm) }
        onNodeWithText("Solver: ${vm.solver.name}").performClick()
        waitForIdle()
        onNodeWithText("Options…").performClick()
        waitForIdle()
        val option = solverOptions(vm.solver).first { it.name == "rfirst" }
        val field = onNodeWithTag("option-rfirst").performScrollTo()
        val b = field.getUnclippedBoundsInRoot()
        assertEquals(40.dp, b.bottom - b.top)
        assertTrue(b.right - b.left < 110.dp, "width ${b.right - b.left}")
        field.performTextReplacement("250")
        waitForIdle()
        assertEquals("250", vm.optionText(vm.solver, option))
        assertEquals(0, onAllNodes(hasTestTag("option-rfirst-plus")).fetchSemanticsNodes().size)
    }
}
