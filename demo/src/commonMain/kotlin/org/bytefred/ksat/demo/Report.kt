package org.bytefred.ksat.demo

/** The full demo report as one string — handy for console targets and tests. */
fun xorDemoReport(): String = XorDemo.run().joinToString("\n")
