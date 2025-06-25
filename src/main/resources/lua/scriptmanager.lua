local Logger = java.import("java.util.logging.Logger")

---@class ScriptManager
---@field scripts table<string, boolean> Table of loaded scripts
---@field environments table<string, table> Table of script environments
ScriptManager = {}


--- Helper function to make a table or function read-only
---@param obj table|function The table or function to make read-only
---@param visited table Table to track already processed tables (prevents circular references)
---@return table|function The read-only table or function
local function makeReadOnly(obj, visited)
    if type(obj) == "function" then
        local proxy = {}
        local mt = {
            __index = obj, -- Allow calling the function
            __newindex = function(_, key, value)
                error("Attempt to modify a read-only function", 2)
            end,
            __call = function(_, ...)
                return obj(...)
            end,
            __metatable = "The metatable is protected" -- Prevent changing the metatable
        }
        return setmetatable(proxy, mt)
    elseif type(obj) == "table" then
        visited = visited or {}

        -- Check if we've already processed this table
        if visited[obj] then
            return visited[obj]
        end

        -- Create a proxy table
        local proxy = {}
        -- Mark this table as being processed
        visited[obj] = proxy

        -- Process all nested tables
        for k, v in pairs(obj) do
            if type(v) == "table" or type(v) == "function" then
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
    else
        error("Expected a table or function")
    end
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

local function load_teal_file_with_config(filename, config, sandbox_env)
    -- Read the file
    local file = io.open(filename, "rb")
    if not file then
        return nil, "Could not open file: " .. filename
    end

    local content = file:read("*a")
    file:close()

    -- Create Teal environment with your config
    local teal_env = tl.new_env({
        defaults = {
            feat_lax = config.lax and "on" or "off",
            feat_arity = config.arity and "on" or "off",
            gen_compat = config.gen_compat or "optional",
            gen_target = config.gen_target or "5.1"
        }
    })

    -- Type check and compile
    local result = tl.check_string(content, teal_env, filename)

    -- Check for errors
    if #result.syntax_errors > 0 or #result.type_errors > 0 then
        local errors = {}
        for _, err in ipairs(result.syntax_errors) do
            table.insert(errors, err.filename .. ":" .. err.y .. ":" .. err.x .. ": " .. err.msg)
        end
        for _, err in ipairs(result.type_errors) do
            table.insert(errors, err.filename .. ":" .. err.y .. ":" .. err.x .. ": " .. err.msg)
        end
        return nil, table.concat(errors, "\n")
    end

    -- Generate Lua code
    local lua_code, gen_err = tl.generate(result.ast, teal_env.defaults.gen_target)
    if not lua_code then
        return nil, gen_err
    end

    -- Load with your custom sandbox
    local chunk, load_err = load(lua_code, "@" .. filename, "t", sandbox_env)
    if not chunk then
        return nil, load_err
    end

    return chunk
end



--- Load and execute the init.lua file (optional)
---@param scriptName string Name of the script
---@param initPath string Path to the init.lua file
---@return table|nil metadata Metadata returned by init.lua or nil if the file doesn't exist
local function loadInitFile(scriptName, initPath)
    local file = io.open(initPath, "r")
    if not file then
        return nil -- init.lua is optional
    end
    file:close()

    local initEnv = {}
    setmetatable(initEnv, { __index = function() return nil end }) -- Empty environment
    local initFunc, initErr = loadfile(initPath, "t", initEnv)
    if not initFunc then
        error("Failed to load init.lua for script " .. scriptName .. ": " .. tostring(initErr))
    end

    local success, metadata = pcall(initFunc)
    if not success then
        error("Error running init.lua for script " .. scriptName .. ": " .. tostring(metadata))
    end

    if type(metadata) ~= "table" then
        error("init.lua for script " .. scriptName .. " must return a table")
    end

    return metadata
end

--- Check if all dependencies are loaded
---@param scriptName string Name of the script
---@param dependencies table List of dependencies
local function checkDependencies(scriptName, dependencies)
    for _, dependency in ipairs(dependencies) do
        if server:getPluginManager():getPlugin(dependency) == nil then
            error("Dependency " .. dependency .. " for script " .. scriptName .. " is missing")
        end
    end
end

--- Load and execute the main.lua or main.tl file
---@param scriptName string Name of the script
---@param mainPath string Path to the main.lua or main.tl file
local function loadMainFile(scriptName, mainPath)
    -- Make sure the file exists before loading
    local file = io.open(mainPath, "r")
    if not file then
        error("main file for script " .. scriptName .. " does not exist")
    end
    file:close()

    local f, err

    -- Check if it's a Teal file
    if mainPath:match("%.tl$") then
        -- Use custom Teal loader
        local config = {
            lax = false,
            arity = true,
            gen_compat = "optional",
            gen_target = "5.3"
        }

        f, err = load_teal_file_with_config(mainPath, config, ScriptManager.createSandbox(scriptName))
    else
        -- Use normal Lua loader
        f, err = loadfile(mainPath, "t", ScriptManager.createSandbox(scriptName))
    end

    if not f then
        local fileType = mainPath:match("%.tl$") and "Teal" or "Lua"
        error("Failed to load " .. fileType .. " file for script " .. scriptName .. ": " .. tostring(err))
    end

    local success, result = pcall(f)
    if not success then
        error("Error running main file for script " .. scriptName .. ": " .. tostring(result))
    end
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
    java = makeReadOnly(copyTable(java)),
    -- Expose standard Lua functions
    pcall = makeReadOnly(pcall),
    assert = makeReadOnly(assert),
    error = makeReadOnly(error),
    type = makeReadOnly(type),
    pairs = makeReadOnly(pairs),
    ipairs = makeReadOnly(ipairs),
    tostring = makeReadOnly(tostring),
    tonumber = makeReadOnly(tonumber),
    select = makeReadOnly(select),
    next = makeReadOnly(next),
    getmetatable = makeReadOnly(getmetatable),
    setmetatable = makeReadOnly(setmetatable),
    rawget = makeReadOnly(rawget),
    rawset = makeReadOnly(rawset),

    -- LuaLink globals
    server = server,
    import = java.import, -- Simple alias for java.import
    synchronized = __synchronized
}

