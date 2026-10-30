package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.Composable

/**
 * Remember a file-open launcher (platform shim, as in ktoy). The returned lambda opens the
 * platform's file picker; on a successful pick it calls [onLoaded] with the file's text, if the
 * file cannot be read [onFailed] with a message naming it. A cancel does nothing.
 */
@Composable
expect fun rememberFileLoader(onLoaded: (text: String) -> Unit, onFailed: (message: String) -> Unit): () -> Unit

/** True in the browser build: the header then shows the web-only subtitle. */
expect val isWeb: Boolean
