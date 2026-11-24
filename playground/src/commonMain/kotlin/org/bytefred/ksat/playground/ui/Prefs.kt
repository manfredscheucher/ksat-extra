package org.bytefred.ksat.playground.ui

/**
 * Tiny persistent key/value store for the playground's settings (solver, mode, edited options).
 * Ported from ktoy's loadPref/savePref. Failures are swallowed: a setting that can't be read or
 * written just falls back to the default.
 */
expect fun loadPref(key: String): String?

expect fun savePref(key: String, value: String)

internal const val SOLVER_PREF = "solver"
internal const val MODE_PREF = "mode"

/** The edited option texts of one solver, one "name=text" per line. */
internal fun optionsPref(solverName: String) = "options.$solverName"
