package org.bytefred.ksat.playground.ui

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.viewmodel.compose.viewModel

/** The app root: the playground screen; its state lives in a ViewModel that survives rotation. */
@Composable
fun App() {
    MaterialTheme(colorScheme = PlaygroundColors) {
        ProvideMonoStyle {
            // Keep content out of the status bar and the navigation bar / camera cutout (bottom);
            // the activity draws edge-to-edge.
            Surface(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
                val vm: PlaygroundViewModel = viewModel { PlaygroundViewModel() }
                PlaygroundScreen(vm)
            }
        }
    }
}

/** Teal accents on neutral white and plain grey backgrounds (as in ktoy and ksat-chess). */
private val PlaygroundColors = lightColorScheme(
    primary = Color(0xFF2F5D62),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFCFE3E4),
    onPrimaryContainer = Color(0xFF0E2E31),
    secondary = Color(0xFF5B6F78),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFDDE5E9),
    onSecondaryContainer = Color(0xFF1B2A31),
    tertiary = Color(0xFF8A6A2F),
    tertiaryContainer = Color(0xFFF6E7C8),
    onTertiaryContainer = Color(0xFF2E2208),
    background = Color.White,
    onBackground = Color(0xFF1B1F22),
    surface = Color.White,
    onSurface = Color(0xFF1B1F22),
    surfaceVariant = Color(0xFFE6E6E6),
    onSurfaceVariant = Color(0xFF46535A),
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color(0xFFF7F7F7),
    surfaceContainer = Color(0xFFF2F2F2),
    surfaceContainerHigh = Color(0xFFEDEDED),
    surfaceContainerHighest = Color(0xFFE6E6E6),
    surfaceBright = Color.White,
    surfaceDim = Color(0xFFDDDDDD),
    outline = Color(0xFF8A979E),
    outlineVariant = Color(0xFFCCD5DA),
    error = Color(0xFFB3261E),
)
