/*
 * Temporary workaround for [KT-80582](https://youtrack.jetbrains.com/issue/KT-80582)
 *
 * This file should be safe to be removed once the ticket is closed and the project is updated to Kotlin version which solves that issue.
 */
config.watchOptions = config.watchOptions || {
    ignored: ["**/*.kt", "**/node_modules"]
}

if (config.devServer) {
    config.devServer.static = config.devServer.static.map(file => {
        if (typeof file === "string") {
            return {
                directory: file,
                watch: false,
            }
        } else {
            return file
        }
    })
}
// scripts/runPlaygroundWeb.sh opens Chrome itself. Stop webpack from auto-opening a browser.
// Fixed dev-server port per app (see ~/github/.dev-ports.md) so apps started at the same time
// don't collide. ksat-extra playground = 8609 (mirrored in the PORT= line of the run script).
if (config.devServer) {
    config.devServer.open = false
    config.devServer.port = 8609
}
