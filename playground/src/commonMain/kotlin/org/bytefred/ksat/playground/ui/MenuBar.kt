package org.bytefred.ksat.playground.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.PopupProperties
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeMark
import kotlin.time.TimeSource
import org.bytefred.ksat.facade.Solver

/**
 * The menu bar across the top (as in ktoy and ksat-chess): File (examples, load, save), Solver
 * (which solver, its options), Help (help pages, about), and the app name on the right.
 */
@Composable
fun PlaygroundMenuBar(
    vm: PlaygroundViewModel,
    onExamples: () -> Unit,
    onLoadFile: () -> Unit,
    onSave: () -> Unit,
    onOptions: () -> Unit,
    onHelp: (HelpPage) -> Unit,
    onAbout: () -> Unit,
) {
    var openMenu by remember { mutableStateOf<String?>(null) }
    val barFocus = remember { FocusRequester() }
    // the popup does not take the focus, so the bar must have it for Escape to reach it
    LaunchedEffect(openMenu) { if (openMenu != null) barFocus.requestFocus() }

    // a menu entry: closes the menu, then runs [onClick]
    @Composable
    fun Item(label: String, onClick: () -> Unit) = DropdownMenuItem(
        text = { Text(label) },
        onClick = { openMenu = null; onClick() },
    )

    Row(
        Modifier.fillMaxWidth().background(MENU_BAR_COLOR).padding(start = 4.dp, end = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // scrolls sideways when the menus don't fit (phones)
        Row(
            Modifier.horizontalScroll(rememberScrollState())
                .testTag("menu-bar")
                .focusRequester(barFocus)
                .onKeyEvent {
                    if (it.key == Key.Escape && openMenu != null) { openMenu = null; true } else false
                }
                .focusable(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            MenuButton("CNF", openMenu, { openMenu = it }) {
                Item("Examples…", onExamples)
                Item("Load file…", onLoadFile)
                Item("Save…", onSave)
            }
            MenuButton("Solver", openMenu, { openMenu = it }, title = "Solver: ${vm.solver.name}") {
                for (solver in Solver.entries) {
                    CheckItem(solver.name, vm.solver == solver) {
                        openMenu = null
                        vm.whenStopped { vm.chooseSolver(solver) }
                    }
                }
                HorizontalDivider()
                Item("Options…", onOptions)
            }
            MenuButton("Help", openMenu, { openMenu = it }) {
                for (page in HelpPage.entries) Item(page.title) { onHelp(page) }
                Item("About ksat playground", onAbout)
            }
        }
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("ksat playground") }
                if (isWeb) append("  SAT solvers ported to Kotlin, running in your browser")
            },
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false).padding(start = 8.dp),
        )
    }
}

/**
 * A menu title with its dropdown. The popup does not take the focus, so a click outside it still
 * reaches what is underneath: clicking another menu title closes this menu and opens that one in one
 * click. A click on the open menu's own title closes it: the popup's outside-click dismissal fires
 * first (on press), so the title click right after it must not reopen the menu.
 */
@Composable
private fun MenuButton(
    label: String,
    openMenu: String?,
    setOpenMenu: (String?) -> Unit,
    title: String = label,
    items: @Composable () -> Unit,
) {
    var dismissedAt by remember { mutableStateOf<TimeMark?>(null) }
    Box {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .testTag("menu-$label")
                .clip(RoundedCornerShape(4.dp))
                .clickable {
                    val justClosed = dismissedAt?.let { it.elapsedNow() < REOPEN_GUARD } == true
                    setOpenMenu(if (openMenu == label || justClosed) null else label)
                }
                .padding(horizontal = 8.dp, vertical = 10.dp),
        )
        DropdownMenu(
            expanded = openMenu == label,
            // only close if this menu is still the open one: the outside click may have just opened another
            onDismissRequest = {
                if (openMenu == label) {
                    dismissedAt = TimeSource.Monotonic.markNow()
                    setOpenMenu(null)
                }
            },
            properties = PopupProperties(focusable = false),
        ) {
            items()
        }
    }
}

// a title click this soon after its menu's outside-click dismissal belongs to the same click
// (press dismissed, release clicked)
private val REOPEN_GUARD = 500.milliseconds

private val MENU_BAR_COLOR = Color(0xFFE6E8EB)

@Composable
private fun CheckItem(label: String, checked: Boolean, onToggle: () -> Unit) {
    DropdownMenuItem(
        text = { Text((if (checked) "✓ " else "   ") + label) },
        onClick = onToggle,
    )
}
