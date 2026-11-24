package org.bytefred.ksat.playground

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import org.bytefred.ksat.playground.ui.App
import org.bytefred.ksat.playground.ui.initPrefs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        initPrefs(this)
        setContent { App() }
    }
}
