package org.bytefred.ksat.playground.ui

import android.content.Context
import android.content.SharedPreferences

// SharedPreferences need a Context; MainActivity calls initPrefs() before
// setContent. Until then (or on failure) loads return null and saves are no-ops.
private var prefs: SharedPreferences? = null

fun initPrefs(context: Context) {
    prefs = context.applicationContext.getSharedPreferences("ksatplayground", Context.MODE_PRIVATE)
}

actual fun loadPref(key: String): String? = try { prefs?.getString(key, null) } catch (e: Exception) { null }

actual fun savePref(key: String, value: String) {
    try { prefs?.edit()?.putString(key, value)?.apply() } catch (e: Exception) { }
}