local globalModuleCache = {} -- Global cache for modules in the libs folder

local function getCustomRequire(scriptName)
    return function(moduleName)
        if ScriptManager.environments[scriptName]["_moduleCache"][moduleName] then
            return ScriptManager.environments[scriptName]["_moduleCache"][moduleName]
        end

        -- Define search paths
        local scriptFolder = __plugin:getDataFolder():getAbsolutePath() .. "/scripts/" .. scriptName
        local libsFolder = __plugin:getDataFolder():getAbsolutePath() .. "/libs"
        local searchPaths = {
            { path = scriptFolder .. "/" .. moduleName:gsub("%.", "/") .. ".lua", cache = ScriptManager.environments[scriptName]["_moduleCache"] },
            { path = libsFolder .. "/" .. moduleName:gsub("%.", "/") .. "/main.lua", cache = globalModuleCache },
            { path = libsFolder .. "/" .. moduleName:gsub("%.", "/") .. ".lua", cache = globalModuleCache }
        }

        -- Attempt to load the module from the search paths
        for _, entry in ipairs(searchPaths) do
            local file = io.open(entry.path, "r")
            if file then
                file:close()
                local chunk, loadErr = loadfile(entry.path, "t", ScriptManager.environments[scriptName]) -- Reuse the script's environment
                if chunk then
                    local success, result = pcall(chunk)
                    if success then
                        entry.cache[moduleName] = result
                        return result
                    else
                        __plugin:getLogger():warning("Error running module '" .. moduleName .. "' from path '" .. entry.path .. "': " .. tostring(result))
                    end
                else
                    __plugin:getLogger():warning("Failed to load module '" .. moduleName .. "' from path '" .. entry.path .. "': " .. tostring(loadErr))
                end
            end
        end

        -- If no valid module is found, raise an error
        error("Module '" .. moduleName .. "' not found in any search paths")
    end
end


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

            -- Then check shared environment
            return sharedEnv[k]
        end,

        -- Prevent changing the metatable
        __metatable = "The metatable is protected"
    }

    setmetatable(sandbox, mt)

    local logger = Logger:getLogger("LuaLink/" .. scriptName)

    -- Add script-specific fields
    sandbox._NAME = scriptName
    sandbox._SCRIPT = scriptName
    sandbox.print = function(...)
        local args = { ... }
        local message = table.concat(args, " ")

        logger:info(message)
    end
    sandbox._moduleCache = {} -- Cache for loaded modules
    sandbox.require = getCustomRequire(scriptName)

    local script = Script.new(scriptName, server, __plugin, logger, debug)

    sandbox.script = script

    local scheduler = Scheduler.new(__plugin, script)
    sandbox.scheduler = scheduler

    -- Store the environment
    ScriptManager.environments[scriptName] = sandbox

    return sandbox
end

--- Load a script from a file
---@param scriptName string Name for the script
---@return boolean success Whether the script was loaded successfully
function ScriptManager.loadScript(scriptName)
    local scriptFolder = __plugin:getDataFolder():getAbsolutePath() .. "/scripts/" .. scriptName
    local initPath = scriptFolder .. "/init.lua"
    local mainPathLua = scriptFolder .. "/main.lua"
    local mainPathTeal = scriptFolder .. "/main.tl"
    -- Load init.lua and get metadata
    local metadata = loadInitFile(scriptName, initPath)

    -- Check dependencies
    if metadata and metadata.dependencies then
        checkDependencies(scriptName, metadata.dependencies)
    end

    -- Check if the main.tl file exists and load it if it does
    local mainPath = nil
    local file = io.open(mainPathTeal, "r")
    if file then
        file:close()
        mainPath = mainPathTeal
    else
        -- If main.tl doesn't exist, check for main.lua
        file = io.open(mainPathLua, "r")
        if file then
            file:close()
            mainPath = mainPathLua
        else
            error("No main file found for script '" .. scriptName .. "'. Expected main.lua or main.tl.")
        end
    end

    local success, err = pcall(function()
        loadMainFile(scriptName, mainPath)
    end)

    if not success then
        -- Clean up any partial registrations if script fails to load
        if ScriptManager.environments[scriptName] and ScriptManager.environments[scriptName].script then
            pcall(function()
                ScriptManager.environments[scriptName].script:_callUnloadHandlers()
            end)
        end
        ScriptManager.scripts[scriptName] = nil
        ScriptManager.environments[scriptName] = nil
        error("Failed to load script '" .. scriptName .. "': " .. tostring(err or "Unknown error"))
    end

    ScriptManager.scripts[scriptName] = true
    local script = ScriptManager.environments[scriptName].script
    script.metadata = metadata -- Let scripts access their metadata
    script:_callLoadHandlers()

    return true
end

--- Load a script from a string
--- Only used to load the internal LuaLink script
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


-- Return the ScriptManager table
return ScriptManager
