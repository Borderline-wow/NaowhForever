-------------------------------------------------------------------------------
--  NaowhForever_CombatTimer.lua -- the QoL combat timer: how long the current fight has
--  run, optionally kept on screen after it ends, and reported to chat when it does.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI
local Parts = ns.Shared.Parts

-- Card is the panel the old Show Background toggle drew, black or the theme's Background; on and
-- off are saved as Card and None.
local CARD_COLOR, CARD_ALPHA = { r = 0, g = 0, b = 0 }, 0.8
local OLD_BACKGROUNDS = { [true] = "card", [false] = "none" }

local frame, clock, unlocked
local started, last = nil, 0

local function On()
    return S.Get("enabled") and S.Get("combatTimer")
end

local function InstanceOk()
    if not S.Get("combatTimerInstanceOnly") then return true end
    local inInstance, kind = IsInInstance()
    return inInstance and kind ~= "none"
end

local function Format(seconds)
    local text = ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
    if S.Get("combatTimerHidePrefix") then return text end
    return "COMBAT: " .. text
end

-- Shown while fighting, while unlocked, and after a fight when Sticky keeps the last one up.
local function Update()
    local elapsed
    if started then
        elapsed = GetTime() - started
    elseif unlocked or (S.Get("combatTimerSticky") and last > 0 and InstanceOk()) then
        elapsed = last
    end
    if not elapsed then
        frame:Hide()
        return
    end
    frame.text:SetText(Format(elapsed))
    frame:Show()
end

local function Report(duration)
    local h, m, s = math.floor(duration / 3600), math.floor(duration % 3600 / 60),
        math.floor(duration % 60)
    local text
    if h > 0 then
        text = ("%d:%02d:%02d hours"):format(h, m, s)
    elseif m > 0 then
        text = ("%d:%02d minutes"):format(m, s)
    else
        text = ("%d second%s"):format(s, s == 1 and "" or "s")
    end
    ns.Print("You were in combat for: |cffffa300" .. text .. "|r")
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if not InstanceOk() then return end
        started = GetTime()
        if not clock then clock = C_Timer.NewTicker(1, Update) end
    elseif event == "PLAYER_REGEN_ENABLED" and started then
        last = GetTime() - started
        started = nil
        if clock then clock:Cancel(); clock = nil end
        if S.Get("combatTimerChat") then Report(last) end
    end
    Update()
end)

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverCombatTimer", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.backdrop = Parts.HudBackdrop(frame, { color = ns.ThemeTint("bg", CARD_COLOR), alpha = CARD_ALPHA,
        mode = "none" })
    frame.text = ns.Font(frame, 32, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.mover = UI.AttachMover(frame, "Combat Timer", function(pos) S.Set("combatTimerPos", pos) end, "QoL/Combat", "QoL/Combat:combatTimer")
    frame:Hide()
end

local function Place()
    local pos = S.Get("combatTimerPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
end

local function MigrateBackground()
    local db = S.DB()
    local mode = OLD_BACKGROUNDS[db.combatTimerBackground]
    if mode then db.combatTimerBackground = mode end
end

local function Apply()
    MigrateBackground()
    events:UnregisterAllEvents()
    if not On() then
        started = nil
        if clock then clock:Cancel(); clock = nil end
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    local size = S.Get("combatTimerFontSize")
    local mode = frame.backdrop:SetMode(S.Get("combatTimerBackground"))
    Parts.HudFont(frame.text, S.Get("combatTimerFont"), size, S.Get("combatTimerOutline"), mode)
    local c = S.Get("combatTimerClassColor") and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        or S.Get("combatTimerColor")
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame:SetSize(size * 7, size + 16)
    Place()
    frame.mover:SetShown(unlocked == true)
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^combatTimer") and key ~= "combatTimerPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared.Settings
local Group = Settings.Group

local function OwnColour() return not S.Get("combatTimerClassColor") end

local function Summary(store)
    local parts = store.Get("combatTimerInstanceOnly") and "In instances" or "Everywhere"
    if store.Get("combatTimerChat") then parts = parts .. ", reported to chat" end
    if store.Get("combatTimerSticky") then parts = parts .. ", kept after the fight" end
    return parts
end

Settings.Page("QoL/Combat", S):Card({
    id = "combatTimer", name = "Combat Timer", order = 90, switch = "combatTimer",
    help = "How long the current fight has run, on screen while you fight. Move it in the HUD Editor.",
    summary = Summary,
    rows = {
        Group("When"),
        { key = "combatTimerInstanceOnly", label = "Only In Instances", toggle = true },
        { key = "combatTimerChat", label = "Report to Chat", toggle = true,
          help = "How long the fight lasted, in chat when it ends." },
        { key = "combatTimerSticky", label = "Keep After the Fight", toggle = true,
          help = "The last fight's time stays on screen until the next one starts." },
        Settings.Look("combatTimer", { text = true, size = { 10, 72, 1 } }),
        { key = "combatTimerHidePrefix", label = "Hide the COMBAT Label", toggle = true },
        Settings.Look("combatTimer", { background = "card" }),
        Group("Colours"),
        { key = "combatTimerClassColor", label = "Class Colour", toggle = true },
        { key = "combatTimerColor", label = "Timer Colour", colour = true, needs = OwnColour,
          why = "Class colour is on" },
    },
})
