-------------------------------------------------------------------------------
--  NaowhForever_SmartRemindersSettings.lua -- Smart Reminders' settings page (/nf), declared
--  on ns.Shared.Settings over the module's own profile table (ns.DB()), with live previews of
--  the defensive alert and the reminder displays.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group
local Parts = ns.Shared.Parts

local PAGE = "Smart Reminders/Settings"
local OFF = "Turn on Smart Reminders"
local STAGE_H = 170
local STAGE_MARGIN = 16
local NOTE_Y, NOTE_SIZE = 10, 11
local SAMPLE_ICON = "Interface\\Icons\\Ability_Warrior_ShieldWall"
local SAMPLE_CALLOUT = "Shield Wall"

local SOURCES = { timeline = "Blizzard Timeline", bigwigs = "BigWigs", dbm = "DBM" }
local SOURCE_ORDER = { "timeline", "bigwigs", "dbm" }
local SIDES = { TOP = "Above the Icon", BOTTOM = "Below the Icon", LEFT = "Left of the Icon", RIGHT = "Right of the Icon" }
local SIDE_ORDER = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local EXTRA_DEFAULTS = { fontName = "", ttsVoiceID = "", hideOnCast = false, castTargetBoss = false, windowAlpha = 1,
    defensiveTextColorOn = false, defensiveTextColor = { r = 1, g = 1, b = 1, a = 1 },
    defensiveOutline = "OUTLINE", defensiveTextTheme = false }

local function NilIfEmpty(v) if v ~= "" then return v end end
local function NilIfOff(v) if v then return true end end
local STORED = { fontName = NilIfEmpty, ttsVoiceID = NilIfEmpty, hideOnCast = NilIfOff, castTargetBoss = NilIfOff }

local RESIZE = {
    raidReminderTextWidth = "ResizeRaidReminderText", raidReminderTextFontSize = "ResizeRaidReminderText",
    raidReminderTimerTextSize = "ResizeRaidReminderTimer", raidReminderTimerNumberSize = "ResizeRaidReminderTimer",
    raidReminderIconSize = "ResizeRaidReminderIcon", raidReminderIconTextSize = "ResizeRaidReminderIcon",
    raidReminderBarWidth = "ResizeRaidReminderBar", raidReminderBarHeight = "ResizeRaidReminderBar",
    raidReminderBarTextSize = "ResizeRaidReminderBar",
    raidReminderCircleSize = "ResizeRaidReminderCircle", raidReminderCircleThickness = "ResizeRaidReminderCircle",
    raidReminderCircleTextSize = "ResizeRaidReminderCircle",
    fontName = "RestyleRaidReminders", raidReminderOutline = "RestyleRaidReminders",
    raidReminderBarTexture = "RestyleRaidReminders", raidReminderBarBgAlpha = "RestyleRaidReminders",
    raidReminderCircleBgAlpha = "RestyleRaidReminders", raidReminderTextTheme = "RestyleRaidReminders",
}

local listeners = {}
local Store = {}
ns.SmartReminderSettings = Store

function Store.Default(key)
    local value = ns.SettingDefault(key)
    if value ~= nil then return value end
    value = EXTRA_DEFAULTS[key]
    if value ~= nil then return value end
    return ns.RaidReminderSizeDefaults and ns.RaidReminderSizeDefaults[key]
end

function Store.Raw(key)
    return ns.DB()[key]
end

function Store.Get(key)
    local value = ns.DB()[key]
    if value == nil then return Store.Default(key) end
    return value
end

function Store.Set(key, value)
    local stored = STORED[key]
    if stored then value = stored(value) end
    ns.DB()[key] = value
    local apply = ns.SmartReminderApply and ns.SmartReminderApply[key]
    if apply then apply(value) end
    local resize = RESIZE[key]
    if resize and ns[resize] then
        ns[resize]()
        if ns.RefreshRaidReminderAnchorConfig then ns.RefreshRaidReminderAnchorConfig() end
    end
    for i = 1, #listeners do listeners[i](key, value) end
end

function Store.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function On() return ns.DB().enabled == true end
local function NotColoured() return On() and not Store.Get("defensiveTextColorOn") end

local function SourceName()
    return SOURCES[ns.BossSource()] or SOURCES.timeline
end

local function BossModMissing()
    local source = ns.BossSource()
    return (source == "bigwigs" and not _G.BigWigsLoader) or (source == "dbm" and not _G.DBM)
end

local function Headline()
    if not On() then return "Smart Reminders is off" end
    return "On, following " .. SourceName()
end

