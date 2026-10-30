package org.bytefred.ksat.playground.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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

actual val isWeb: Boolean = false
