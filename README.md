# LuaLink Plugin
<a href=https://modrinth.com/plugin/lualink><img alt="modrinth" height="54" src="https://cdn.jsdelivr.net/npm/@intergrav/devins-badges@3/assets/cozy/available/modrinth_vector.svg"></a>
<a href=https://hangar.papermc.io/lualink/LuaLink><img alt="hangar" height="54" src="https://cdn.jsdelivr.net/npm/@intergrav/devins-badges@3/assets/cozy/available/hangar_vector.svg"></a>
<a href=https://discord.gg/xYcjBKqkDz><img alt="discord-plural" height="54" src="https://cdn.jsdelivr.net/npm/@intergrav/devins-badges@3/assets/cozy/social/discord-plural_vector.svg"></a>

LuaLink is a plugin that provides a Lua scripting runtime for Paper-based Minecraft servers. It is designed for small and simple tasks and serves as an alternative to Skript however can do just about anything a typical Java plugin can do.

The scripting runtime is based on [LuaJava](https://github.com/gudzpoz/luajava) with LuaJIT.

## Features

- **High Performance**  
  LuaLink leverages LuaJava and LuaJIT, which are implemented primarily in C, ensuring fast and efficient execution.  

- **User-Friendly API**  
  Simplifies scripting with an intuitive and easy-to-use API.  

- **Simple Command Registration**  
  Register commands effortlessly with a single function. [Learn more](https://lualink.github.io/docs/getting-started/#commands).  

- **Event Listening**  
  Listen to Bukkit, Spigot, Paper, or even custom plugin events. [Example here](https://lualink.github.io/docs/getting-started/#events).  

- **Script Organization**  
  Split scripts into multiple files. Each script requires a ```main.lua``` entry point but can load additional files using Lua’s ```require``` function.  

- **Java Library Integration**  
  Extend LuaLink’s capabilities by using any Java library—whether it’s for a Discord bot, HTTP server, or anything else you can imagine.  


## Requirements

To use the LuaLink plugin, you need the following:

- A [Paper](https://papermc.io/) based Minecraft server.
- A basic understanding of Lua scripting.

<br />

## Documentation
Documentation and examples are available [here](https://lualink.github.io/docs).
