package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.Composable

/**
 * Remember a file-open launcher (platform shim, as in ktoy). The returned lambda opens the
 * platform's file picker; on a successful pick it calls [onLoaded] with the file's text, if the
 * file cannot be read [onFailed] with a message naming it. A cancel does nothing.
 */
@Composable
expect fun rememberFileLoader(onLoaded: (text: String) -> Unit, onFailed: (message: String) -> Unit): () -> Unit

/**
 * Remember a file-save launcher (platform shim, as in ktoy) taking (suggested file name, text): a
 * save dialog on desktop and Android, a download in the browser. It calls [onSaved] with the file
 * name, or with null if the user cancelled or the file cannot be written (then [onFailed] first,
 * with a message naming it).
 */
@Composable
expect fun rememberFileSaver(
    onSaved: (fileName: String?) -> Unit,
    onFailed: (message: String) -> Unit,
): (fileName: String, text: String) -> Unit

/** True in the browser build: the header then shows the web-only subtitle. */
expect val isWeb: Boolean
