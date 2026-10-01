package org.bytefred.ksat.demo

// JS (browser) entry point:  ./gradlew :demo:jsBrowserDevelopmentRun
// Writes the demo report into a <pre> on the page (and to the console).
private fun showOnPage(text: String) {
    js("document.body.innerHTML = '<pre>' + text + '</pre>'")
}

fun main() {
    val report = XorDemo.report("Kotlin/JS")
    println(report)
    showOnPage(report)
}
