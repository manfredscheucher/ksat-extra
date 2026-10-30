package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp
import ksat_extra.playground.generated.resources.Res
import ksat_extra.playground.generated.resources.dejavu_sans_mono
import org.jetbrains.compose.resources.Font

/** Monospace style of the editor and the output; FontFamily.Monospace outside [ProvideMonoStyle]. */
val LocalMonoStyle = staticCompositionLocalOf {
    TextStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp)
}

/**
 * Provide the bundled DejaVu Sans Mono as [LocalMonoStyle]. FontFamily.Monospace is not reliably
 * monospaced across targets (the web build has no system fonts), as in ktoy. License:
 * licenses/dejavu-LICENSE.txt.
 */
@Composable
fun ProvideMonoStyle(content: @Composable () -> Unit) {
    val family = FontFamily(Font(Res.font.dejavu_sans_mono))
    val style = remember(family) { TextStyle(fontFamily = family, fontSize = 13.sp) }
    CompositionLocalProvider(LocalMonoStyle provides style, content = content)
}
