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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.LocalTextStyle
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
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import org.bytefred.ksat.facade.OptionType
import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.facade.SolverOption
import org.bytefred.ksat.facade.solverOptions
import org.bytefred.ksat.playground.GeneratedBuildInfo
import org.bytefred.ksat.playground.core.Example
import org.bytefred.ksat.playground.core.Mode
import org.bytefred.ksat.playground.core.formatOptionValue
import org.bytefred.ksat.playground.core.formatSolution
import org.bytefred.ksat.playground.core.formatTimestamp
import org.bytefred.ksat.playground.core.isParamText

/** Side by side (editor | output) from this width on; stacked below it (phones). */
private val WIDE_LAYOUT = 840.dp

/**
 * The playground: a header, one row of controls (wrapping on narrow screens), then the DIMACS
 * editor and the output.
 */
@Composable
fun PlaygroundScreen(vm: PlaygroundViewModel) {
    var showExamples by remember { mutableStateOf(false) }
    var showOptions by remember { mutableStateOf(false) }
    var showAbout by remember { mutableStateOf(false) }
    val loadFile = rememberFileLoader(onLoaded = { vm.dimacs = it }, onFailed = vm::logError)

    Column(Modifier.fillMaxSize().padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("ksat playground", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            OutlinedButton(onClick = { showAbout = true }) { Text("About") }
        }
        if (isWeb) Text("SAT solvers ported to Kotlin, running in your browser", style = MaterialTheme.typography.bodyMedium)
        Controls(vm, onExamples = { showExamples = true }, onLoadFile = loadFile, onOptions = { showOptions = true })
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            if (maxWidth >= WIDE_LAYOUT) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Editor(vm, Modifier.weight(1f).fillMaxSize())
                    Output(vm, Modifier.weight(1f).fillMaxSize())
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Editor(vm, Modifier.weight(1f).fillMaxWidth())
                    Output(vm, Modifier.weight(1f).fillMaxWidth())
                }
            }
        }
    }

    if (showExamples) ExamplesDialog(vm, onClose = { showExamples = false })
    if (showOptions) OptionsDialog(vm, onClose = { showOptions = false })
    if (showAbout) AboutDialog(onLinkFailed = vm::logError, onClose = { showAbout = false })
}

