-- Run with Lua 5.1 from the repository root: the look options of Smart Reminders' reminder
-- displays and defensive alert. With nothing set they draw exactly what they drew before the
-- options existed, and each option reaches the regions already built and the settings preview.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local function Mock()
    local o = { last = {} }
    return setmetatable(o, { __index = function(t, method)
        if not method:find("^%u") then return nil end
        return function(self, ...)
            t.last[method] = { ... }
            if method == "CreateTexture" or method == "CreateFontString" or method == "CreateMaskTexture" then
                return Mock()
            elseif method == "GetStatusBarTexture" then
                t.fill = rawget(t, "fill") or Mock()
                return t.fill
            elseif method == "GetFrameStrata" then
                return "HIGH"
            elseif method == "GetFrameLevel" or method == "GetWidth" or method == "GetHeight" then
                return 1
            end
        end
    end })
end

local OWN_GRADIENT = "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga"
local media = { Solid = "solid.tga" }
local db = {}
local fonts = {}
local ns = {
    THEME = { fg = { r = 0.9, g = 0.8, b = 0.7 }, bg = { r = 0.1, g = 0.1, b = 0.1 },
        accent = { r = 0, g = 0.5, b = 0.9 } },
    DB = function() return db end,
    Font = function() return Mock() end,
    PixelInset = function() end,
    Border = function() end,
    AddUnlockModeChecks = function() end,
    IsReminderEnabled = function() return true end,
    PlayReminderSound = function() end,
    SpeakReminderTTS = function() end,
    Shared = { Parts = { HudFont = function(fs, font, size, outline, background)
        fonts[fs] = { font = font, size = size, outline = outline, background = background }
        return fs
    end } },
    UI = { TexturePath = function(name, own)
        return name and name ~= "" and media[name] or own
    end },
}
local env = setmetatable({
    NaowhForever = ns, UIParent = Mock(),
    CreateFrame = function() return Mock() end,
    hooksecurefunc = function() end,
    GetTime = function() return 0 end,
    C_Timer = { NewTimer = function() return { Cancel = function() end } end },
}, { __index = _G })
env._G = env
Load({ "NaowhForever_SmartReminders/NaowhForever_RaidReminders.lua" }, env)

local function Sample(kind)
    local r = ns.NewRaidReminderSample(kind, Mock())
    ns.PaintRaidReminderSample(kind, r)
    return r
end

-- Today's look.
local text, timer, icon, bar, circle = Sample("text"), Sample("timer"), Sample("icon"), Sample("bar"), Sample("circle")
for _, fs in ipairs({ text.text, timer.label, timer.number, icon.label, bar.label, circle.label }) do
    Check(fonts[fs] and fonts[fs].outline == "OUTLINE" and fonts[fs].font == nil,
        "every display's text keeps the reminder font, outlined")
end
Check(table.concat(text.text.last.SetTextColor, ",") == "1,1,1,1", "the message is white")
Check(table.concat(circle.label.last.SetTextColor, ",") == "1,1,1", "the circle's caption is white")
Check(bar.bar.last.SetStatusBarTexture[1] == OWN_GRADIENT,
    "without NaowhUI_Media the bar draws the gradient this addon ships")
Check(bar.bar.bg.last.SetColorTexture[4] == 0.9, "the bar's backplate is 90% opaque")
Check(table.concat(circle.bg.last.SetVertexColor, ",") == "0,0,0,0.5", "the ring's backplate is black at half")
media.NaowhGradient = "naowhui-media-gradient.tga"
ns.PaintRaidReminderSample("bar", bar)
Check(bar.bar.last.SetStatusBarTexture[1] == "naowhui-media-gradient.tga",
    "with NaowhUI_Media installed its NaowhGradient stays the bar's texture")
Check(ns.RaidReminderSizeDefaults.raidReminderOutline == "OUTLINE"
    and ns.RaidReminderSizeDefaults.raidReminderBarBgAlpha == 0.9, "the settings page reads the same defaults")

-- Each option, on the preview.
db.fontName, db.raidReminderOutline = "Expressway", ""
db.raidReminderBarTexture, db.raidReminderBarBgAlpha, db.raidReminderCircleBgAlpha = "Solid", 0.4, 0.2
db.raidReminderTextTheme = true
for _, kind in ipairs({ "text", "bar", "circle" }) do
    ns.PaintRaidReminderSample(kind, ({ text = text, bar = bar, circle = circle })[kind])
end
Check(fonts[text.text].font == "Expressway" and fonts[text.text].outline == ""
    and fonts[text.text].background == "none", "font and Shadow reach the message, with the bare HUD shadow")
Check(fonts[circle.label].outline == "" and fonts[bar.label].outline == "", "and every other display")
Check(bar.bar.last.SetStatusBarTexture[1] == "solid.tga", "Bar Texture picks a SharedMedia statusbar")
Check(bar.bar.fill.last.SetVertexColor[3] == 0.9, "a new texture keeps the accent fill")
Check(bar.bar.bg.last.SetColorTexture[4] == 0.4, "Bar Background Opacity sets the backplate")
Check(circle.bg.last.SetVertexColor[4] == 0.2, "Circle Background Opacity sets the ring's backplate")
Check(text.text.last.SetTextColor[1] == 0.9 and circle.label.last.SetTextColor[3] == 0.7,
    "Apply Theme to Text writes the message and circle in the theme's text colour")

-- On a region a fight already showed.
db.fontName, db.raidReminderOutline, db.raidReminderTextTheme = nil, nil, nil
local entry = { display = { type = "text", text = "Go", dur = 3 } }
ns.FormatReminderMsg = function(s) return s end
ns.DisplayRaidReminder(entry)
local shown = ns.GetRaidReminderAnchor("text").active[1]
Check(fonts[shown.text].outline == "OUTLINE" and shown.text.last.SetTextColor[1] == 1,
    "a fired message draws today's look")
db.raidReminderOutline = "THICKOUTLINE"
ns.RestyleRaidReminders()
Check(fonts[shown.text].outline == "THICKOUTLINE", "a change restyles the message already on screen")

-- The defensive alert.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local source = Read("NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua")
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end
local alert = {}
local alertEnv = setmetatable({ TRDB = function() return alert end, Parts = ns.Shared.Parts,
    DefensiveTextColor = function() return 0.1, 0.2, 0.3, 1 end, Look = {} }, { __index = _G })
local chunk = assert(loadstring("local ns = ...\n" .. Slice("function Look.TextColour()", "function Look.PlaceText(")
    .. Slice("local function SetAlertFont(", "-- Display only, never clickable.")
    .. "\nreturn SetAlertFont"))
setfenv(chunk, alertEnv)
local SetAlertFont = chunk(ns)
local Look = alertEnv.Look

local callout = {}
SetAlertFont(callout, 21)
Check(fonts[callout].outline == "OUTLINE" and fonts[callout].size == 21 and fonts[callout].font == nil,
    "the callout stays outlined in the reminder font")
Check(table.concat({ Look.TextColour() }, ",") == "1,1,1,1", "and white")
alert.defensiveOutline, alert.fontName, alert.defensiveTextTheme = "", "Expressway", true
SetAlertFont(callout, 21)
Check(fonts[callout].outline == "" and fonts[callout].font == "Expressway", "Outline and Font reach the callout")
Check(select(1, Look.TextColour()) == 0.9, "Apply Theme to the Callout uses the theme's text colour")
alert.defensiveTextColorOn = true
Check(select(1, Look.TextColour()) == 0.1, "a colour of the player's own still wins")

print(("test-smart-reminders-look: %d checks passed"):format(checks))
