package win.templeos.lualink.lua

import org.bukkit.Bukkit
import org.bukkit.scheduler.BukkitRunnable
import party.iroiro.luajava.JFunction
import party.iroiro.luajava.Lua
import party.iroiro.luajava.lua54.Lua54
import party.iroiro.luajava.luajit.LuaJit
import party.iroiro.luajava.luajit.LuaJitConsts
import party.iroiro.luajava.value.LuaValue
import win.templeos.lualink.LuaLink
import win.templeos.lualink.config.LuaRuntimes
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.util.stream.Collectors

class LuaManager(private val plugin: LuaLink, luaRuntime: LuaRuntimes) {
    // Create a new Lua state
    private val lua: Lua = try {
        when (luaRuntime) {
            LuaRuntimes.LUAJIT -> {
                plugin.logger.info("Initializing LuaJIT")
                LuaJit()
            }
            LuaRuntimes.LUA54 -> {
                plugin.logger.info("Initializing Lua 5.4")
                Lua54()
            }
            else -> {
                throw UnsupportedOperationException("Configured runtime is not LuaJIT or Lua 5.4")
            }
        }
    } catch (e: UnsatisfiedLinkError) {
        plugin.logger.warning("LuaJIT failed to load due to missing dependencies (likely libgcc). Falling back to Lua 5.4.")
        Lua54()
    } catch (e: UnsupportedOperationException) {
        Lua54()
    }
    private var scriptManagerTable: LuaValue? = null

    // Path to the Lua script in resources
    companion object {
        private const val LUA_SCRIPT_MANAGER_PATH = "/lua/scriptmanager.lua"
        private const val LUA_SCRIPT_CLASS_PATH = "/lua/script.lua"
        private const val LUA_SCRIPT_PATH = "/lua/lualink.lua"
        private const val LUA_SCRIPT_SCHEDULER_PATH = "/lua/scheduler.lua"
        private const val LUA_SCRIPT_TEAL_PATH = "/lua/teal/tl.lua"
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
        lua.openLibrary("debug")

        lua.pushJavaObject(Bukkit.getServer())
        lua.setGlobal("server")
        lua.pushJavaObject(plugin)
        lua.setGlobal("__plugin")

        lua.push(JFunction {
            // Possibly a bad solution? Possibly not?
            if (!it.isString(1)) {
                it.error("Script name is null")
                return@JFunction 0
            }
            if (!it.isString(2)) {
                it.error("Command name is null")
                return@JFunction 0
            }

            val scriptName: String? = it.toString(1)
            val commandName: String? = it.toString(2)
            if (scriptName == null) {
                it.error("Script name is null")
                return@JFunction 0
            }

            if (commandName == null) {
                it.error("Command name is null")
                return@JFunction 0
            }
            if (scriptManagerTable == null) {
                it.error("ScriptManager table is null")
                return@JFunction 0
            }
            val commands = scriptManagerTable!!.get("getVariable").call(scriptName, "script.commands")[0]
            if (commands?.size == 0) {
                it.error("Commands table is null")
                return@JFunction 0
            }

            val commandData = commands?.get(commandName)
            if (commandData == null) {
                it.error("Command data is null")
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
            val scriptFolders = scriptsDir.listFiles()?.filter { it.isDirectory && (it.resolve("main.lua").exists() || it.resolve("main.tl").exists()) }
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

        lua.push(JFunction { it ->
            // The first argument is a Lua function
            if (!it.isFunction(-2)) {
                it.error("Expected a function as the first argument")
                return@JFunction 0
            }

            // The second argument is a boolean indicating if it should be unrefed after execution
            val shouldUnref = if (it.isBoolean(-1)) it.toBoolean(-1) else false

            // Create a reference to the function at stack position 1
            it.pushValue(-2) // Duplicate the function on the stack
            val ref = it.ref() // Store in registry and get reference


            val runnable: BukkitRunnable = object : BukkitRunnable() {
                override fun run() {
                    synchronized(lua.mainState) {
                        // Get the Lua function from the registry using the reference
                        it.refGet(ref)

                        // Push this runnable as the first argument
                        it.pushJavaObject(this)

                        // Call the function with pcall (1 arg, 0 returns)
                        it.pCall(1, 0)

                        if (shouldUnref) {
                            it.unref(ref)
                        }
                    }
                }

                // Clean up the reference when the runnable is cancelled/finished
                override fun cancel() {
                    super.cancel()
                    it.unref(ref)
                    plugin.logger.info("Runnable cancelled and reference cleaned up")
                }
            }

            // Push the runnable as the return value
            it.pushJavaObject(runnable)

            // Push the reference as the second return value
            it.push(ref)

            return@JFunction 2
        })
        lua.setGlobal("__createRunnable")

        // Create a function to ref stuff. Mainly used to ensure references to tasks are kept alive
        lua.push(JFunction { it ->
            if (!it.isFunction(-1)) {
                it.error("Expected a function as the first argument")
                return@JFunction 0
            }

            it.pushValue(-1)
            val ref = it.ref()

            it.push(ref)

            return@JFunction 1
        })
        lua.setGlobal("__ref")

        // Create a function to unref stuff. Mainly used to ensure references to tasks are cleaned up
        lua.push(JFunction { it ->
            // The first argument is a reference to unref
            if (!it.isNumber(-1)) {
                it.error("Expected a number as the first argument")
                return@JFunction 0
            }

            // Unref the reference
            val ref = it.toNumber(-1)
            it.unref(ref.toInt())
            return@JFunction 0
        })
        lua.setGlobal("__unref")

       lua.push(JFunction { it ->
           // The first argument is a Java object
           if (!it.isJavaObject(-2)) {
               it.error("Expected a Java object as the first argument")
               return@JFunction 0
           }

           // The second argument is a Lua function
           if (!it.isFunction(-1)) {
               it.error("Expected a Lua function as the second argument")
               return@JFunction 0
           }

           // Get the Java object
           val javaObject: Any? = it.toJavaObject(-2)

           if (javaObject != null) {
               synchronized(javaObject) {
                   it.pushValue(-1)

                   it.pCall(0, 0)
               }
           } else {
             it.error("Java object is null")
           }

           return@JFunction 0
       })
       lua.setGlobal("__synchronized")

        // Load the script class
        val scriptCode = loadResourceAsStringByteBuffer(LUA_SCRIPT_CLASS_PATH)
        lua.load(scriptCode, "script.lua")
        lua.pCall(0, 0)

        val schedulerCode = loadResourceAsStringByteBuffer(LUA_SCRIPT_SCHEDULER_PATH)
        lua.load(schedulerCode, "scheduler.lua")
        lua.pCall(0, 0)

        val tealCode = loadResourceAsStringByteBuffer(LUA_SCRIPT_TEAL_PATH)
        lua.load(tealCode, "tl.lua")
        lua.pCall(0, 1)
        lua.setGlobal("tl")

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
    private fun createScriptFromString(scriptCode: String, scriptName: String) {
        scriptManagerTable!!.get("loadScriptFromString").call(scriptCode, scriptName)
    }

    /**
     * Closes the Lua state and cleans up resources
     */
    fun close() {
        scriptManagerTable?.get("unloadAllScripts")?.call()
        lua.close()
    }

    /**
     * Returns the selected Lua runtime as a string.
     * @return The name of the Lua runtime.
     */
    fun getLuaRuntime(): String {
        return when (lua) {
            is LuaJit -> "LuaJIT"
            is Lua54 -> "Lua 5.4"
            else -> "Unknown"
        }
    }
}