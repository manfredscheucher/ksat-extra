plugins {
    alias(libs.plugins.androidApplication)
    // NO kotlinMultiplatform, NO kotlin.android (AGP 9 has built-in Kotlin).
}

// The Android app of the ksat demo: MainActivity shows XorDemo.report() (from :demo's
// commonMain) in a TextView. Split out of :demo because AGP 9 does not allow
// com.android.application together with the Kotlin Multiplatform plugin.
// Build/install: ./gradlew :androidApp:installDebug  (or scripts/runAndroid*.sh).
android {
    namespace = "org.bytefred.ksat.demo"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    defaultConfig {
        applicationId = "org.bytefred.ksat.demo"
        minSdk = libs.versions.android.minSdk.get().toInt()
        targetSdk = libs.versions.android.compileSdk.get().toInt()
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation(project(":demo"))
}
