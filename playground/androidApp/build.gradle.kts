plugins {
    // AGP 9 has built-in Kotlin support, so no kotlin.android plugin here.
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
}

// The Android app of the ksat playground: MainActivity hosts the shared App() from :playground.
// Split out because AGP 9 does not allow com.android.application together with the Kotlin
// Multiplatform plugin (same as demo/androidApp). Run: scripts/runPlaygroundAndroidEmulator.sh.
kotlin {
    jvmToolchain(21)
}

android {
    namespace = "org.bytefred.ksat.playground"
    compileSdk = libs.versions.android.playgroundCompileSdk.get().toInt()

    defaultConfig {
        applicationId = "org.bytefred.ksat.playground"
        minSdk = libs.versions.android.minSdk.get().toInt()
        targetSdk = libs.versions.android.playgroundCompileSdk.get().toInt()
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    implementation(project(":playground"))
    implementation(libs.androidx.activity.compose)
    implementation(compose.runtime)
}
