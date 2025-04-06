package win.templeos.lualink.lua

import org.bukkit.Bukkit
import party.iroiro.luajava.JFunction
import party.iroiro.luajava.Lua
import party.iroiro.luajava.luajit.LuaJit
import party.iroiro.luajava.value.LuaValue
import win.templeos.lualink.LuaLink
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.util.stream.Collectors

class LuaManager(private val plugin: LuaLink) {
    // Create a new Lua state
    private val lua: Lua = LuaJit()
    private var scriptManagerTable: LuaValue? = null

    // Path to the Lua script in resources
    companion object {
        private const val LUA_SCRIPT_MANAGER_PATH = "/lua/scriptmanager.lua"
        private const val LUA_SCRIPT_CLASS_PATH = "/lua/script.lua"
        private const val LUA_SCRIPT_PATH = "/lua/lualink.lua"
    }

    /**
     * Creates a new ScriptManager
     */
    init {
        lua.openLibrary("string")
        lua.openLibrary("table")
        lua.openLibrary("math")
        lua.openLibrary("os")
        lua.openLibrary("io")
        lua.openLibrary("package")

        lua.pushJavaObject(Bukkit.getServer())
        lua.setGlobal("server")
        lua.pushJavaObject(plugin)
        lua.setGlobal("__plugin")

        lua.push(JFunction {
            // Possibly a bad solution? Possibly not?
            if (!it.isString(1)) {
                plugin.logger.info("Script name is null")
                return@JFunction 0
            }
            if (!it.isString(2)) {
                plugin.logger.info("Command name is null")
                return@JFunction 0
            }

            val scriptName: String? = it.toString(1)
            val commandName: String? = it.toString(2)
            if (scriptName == null) {
                plugin.logger.info("Script name is null")
                return@JFunction 0
            }

            if (commandName == null) {
                plugin.logger.info("Command name is null")
                return@JFunction 0
            }
            if (scriptManagerTable == null) {
                plugin.logger.severe("ScriptManager table is null")
                return@JFunction 0
            }
            val commands = scriptManagerTable!!.get("getVariable").call(scriptName, "script.commands")[0]
            if (commands?.size == 0) {
                plugin.logger.severe("Commands table is null")
                return@JFunction 0
            }

            val commandData = commands?.get(commandName)
            if (commandData == null) {
                plugin.logger.severe("Command data is null")
                return@JFunction 0
            }
            val command = LuaCommand(commandData!!)

            plugin.server.commandMap.register("lualinkscript", command)

            return@JFunction 0
        })
        lua.setGlobal("__registerCommand")

        lua.push(JFunction {
            val scriptsDir = this.plugin.dataFolder.resolve("scripts")
            if (!scriptsDir.exists()) {
                scriptsDir.mkdirs()
            }

            // Get all subdirectories in the scripts directory that contain a main.lua file
            val scriptFolders = scriptsDir.listFiles()?.filter { it.isDirectory && it.resolve("main.lua").exists() }
            // Create a table to hold the script names
            lua.newTable()
            // Iterate through the script folders and add their names to the table
            scriptFolders?.forEachIndexed { index, folder ->
                val scriptName = folder.name
                lua.push(index + 1)  // Push the key (1-based index for Lua arrays)
                lua.push(scriptName) // Push the value
                lua.setTable(-3)     // Set table[-3][index+1] = scriptName
            }
            return@JFunction 1
        })
        lua.setGlobal("__getAvailableScripts")

        lua.push(JFunction {
            Bukkit.getServer().javaClass.getMethod("syncCommands").invoke(Bukkit.getServer())
            return@JFunction 0
        })
        lua.setGlobal("__syncCommands")

        // Load the script class
        val scriptCode = loadResourceAsStringByteBuffer(LUA_SCRIPT_CLASS_PATH)
        lua.load(scriptCode, "script.lua")
        lua.pCall(0, 0)
        // Load the script manager implementation from resources
        val scriptManagerCode = loadResourceAsStringByteBuffer(LUA_SCRIPT_MANAGER_PATH)
        lua.load(scriptManagerCode, "scriptmanager.lua")
        lua.pCall(0, 0)

        scriptManagerTable = lua.get("ScriptManager")

        // Load the LuaLink internal script
        val luaLinkCode = loadResourceAsString(LUA_SCRIPT_PATH)
        this.createScriptFromString(luaLinkCode, "LuaLink")
    }


    /**
     * Loads a resource file as a string
     */
    @Throws(IOException::class)
    private fun loadResourceAsStringByteBuffer(resourcePath: String): ByteBuffer {
        javaClass.getResourceAsStream(resourcePath).use { inputStream ->
            if (inputStream == null) {
                throw IOException("Resource not found: $resourcePath")
            }
            val reader = BufferedReader(InputStreamReader(inputStream, StandardCharsets.UTF_8))
            val content = reader.lines().collect(Collectors.joining("\n"))
            val byteArray = content.toByteArray(StandardCharsets.UTF_8)
            val buffer = ByteBuffer.allocateDirect(byteArray.size)
            buffer.put(byteArray)
            buffer.flip()
            return buffer
        }
    }

    @Throws(IOException::class)
    private fun loadResourceAsString(resourcePath: String): String {
        javaClass.getResourceAsStream(resourcePath).use { inputStream ->
            if (inputStream == null) {
                throw IOException("Resource not found: $resourcePath")
            }
            val reader = BufferedReader(InputStreamReader(inputStream, StandardCharsets.UTF_8))
            return reader.lines().collect(Collectors.joining("\n"))
        }
    }

    /**
     * Loads all available scripts from the scripts directory
     */
    fun loadAllScripts() {
        scriptManagerTable?.get("loadAllScripts")?.call()
    }

    /**
     * Creates a new script from a string
     * @param scriptCode The Lua code
     * @param scriptName Unique name for the script
     * @return A Script object representing the loaded script
     */
    private fun createScriptFromString(scriptCode: String, scriptName: String){
        scriptManagerTable!!.get("loadScriptFromString").call(scriptCode, scriptName)
    }

    /**
     * Closes the Lua state and cleans up resources
     */
    fun close() {
        scriptManagerTable?.get("unloadAll")?.call()
        lua.close()
    }
}