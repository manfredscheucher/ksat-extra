package org.bytefred.ksat.playground.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.playground.core.Mode
import org.bytefred.ksat.playground.core.PIGEONHOLE_K_RANGE
import org.bytefred.ksat.playground.core.STARTER_EXAMPLE
import org.bytefred.ksat.playground.core.formatElapsed
import org.bytefred.ksat.playground.core.formatSolution
import org.bytefred.ksat.playground.core.formatTimestamp
import org.bytefred.ksat.playground.core.nowMillis
import org.bytefred.ksat.playground.core.pigeonholeDimacs

/** Side by side (editor | console) from this width on; stacked below it (phones). */
private val WIDE_LAYOUT = 840.dp

/**
 * The playground: a header, one row of controls (wrapping on narrow screens), then the DIMACS
 * editor and the console log.
 */
@Composable
fun PlaygroundScreen(vm: PlaygroundViewModel) {
    var showExamples by remember { mutableStateOf(false) }
    val loadFile = rememberFileLoader(onLoaded = { vm.dimacs = it }, onFailed = vm::logError)

    Column(Modifier.fillMaxSize().padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Header()
        Controls(vm, onExamples = { showExamples = true }, onLoadFile = loadFile)
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            if (maxWidth >= WIDE_LAYOUT) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Editor(vm, Modifier.weight(1f).fillMaxSize())
                    Console(vm, Modifier.weight(1f).fillMaxSize())
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Editor(vm, Modifier.weight(1f).fillMaxWidth())
                    Console(vm, Modifier.weight(1f).fillMaxWidth())
                }
            }
        }
    }

    if (showExamples) {
        ExamplesDialog(
            onPick = { text ->
                vm.dimacs = text
                showExamples = false
            },
            onDismiss = { showExamples = false },
        )
    }
}

@Composable
private fun Header() {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("ksat playground", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        xorDemoLink?.let { link ->
            val uriHandler = LocalUriHandler.current
            TextButton(onClick = { uriHandler.openUri(link) }) { Text("XOR demo") }
        }
    }
}

@Composable
private fun Controls(vm: PlaygroundViewModel, onExamples: () -> Unit, onLoadFile: () -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedButton(onClick = onExamples) { Text("Examples") }
        OutlinedButton(onClick = onLoadFile) { Text("Load file") }
        SolverDropdown(vm.solver, onPick = { vm.solver = it })
        for (mode in Mode.entries) {
            Row(
                Modifier.selectable(selected = vm.mode == mode, onClick = { vm.mode = mode }, role = Role.RadioButton),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = vm.mode == mode, onClick = null)
                Text(mode.label, Modifier.padding(start = 4.dp, end = 8.dp))
            }
        }
        Button(onClick = vm::solve, enabled = !vm.running) { Text("Solve") }
        OutlinedButton(onClick = vm::stop, enabled = vm.running) { Text("Stop") }
        ElapsedTime(vm)
    }
}

@Composable
private fun SolverDropdown(selected: Solver, onPick: (Solver) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { expanded = true }) { Text("Solver: ${selected.name}") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            for (solver in Solver.entries) {
                DropdownMenuItem(
                    text = { Text(solver.name) },
                    onClick = {
                        onPick(solver)
                        expanded = false
                    },
                )
            }
        }
    }
}

/** How long the latest run has been running (live, every 0.1 s), or how long it took. */
@Composable
private fun ElapsedTime(vm: PlaygroundViewModel) {
    val start = vm.startedAt ?: return
    var now by remember { mutableStateOf(nowMillis()) }
    LaunchedEffect(vm.running) {
        while (vm.running) {
            now = nowMillis()
            delay(100)
        }
    }
    val elapsed = formatElapsed((vm.endedAt ?: now) - start)
    Text(if (vm.running) "running $elapsed" else "time $elapsed", style = LocalMonoStyle.current)
}

@Composable
private fun Editor(vm: PlaygroundViewModel, modifier: Modifier) {
    OutlinedTextField(
        value = vm.dimacs,
        onValueChange = { vm.dimacs = it },
        modifier = modifier,
        label = { Text("DIMACS CNF") },
        textStyle = LocalMonoStyle.current,
    )
}

/** The console log: one time-stamped line per event; a solution line expands on click. */
@Composable
private fun Console(vm: PlaygroundViewModel, modifier: Modifier) {
    val listState = rememberLazyListState()
    LaunchedEffect(vm.log.size) {
        if (vm.log.isNotEmpty()) listState.scrollToItem(vm.log.size - 1)
    }
    val mono = LocalMonoStyle.current.copy(color = CONSOLE_TEXT)
    // top padding: line up with the editor's outline, which sits below its floating label
    Column(modifier.padding(top = 8.dp).background(CONSOLE_BACKGROUND, RoundedCornerShape(4.dp)).padding(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("console", style = mono.copy(color = CONSOLE_DIM), modifier = Modifier.weight(1f))
            TextButton(
                onClick = vm::clearLog,
                enabled = vm.log.isNotEmpty(),
                colors = ButtonDefaults.textButtonColors(contentColor = CONSOLE_TEXT, disabledContentColor = CONSOLE_DIM),
            ) { Text("Clear") }
        }
        Spacer(Modifier.height(4.dp))
        LazyColumn(Modifier.fillMaxSize(), state = listState) {
            itemsIndexed(vm.log) { index, line ->
                val solution = line.solution
                Column(
                    if (solution != null) Modifier.fillMaxWidth().clickable { vm.toggleSolution(index) }
                    else Modifier.fillMaxWidth(),
                ) {
                    // time stamp and message side by side, so a wrapped message stays indented
                    Row {
                        Text(formatTimestamp(line.timeMillis) + "  ", style = mono.copy(color = CONSOLE_DIM))
                        Column(Modifier.weight(1f)) {
                            Text(line.text, style = mono)
                            if (solution != null && line.expanded) {
                                Text(formatSolution(solution), style = mono.copy(color = CONSOLE_SOLUTION))
                            }
                        }
                    }
                }
            }
        }
    }
}

private val CONSOLE_BACKGROUND = Color(0xFF1E1E1E)
private val CONSOLE_TEXT = Color(0xFFD4D4D4)
private val CONSOLE_DIM = Color(0xFF8A8A8A)
private val CONSOLE_SOLUTION = Color(0xFF9CDCFE)

/** The starter CNF, or the pigeonhole formula PHP(k) for a chosen k. */
@Composable
private fun ExamplesDialog(onPick: (String) -> Unit, onDismiss: () -> Unit) {
    var kText by remember { mutableStateOf("5") }
    val k = kText.trim().toIntOrNull()?.takeIf { it in PIGEONHOLE_K_RANGE }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Examples") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { onPick(STARTER_EXAMPLE) }) {
                    Text("Exactly one of x1, x2, x3 (3 solutions)")
                }
                Text("Pigeonhole PHP(k): k+1 pigeons into k holes (UNSAT)")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = kText,
                        onValueChange = { kText = it },
                        modifier = Modifier.width(160.dp),
                        label = { Text("k (${PIGEONHOLE_K_RANGE.first} to ${PIGEONHOLE_K_RANGE.last})") },
                        singleLine = true,
                        isError = k == null,
                    )
                    TextButton(onClick = { k?.let { onPick(pigeonholeDimacs(it)) } }, enabled = k != null) {
                        Text("Generate")
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
