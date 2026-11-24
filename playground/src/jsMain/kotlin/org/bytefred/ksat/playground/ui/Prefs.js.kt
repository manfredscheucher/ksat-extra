package org.bytefred.ksat.playground.ui

actual fun loadPref(key: String): String? =
    try { kotlinx.browser.localStorage.getItem("ksatplayground.$key") } catch (e: Throwable) { null }

actual fun savePref(key: String, value: String) {
    try { kotlinx.browser.localStorage.setItem("ksatplayground.$key", value) } catch (e: Throwable) { }
}
