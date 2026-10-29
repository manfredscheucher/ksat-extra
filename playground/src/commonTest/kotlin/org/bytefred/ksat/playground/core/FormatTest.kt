package org.bytefred.ksat.playground.core

import kotlinx.datetime.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

class FormatTest {

    @Test
    fun timestampIsLocalDateTimeWithMilliseconds() {
        // 2026-10-29T12:03:41.007Z
        assertEquals("2026-10-29 12:03:41.007", formatTimestamp(1_793_275_421_007L, TimeZone.UTC))
        assertEquals("1970-01-01 00:00:00.000", formatTimestamp(0L, TimeZone.UTC))
    }

    @Test
    fun timestampUsesTheGivenZone() {
        // a fixed offset, so the test needs no time-zone database (Kotlin/JS has none built in)
        assertEquals("1970-01-01 01:00:00.000", formatTimestamp(0L, TimeZone.of("+01:00")))
    }

    @Test
    fun elapsedIsMinutesSecondsTenths() {
        assertEquals("0:00.0", formatElapsed(0))
        assertEquals("0:03.4", formatElapsed(3_456))
        assertEquals("2:05.0", formatElapsed(125_000))
        assertEquals("0:00.0", formatElapsed(-5))
    }

    @Test
    fun solutionIsOneLineOfLiterals() {
        assertEquals("1 -2 3", formatSolution(listOf(1, -2, 3)))
        assertEquals("(no variables)", formatSolution(emptyList()))
    }
}
