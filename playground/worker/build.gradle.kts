plugins {
    alias(libs.plugins.kotlinMultiplatform)
}

// The playground's Web Worker bundle: receives one encoded SolveRequest, runs PlaygroundSolver.run
// and posts every SolveEvent back (protocol in :playground's SolveProtocol.kt). :playground copies
// the webpack output (playground-worker.js) next to its index.html (syncPlaygroundWorker).
kotlin {
    js {
        browser {
            commonWebpackConfig { outputFileName = "playground-worker.js" }
        }
        binaries.executable()
    }

    sourceSets {
        jsMain.dependencies {
            implementation(project(":playground"))
        }
    }
}
