plugins {
    // Applied per-module; declared here (apply false) so the version is shared and the Android
    // Gradle Plugin is on the shared buildscript classpath. AGP 9: KMP modules (the included
    // solver modules and :demo) apply androidKmpLibrary; the Android app is the separate
    // :androidApp module (com.android.application, no KMP plugin — AGP 9 has built-in Kotlin).
    alias(libs.plugins.kotlinMultiplatform) apply false
    alias(libs.plugins.androidLibrary) apply false
    alias(libs.plugins.androidKmpLibrary) apply false
    alias(libs.plugins.androidApplication) apply false
    // The playground (Compose Multiplatform, like ktoy).
    alias(libs.plugins.composeMultiplatform) apply false
    alias(libs.plugins.composeCompiler) apply false
}
