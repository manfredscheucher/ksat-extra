package org.bytefred.ksat.playground.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.asCoroutineDispatcher
import java.util.concurrent.Executors

// Android: the solver runs on a background coroutine; files are picked with the Storage Access
// Framework (OpenDocument).
actual fun createSolverService(): SolverService = CoroutineSolverService(solverDispatcher)

actual fun createGeneratorService(): GeneratorService = CoroutineGeneratorService(solverDispatcher)

/**
 * One daemon thread per running solve or generation (a cached pool): a solve the ksat facade
 * cannot interrupt keeps running after Stop, and must not block the next run.
 */
private val solverDispatcher = Executors.newCachedThreadPool { task ->
    Thread(task, "ksat-solver").apply { isDaemon = true }
}.asCoroutineDispatcher()

@Composable
actual fun rememberFileLoader(onLoaded: (text: String) -> Unit, onFailed: (message: String) -> Unit): () -> Unit {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            val text = try {
                val stream = context.contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("the content provider returned no stream")
                stream.bufferedReader().use { it.readText() }
            } catch (e: Exception) {
                null.also { onFailed("cannot read ${uri.lastPathSegment ?: uri}: ${e.message ?: e.toString()}") }
            }
            if (text != null) onLoaded(text)
        }
    }
    // DIMACS has no registered MIME type; accept anything (the parser rejects non-CNF text loudly).
    return remember(launcher) { { launcher.launch(arrayOf("*/*")) } }
}

@Composable
actual fun rememberFileSaver(
    onSaved: (fileName: String?) -> Unit,
    onFailed: (message: String) -> Unit,
): (fileName: String, text: String) -> Unit {
    val context = LocalContext.current
    // CreateDocument needs the text at launch time; stash it between the call and the result
    // callback (saveable, so a recreated activity still has it; the launch lambda keeps its first closure, the callback is the latest)
    var pending by remember { mutableStateOf<String?>(null) }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/plain")
    ) { uri: Uri? ->
        val text = pending
        pending = null
        if (uri != null && text != null) {
            try {
                (context.contentResolver.openOutputStream(uri) ?: throw IllegalStateException("the content provider returned no stream")).use {
                    it.write((if (text.endsWith("\n")) text else text + "\n").toByteArray())
                }
                onSaved(displayName(context, uri))
            } catch (e: Exception) {
                onFailed("cannot write ${uri.lastPathSegment ?: uri}: ${e.message ?: e.toString()}")
                onSaved(null)
            }
        } else {
            onSaved(null)
        }
    }
    return remember(launcher) {
        { fileName: String, text: String ->
            pending = text
            launcher.launch(fileName)
        }
    }
}

/** The human file name behind a content:// Uri. */
private fun displayName(context: android.content.Context, uri: Uri): String {
    var name = uri.lastPathSegment ?: "formula.cnf"
    context.contentResolver.query(uri, null, null, null, null)?.use { c ->
        val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
        if (idx >= 0 && c.moveToFirst()) name = c.getString(idx) ?: name
    }
    return name
}

actual val isWeb: Boolean = false