@Composable
private fun Controls(vm: PlaygroundViewModel, onExamples: () -> Unit, onLoadFile: () -> Unit, onOptions: () -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedButton(onClick = onExamples) { Text("Examples") }
        OutlinedButton(onClick = onLoadFile) { Text("Load file") }
        SolverDropdown(vm.solver, onPick = { vm.solver = it })
        OutlinedButton(onClick = onOptions) { Text("Options") }
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
        OutlinedButton(onClick = { vm.showSolutions = !vm.showSolutions }) {
            Text(if (vm.showSolutions) "Hide solutions" else "Show solutions")
        }
        OutlinedButton(onClick = vm::stop, enabled = vm.running) { Text("Stop") }
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

/** The output of the latest run: one time-stamped line per event, solutions shown on the toggle. */
@Composable
private fun Output(vm: PlaygroundViewModel, modifier: Modifier) {
    val listState = rememberLazyListState()
    LaunchedEffect(vm.log.size) {
        if (vm.log.isNotEmpty()) listState.scrollToItem(vm.log.size - 1)
    }
    val mono = LocalMonoStyle.current.copy(color = OUTPUT_TEXT)
    // top padding: line up with the editor's outline, which sits below its floating label
    Column(modifier.padding(top = 8.dp).background(OUTPUT_BACKGROUND, RoundedCornerShape(4.dp)).padding(8.dp)) {
        Text("Output", style = mono.copy(color = OUTPUT_DIM))
        Spacer(Modifier.height(4.dp))
        LazyColumn(Modifier.fillMaxSize(), state = listState) {
            items(vm.log) { line ->
                // time stamp and message side by side, so a wrapped message stays indented
                Row(Modifier.fillMaxWidth()) {
                    Text(formatTimestamp(line.timeMillis) + "  ", style = mono.copy(color = OUTPUT_DIM))
                    Column(Modifier.weight(1f)) {
                        Text(line.text, style = mono)
                        val solution = line.solution
                        if (solution != null && vm.showSolutions) {
                            Text(formatSolution(solution), style = mono.copy(color = OUTPUT_SOLUTION))
                        }
                    }
                }
            }
        }
    }
}

private val OUTPUT_BACKGROUND = Color(0xFF1E1E1E)
private val OUTPUT_TEXT = Color(0xFFD4D4D4)
private val OUTPUT_DIM = Color(0xFF8A8A8A)
private val OUTPUT_SOLUTION = Color(0xFF9CDCFE)

/**
 * One radio button per [Example]; the selected one shows its parameter fields and description.
 * Generate creates the instance into the editor (in the background; Cancel stops it).
 */
@Composable
private fun ExamplesDialog(vm: PlaygroundViewModel, onClose: () -> Unit) {
    var selected by remember { mutableStateOf(Example.entries.first()) }
    val values = remember { Example.entries.associateWith { e -> e.params.map { mutableStateOf(it.default.toString()) } } }
    val texts = values.getValue(selected).map { it.value }
    var confirmStop by remember { mutableStateOf(false) }
    if (confirmStop) {
        AlertDialog(
            onDismissRequest = { confirmStop = false },
            text = { Text("A computation is still running. Stop it and load the new example?") },
            confirmButton = {
                TextButton(onClick = {
                    confirmStop = false
                    vm.stop()
                    vm.generate(selected, texts, onFinished = onClose)
                }) { Text("Stop and load") }
            },
            dismissButton = { TextButton(onClick = { confirmStop = false }) { Text("Cancel") } },
        )
    }
    AlertDialog(
        onDismissRequest = {
            vm.cancelGeneration()
            onClose()
        },
        title = { Text("Examples") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                for (example in Example.entries) {
                    Row(
                        Modifier.fillMaxWidth()
                            .selectable(selected = example == selected, onClick = { selected = example }, role = Role.RadioButton),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = example == selected, onClick = null)
                        Text(example.title, Modifier.padding(start = 8.dp))
                    }
                    if (example == selected) {
                        Column(Modifier.padding(start = 40.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            for ((param, value) in example.params.zip(values.getValue(example))) {
                                OutlinedTextField(
                                    value = value.value,
                                    onValueChange = { value.value = it },
                                    modifier = Modifier.width(240.dp),
                                    label = { Text("${param.name} (${param.meaning})") },
                                    singleLine = true,
                                    isError = !isParamText(value.value),
                                    enabled = !vm.generating,
                                )
                            }
                            if (example.description.isNotEmpty()) {
                                Text(example.description, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
                if (vm.generating) Text("generating ...")
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (vm.running) confirmStop = true
                    else vm.generate(selected, texts, onFinished = onClose)
                },
                enabled = !vm.generating && texts.all(::isParamText),
            ) { Text("Generate") }
        },
        dismissButton = {
            TextButton(onClick = {
                vm.cancelGeneration()
                onClose()
            }) { Text("Cancel") }
        },
    )
}

/**
 * All options of the selected solver ([solverOptions]): name, upstream description and default;
 * a checkbox for BOOL, a text field for INT / DOUBLE. Edits take effect at once and are kept per
 * solver for the session; only values that differ from the default are passed to the solver.
 */
@Composable
private fun OptionsDialog(vm: PlaygroundViewModel, onClose: () -> Unit) {
    val solver = vm.solver
    val options = remember(solver) { solverOptions(solver) }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("${solver.name} options") },
        text = {
            if (options.isEmpty()) {
                Text("${solver.name} has no options.")
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(options, key = { it.name }) { option -> OptionRow(vm, solver, option) }
                }
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Close") } },
        dismissButton = {
            if (options.isNotEmpty()) TextButton(onClick = { vm.resetOptions(solver) }) { Text("Reset to defaults") }
        },
    )
}

@Composable
private fun OptionRow(vm: PlaygroundViewModel, solver: Solver, option: SolverOption) {
    val text = vm.optionText(solver, option)
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(option.name, Modifier.weight(1f), style = LocalMonoStyle.current, fontWeight = FontWeight.Bold)
            if (option.type == OptionType.BOOL) {
                Checkbox(
                    checked = parseOptionValue(text)?.toDouble() == 1.0,
                    onCheckedChange = { vm.setOptionText(solver, option.name, if (it) "1" else "0") },
                )
            } else {
                OutlinedTextField(
                    value = text,
                    onValueChange = { vm.setOptionText(solver, option.name, it) },
                    modifier = Modifier.width(160.dp),
                    singleLine = true,
                    isError = parseOptionValue(text) == null,
                    textStyle = LocalMonoStyle.current,
                )
            }
        }
        Text(
            "${option.help} (default: ${formatOptionValue(option.default)})",
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

/** About: build identity, the two repos, license. Modeled on ktoy's About. */
@Composable
private fun AboutDialog(onLinkFailed: (String) -> Unit, onClose: () -> Unit) {
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("About ksat playground") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                val sha = GeneratedBuildInfo.COMMIT_SHA
                if (sha != "unknown") {
                    val tag = if (GeneratedBuildInfo.IS_DIRTY == "dirty") "$sha (modified)" else sha
                    Text("commit $tag")
                }
                if (GeneratedBuildInfo.COMMIT_DATE != "unknown") {
                    Text("committed ${GeneratedBuildInfo.COMMIT_DATE}")
                }
                Text("built ${GeneratedBuildInfo.BUILD_DATE}")
                Spacer(Modifier.height(8.dp))
                Text("Kotlin Multiplatform ports of state-of-the-art SAT solvers (MiniSat, CaDiCaL, kissat, MicroSAT). Runs on JVM, Android, iOS, native and in the browser.")
                Spacer(Modifier.height(8.dp))
                Row {
                    LinkText("ksat-extra on GitHub", "https://github.com/manfredscheucher/ksat-extra", onLinkFailed)
                    Text(" (playground, demos, website)", Modifier.padding(vertical = 2.dp))
                }
                Row {
                    LinkText("ksat on GitHub", "https://github.com/manfredscheucher/ksat", onLinkFailed)
                    Text(" (the interface with the solvers)", Modifier.padding(vertical = 2.dp))
                }
                Spacer(Modifier.height(8.dp))
                Text("License", fontWeight = FontWeight.Bold)
                LinkText(
                    "ksat-extra is MIT-licensed (LICENSE)",
                    "https://github.com/manfredscheucher/ksat-extra/blob/main/LICENSE",
                    onLinkFailed,
                )
                Text("Font: DejaVu Sans Mono (Bitstream Vera license, DejaVu changes public domain).")
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("OK") } },
    )
}

/**
 * A clickable, underlined link that opens [url] in the browser. Android throws when no browser is
 * installed, the JVM when the desktop can't browse: then [onFailed] reports it (the output shows it).
 */
@Composable
private fun LinkText(label: String, url: String, onFailed: (String) -> Unit) {
    val uri = LocalUriHandler.current
    Text(
        label,
        style = LocalTextStyle.current.copy(textDecoration = TextDecoration.Underline),
        color = Color(0xFF1A4FB0),
        modifier = Modifier.clickable {
            try {
                uri.openUri(url)
            } catch (e: Exception) {
                onFailed("cannot open $url: ${e.message ?: e}")
            }
        }.padding(vertical = 2.dp),
    )
}
