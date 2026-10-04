-- Run with Lua 5.1 from the repository root: Smart Reminders' declared settings page. Its store
-- reads the module's own profile table through the defaults, writes what the runtime expects,
-- re-applies the right thing on a change, and its cards reset to the defaults.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local db = { enabled = true, leadTime = 3, showIcon = false, soundKey = "none", textSide = "BOTTOM" }
local applied, resized, refreshed = {}, 0, 0
local ns = {
    THEME = { muted = {} },
    Shared = { Style = { OPACITY_MIN = 40 } },
    DB = function() return db end,
    SettingDefault = function(key)
        local defaults = { enabled = false, leadTime = 3, showIcon = false, soundKey = "none", textSide = "BOTTOM",
            iconSize = 64, textSize = 21, soundOn = false, voiceOn = false }
        return defaults[key]
    end,
    RaidReminderSizeDefaults = { raidReminderBarWidth = 240 },
    SmartReminderApply = { soundOn = function(v) applied.soundOn = v end, bossSource = function() applied.source = true end },
    ResizeRaidReminderBar = function() resized = resized + 1 end,
    RefreshRaidReminderAnchorConfig = function() refreshed = refreshed + 1 end,
    DefensiveLook = {},
    BossSource = function() return db.bossSource or "timeline" end,
}
local env = setmetatable({ NaowhForever = ns }, { __index = _G })
env._G = env
Load({ "Shared/Settings/Settings.lua", "SmartReminders/NaowhForever_SmartRemindersSettings.lua" }, env)

local Settings = ns.Shared.Settings
local Store = ns.SmartReminderSettings
local page = Settings.pages["Smart Reminders/Settings"]
Check(page ~= nil, "the page is declared under its options key")
local window, cards = 0, 0
for _, item in ipairs(page.items) do
    if item.window then window = window + 1 else cards = cards + 1 end
end
Check(window == 1 and cards == 5, "an Open card and five setting cards")

Check(Store.Get("fontName") == "", "an unset font reads as the Addon Font")
Store.Set("fontName", "")
Check(db.fontName == nil and Store.Raw("fontName") == nil, "the Addon Font is stored as nothing")
Store.Set("hideOnCast", false)
Check(db.hideOnCast == nil, "Hide After Casting off is stored as nothing")
Store.Set("hideOnCast", true)
Check(db.hideOnCast == true, "and on as true")

Store.Set("soundOn", true)
Check(applied.soundOn == true, "a change re-applies what the runtime needs")
Store.Set("raidReminderBarWidth", 300)
Check(resized == 1 and refreshed == 1, "a display size resizes that display and Unlock Mode's sample")
Check(Store.Get("raidReminderTextWidth") == nil and Store.Get("raidReminderBarWidth") == 300,
    "display sizes read through their own defaults")

local seen
Store.OnChange(function(key) seen = key end)
Store.Set("leadTime", 4)
Check(seen == "leadTime", "the page hears every change")

local callouts = Settings.CardOf("Smart Reminders/Settings:callouts")
Check(Settings.ChangedCount(callouts) == 1, "only the changed setting is marked")
Settings.Reset(callouts)
Check(db.leadTime == 3 and Settings.ChangedCount(callouts) == 0, "Reset puts the card back to its defaults")

db.bossSource = "dbm"
Check(Settings.ChangedCount(callouts) == 1, "a chosen boss addon counts as a change")
Settings.Reset(callouts)
Check(db.bossSource == nil and applied.source, "and its reset follows the installed boss addon again")

db.enabled = false
local row
for _, r in ipairs(callouts.rows) do if r.key == "leadTime" then row = r end end
local off, why = Settings.Off(row)
Check(off and why == "Turn on Smart Reminders", "every setting waits for the module's switch")

local keys = {}
Settings.Index("Smart Reminders/Settings", function(_, label) keys[label] = true end)
Check(keys["Boss Addon"] and keys["Circle Thickness"] and keys["Window Opacity"], "the search finds the settings")

print(("test-smart-reminders-settings: %d checks passed"):format(checks))
