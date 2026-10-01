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
            text = XorDemo.report("Android")
        }
        val scroll = ScrollView(this).apply {
            // Inset the content below the status bar / above the nav bar so the top line
            // isn't clipped; fitsSystemWindows applies the system-bar insets as padding.
            fitsSystemWindows = true
            clipToPadding = false
            setPadding(32, 32, 32, 32)
            addView(text)
        }
        setContentView(scroll)
    }
}
