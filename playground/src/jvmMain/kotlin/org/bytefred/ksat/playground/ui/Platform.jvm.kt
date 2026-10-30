package org.bytefred.ksat.playground.ui

import androidx.compose.runtime.Composable
import kotlinx.coroutines.asCoroutineDispatcher
import java.util.concurrent.Executors
import javax.swing.JFileChooser
import javax.swing.filechooser.FileNameExtensionFilter

// Desktop: the solver runs on a background coroutine; files are picked with a Swing file chooser.
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
actual fun rememberFileLoader(onLoaded: (text: String) -> Unit, onFailed: (message: String) -> Unit): () -> Unit = {
    val chooser = JFileChooser().apply {
        dialogTitle = "Load CNF"
        fileFilter = FileNameExtensionFilter("DIMACS CNF (*.cnf, *.dimacs, *.txt)", "cnf", "dimacs", "txt")
    }
    if (chooser.showOpenDialog(null) == JFileChooser.APPROVE_OPTION) {
        val f = chooser.selectedFile
        val text = try {
            f.readText()
        } catch (e: Exception) {
            null.also { onFailed("cannot read ${f.name}: ${e.message ?: e.toString()}") }
        }
        if (text != null) onLoaded(text)
    }
}
