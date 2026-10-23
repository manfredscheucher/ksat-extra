import org.jetbrains.kotlin.gradle.ExperimentalWasmDsl

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidKmpLibrary)
}

// One shared SAT demo (org.bytefred.ksat.demo.XorDemo) compiled to EVERY Kotlin Multiplatform
// target, to show that the pure-Kotlin ksat solver runs everywhere. The demo logic lives in
// commonMain; each target has a thin entry point (console main / browser DOM / iOS framework fn).
// Consumes :ksat from the main repo (see settings.gradle.kts). Android: AGP 9 no longer allows
// com.android.application in a KMP module, so this module is an Android LIBRARY target and the
// app (MainActivity + manifest) lives in the separate :androidApp module (demo/androidApp/).
kotlin {
    jvm {
        binaries { executable { mainClass.set("org.bytefred.ksat.demo.MainKt") } }
    }
    androidLibrary {
        namespace = "org.bytefred.ksat.demo.shared"
        compileSdk = libs.versions.android.compileSdk.get().toInt()
        minSdk = libs.versions.android.minSdk.get().toInt()
    }

    js { browser(); binaries.executable() }

    @OptIn(ExperimentalWasmDsl::class)
    wasmJs { browser(); binaries.executable() }

    // Native console executables. Targets match what :ksat provides.
    linuxX64 { binaries { executable { entryPoint = "org.bytefred.ksat.demo.main" } } }
    mingwX64 { binaries { executable { entryPoint = "org.bytefred.ksat.demo.main" } } }
    macosArm64 { binaries { executable { entryPoint = "org.bytefred.ksat.demo.main" } } }
    macosX64 { binaries { executable { entryPoint = "org.bytefred.ksat.demo.main" } } }

    // iOS: static framework — call iosDemoReport() from Swift (Text(DemoKt.iosDemoReport())).
    // isStatic + the embedAndSignAppleFrameworkForXcode task is what the iosApp/ Xcode project
    // uses to pull this in (see scripts/runIosSimulator.sh).
    iosArm64 { binaries { framework { baseName = "Demo"; isStatic = true } } }
    iosSimulatorArm64 { binaries { framework { baseName = "Demo"; isStatic = true } } }
    iosX64 { binaries { framework { baseName = "Demo"; isStatic = true } } }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(project(":ksat"))
            }
        }
        val commonTest by getting {
            dependencies {
                implementation(libs.kotlin.test)
            }
        }
        // nativeMain (console main() for linux/mingw, in src/nativeMain) and iosMain (the
        // framework fn, in src/iosMain) are created by the default KMP hierarchy template —
        // no manual dependsOn wiring needed.
    }
}
