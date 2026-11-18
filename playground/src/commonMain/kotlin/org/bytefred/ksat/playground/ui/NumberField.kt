package org.bytefred.ksat.playground.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp

/** Inner padding left and right of the number in a [NumberField]. */
private val FIELD_PADDING = 6.dp

/**
 * A compact number input (ktoy's steps/sec field): a low field with a 1 dp grey border, as high as
 * the buttons, mono text, [chars] characters wide (the longest allowed value). Material's
 * OutlinedTextField is at least 280 dp wide and 56 dp high, far bigger than a number. The border
 * turns red when [isError]. With [steps], "−"/"+" buttons change the whole number in the field by
 * 1 within that range. Typing works as before: [onValueChange] gets the text, the caller validates.
 * Test tags: [tag] on the field, "<tag>-minus" / "<tag>-plus" on the buttons.
 */
@Composable
fun NumberField(
    value: String,
    onValueChange: (String) -> Unit,
    chars: Int,
    tag: String,
    isError: Boolean = false,
    enabled: Boolean = true,
    steps: IntRange? = null,
) {
    val style = LocalMonoStyle.current.copy(color = MaterialTheme.colorScheme.onSurface)
    val measurer = rememberTextMeasurer()
    val textPx = remember(chars, style) { measurer.measure("0".repeat(chars), style).size.width }
    // + 2 dp for the cursor after the last character
    val width = with(LocalDensity.current) { textPx.toDp() } + FIELD_PADDING * 2 + 2.dp
    val current = value.trim().toIntOrNull()
    fun step(by: Int) {
        if (steps == null || current == null) return
        // in Long, so a step next to Int.MAX_VALUE cannot overflow
        val next = (current.toLong() + by).coerceIn(steps.first.toLong(), steps.last.toLong())
        onValueChange(next.toString())
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (steps != null) OutlinedButton(
            onClick = { step(-1) },
            enabled = enabled && current != null && current > steps.first,
            modifier = Modifier.testTag("$tag-minus"),
        ) { Text("−") }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = true,
            textStyle = style,
            cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.width(width).height(ButtonDefaults.MinHeight).testTag(tag),
            // the text centred vertically instead of fixed padding, so a larger font scale does not clip it
            decorationBox = { inner ->
                Box(
                    Modifier.fillMaxSize()
                        .border(1.dp, if (isError) MaterialTheme.colorScheme.error else Color(0xFF888888), RoundedCornerShape(4.dp))
                        .padding(horizontal = FIELD_PADDING),
                    contentAlignment = Alignment.CenterStart,
                ) { inner() }
            },
        )
        if (steps != null) OutlinedButton(
            onClick = { step(1) },
            enabled = enabled && current != null && current < steps.last,
            modifier = Modifier.testTag("$tag-plus"),
        ) { Text("+") }
    }
}
