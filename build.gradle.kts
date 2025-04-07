import com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar

plugins {
    kotlin("jvm") version "2.1.20"
    id("net.minecrell.plugin-yml.paper") version "0.6.0"
    id("xyz.jpenilla.run-paper") version "2.3.1"
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

group = "win.templeos.lualink"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
    maven("https://repo.purpurmc.org/snapshots")
}

val luaJavaVersion:String by project

dependencies {
    testImplementation(kotlin("test"))
    library(kotlin("stdlib"))
    api(kotlin("stdlib"))
    compileOnly("org.purpurmc.purpur:purpur-api:1.21-R0.1-SNAPSHOT")
    implementation("party.iroiro.luajava:luajava:$luaJavaVersion")
    implementation("party.iroiro.luajava:luajit:$luaJavaVersion")
    runtimeOnly("party.iroiro.luajava:luajit-platform:$luaJavaVersion:natives-desktop")
}

tasks.withType<ShadowJar> {
    dependencies {

    }
}

paper {
    main = "win.templeos.lualink.LuaLink"
    apiVersion = "1.20"
    generateLibrariesJson = true
    authors = listOf("Saturn745")
    loader = "win.templeos.lualink.PluginLibrariesLoader"
}

tasks {
    runServer {
        // Configure the Minecraft version for our task.
        // This is the only required configuration besides applying the plugin.
        // Your plugin's jar (or shadowJar if present) will be used automatically.
        minecraftVersion("1.21.4")
    }
}

tasks.test {
    useJUnitPlatform()
}