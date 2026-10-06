-- Loads NaowhForever_FocusCastBar.lua against stubbed frames and cast APIs and checks the bar's
-- colour while a focus cast runs (interrupt ready, on cooldown, uninterruptible), and what one
-- throttled update of a running cast costs: it must not build colour objects every tick.
-- Run from the repo root: lua Tools/regression/test-focus-cast-bar.lua
local f = assert(io.open(arg[1] or "QoL/NaowhForever_FocusCastBar.lua", "rb"))
local source = f:read("*a"); f:close()

local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end
local Measure = dofile("Tools/regression/measure.lua")(check)

local READY = { r = 0, g = 0.5, b = 1 }
local COOLDOWN = { r = 0.5, g = 0.5, b = 0.5 }
local NONINT = { r = 0.8, g = 0.2, b = 0.2 }

-- Blizzard's ColorMixin, cut down: CreateColor copies every method into a new table, as the
-- client's CreateFromMixins does, so each one made is real garbage.
local ColorMixin = {}
function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a end
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:OnLoad(r, g, b, a) self:SetRGBA(r, g, b, a) end
for _, name in ipairs({ "SetRGB", "IsRGBEqualTo", "IsEqualTo", "GenerateHexColor", "GenerateHexColorNoAlpha",
    "GenerateHexColorMarkup", "WrapTextInColorCode", "GetRGBAsBytes", "GetRGBAAsBytes" }) do
    ColorMixin[name] = function() end
end
local made = 0
local function CreateColor(r, g, b, a)
    made = made + 1
    local c = {}
    for k, v in pairs(ColorMixin) do c[k] = v end
    c:OnLoad(r, g, b, a)
    return c
end

local function Noop() end
local Widget
local methods = {
    SetScript = function(self, k, fn) self.scripts[k] = fn end,
    GetScript = function(self, k) return self.scripts[k] end,
    RegisterEvent = function(self, e) self.events[e] = true end,
    RegisterUnitEvent = function(self, e) self.events[e] = true end,
    UnregisterAllEvents = function(self) for k in pairs(self.events) do self.events[k] = nil end end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, v) self.shown = v and true or false end,
    IsShown = function(self) return self.shown end,
    SetAlpha = function(self, a) self.alpha = a end,
    GetAlpha = function(self) return self.alpha or 1 end,
    SetVertexColor = function(self, r, g, b) self.r, self.g, self.b = r, g, b end,
    GetFrameLevel = function() return 1 end,
    GetWidth = function() return 300 end,
    CreateTexture = function(self) return Widget("Texture", self) end,
    GetStatusBarTexture = function(self)
        self.fill = self.fill or Widget("Texture", self)
        return self.fill
    end,
    SetFormattedText = function(self, _, v) self.value = v end,
    SetText = function(self, v) self.text = v end,
}
local meta = { __index = function(_, k)
    local m = methods[k]
    if m then return m end
    if type(k) == "string" and k:find("^%u") then return Noop end
end }
function Widget(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, events = {} }, meta)
end

local values = {
    enabled = true, focusCastBar = true, focusWidth = 250, focusHeight = 24,
    focusBgColor = { r = 0.1, g = 0.1, b = 0.1 }, focusBgAlpha = 0.8,
    focusReadyColor = READY, focusReadyClassColor = false, focusCooldownColor = COOLDOWN,
    focusColorNonInt = true, focusNonIntColor = NONINT, focusInterruptedColor = { r = 0.5, g = 0.5, b = 0.5 },
    focusIcon = true, focusIconSide = "LEFT", focusSpellName = true, focusNameLength = 0,
    focusTarget = false, focusTime = true, focusShield = true, focusTick = false,
    focusTickColor = { r = 1, g = 1, b = 1 }, focusFont = "", focusFontSize = 12,
    focusTextColor = { r = 1, g = 1, b = 1 }, focusFadeTime = 0.75, focusAudio = "none",
}
local S = { Get = function(k) return values[k] end, Set = function(k, v) values[k] = v end }

