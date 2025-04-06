local ComponentLogger = java.import("net.kyori.adventure.text.logger.slf4j.ComponentLogger")
local Logger = java.import("java.util.logging.Logger")
local MiniMessage = java.import("net.kyori.adventure.text.minimessage.MiniMessage")

local ScriptManagerLogger = Logger:getLogger("LuaLink/ScriptManager")

local function print(...)
    local args = {...}
    local message = table.concat(args, " ")
    ScriptManagerLogger:info(message)
end

---@class ScriptManager
---@field scripts table<string, boolean> Table of loaded scripts
---@field environments table<string, table> Table of script environments
---@field sharedObjects table<string, any> Table of shared objects available to all scripts
ScriptManager = {}


--- Helper function to make a table read-only (including nested tables)
---@param t table The table to make read-only
---@param visited table Table to track already processed tables (prevents circular references)
---@return table The read-only table
local function makeReadOnly(t, visited)
    if type(t) ~= "table" then return t end

    visited = visited or {}

    -- Check if we've already processed this table
    if visited[t] then
        return visited[t]
    end

    -- Create a proxy table
    local proxy = {}
    -- Mark this table as being processed
    visited[t] = proxy

    -- Process all nested tables
    for k, v in pairs(t) do
        if type(v) == "table" then
            proxy[k] = makeReadOnly(v, visited)
        else
            proxy[k] = v
        end
    end

    -- Create a protected proxy for this table
    local mt = {
        __index = proxy,

        __newindex = function(_, k, v)
            error("Attempt to modify a read-only table", 2)
        end,

        -- Prevent changing the metatable
        __metatable = "The metatable is protected",

        -- Forward pairs/ipairs to the original table
        __pairs = function() return pairs(proxy) end,
        __ipairs = function() return ipairs(proxy) end
    }

    return setmetatable({}, mt)
end

--- Helper function to deep copy tables
---@param t table The table to copy
---@param visited table Table to track already processed tables (prevents circular references)
---@return table A deep copy of the table
local function copyTable(t, visited)
    if type(t) ~= "table" then return t end

    -- Initialize visited table on first call
    visited = visited or {}

    -- Check if we've already processed this table
    if visited[t] then
        return visited[t]
    end

    local result = {}
    -- Mark this table as being processed
    visited[t] = result

    for k, v in pairs(t) do
        result[k] = copyTable(v, visited)
    end

    return result
end

--- Create a shared environment for all scripts
---@class SharedEnvironment
---@field string table Read-only string library
---@field table table Read-only table library
---@field math table Read-only math library
---@field print function Print function
---@field API table API namespace
local sharedEnv = {
    -- Read-only standard libraries
    string = makeReadOnly(copyTable(string)),
    table = makeReadOnly(copyTable(table)),
    math = makeReadOnly(copyTable(math)),
    os = makeReadOnly(copyTable(os)),
    io = makeReadOnly(copyTable(io)),
    package = makeReadOnly(copyTable(package)),
    java = makeReadOnly(copyTable(java)),
    -- Expose standard Lua functions
    pcall = pcall,
    assert = assert,
    error = error,
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    tostring = tostring,
    tonumber = tonumber,
    select = select,
    unpack = unpack,
    next = next,
    

    -- LuaLink internal
    __registerCommand = __registerCommand,
    server = server,
}

--- Create a sandbox environment for a script
---@param scriptName string The name of the script
---@return table The sandbox environment
function ScriptManager.createSandbox(scriptName)
    ---@class ScriptEnvironment
    ---@field _NAME string The name of the script
    ---@field _SCRIPT string The name of the script
    ---@field registerCleanupHandler fun(handler: function) Register a function to be called when the script is unloaded
    local sandbox = {}

    -- Set up metatable for the sandbox
    local mt = {
        __index = function(t, k)
            -- Check script's own globals first
            local v = rawget(t, k)
            if v ~= nil then return v end

            -- Then check shared objects
            v = ScriptManager.sharedObjects[k]
            if v ~= nil then return v end

            -- Then check shared environment
            return sharedEnv[k]
        end,

        -- Prevent changing the metatable
        __metatable = "The metatable is protected"
    }

    setmetatable(sandbox, mt)

    -- Add script-specific fields
    sandbox._NAME = scriptName
    sandbox._SCRIPT = scriptName
    sandbox.logger = Logger:getLogger("LuaLink/"..scriptName)
    sandbox.print = function(...)
        local args = {...}
        local message = table.concat(args, " ")

        sandbox.logger:info(message)
    end

    local script = Script.new(scriptName, server, __plugin, sandbox.logger)

    sandbox.script = script

    -- Store the environment
    ScriptManager.environments[scriptName] = sandbox

    return sandbox
end

--- Load a script from a file
---@param scriptPath string Path to the script file
---@param scriptName string Name for the script
---@return boolean success Whether the script was loaded successfully
function ScriptManager.loadScript(scriptName)
    local f, err = loadfile(__plugin:getDataFolder():getAbsolutePath() .. "/scripts/" .. scriptName .. "/main.lua", "t", ScriptManager.createSandbox(scriptName))
    if not f then
        error("Failed to load script " .. scriptName .. ": " .. tostring(err))
    end

    -- Run the script and store its environment
    local success, result = pcall(f)
    if not success then
        -- Clean up the environment if script fails
        ScriptManager.environments[scriptName] = nil
        error("Error running script " .. scriptName .. ": " .. tostring(result))
    end

    -- Store the script's environment
    ScriptManager.scripts[scriptName] = true
    local script = ScriptManager.environments[scriptName].script
    script:_callLoadHandlers()

    return true
