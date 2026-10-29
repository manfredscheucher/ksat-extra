package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.Composable

/**
 * Remember a file-open launcher (platform shim, as in ktoy). The returned lambda opens the
 * platform's file picker; on a successful pick it calls [onLoaded] with the file's text, if the
 * file cannot be read [onFailed] with a message naming it. A cancel does nothing.
 */
@Composable
expect fun rememberFileLoader(onLoaded: (text: String) -> Unit, onFailed: (message: String) -> Unit): () -> Unit

/** Link to the XOR demo next to the playground (the web build on GitHub Pages), or null. */
expect val xorDemoLink: String?
