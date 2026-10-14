-- Run with Lua 5.1 from the repository root: the Total Craft Timer counts only the crafts your bags
-- can pay for. Create x20 with no reagents shows no bar (the game refuses it and sends no cast
-- events), and with reagents for 5 the bar counts 5. Loads CraftTimer.lua against stubs.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local RECIPE = 3946
local boot, bar, craftHook
local craftable = 0

local function Noop() end
local frameMethods = {
    GetAlpha = function() return 1 end,
    GetFrameLevel = function() return 1 end,
    GetScale = function() return 1 end,
    Show = function(f) f.shown = true end,
    Hide = function(f) f.shown = false end,
    SetText = function(f, text) f.text = text end,
    SetScript = function(f, name, fn) f[name] = fn end,
    RegisterEvent = function(f, event)
        if event == "PLAYER_LOGIN" then boot = f end
    end,
}
local frameMeta = { __index = function(_, k) return frameMethods[k] or Noop end }
local function Frame(_, name)
    local f = setmetatable({}, frameMeta)
    if name == "NaowhForeverCraftTimer" then bar = f end
    return f
end
frameMethods.CreateTexture = function() return Frame() end

local color = { r = 1, g = 1, b = 1 }
local settings = { enabled = true, craftTimer = true, craftTimerFontSize = 14, craftTimerBgAlpha = 0.9 }
local ns = {
    L = dofile("Tools/regression/locale_stub.lua").L,
    THEME = { bg = color, accent = color, accentSoft = color },
    Shared = { Parts = { HudFont = Noop } },
    UI = { TexturePath = function() return "" end },
    Solid = function() return Frame() end, Border = Noop, Font = function() return Frame() end, Apply = Noop,
    Professions = {
        Settings = { Get = function(k) return settings[k] end, Set = Noop },
        Style = { BORDER_RGB = color },
        Widgets = { Crop = function(t) return t end },
        Recipes = { Craftable = function() return craftable end },
    },
}

local env = setmetatable({
    NaowhForever = ns,
    UIParent = Frame(),
    CreateFrame = Frame,
    GetTime = function() return 100 end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    UnitCastingInfo = Noop,
    C_Spell = { GetSpellInfo = function() return { name = "Solid Dynamite", castTime = 5000 } end },
    C_TradeSkillUI = { GetRecipeInfo = function() return { name = "Solid Dynamite", icon = 1 } end },
    C_Timer = { NewTicker = function() return { Cancel = Noop } end },
    hooksecurefunc = function(_, name, fn)
        if name == "CraftRecipe" then craftHook = fn end
    end,
}, { __index = _G })
env._G = env

Load({ "NaowhForever_Professions/UI/CraftTimer.lua" }, env)
boot.OnEvent(boot, "PLAYER_LOGIN")
check("logging in hooks CraftRecipe", craftHook ~= nil)

craftHook(RECIPE, 20)
check("Create x20 with no reagents shows no bar", bar == nil or not bar.shown)

craftable = 1
craftHook(RECIPE, 20)
check("reagents for one craft is not a batch", bar == nil or not bar.shown)

craftable = 5
craftHook(RECIPE, 20)
check("reagents for 5 of 20 shows the bar", bar and bar.shown)
check("and it counts 5, not 20", bar.labels[2].text == "0 / 5 crafted")

craftable = 50
craftHook(RECIPE, 20)
check("plenty of reagents counts what was asked", bar.labels[2].text == "0 / 20 crafted")

print(("test-craft-timer-craftable: %d checks passed"):format(checks))