end

--- Load a script from a string
--- Unused at the moment but gonna keep it incase we add a /lualink run command
---@param scriptCode string The Lua code
---@param scriptName string Name for the script
---@return boolean success Whether the script was loaded successfully
function ScriptManager.loadScriptFromString(scriptCode, scriptName)
    local sandbox = ScriptManager.createSandbox(scriptName)
    local f, err = load(scriptCode, scriptName, "t", sandbox)
    if not f then
        error("Failed to load script " .. scriptName .. ": " .. tostring(err))
    end

    -- Run the script and store its environment
    local success, result = pcall(f)
    if not success then
        -- Clean up the environment if script fails
        ScriptManager.environments[scriptName] = nil
        error("Error running script " .. scriptName .. ": " .. tostring(result))
    end

    -- Store the script's environment
    ScriptManager.scripts[scriptName] = true
    local script = ScriptManager.environments[scriptName].script
    -- Hack to let the internal script manage scripts
    if scriptName == "LuaLink" then
        ScriptManager.environments[scriptName].ScriptManager = ScriptManager
        ScriptManager.environments[scriptName].__getAvailableScripts = __getAvailableScripts
    end
    script:_callLoadHandlers()

    return true
end

--- Unload a script
---@param scriptName string The name of the script to unload
---@return boolean success Whether the script was unloaded successfully
function ScriptManager.unloadScript(scriptName)
    if not ScriptManager.scripts[scriptName] then
        return false -- Script not found
    end

    ScriptManager.environments[scriptName].script:_callUnloadHandlers()


    -- Remove script from tables
    ScriptManager.scripts[scriptName] = nil
    ScriptManager.environments[scriptName] = nil

    -- Force garbage collection to clean up resources
    collectgarbage("collect")

    return true
end

--- Unload all scripts
function ScriptManager.unloadAllScripts()
    for scriptName, _ in pairs(ScriptManager.scripts) do
        local success, err = pcall(ScriptManager.unloadScript, scriptName)
        if not success then
            __plugin:getLogger():warning("Failed to unload script " .. scriptName .. ": " .. tostring(err))
        else
            __plugin:getLogger():info("Unloaded script: " .. scriptName)
        end
    end
end

--- Check if a script is loaded
---@param scriptName string The name of the script to check
---@return boolean isLoaded Whether the script is loaded
function ScriptManager.isScriptLoaded(scriptName)
    return ScriptManager.scripts[scriptName] ~= nil
end

--- Get a list of all loaded scripts
---@return string[] scripts List of script names
function ScriptManager.getLoadedScripts()
    local result = {}
    for name, _ in pairs(ScriptManager.scripts) do
        table.insert(result, name)
    end
    return result
end

--- Register a shared object (available to all scripts)
---@param name string The name to expose the object as
---@param object any The object to share
function ScriptManager.registerSharedObject(name, object)
    ScriptManager.sharedObjects[name] = object
end

--- Get a variable from a script's environment, supporting class instances and nested tables
--- Used for getting variables from scripts from the Java side
---@param scriptName string The name of the script
---@param variablePath string The path to the variable (e.g. "instance.field" or "table.subtable.value")
---@return any value The value of the variable or nil if not found
function ScriptManager.getVariable(scriptName, variablePath)

    if not ScriptManager.scripts[scriptName] then
        return nil
    end

    local scriptEnv = ScriptManager.environments[scriptName]

    -- Handle simple variable case
    if not variablePath:find("%.") then
        local value = scriptEnv[variablePath]
        return value
    end

    -- Handle nested tables and class instances using dot notation
    local segments = {}
    for segment in variablePath:gmatch("([^%.]+)") do
        table.insert(segments, segment)
    end


    -- Start with the first segment (the global variable or class instance)
    local currentValue = scriptEnv[segments[1]]

    -- Traverse through the remaining segments
    for i = 2, #segments do
        if currentValue == nil then
            return nil
        end

        if type(currentValue) ~= "table" then
            return nil
        end

        currentValue = currentValue[segments[i]]
    end

    return currentValue
end

function ScriptManager.loadAllScripts()
    local availableScripts = __getAvailableScripts()

    __plugin:getLogger():info("Discovered " .. #availableScripts .. " scripts")
    for _, scriptName in ipairs(availableScripts) do
        local success, err = pcall(ScriptManager.loadScript, scriptName)
        if not success then
            __plugin:getLogger():warning("Failed to load script " .. scriptName .. ": " .. tostring(err))
        else
            __plugin:getLogger():info("Loaded script: " .. scriptName)
        end
    end
end

-- Initialize the ScriptManager tables
ScriptManager.scripts = {}
ScriptManager.environments = {}
ScriptManager.cleanupHandlers = {}
ScriptManager.sharedObjects = {}


-- Return the ScriptManager table
return ScriptManager