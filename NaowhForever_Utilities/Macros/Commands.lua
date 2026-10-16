-- Commands.lua: the slash commands the game knows, whose they are, and which run a script (ns.Macros.Commands).
local ns = _G.NaowhForever

local M = ns.Macros
local SCRIPT = M.C.SCRIPT_COMMANDS

local known
local own, addon = {}, {}

local function Learn(key, value)
    local command = value:lower()
    known[command] = true
    if key:find("^SLASH_NAOWH") then
        own[command] = true
    elseif key:find("^SLASH_") and issecurevariable and not issecurevariable(key) then
        addon[command] = true
    end
end

local function IsCommandString(key, value)
    return type(key) == "string" and type(value) == "string"
        and (key:find("^SLASH_") or key:find("^EMOTE%d+_CMD%d+$")) and value:sub(1, 1) == "/"
end

local function KnownCommands()
    if known then return known end
    known = {}
    for key, value in pairs(_G) do
        if IsCommandString(key, value) then Learn(key, value) end
    end
    return known
end

local function IsChannel(command)
    return command:find("^/%d+$") ~= nil
end

local function CommandKind(command)
    command = command:lower()
    if SCRIPT[command] then return "script" end
    local all = KnownCommands()
    if own[command] then return "own" end
    if addon[command] then return "addon" end
    if not all[command] and not IsChannel(command) then return "unknown" end
end

local function RunsScript(body)
    for line in body:gmatch("[^\n]+") do
        local command = line:match("^%s*(/%a+)")
        if command and SCRIPT[command:lower()] then return true end
    end
    return false
end

M.Commands = { RunsScript = RunsScript, Known = KnownCommands }

ns.MacroCommandKind = CommandKind