local state = { kickReady = true, notInt = false }
local duration = { GetRemainingDuration = function() return 1.5 end, GetElapsedDuration = function() return 0.5 end,
    GetTotalDuration = function() return 2 end }
local kick = { IsZero = function() return state.kickReady end, GetRemainingDuration = function() return 0 end }

local frames = {}
local ns = {
    QoLSettings = S, THEME = { muted = {} },
    UI = { FontPath = function() return "font" end, AttachMover = function() return Widget("Mover") end },
    Shared = { Settings = { Group = function() return {} end,
        Page = function() return { Card = Noop } end } },
    Font = function(parent) return Widget("FontString", parent) end,
    Border = Noop,
    Apply = Noop, ShowRaidReminderAnchorConfig = Noop, HideRaidReminderAnchorConfig = Noop,
}
local env = setmetatable({
    _G = { NaowhForever = ns },
    UIParent = Widget("Frame"),
    CreateFrame = function(kind, _, parent)
        local w = Widget(kind, parent)
        frames[#frames + 1] = w
        return w
    end,
    CreateColor = CreateColor,
    hooksecurefunc = function(t, name, post)
        local orig = t[name]
        t[name] = function(...) orig(...); post(...) end
    end,
    issecretvalue = function() return false end,
    UnitClass = function() return "Rogue", "ROGUE" end,
    UnitExists = function() return true end,
    UnitIsFriend = function() return false end,
    UnitCastingInfo = function()
        return "Frostbolt", "Frostbolt", 135846, 0, 2000, false, "guid", state.notInt
    end,
    UnitChannelInfo = function() end,
    UnitCastingDuration = function() return duration end,
    UnitChannelDuration = function() end,
    RAID_CLASS_COLORS = {},
    Enum = { StatusBarInterpolation = {}, StatusBarTimerDirection = {} },
    C_SpellBook = { IsSpellKnown = function(id) return id == 1766 end },
    C_Spell = { GetSpellCooldownDuration = function() return kick end },
    C_CurveUtil = { EvaluateColorFromBoolean = function(b, yes, no) if b then return yes end return no end },
    C_Timer = { NewTimer = function() return { Cancel = Noop } end },
}, { __index = _G })
local chunk = assert(loadstring(source, "FocusCastBar"))
setfenv(chunk, env)
chunk()

local boot, events, bar
for _, w in ipairs(frames) do
    if w.events.PLAYER_LOGIN then boot = w end
end
boot.scripts.OnEvent(boot, "PLAYER_LOGIN")
for _, w in ipairs(frames) do
    if w.events.UNIT_SPELLCAST_START then events = w end
    if w.kind == "StatusBar" and not bar then bar = w end
end
check("listens to the focus's casts once on", events ~= nil)
local cast
for _, w in ipairs(frames) do
    if w.scripts.OnUpdate then cast = w end
end
check("the bar has its update script", cast ~= nil)

local function Fill() local t = bar:GetStatusBarTexture() return t.r, t.g, t.b end
local function Is(c) local r, g, b = Fill() return r == c.r and g == c.g and b == c.b end

events.scripts.OnEvent(events, "UNIT_SPELLCAST_START", "focus")
check("a cast shows the bar", cast.shown)
check("interrupt ready colour", Is(READY))

local tick = cast.scripts.OnUpdate
state.kickReady = false
tick(cast, 0.05)
check("interrupt on cooldown colour on the next update", Is(COOLDOWN))
state.notInt = true
tick(cast, 0.05)
check("uninterruptible colour wins", Is(NONINT))
values.focusCooldownColor = { r = 0.2, g = 0.3, b = 0.4 }
state.notInt = false
tick(cast, 0.05)
check("a changed colour setting shows on the next update", Is(values.focusCooldownColor))
state.kickReady = true
tick(cast, 0.05)
check("ready again", Is(READY))

made = 0
state.notInt = true
Measure("an update of a running focus cast", 0.05, function() tick(cast, 0.05) end)
check("no colour objects made per update", made == 0)

print(("PASS focus cast bar: %d checks"):format(checks))
