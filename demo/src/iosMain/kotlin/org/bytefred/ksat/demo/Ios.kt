package org.bytefred.ksat.demo

// iOS entry point. The demo builds as a Kotlin/Native framework for iOS; call this from
// Swift (e.g. Text(DemoKt.iosDemoReport()) in SwiftUI) to show the same report an app.
// The iOS *simulator* target can also run the console main() in nativeMain directly.
fun iosDemoReport(): String = XorDemo.report()
