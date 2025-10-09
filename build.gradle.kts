import io.papermc.hangarpublishplugin.model.Platforms

plugins {
    kotlin("jvm") version "2.2.20"
    id("de.eldoria.plugin-yml.paper") version "0.8.0"
    id("xyz.jpenilla.run-paper") version "2.3.1"
    id("com.gradleup.shadow") version "9.2.2"
    id("com.modrinth.minotaur") version "2.8.10"
    id("io.papermc.hangar-publish-plugin") version "0.1.3"
}

val buildNum = System.getenv("GITHUB_RUN_NUMBER") ?: "SNAPSHOT"

group = "win.templeos.lualink"
version = "1.21.8-$buildNum"

repositories {
    mavenLocal()
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
    maven {
        url = uri("https://maven.pkg.github.com/lualink/luajava")
        name = "LuaJava"
        credentials {
            username = findProperty("gpr.actor") as String? ?: System.getenv("GITHUB_ACTOR")
            password = findProperty("gpr.token") as String? ?: System.getenv("GITHUB_TOKEN")
        }
    }
}

val luaJavaVersion:String by project

dependencies {
    // Kotlin (downloaded and loaded at runtime)
    paperLibrary(kotlin("stdlib"))
    // Paper API
    compileOnly("io.papermc.paper:paper-api:1.21.8-R0.1-SNAPSHOT")
    // LuaJava (cannot be easily relocated or downloaded at runtime)
    implementation("party.iroiro.luajava:luajava:$luaJavaVersion") // Use our fork of the LuaJava library
    implementation("party.iroiro.luajava:luajit:$luaJavaVersion")
    implementation("party.iroiro.luajava:lua54:$luaJavaVersion")
    implementation("org.bstats:bstats-bukkit:3.1.0")
    // LuaJava natives (cannot be easily relocated or downloaded at runtime)
    runtimeOnly("party.iroiro.luajava:luajit-platform:$luaJavaVersion:natives-desktop")
    runtimeOnly("party.iroiro.luajava:lua54-platform:$luaJavaVersion:natives-desktop")
}

paper {
    main = "win.templeos.lualink.LuaLink"
    apiVersion = "1.20"
    generateLibrariesJson = true
    authors = listOf("Saturn745", "Grabsky")
    website = "https://lualink.github.io/docs/"
    description = "A Lua plugin for Paper servers, allowing you to run Lua scripts and commands in Minecraft."
    loader = "win.templeos.lualink.PluginLibrariesLoader"
    // This allows the plugin to access external plugins' APIs without depending on them.
    // This may cause conflicts if different versions of the same dependency are loaded by different plugins.
    hasOpenClassloader = true
}

modrinth {
    token.set(System.getenv("MODRINTH_TOKEN"))
    projectId.set("lualink")
    versionNumber.set(version.toString())
    versionType.set("release")
    uploadFile.set(tasks.shadowJar.get())
    gameVersions.addAll("1.21.4", "1.21.5", "1.21.6", "1.21.7", "1.21.8")
    loaders.addAll("paper", "purpur")
    changelog.set(System.getenv("GIT_COMMIT_MESSAGE"))
}

hangarPublish {
    publications.register("plugin") {
        version.set(project.version as String)
        id.set("LuaLink")
        channel.set("Release")
        changelog.set(System.getenv("GIT_COMMIT_MESSAGE"))

        apiKey.set(System.getenv("HANGAR_API_KEY"))

        platforms {
            register(Platforms.PAPER) {
                jar.set(tasks.shadowJar.flatMap { it.archiveFile })
                platformVersions.set(listOf("1.21.4", "1.21.5", "1.21.6", "1.21.7", "1.21.8"))
            }
        }
    }
}

tasks {
    runServer {
        minecraftVersion("1.21.8")
    }
    shadowJar {
        archiveBaseName.set("LuaLink")
        archiveClassifier.set("")
        archiveVersion.set(version.toString())
        relocate("org.bstats", "win.templeos.lualink.bstats")
    }
}

// Using JetBrains Runtime for 'runServer' tasks to enable enhanced hot-swap capabilities.
tasks.withType(xyz.jpenilla.runtask.task.AbstractRun::class) {
    javaLauncher = javaToolchains.launcherFor {
        vendor = JvmVendorSpec.JETBRAINS
        languageVersion = JavaLanguageVersion.of(21)
    }
    jvmArgs(
        // Enables enhanced hot-swap capabilities; slows down the internal server so should be off by default
        // "-XX:+AllowEnhancedClassRedefinition",
        // Required for some classes to be accessible from Lua
        "--add-opens=java.base/java.util=ALL-UNNAMED",
        // Enables text colors in IntelliJ IDEA debugging console
        "-Dnet.kyori.ansi.colorLevel=truecolor",
        // Automatically agrees to Mojang's EULA when runServer is ran for the first time
        "-Dcom.mojang.eula.agree=true"
    )
}
