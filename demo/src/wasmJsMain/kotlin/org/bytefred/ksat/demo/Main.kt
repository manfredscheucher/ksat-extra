package org.bytefred.ksat.demo

// Wasm/JS (browser) entry point:  ./gradlew :demo:wasmJsBrowserDevelopmentRun
// Same demo, compiled to WebAssembly. Writes the report to a <pre> and the console.
private fun showOnPage(text: String): Unit =
    js("{ document.body.innerHTML = '<pre>' + text + '</pre>'; }")

fun main() {
    val report = XorDemo.report("Kotlin/Wasm")
    println(report)
    showOnPage(report)
}
