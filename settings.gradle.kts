rootProject.name = "ksat-extra"

pluginManagement {
    repositories {
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
    }
}

// The demo consumes the ksat solver from the MAIN repo via relative paths. This only works
// when ksat-extra is checked out as the ksat-extra/ submodule INSIDE sat-solvers-kotlin
// (the normal case). A standalone clone of ksat-extra on its own cannot resolve these.
val main = file("..")
require(file("$main/ksat/build.gradle.kts").exists()) {
    "ksat solver not found at ${main.absolutePath}. The demo needs ksat-extra to be checked " +
        "out inside the sat-solvers-kotlin main repo (git submodule update --init --checkout ksat-extra)."
}

include(":ksat-common")
project(":ksat-common").projectDir = file("../ksat-common")
include(":microsat")
project(":microsat").projectDir = file("../solver/microsat")
include(":minisat")
project(":minisat").projectDir = file("../solver/minisat")
include(":cadical")
project(":cadical").projectDir = file("../solver/cadical")
include(":kissat")
project(":kissat").projectDir = file("../solver/kissat")
include(":ksat")
project(":ksat").projectDir = file("../ksat")

include(":demo")
