package org.bytefred.ksat.playground.ui

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel

/** The app root: the playground screen; its state lives in a ViewModel that survives rotation. */
@Composable
fun App() {
    MaterialTheme {
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
