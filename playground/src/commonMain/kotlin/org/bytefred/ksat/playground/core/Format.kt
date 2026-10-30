package org.bytefred.ksat.playground.core

import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.math.abs
import kotlin.math.floor
import kotlin.time.Clock
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant

/** Wall-clock time in epoch milliseconds. */
fun nowMillis(): Long = Clock.System.now().toEpochMilliseconds()

/** An output time stamp: local date and time with milliseconds, `yyyy-MM-dd HH:mm:ss.SSS`. */
fun formatTimestamp(epochMillis: Long, zone: TimeZone = TimeZone.currentSystemDefault()): String {
    val t = Instant.fromEpochMilliseconds(epochMillis).toLocalDateTime(zone)
    fun pad(n: Int, width: Int = 2) = n.toString().padStart(width, '0')
    return "${pad(t.year, 4)}-${pad(t.month.ordinal + 1)}-${pad(t.day)} " +
        "${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}.${pad(t.nanosecond / 1_000_000, 3)}"
}

/**
 * A run's duration as Kotlin's `Duration.toString()` prints it, from whole milliseconds: `412ms`,
 * `3.412s`, `1m 3.412s`, `1h 0m 5.001s`.
 */
fun formatDuration(millis: Long): String = millis.milliseconds.toString()

/**
 * A solver option value for display: an integral value without a fraction (`2`, `91648253`), else
 * as Kotlin prints the Double (`0.95`, `Infinity`).
 */
fun formatOptionValue(value: Number): String {
    val d = value.toDouble()
    return if (d == floor(d) && abs(d) < 1e15) d.toLong().toString() else d.toString()
}

/** A solution as one line of signed DIMACS literals, e.g. `1 -2 3`. */
fun formatSolution(literals: List<Int>): String =
    if (literals.isEmpty()) "(no variables)" else literals.joinToString(" ")
