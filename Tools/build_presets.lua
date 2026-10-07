-- Writes Core/NaowhForever_Presets.lua, the setups a player can start from or apply on QoL >
-- System > Defaults (ns.PRESETS; a new install starts from the one NEW_INSTALL names). Builds
-- one preset at a time, out of a profile string from Export Profile (NFPROFILE1:) saved to a
-- file, or a .lua file returning a profile table (one profiles entry of NaowhForever.lua, the
-- SavedVariables) with its author's name after it; the other presets are kept as they are.
-- Takes every module's settings and positions, the Macros settings and the look; Smart
-- Reminders and what the exporter answered about EllesmereUI's windows (ns.PROFILE_OWN) are
-- left out, so a player asks as on a first run. Run from the repo root with Libs/:
--   lua5.1 Tools/build_presets.lua minimalist profile.txt
--   lua5.1 Tools/build_presets.lua recommended profile.lua Naowh
local INFO = {
    minimalist = { order = 1, name = "Minimalist", about = "Almost everything off, to turn on what you want." },
    recommended = { order = 2, name = "Recommended", about = "Naowh's recommended setup, with the modules he uses on." },
}
local NEW_INSTALL = "minimalist"
local OUT = "Core/NaowhForever_Presets.lua"
local usage = "usage: lua5.1 Tools/build_presets.lua <" .. "minimalist|recommended> <profile string file, or profile .lua> [author]"
local which, source = assert(INFO[arg[1] or ""] and arg[1], usage), assert(arg[2], usage)
-- Smart Reminders' own settings, and the Custom Reminders that run on its triggers.
local LEFT_OUT = { tankReminder = true, customReminders = true }

strmatch = string.match
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/LibSerialize/LibSerialize.lua")
local ns = { UI = {}, PlainText = function(s) return s end, ValidPackData = function(d) return type(d) == "table" end }
local env = setmetatable({ _G = { NaowhForever = ns }, date = os.date }, { __index = _G })
ns.Shared = { Decode = dofile("Tools/regression/load_decode.lua")(env) }
local chunk = assert(loadfile("Core/NaowhForever_ProfileShare.lua"))
setfenv(chunk, env)
chunk()

local presets = {}
local existing = io.open(OUT, "rb")
if existing then
    existing:close()
    local kept = { NaowhForever = {} }
    kept._G = kept
    local load = assert(loadfile(OUT))
    setfenv(load, kept)
    load()
    for key, preset in pairs(kept.NaowhForever.PRESETS or {}) do
        if INFO[key] then presets[key] = preset end
    end
end

local payload
if source:match("%.lua$") then
    local settings = assert(dofile(source), "the file returns no profile table")
    local macros = settings.macros
    settings.macros = nil
    payload = { name = INFO[which].name, author = arg[3] or "?", made = os.date("%Y-%m-%d"),
        parts = { settings = settings, macros = { module = macros } } }
else
    local f = assert(io.open(source, "rb"))
    local why
    payload, why = ns.DecodeProfile(f:read("*a"))
    f:close()
    assert(payload, "not a profile string: " .. tostring(why))
end
local parts = payload.parts

-- Taken into the account by the import's own checks, which this does not repeat.
for _, part in ipairs({ "library", "builds", "bisLists" }) do
    assert(parts[part] == nil, "the string carries " .. part .. ", which this does not take yet")
end
assert(not (parts.macros and parts.macros.classMacros), "the string carries class macros, which this does not take yet")

local profile, account = {}, {}
for key, values in pairs(parts.settings or {}) do
    if not LEFT_OUT[key] then profile[key] = values end
end
for key, own in pairs(ns.PROFILE_OWN) do
    for i = 1, #own do
        if profile[key] then profile[key][own[i]] = nil end
    end
