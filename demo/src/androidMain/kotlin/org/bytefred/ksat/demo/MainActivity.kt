package org.bytefred.ksat.demo

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

// Android entry point: a single Activity that shows the same demo report in a TextView.
// Build/install:  ./gradlew :demo:installDebug   then launch "ksat demo".
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = TextView(this).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            textSize = 14f
            setPadding(24, 24, 24, 24)
            text = XorDemo.report()
        }
        setContentView(ScrollView(this).apply { addView(text) })
    }
}
