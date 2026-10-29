package org.bytefred.ksat.playground

import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import org.bytefred.ksat.playground.ui.App

/** Desktop (JVM) entry point. Opens a single window hosting the shared [App]. */
fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "ksat playground",
        state = rememberWindowState(width = 1100.dp, height = 800.dp),
    ) {
        App()
    }
}