end
if parts.macros and parts.macros.module then profile.macros = parts.macros.module end
for key, value in pairs(parts.look or {}) do account[key] = value end
profile.qol = profile.qol or {}
profile.qol.preset = which
presets[which] = { source = ("%s by %s, %s"):format(tostring(payload.name), tostring(payload.author),
    tostring(payload.made)), profile = profile, account = account }
assert(presets[NEW_INSTALL], "build the " .. NEW_INSTALL .. " preset first: a new install starts from it")

local function Key(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
    if type(k) == "string" then return "[" .. ("%q"):format(k) .. "]" end
    return "[" .. tostring(k) .. "]"
end

local function Value(v)
    if type(v) == "string" then
        -- ASCII only in the source: anything else as a decimal escape.
        return (("%q"):format(v):gsub("\\\n", "\\n"):gsub("[\128-\255]", function(c)
            return ("\\%d"):format(c:byte())
        end))
    end
    if type(v) == "number" then
        local short = ("%.14g"):format(v)
        return tonumber(short) == v and short or ("%.17g"):format(v)
    end
    return tostring(v)
end

local function Sorted(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

local lines = {}
local function Emit(t, indent)
    for _, k in ipairs(Sorted(t)) do
        local v = t[k]
        if type(v) == "table" then
            if next(v) == nil then
                lines[#lines + 1] = ("%s%s = {},"):format(indent, Key(k))
            else
                lines[#lines + 1] = ("%s%s = {"):format(indent, Key(k))
                Emit(v, indent .. "    ")
                lines[#lines + 1] = indent .. "},"
            end
        else
            lines[#lines + 1] = ("%s%s = %s,"):format(indent, Key(k), Value(v))
        end
    end
end

local keys = {}
for key in pairs(presets) do keys[#keys + 1] = key end
table.sort(keys, function(a, b) return INFO[a].order < INFO[b].order end)

lines[#lines + 1] = "-------------------------------------------------------------------------------"
lines[#lines + 1] = "--  NaowhForever_Presets.lua -- the setups a player can start from (ns.PRESETS): each a"
lines[#lines + 1] = "--  Default profile and the account's look. A new install starts from the one newInstall"
lines[#lines + 1] = "--  names (ns.STARTER); QoL > System > Defaults applies any of them. Generated by"
lines[#lines + 1] = "--  Tools/build_presets.lua; do not edit by hand."
for _, key in ipairs(keys) do
    lines[#lines + 1] = ("--  %s: %s."):format(INFO[key].name, presets[key].source)
end
lines[#lines + 1] = "-------------------------------------------------------------------------------"
lines[#lines + 1] = "local ns = _G.NaowhForever"
lines[#lines + 1] = ""
lines[#lines + 1] = "ns.PRESETS = {"
lines[#lines + 1] = "    newInstall = " .. Value(NEW_INSTALL) .. ","
local order = {}
for _, key in ipairs(keys) do order[#order + 1] = Value(key) end
lines[#lines + 1] = "    order = { " .. table.concat(order, ", ") .. " },"
for _, key in ipairs(keys) do
    lines[#lines + 1] = ("    %s = {"):format(key)
    lines[#lines + 1] = "        name = " .. Value(INFO[key].name) .. ","
    lines[#lines + 1] = "        about = " .. Value(INFO[key].about) .. ","
    lines[#lines + 1] = "        source = " .. Value(presets[key].source) .. ","
    lines[#lines + 1] = "        profile = {"
    Emit(presets[key].profile, "            ")
    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "        account = {"
    Emit(presets[key].account, "            ")
    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "    },"
end
lines[#lines + 1] = "}"
lines[#lines + 1] = "ns.STARTER = ns.PRESETS[ns.PRESETS.newInstall]"

local out = assert(io.open(OUT, "wb"))
out:write(table.concat(lines, "\r\n"), "\r\n")
out:close()
print(("%s: %s built (%d modules); presets: %s"):format(OUT, which, #Sorted(profile), table.concat(order, ", ")))
