package org.bytefred.ksat.playground.ui

import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.test.swipeRight
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Big dialogs, Help, CNF → Save / "Save changes?", license texts, scrollbars and the divider. */
@OptIn(ExperimentalTestApi::class)
class DialogsTest {
    @BeforeTest
    fun resetPrefs() = resetPlaygroundPrefs()

    private fun ComposeUiTest.menu(title: String, item: String) {
        onNodeWithTag("menu-$title").performClick()
        waitForIdle()
        onNodeWithText(item).performClick()
        waitForIdle()
    }

    /** The open dialog covers the window but a 16 dp margin on each side. */
    private fun ComposeUiTest.assertFills(w: Int, h: Int) {
        val b = onNodeWithTag("big-dialog").fetchSemanticsNode().boundsInRoot
        assertTrue(b.width >= w - 40f && b.height >= h - 40f, "dialog $b in ${w}x$h")
    }

    private fun dialogsFill(w: Int, h: Int) = runDesktopComposeUiTest(w, h) {
        val vm = PlaygroundViewModel()
        setContent { PlaygroundScreen(vm) }
        for ((title, item, close) in listOf(
            Triple("CNF", "Examples…", "Cancel"),
            Triple("Solver", "Options…", "Close"),
            Triple("Help", "General", "OK"),
            Triple("Help", "DIMACS format", "OK"),
            Triple("Help", "About ksat playground", "OK"),
        )) {
            if (title == "Solver") {
                onNodeWithText("Solver: ${vm.solver.name}").performClick()
                waitForIdle()
                onNodeWithText(item).performClick()
                waitForIdle()
            } else {
                menu(title, item)
            }
            assertFills(w, h)
            onNodeWithText(close).performClick()
            waitForIdle()
        }
    }

    @Test
    fun theDialogsFillADesktopWindow() = dialogsFill(1280, 800)

    @Test
    fun theDialogsFillAPhone() = dialogsFill(360, 640)

    @Test
    fun theHelpMenuListsThePagesThenAbout() = runDesktopComposeUiTest(1000, 600) {
        setContent { PlaygroundScreen(PlaygroundViewModel()) }
        onNodeWithTag("menu-Help").performClick()
        waitForIdle()
        val tops = listOf("General", "DIMACS format", "About ksat playground")
            .map { onNodeWithText(it).fetchSemanticsNode().boundsInRoot.top }
        assertEquals(tops.sorted(), tops)
        onNodeWithText("DIMACS format").performClick()
        waitForIdle()
        onNodeWithText("A line starting with c is a comment", substring = true).assertExists()
        onNodeWithTag("big-dialog").assertExists()
        onAllNodesWithText("p cnf 3 4", substring = true).fetchSemanticsNodes().let { assertEquals(2, it.size, "editor and help") }
    }

    @Test
    fun aboutShowsTheLicenseTexts() = runDesktopComposeUiTest(1000, 800) {
        setContent { PlaygroundScreen(PlaygroundViewModel()) }
        menu("Help", "About ksat playground")
        onNodeWithText("License texts").performClick()
        waitForIdle()
        for (title in listOf("ksat (MIT)", "MicroSAT (MIT)", "MiniSat (MIT)", "CaDiCaL (MIT)", "kissat (MIT)")) {
            onNodeWithText(title).assertExists()
        }
        onNodeWithText("DejaVu Sans Mono font (Bitstream Vera license)").assertExists()
        onNodeWithText("Hide license texts").assertExists()
    }

    @Test
    fun fileHasSave() = runDesktopComposeUiTest(1000, 600) {
        setContent { PlaygroundScreen(PlaygroundViewModel()) }
        onNodeWithTag("menu-CNF").performClick()
        waitForIdle()
        val tops = listOf("Examples…", "Load file…", "Save…").map { onNodeWithText(it).fetchSemanticsNode().boundsInRoot.top }
        assertEquals(tops.sorted(), tops)
    }

    @Test
    fun generatingOverAnEditAsksFirst() = runDesktopComposeUiTest(1000, 700) {
        val vm = PlaygroundViewModel()
        setContent { PlaygroundScreen(vm) }
        vm.dimacs = "p cnf 1 1\n1 0\n"
        menu("CNF", "Examples…")
        onNodeWithText("Generate").performClick()
        waitForIdle()
        onNodeWithText("Save changes?").assertExists()
        onAllNodesWithText("Cancel").fetchSemanticsNodes().let { assertEquals(2, it.size) }
        onNodeWithText("Discard").performClick()
        waitUntil(timeoutMillis = 10_000) { !vm.generating && !vm.unsavedEdits }
        assertTrue(vm.dimacs != "p cnf 1 1\n1 0\n", "generated")
    }

    @Test
    fun aLongCnfGetsAScrollbar() = runDesktopComposeUiTest(1000, 600) {
        val vm = PlaygroundViewModel()
        vm.dimacs = (1..200).joinToString("\n") { "$it 0" }
        setContent { PlaygroundScreen(vm) }
        waitForIdle()
        assertTrue(onAllNodesWithTag("vscroll-thumb").fetchSemanticsNodes().isNotEmpty(), "editor thumb")
    }

    @Test
    fun typingAtTheEndOfALongCnfScrollsTheEditor() = runDesktopComposeUiTest(1000, 600) {
        val vm = PlaygroundViewModel()
        vm.dimacs = (1..200).joinToString("\n") { "$it 0" }
        setContent { PlaygroundScreen(vm) }
        onNodeWithTag("editor").performClick()
        onNodeWithTag("editor").performTextInputSelection(TextRange(vm.dimacs.length))
        onNodeWithTag("editor").performTextInput("\n201 0")
        waitForIdle()
        val range = onNodeWithTag("editor").fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange]
        assertTrue(range.value() > 0f && range.value() >= range.maxValue() - 1f, "scrolled to ${range.value()} of ${range.maxValue()}")
    }

    @Test
    fun theDividerResizesEditorAndOutput() = runDesktopComposeUiTest(1280, 700) {
        val vm = PlaygroundViewModel()
        setContent { PlaygroundScreen(vm) }
        val before = onNodeWithTag("editor").fetchSemanticsNode().boundsInRoot.width
        onNodeWithTag("divider-0").performTouchInput { swipeRight(centerX, centerX + 200f) }
        waitForIdle()
        val after = onNodeWithTag("editor").fetchSemanticsNode().boundsInRoot.width
        assertTrue(after > before + 100f, "editor $before -> $after")
    }
}
