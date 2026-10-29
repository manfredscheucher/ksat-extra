package org.bytefred.ksat.playground

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.window.ComposeViewport
import kotlinx.browser.document
import org.bytefred.ksat.playground.ui.App

/**
 * Web (JS/browser) entry point. Hosts the shared [App] in a Compose viewport bound to the document
 * body. The generated bundle is loaded by src/jsMain/resources/index.html.
 */
@OptIn(ExperimentalComposeUiApi::class)
fun main() {
    ComposeViewport(document.body!!) {
        App()
    }
}
