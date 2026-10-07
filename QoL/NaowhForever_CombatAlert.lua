-------------------------------------------------------------------------------
--  NaowhForever_CombatAlert.lua -- the QoL combat alert: fading text, with an optional sound or
--  spoken line, as you enter and leave combat.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local WIDTH = 300

local frame, fade, unlocked

local function On()
    return S.Get("enabled") and S.Get("combatAlert")
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverCombatAlert", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.text = ns.Font(frame, 32, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
    frame.mover = UI.AttachMover(frame, "Combat Alert", function(pos) S.Set("combatAlertPos", pos) end, "QoL/Combat", "QoL/Combat:combatAlert")
    frame:Hide()

    fade = frame:CreateAnimationGroup()
    local fadeIn = fade:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.4)
    fadeIn:SetOrder(1)
    local fadeOut = fade:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.4)
    fadeOut:SetStartDelay(1.7)
    fadeOut:SetOrder(2)
    fade:SetScript("OnFinished", function() frame:Hide() end)
end

local function Place()
    local pos = S.Get("combatAlertPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

-- prefix is "combatEnter" or "combatLeave".
local function Flash(prefix)
    fade:Stop()
    local c = S.Get(prefix .. "ClassColor") and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        or S.Get(prefix .. "Color")
    frame.text:SetText(S.Get(prefix .. "Text"))
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    -- Fitted to the text only with a background, so elements anchored to it keep their spot.
    frame:SetWidth(frame.mode == "none" and WIDTH or frame.text:GetStringWidth() + 2 * St.CARD_PAD)
    frame:Show()
    if not unlocked then fade:Play() end
end

-- "Game Default" stores "" and speaks in the voice the rest of the addon uses.
local function Speak(prefix)
    local text = S.Get(prefix .. "Speech")
    if not (C_VoiceChat and C_VoiceChat.SpeakText) or text == "" then return end
    local voice = S.Get(prefix .. "Voice")
    if voice == "" then voice = ns.TTSVoiceID() end
    pcall(C_VoiceChat.SpeakText, voice, text, S.Get(prefix .. "Rate"), S.Get(prefix .. "Volume"), true)
end

local function Announce(prefix)
    local mode = S.Get(prefix .. "Audio")
    if mode == "sound" then
        UI._PlayLSMSound(UI.SoundPathFor(S.Get(prefix .. "Sound")))
    elseif mode == "tts" then
        Speak(prefix)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if unlocked then return end
    local prefix = event == "PLAYER_REGEN_DISABLED" and "combatEnter" or "combatLeave"
    Flash(prefix)
    -- Speech is made on the game's own thread and the client waits for it, so it goes out a
    -- frame later instead of stacking on the combat change every other addon is handling.
    C_Timer.After(0, function() Announce(prefix) end)
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if frame then
            fade:Stop()
            frame:Hide()
        end
        return
    end
    if not frame then Build() end
    local size = S.Get("combatAlertFontSize")
    frame.mode = frame.backdrop:SetMode(S.Get("combatAlertBackground"))
    Parts.HudFont(frame.text, S.Get("combatAlertFont"), size, S.Get("combatAlertOutline"), frame.mode)
    frame:SetSize(WIDTH, size + 16)
    Place()
    frame.mover:SetShown(unlocked == true)
    if unlocked then
        Flash("combatEnter")
    else
        fade:Stop()
        frame:Hide()
    end
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "combatAlert"
        or ((key:find("^combatEnter") or key:find("^combatLeave") or key:find("^combatAlert"))
            and key ~= "combatAlertPos") then
        Apply()
    end
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

local Group = ns.Shared.Settings.Group
local AUDIO = { { none = "None", sound = "Sound", tts = "Text to Speech" }, { "none", "sound", "tts" } }
local AUDIO_HELP = "A sound, or the Speech text read aloud. Text to Speech can stutter on some PCs, "
    .. "as the game waits while Windows speaks it; a Sound costs nothing."
local VOICE_HELP = "Game Default speaks in the voice the rest of the addon uses."
local SPEAKS_WHY = "Needs Text to Speech"

local function Voices()
    return ns.TTSVoiceChoices()
end

local rows = {}

local function Side(prefix, name, verb)
    local function OwnColour() return not S.Get(prefix .. "ClassColor") end
    local function PlaysSound() return S.Get(prefix .. "Audio") == "sound" end
    local function Speaks() return S.Get(prefix .. "Audio") == "tts" end
    local list = {
        Group(name .. " Combat"),
        { key = prefix .. "Text", label = name .. " Text", text = true, help = "What it shows as you " .. verb .. " combat." },
        { key = prefix .. "ClassColor", label = name .. " Class Colour", toggle = true },
        { key = prefix .. "Color", label = name .. " Colour", colour = true, needs = OwnColour,
          why = "Class colour is on" },
        { key = prefix .. "Audio", label = name .. " Audio", choice = AUDIO, help = AUDIO_HELP },
        { key = prefix .. "Sound", label = name .. " Sound", sound = true, needs = PlaysSound,
          why = name .. " Audio is not Sound" },
        { key = prefix .. "Voice", label = name .. " Voice", choice = Voices, help = VOICE_HELP, needs = Speaks,
          why = SPEAKS_WHY },
        { key = prefix .. "Volume", label = name .. " Volume", slider = { 0, 100, 1 }, needs = Speaks,
          why = SPEAKS_WHY },
        { key = prefix .. "Rate", label = name .. " Speech Rate", slider = { -10, 10, 1 }, needs = Speaks,
          why = SPEAKS_WHY },
        { key = prefix .. "Speech", label = name .. " Speech", text = true, needs = Speaks, why = SPEAKS_WHY,
          help = "Read aloud as you " .. verb .. " combat." },
    }
    for _, row in ipairs(list) do rows[#rows + 1] = row end
end

Side("combatEnter", "Entering", "enter")
Side("combatLeave", "Leaving", "leave")
rows[#rows + 1] = ns.Shared.Settings.Look("combatAlert", { text = true, size = { 10, 72, 1 }, background = "card" })

local function Summary(store)
    return ("%s and %s"):format(store.Get("combatEnterText"), store.Get("combatLeaveText"))
end

local page = ns.Shared.Settings.Page("QoL/Combat", S)

page:Card({
    id = "combatAlert", name = "Combat Alert", order = 70, switch = "combatAlert",
    help = "A short flash of text entering and leaving combat. Move it in the HUD Editor.",
    summary = Summary,
    rows = rows,
})
