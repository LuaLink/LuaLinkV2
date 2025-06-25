import java.net.URI

val tealVersion: String by project
val tealCacheDir = file("${gradle.gradleUserHomeDir}/caches/teal")
val tealCachedFile = file("$tealCacheDir/tl-$tealVersion.lua")
val tealResourceFile = file("src/main/resources/lua/teal/tl.lua")


val downloadTeal by tasks.registering {
    description = "Downloads and caches Teal compiler v$tealVersion"

    inputs.property("tealVersion", tealVersion)
    outputs.file(tealResourceFile)

    doLast {
        if (!tealCachedFile.exists()) {
            println("Downloading Teal v$tealVersion...")
            tealCacheDir.mkdirs()

            val url = "https://raw.githubusercontent.com/teal-language/tl/refs/tags/v${tealVersion}/tl.lua"
            val connection = URI(url).toURL().openConnection().apply {
                connectTimeout = 10000
                readTimeout = 30000
            }

            tealCachedFile.outputStream().use { output ->
                connection.getInputStream().use { input ->
                    input.copyTo(output)
                }
            }

            println("Cached Teal v$tealVersion")
        } else {
            println("Using cached Teal v$tealVersion")
        }

        tealResourceFile.parentFile.mkdirs()
        tealCachedFile.copyTo(tealResourceFile, overwrite = true)
    }
}

tasks.named("processResources") {
    dependsOn(downloadTeal)
}

val cleanTealCache by tasks.registering(Delete::class) {
    description = "Clears Teal cache"
    delete(tealCacheDir)
}