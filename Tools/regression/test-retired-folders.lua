-- Run with Lua 5.1 from the repository root: RetireOldFolders cut out of Core/Core.lua and run on stubs.
-- An old module folder that moved into QoL is switched off at login; when it loaded this session too,
-- a reload is offered at once. For that session the QoL Top Bar stays off and leaves its card to the old
-- addon, so the bar and its secure buttons are built once and the card is declared once.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local f = assert(io.open("Core/Core.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()

local retired = assert(loadstring("return " .. assert(source:match("\nlocal RETIRED_ADDONS = (%b{})\n"), "RETIRED_ADDONS")))()
local text = assert(source:match('\nlocal TEXT_RETIRED = "([^"]+)"\n'), "TEXT_RETIRED")
local body = assert(source:match("\n(local function RetireOldFolders%(%)\n.-\nend)\n"), "RetireOldFolders")

local listed = {}
for _, addon in ipairs(retired) do listed[addon] = true end
check("the old Top Bar folder is retired", listed.NaowhForever_TopBar)
check("as are the old Glimmer folders", listed.NaowhForever_Glimmer and listed.NaowhForever_GlimmerData)
check("and the Top Bar ships no addon of its own", io.open("NaowhForever_TopBar/NaowhForever_TopBar.toc") == nil)

local function Run(exists, loaded)
    local w = { disabled = {}, printed = {}, reloads = {} }
    local ns = {
        L = function(s) return s end,
        Print = function(s) w.printed[#w.printed + 1] = s end,
        ConfirmReload = function(s) w.reloads[#w.reloads + 1] = s end,
    }
    local C_AddOns = {
        DoesAddOnExist = function(addon) return exists[addon] == true end,
        IsAddOnLoaded = function(addon) return loaded[addon] == true end,
        DisableAddOn = function(addon, who) w.disabled[addon] = who == nil end,
    }
    local chunk = assert(loadstring("local ns, C_AddOns, RETIRED_ADDONS, TEXT_RETIRED = ...\n" .. body
        .. "\nRetireOldFolders()"))
    chunk(ns, C_AddOns, retired, text)
    return w
end

local w = Run({}, {})
check("no old folder: nothing is switched off or said", next(w.disabled) == nil and #w.printed == 0 and #w.reloads == 0)

w = Run({ NaowhForever_TopBar = true }, {})
check("an old folder that did not load is switched off", w.disabled.NaowhForever_TopBar)
check("with a line in chat and no reload", #w.printed == 1 and w.printed[1] == text:format("NaowhForever_TopBar")
    and #w.reloads == 0)

w = Run({ NaowhForever_TopBar = true }, { NaowhForever_TopBar = true })
check("an old folder that loaded is switched off too", w.disabled.NaowhForever_TopBar)
check("and a reload is offered instead of the chat line", #w.reloads == 1
    and w.reloads[1] == text:format("NaowhForever_TopBar") and #w.printed == 0)

-- The QoL copy of the Top Bar, its TopBar.lua and its card's file, run on stubs.
local function Guard(exists, enabled, loaded)
    local cards = {}
    local ns = {
        L = function(s) return s end,
        FEATURES = { topBar = {} },
        UI = { ModuleSettings = function() return { Get = function(k) return k == "enabled" end } end },
        Shared = {
            Parts = {},
            Style = {},
            Settings = {
                Group = function(name) return { group = name } end,
                Page = function() return { Card = function(_, spec) cards[#cards + 1] = spec end } end,
            },
        },
    }
    local old = "NaowhForever_TopBar"
    local env = setmetatable({ NaowhForever = ns, C_AddOns = {
        DoesAddOnExist = function(addon) return addon == old and exists end,
        GetAddOnEnableState = function(addon) return addon == old and enabled and 2 or 0 end,
        IsAddOnLoaded = function(addon) return addon == old and loaded end,
    } }, { __index = _G })
    env._G = env
    for _, path in ipairs({ "NaowhForever_QoL/TopBar/TopBar.lua", "NaowhForever_QoL/TopBar/UI/SettingsPage.lua" }) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        if path:find("SettingsPage") then
            ns.TopBar.Layout, ns.TopBar.Preview = { Reset = function() end }, {}
        end
        chunk()
    end
    return ns.TopBar.On(), #cards
end

local on, cards = Guard(false, false, false)
check("no old folder: the QoL Top Bar runs and declares its card", on and cards == 1)
on, cards = Guard(true, false, false)
check("an old folder switched off: the same", on and cards == 1)
on, cards = Guard(true, true, true)
check("the old addon loaded this session: the QoL Top Bar stays off", not on)
check("and leaves the card to the old addon, which declares it after QoL", cards == 0)

print(("test-retired-folders: %d checks passed"):format(checks))
