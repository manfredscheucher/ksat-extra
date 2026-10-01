package org.bytefred.ksat.demo

// Wasm/JS (browser) entry point:  ./gradlew :demo:wasmJsBrowserDevelopmentRun
// Same demo, compiled to WebAssembly. Writes the report to a <pre> and the console.
private fun showOnPage(text: String): Unit =
    js("{ document.body.innerHTML = '<h3>ksat SAT demo (Kotlin/Wasm)</h3><pre>' + text + '</pre>'; }")

fun main() {
    val report = XorDemo.report()
    println(report)
    showOnPage(report)
}
