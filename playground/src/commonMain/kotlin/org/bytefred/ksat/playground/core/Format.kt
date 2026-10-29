package org.bytefred.ksat.playground.core

import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Clock
import kotlin.time.Instant

/** Wall-clock time in epoch milliseconds. */
fun nowMillis(): Long = Clock.System.now().toEpochMilliseconds()

/** A console time stamp: local date and time with milliseconds, `yyyy-MM-dd HH:mm:ss.SSS`. */
fun formatTimestamp(epochMillis: Long, zone: TimeZone = TimeZone.currentSystemDefault()): String {
    val t = Instant.fromEpochMilliseconds(epochMillis).toLocalDateTime(zone)
    fun pad(n: Int, width: Int = 2) = n.toString().padStart(width, '0')
    return "${pad(t.year, 4)}-${pad(t.month.ordinal + 1)}-${pad(t.day)} " +
        "${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}.${pad(t.nanosecond / 1_000_000, 3)}"
}

/** Elapsed solver time as `m:ss.t` (minutes, seconds, tenths), e.g. `0:03.4`. */
fun formatElapsed(millis: Long): String {
    val tenths = millis.coerceAtLeast(0) / 100
    val seconds = tenths / 10
    return "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}.${tenths % 10}"
}

/** A solution as one line of signed DIMACS literals, e.g. `1 -2 3`. */
fun formatSolution(literals: List<Int>): String =
    if (literals.isEmpty()) "(no variables)" else literals.joinToString(" ")
