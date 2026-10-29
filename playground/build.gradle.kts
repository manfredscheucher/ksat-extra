import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidKmpLibrary)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
}

// The interactive ksat playground (doc/playground.md): paste or load a DIMACS CNF, pick a solver,
// find one or all solutions. Shared Compose UI for web (JS), JVM desktop and Android, laid out like
// ktoy's composeApp. Android: AGP 9 does not allow com.android.application in a KMP module, so this
// is an Android LIBRARY target and the app lives in :playgroundAndroidApp (playground/androidApp/).

// ── Web Worker bundle (:playgroundWorker) ───────────────────────────────────
// On the web the solver runs in a Web Worker, so a long solve never blocks the page. The worker is
// its own Kotlin/JS executable (playground-worker.js); this Sync copies it into a generated resources
// dir registered for jsMain, so both the dev-server and the distribution serve it next to index.html.
// Always the production bundle: :playgroundWorker depends on :playground (for the solver logic), and
// only the production build's dead-code elimination drops the Compose UI from the worker (the
// development bundle would pull in Compose and fail on skiko.mjs).
val syncPlaygroundWorker = tasks.register<Sync>("syncPlaygroundWorker") {
    dependsOn(":playgroundWorker:jsBrowserProductionWebpack")
    from(layout.projectDirectory.dir("worker/build/kotlin-webpack/js/productionExecutable")) {
        include("playground-worker.js", "playground-worker.js.map")
    }
    into(layout.buildDirectory.dir("generated/workerResources"))
}

kotlin {
    jvmToolchain(21)

    androidLibrary {
        namespace = "org.bytefred.ksat.playground.shared"
        compileSdk = libs.versions.android.playgroundCompileSdk.get().toInt()
        minSdk = libs.versions.android.minSdk.get().toInt()
        androidResources { enable = true }   // CRITICAL: else Compose resources aren't packaged (CMP-9547)
        withHostTest {}
    }

    jvm()

    js {
        browser {
            commonWebpackConfig { outputFileName = "playground.js" }
        }
        binaries.executable()
    }

    sourceSets {
        commonMain.dependencies {
            implementation(project(":ksat"))
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
            // bundled DejaVu Sans Mono for the editor and the console (composeResources/font)
            implementation(compose.components.resources)
            implementation(libs.androidx.lifecycle.viewmodelCompose)
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.datetime)
        }
        androidMain.dependencies {
            // Platform.android.kt: the Storage Access Framework picker (rememberLauncherForActivityResult)
            implementation(libs.androidx.activity.compose)
            // the Main (Android UI thread) dispatcher the solver service delivers its events on
            implementation(libs.kotlinx.coroutines.android)
        }
        jvmMain.dependencies {
            implementation(compose.desktop.currentOs)
            // provides the Main (AWT/Swing EDT) coroutine dispatcher on desktop, which the solver
            // service delivers its events on
            implementation(libs.kotlinx.coroutines.swing)
        }
        jsMain {
            resources.srcDir(syncPlaygroundWorker)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
        }
    }
}

compose.desktop {
    application {
        mainClass = "org.bytefred.ksat.playground.MainKt"

        nativeDistributions {
            targetFormats(TargetFormat.Dmg, TargetFormat.Msi, TargetFormat.Deb)
            packageName = "ksat-playground"
            packageVersion = "1.0.0"
        }
    }
}
