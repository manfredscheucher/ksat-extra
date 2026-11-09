package org.bytefred.ksat.playground.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.bytefred.ksat.playground.core.STARTER_EXAMPLE

/** The Help menu's pages, in menu order (About has its own dialog). */
enum class HelpPage(val title: String) {
    GENERAL("General"),
    DIMACS("DIMACS format"),
}

/** One Help page in a [BigDialog]: plain paragraphs, monospace only for the DIMACS example. */
@Composable
fun HelpDialog(page: HelpPage, onDismiss: () -> Unit) {
    BigDialog(page.title, onDismiss, buttons = { TextButton(onClick = onDismiss) { Text("OK") } }) {
        val vScroll = rememberScrollState()
        ScrollbarBox(vScroll, Modifier.weight(1f).fillMaxWidth()) {
            Column(
                Modifier.verticalScroll(vScroll).padding(end = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                when (page) {
                    HelpPage.GENERAL -> GENERAL_TEXT.forEach { Paragraph(it) }
                    HelpPage.DIMACS -> {
                        Paragraph(DIMACS_INTRO)
                        Text(
                            STARTER_EXAMPLE.trimEnd(),
                            style = LocalMonoStyle.current,
                            softWrap = false,
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                        )
                        Paragraph(DIMACS_RULES)
                    }
                }
            }
        }
    }
}

@Composable
private fun Paragraph(text: String) {
    Text(text, style = MaterialTheme.typography.bodyLarge)
}

internal val GENERAL_TEXT = listOf(
    "The playground solves a formula in conjunctive normal form (CNF) with one of four SAT solvers " +
        "ported to Kotlin: MicroSAT, MiniSat, CaDiCaL and kissat.",
    "Type or paste the formula into the editor. File → Examples… generates one, File → Load file… reads " +
        "one from a file, and File → Save… writes the editor's text to a file. Before a load or an example " +
        "replaces edits that are not saved, the playground asks.",
    "The Solver menu picks the solver. Options… lists its options with their defaults; a changed value " +
        "applies to the following runs.",
    "With one solution, Solve stops at the first solution. With all solutions, it finds every solution, " +
        "one after the other. While it runs, the button turns into Stop.",
    "The output shows the latest run, one line per event with its time: the start, each solution found and the " +
        "end, such as UNSAT or no more solutions. Show solutions shows each solution as a list of literals, " +
        "for example 1 -2 3 for variable 1 true, 2 false and 3 true.",
)

internal const val DIMACS_INTRO = "The editor takes a CNF in the DIMACS format. A formula is a list of " +
    "clauses, and a clause is true if at least one of its literals is. A literal is the number of a " +
    "variable, negative for its negation. This formula says that exactly one of x1, x2 and x3 is true:"

internal const val DIMACS_RULES = "A line starting with c is a comment. The header p cnf gives the number " +
    "of variables and of clauses; it may be left out, and the numbers are not checked against the " +
    "clauses. Each clause ends with 0 and may go over several lines."