local function Detail()
    if On() and ns.CombatWarningsOff and ns.CombatWarningsOff() then
        return "Boss Warnings are off in the game options: Options, Advanced, Enable Boss Warnings."
    end
    if On() and BossModMissing() then
        return SourceName() .. " is not loaded, so the callouts have nothing to listen to."
    end
    return "Cooldown presets and each boss's reminders are in the Smart Reminders window."
end

local Look = ns.DefensiveLook
local OFF_ALPHA = 0.3

local function NewAlert(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.group = CreateFrame("Frame", nil, preview)
    preview.group:SetAllPoints()
    preview.icon = CreateFrame("Frame", nil, preview.group)
    preview.icon.art = Look.Icon(preview.icon)
    preview.icon.art:SetTexture(SAMPLE_ICON)
    preview.text = CreateFrame("Frame", nil, preview.group)
    preview.text:SetSize(1, 1)
    preview.label = preview.text:CreateFontString(nil, "OVERLAY")
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return preview
end

local function PaintAlert(preview)
    local size, fontSize, side = Store.Get("iconSize"), Store.Get("textSize"), Store.Get("textSide")
    local showIcon, showText = Store.Get("showIcon"), Store.Get("showText")
    local icon, label = preview.icon, preview.label
    icon:SetSize(size, size)
    icon.art:SetAlpha(showIcon and 1 or OFF_ALPHA)
    preview.text:ClearAllPoints()
    local point = Look.PlaceText(preview.text, icon, side, 0)
    label:ClearAllPoints()
    label:SetPoint(point, preview.text, point, 0, 0)
    Parts.HudFont(label, Store.Get("fontName"), fontSize, Store.Get("defensiveOutline"), "none")
    label:SetTextColor(Look.TextColour())
    label:SetText(SAMPLE_CALLOUT)
    label:SetAlpha(showText and 1 or OFF_ALPHA)
    local gap = Look.TEXT_GAP
    local textW = math.ceil(label:GetStringWidth()) + gap
    local textH = fontSize + gap
    local w, h, x, y = size, size, 0, 0
    if side == "LEFT" or side == "RIGHT" then
        w = size + textW
        x = side == "LEFT" and textW / 2 or -textW / 2
    else
        h = size + textH
        y = side == "BOTTOM" and textH / 2 or -textH / 2
    end
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h * scale > roomH then scale = roomH / h end
    preview.group:SetScale(scale)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", preview.group, "CENTER", x, y)
    local note = ""
    if not showIcon and not showText then
        note = "Show Icon and Show Text Callout are off: faded here, nothing in a fight."
    elseif not showIcon then
        note = "Show Icon is off: faded here, not shown in a fight."
    elseif not showText then
        note = "Show Text Callout is off: faded here, not shown in a fight."
    end
    preview.note:SetText(note)
end

local ALERT_STATES = {
    { key = "callout", label = "Callout", tip = "The alert as a fight draws it, with your size, font and colour." },
}

local DISPLAY_STATES = {
    { key = "text", label = "Message", tip = "A line of text." },
    { key = "timer", label = "Timer", tip = "A big countdown in whole seconds, with its caption." },
    { key = "icon", label = "Icon", tip = "The spell's icon with its caption." },
    { key = "bar", label = "Bar", tip = "A bar that empties as the moment comes." },
    { key = "circle", label = "Circle", tip = "A ring that sweeps round as the moment comes." },
}

local function NewDisplays(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.group = CreateFrame("Frame", nil, preview)
    preview.group:SetAllPoints()
    preview.samples = {}
    return preview
end

local function PaintDisplays(preview, state)
    for key, sample in pairs(preview.samples) do sample:SetShown(key == state) end
    local sample = preview.samples[state]
    if not sample then
        sample = ns.NewRaidReminderSample(state, preview.group)
        preview.samples[state] = sample
    end
    ns.PaintRaidReminderSample(state, sample)
    local w, h = sample:GetWidth(), sample:GetHeight()
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h * scale > roomH then scale = roomH / h end
    preview.group:SetScale(scale)
    sample:ClearAllPoints()
    sample:SetPoint("CENTER", preview.group, "CENTER")
end

local function CalloutSummary(store)
    return ("%s, %ds early"):format(SourceName(), store.Get("leadTime"))
end

local function AlertSummary(store)
    local icon, text = store.Get("showIcon"), store.Get("showText")
    if icon and text then return ("Icon and text, %d px"):format(store.Get("iconSize")) end
    if icon then return ("Icon, %d px"):format(store.Get("iconSize")) end
    if text then return "Text only" end
    return "Nothing shown"
end

local function SoundSummary(store)
    local err = store.Get("soundOn") and ns.SoundError and ns.SoundError()
    if err then return err end
    local sound, voice = store.Get("soundOn"), store.Get("voiceOn")
    if sound and voice then return "Sound and voice" end
    if sound then return "Sound" end
    if voice then return "Voice" end
    return "Silent"
end

local function ResetIconPosition()
    ns.DB().pos = nil
    if ns.ApplyDefensiveAlertPosition then ns.ApplyDefensiveAlertPosition() end
end

local page = Settings.Page(PAGE, Store)

page:Window({
    text = "Open Smart Reminders",
    open = function() ns.OpenSmartRemindersWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "callouts", name = "Callouts", order = 10,
    help = "Shows what to press when a boss ability is about to land: the highest defensive on your "
        .. "list that you have talented and off cooldown. Build the lists in the Smart Reminders window.",
    summary = CalloutSummary,
    rows = {
        { key = "bossSource", label = "Boss Addon", choice = { SOURCES, SOURCE_ORDER }, needs = On, why = OFF,
          get = function() return ns.BossSource() end, set = function(v) Store.Set("bossSource", v) end,
          help = "The one source the callouts follow. Blizzard Timeline needs no addons, and per-ability "
              .. "sounds only work there. BigWigs or DBM ride that addon's bars and messages, which timer "
              .. "and message reminders need." },
        { label = "Enable Healer Reminders", toggle = true, needs = On, why = OFF,
          get = function() return ns.HealerRemindersEnabled() end,
          set = function(v) ns.SetHealerRemindersEnabled(v) end,
          help = "Shows reminders marked Healer Reminder. Off hides them and cancels their pending alerts. "
              .. "Saved for every character and profile; imports do not change it." },
        Group("Timing"),
        { key = "leadTime", label = "Warn This Many Seconds Early", slider = { 1, 5, 1 }, unit = "s",
          needs = On, why = OFF,
          help = "How long before the hit the alert fires. Each ability can override it from its own cog "
              .. "on its boss's page." },
        { key = "coveredCastWindow", label = "Your Own Cast Covers You For", slider = { 0, 15, 1 }, unit = "s",
          needs = On, why = OFF,
          help = "How long after you press a defensive the callouts stay quiet. Set it to the length of "
              .. "what you press, or 0 to hear about every hit." },
        { key = "coveredSkip", label = "Skip When Already Covered", toggle = true, needs = On, why = OFF,
          help = "Stays quiet when one of your defensives is already up as the warning fires." },
        { key = "castTargetBoss", label = "Show Target on Boss Casts", toggle = true, needs = On, why = OFF,
          help = "Puts the targeted player's name on a Boss Cast Starts reminder's alert, in their class "
              .. "colour, while the cast is going out and only for abilities that name anybody." },
    },
})

page:Card({
    id = "alert", name = "Defensive Alert", order = 20,
    help = "The icon and callout that tell you which defensive to press. Move it with Move Elements.",
    summary = AlertSummary,
    studio = { height = STAGE_H, states = ALERT_STATES, new = NewAlert, paint = PaintAlert },
    rows = {
        Group("Show"),
        { key = "showIcon", label = "Show Icon", toggle = true, needs = On, why = OFF,
          help = "The icon of the defensive to press." },
        { key = "showText", label = "Show Text Callout", toggle = true, needs = On, why = OFF,
          help = "Writes the callout on screen for the defensive it picked. Set each line's wording in the "
              .. "Smart Reminders window." },
        { key = "lingerSec", label = "Icon Display Duration", slider = { 1, 15, 1 }, unit = "s",
          needs = On, why = OFF, help = "How long the icon and callout stay on screen." },
        { key = "hideOnCast", label = "Hide After Casting", toggle = true, needs = On, why = OFF,
          help = "Takes the alert away as soon as you cast the defensive it called." },
        { key = "cdmGlow", label = "Glow It on the Cooldown Manager", toggle = true, needs = On, why = OFF,
          help = "Also glows the called defensive on Blizzard's Cooldown Manager, when it is placed there. "
              .. "It reaches into Blizzard's own frames, so switch it off first if anything misbehaves." },
        Group("Size"),
        { key = "iconSize", label = "Icon Size", slider = { 32, 128, 1 }, needs = On, why = OFF },
        Settings.Look("defensive", { text = true, size = { 10, 40, 1 }, needs = On, why = OFF,
            keys = { Font = "fontName", FontSize = "textSize" } }),
        { key = "textSide", label = "Text Position", choice = { SIDES, SIDE_ORDER }, needs = On, why = OFF,
          help = "Which side of the icon the callout sits on." },
        Group("Colours"),
        { key = "defensiveTextTheme", label = "Apply Theme to the Callout", toggle = true, needs = NotColoured,
          why = "Colour the Callout is on", help = "Writes the callout in your theme's text colour, not white." },
        { key = "defensiveTextColorOn", label = "Colour the Callout", toggle = true, needs = On, why = OFF,
          help = "Your own colour for the callout. Off is white." },
        { key = "defensiveTextColor", label = "Callout Colour", colour = "alpha",
          needs = { "enabled", "defensiveTextColorOn" } },
        Group("Position"),
        { label = "Reset Icon Position", button = ResetIconPosition, buttonText = "Reset", needs = On, why = OFF,
          help = "Puts the alert back in the middle of the screen, if it was lost off the edge." },
    },
})

page:Card({
    id = "sounds", name = "Sounds and Voice", order = 30,
    help = "A sound as a tank ability comes, and a voice that says which defensive to use.",
    summary = SoundSummary,
    rows = {
        { key = "soundOn", label = "Play a Sound", toggle = true, needs = On, why = OFF,
          help = "Plays a sound when a tank ability is coming. The game plays it, at most once per boss "
              .. "fight, and it cannot know whether your defensive is ready." },
        { key = "soundKey", label = "Alert Sound", sound = true, needs = { "enabled", "soundOn" },
          help = "Sound files only: the game will not take its own built-in sounds here." },
        { key = "voiceOn", label = "Speak Which Defensive to Use", toggle = true, needs = On, why = OFF,
          help = "Says the callout for the defensive it picked, and your fallback line when nothing is up." },
        { key = "ttsVoiceID", label = "Voice", choice = function() return ns.TTSVoiceChoices() end,
          needs = { "enabled", "voiceOn" },
          help = "Game Default follows the game's Text to Speech options. The list is the voices your "
              .. "system has." },
        { key = "voiceVol", label = "Voice Volume", slider = { 0, 100, 5 }, unit = "%",
          needs = { "enabled", "voiceOn" } },
    },
})

page:Card({
    id = "displays", name = "Reminder Displays", order = 40,
    help = "How the reminders written on the boss pages look: a message, a timer, an icon, a bar or a "
        .. "circle. Move each one with Move Elements.",
    studio = { height = STAGE_H, states = DISPLAY_STATES, new = NewDisplays, paint = PaintDisplays },
    rows = {
        Group("Message"),
        { key = "raidReminderTextWidth", label = "Message Width", slider = { 60, 800, 1 } },
        { key = "raidReminderTextFontSize", label = "Message Text Size", slider = { 8, 48, 1 } },
        Group("Timer"),
        { key = "raidReminderTimerTextSize", label = "Timer Caption Size", slider = { 8, 48, 1 } },
        { key = "raidReminderTimerNumberSize", label = "Timer Number Size", slider = { 12, 96, 1 } },
        Group("Icon"),
        { key = "raidReminderIconSize", label = "Reminder Icon Size", slider = { 16, 200, 1 } },
        { key = "raidReminderIconTextSize", label = "Reminder Icon Text Size", slider = { 8, 48, 1 } },
        Group("Bar"),
        { key = "raidReminderBarWidth", label = "Bar Width", slider = { 60, 600, 1 } },
        { key = "raidReminderBarHeight", label = "Bar Height", slider = { 6, 60, 1 } },
        { key = "raidReminderBarTextSize", label = "Bar Text Size", slider = { 8, 48, 1 } },
        { key = "raidReminderBarTexture", label = "Bar Texture", texture = "Naowh Gradient" },
        { key = "raidReminderBarBgAlpha", label = "Bar Background Opacity", slider = { 0, 100, 5 }, unit = "%",
          scale = 0.01 },
        Group("Circle"),
        { key = "raidReminderCircleSize", label = "Circle Size", slider = { 20, 200, 1 } },
        { key = "raidReminderCircleThickness", label = "Circle Thickness", slider = { 2, 40, 1 } },
        { key = "raidReminderCircleTextSize", label = "Circle Text Size", slider = { 8, 48, 1 } },
        { key = "raidReminderCircleBgAlpha", label = "Circle Background Opacity", slider = { 0, 100, 5 }, unit = "%",
          scale = 0.01, help = "How dark the ring is behind its sweep." },
        Settings.Look("raidReminder", { text = true, keys = { Font = "fontName", FontSize = false } }),
        Group("Colours"),
        { key = "raidReminderTextTheme", label = "Apply Theme to Text", toggle = true,
          help = "Writes Message and Circle text in your theme's text colour, not white." },
    },
})

page:Card({
    id = "window", name = "Window", order = 50,
    help = "Smart Reminders' own window, with the cooldown presets and every boss's reminders.",
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 },
          unit = "%", scale = 0.01, help = "How solid the window is, in percent. Also on its title bar." },
    },
})
