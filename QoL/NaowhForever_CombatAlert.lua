-------------------------------------------------------------------------------
--  NaowhForever_CombatAlert.lua -- the QoL combat alert: a line of text as you enter combat
--  and another as you leave it, fading in and out, each with an optional sound or spoken
--  line.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

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
    frame.mover = UI.AttachMover(frame, "Combat Alert", function(pos) S.Set("combatAlertPos", pos) end)
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
    frame.text:SetFont(UI.FontPath(S.Get("combatAlertFont")), size, "OUTLINE")
    frame:SetSize(300, size + 16)
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
