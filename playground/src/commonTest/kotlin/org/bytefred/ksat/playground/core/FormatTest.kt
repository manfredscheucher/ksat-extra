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
    fun durationIsKotlinDurationStyle() {
        assertEquals("412ms", formatDuration(412))
        assertEquals("3.412s", formatDuration(3_412))
        assertEquals("1m 3.412s", formatDuration(63_412))
        assertEquals("1h 0m 5.001s", formatDuration(3_605_001))
        assertEquals("0s", formatDuration(0))
    }

    @Test
    fun optionValueWithoutAFractionWhenIntegral() {
        assertEquals("2", formatOptionValue(2))
        assertEquals("91648253", formatOptionValue(91648253.0))
        assertEquals("0.95", formatOptionValue(0.95))
        assertEquals("Infinity", formatOptionValue(Double.POSITIVE_INFINITY))
    }

    @Test
    fun solutionIsOneLineOfLiterals() {
        assertEquals("1 -2 3", formatSolution(listOf(1, -2, 3)))
        assertEquals("(no variables)", formatSolution(emptyList()))
    }
}
