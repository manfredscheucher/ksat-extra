package org.bytefred.ksat.demo

// iOS entry point. The demo builds as a Kotlin/Native framework (baseName "Demo"); this file
// is Demo.kt, so Kotlin/Native exposes this top-level fun to Swift as DemoKt.iosDemoReport().
// The SwiftUI app in demo/iosApp/ calls it: Text(DemoKt.iosDemoReport()).
fun iosDemoReport(): String = XorDemo.report("iOS")
