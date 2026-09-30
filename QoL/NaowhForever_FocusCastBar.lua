-------------------------------------------------------------------------------
--  NaowhForever_FocusCastBar.lua -- the QoL focus cast bar: your focus target's casts on a
--  bar of their own, coloured by whether your interrupt is ready, with a tick where it comes
--  off cooldown and a shield on casts you cannot interrupt. Move it in Unlock Mode.
--
--  Everything about a focus cast is secret to addons, since the focus is never the player
--  or their pet. So the bar never reads it in Lua: the cast's duration object drives the
--  fill, the text setters take the secret strings and numbers as they are, and colour and
--  visibility go through EvaluateColorFromBoolean and SetAlphaFromBoolean, which accept a
--  secret boolean.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

local BAR = "Interface\\Buttons\\WHITE8X8"
local THROTTLE = 0.033
-- Forever cannot tell which spec you play, so the first of these you know is your interrupt.
local INTERRUPTS = {
    WARRIOR = { 6552, 72 },     -- Pummel, Shield Bash
    ROGUE = { 1766 },           -- Kick
    MAGE = { 2139 },            -- Counterspell
    SHAMAN = { 8042 },          -- Earth Shock
    PRIEST = { 15487 },         -- Silence
    DRUID = { 16979 },          -- Feral Charge
}

local frame, bar, tickBar, tick, icon, shield, nameText, targetText, timeText
local unlocked, casting, channeling, fadeTimer
local interrupt, tickSnapshot
local acc = 0

local function On()
    return S.Get("enabled") and S.Get("focusCastBar")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function ClassColor(key, classKey)
    if S.Get(classKey) then return RAID_CLASS_COLORS[select(2, UnitClass("player"))] end
    return S.Get(key)
end

local function FindInterrupt()
    interrupt = nil
    for _, id in ipairs(INTERRUPTS[select(2, UnitClass("player"))] or {}) do
        if C_SpellBook.IsSpellKnown(id) then
            interrupt = id
            return
        end
    end
end

-- A secret boolean in combat. No duration object at all means no cooldown running.
local function KickReady()
    if not interrupt then return true end
    local cd = C_Spell.GetSpellCooldownDuration(interrupt)
    if not cd then return true end
    return cd:IsZero()
end

local function WrapClass(text, classToken)
    if Secret(classToken) or not classToken then return text end
    local c = C_ClassColor.GetClassColor(classToken)
    if not c then return text end
    return c:WrapTextInColorCode(text)
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverFocusCastBar", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture(BAR)
    ns.Border(frame, { r = 0, g = 0, b = 0 })

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetAllPoints()
    bar:SetStatusBarTexture(BAR)
    bar:SetMinMaxValues(0, 1)

    tickBar = CreateFrame("StatusBar", nil, frame)
    tickBar:SetAllPoints(bar)
    tickBar:SetStatusBarTexture(BAR)
    tickBar:SetStatusBarColor(0, 0, 0, 0)
    tickBar:Hide()
    tick = tickBar:CreateTexture(nil, "OVERLAY")
    tick:SetTexture(BAR)
    tick:SetWidth(2)

    icon = CreateFrame("Frame", nil, frame)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Border(icon, { r = 0, g = 0, b = 0 })

    shield = frame:CreateTexture(nil, "OVERLAY")
    shield:SetAtlas("ui-castingbar-shield")
    shield:SetSize(29, 33)
    shield:SetPoint("TOP", frame, "BOTTOM", 0, 4)
    shield:Hide()

    local text = CreateFrame("Frame", nil, frame)
    text:SetAllPoints(bar)
    text:SetFrameLevel(frame:GetFrameLevel() + 5)
    nameText = ns.Font(text, 12, "OUTLINE")
    nameText:SetPoint("LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    targetText = ns.Font(text, 12, "OUTLINE")
    targetText:SetJustifyH("LEFT")
    targetText:SetWordWrap(false)
    timeText = ns.Font(text, 12, "OUTLINE")
    timeText:SetPoint("RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")

    frame.mover = UI.AttachMover(frame, "Focus Cast Bar", function(pos) S.Set("focusCastBarPos", pos) end)
    frame:Hide()
end

local function Place()
    local pos = S.Get("focusCastBarPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
end

local function Layout()
    local w, h = S.Get("focusWidth"), S.Get("focusHeight")
    frame:SetSize(w, h)
    local c = S.Get("focusBgColor")
    frame.bg:SetVertexColor(c.r, c.g, c.b, S.Get("focusBgAlpha"))

    icon:ClearAllPoints()
    icon:SetSize(h, h)
    local side = S.Get("focusIconSide")
    if side == "RIGHT" then
        icon:SetPoint("LEFT", frame, "RIGHT", 1, 0)
    elseif side == "TOP" then
        icon:SetPoint("BOTTOM", frame, "TOP", 0, 1)
    elseif side == "BOTTOM" then
        icon:SetPoint("TOP", frame, "BOTTOM", 0, -1)
    else
        icon:SetPoint("RIGHT", frame, "LEFT", -1, 0)
    end
    icon:SetShown(S.Get("focusIcon"))

    local font, size = UI.FontPath(S.Get("focusFont")), S.Get("focusFontSize")
    local tc = ClassColor("focusTextColor", "focusTextClassColor")
    for _, fs in ipairs({ nameText, targetText, timeText }) do
        fs:SetFont(font, size, "OUTLINE")
        fs:SetTextColor(tc.r, tc.g, tc.b, 1)
    end
    local chars = S.Get("focusNameLength")
    nameText:SetWidth(chars > 0 and chars * size * 0.6 or 0)
    nameText:SetShown(S.Get("focusSpellName"))
    targetText:ClearAllPoints()
    if S.Get("focusSpellName") then
        targetText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    else
        targetText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    end
    timeText:SetShown(S.Get("focusTime"))
    tick:SetHeight(h)
    local t = ClassColor("focusTickColor", "focusTickClassColor")
    tick:SetVertexColor(t.r, t.g, t.b, 0.9)
end

local function NotInterruptible()
    if casting then return select(8, UnitCastingInfo("focus")) end
    if channeling then return select(7, UnitChannelInfo("focus")) end
end

local function Colors(interrupted)
    local tex = bar:GetStatusBarTexture()
    if interrupted then
        local c = S.Get("focusInterruptedColor")
        tex:SetVertexColor(c.r, c.g, c.b, 1)
        frame:SetAlpha(1)
        return
    end
    local ready = KickReady()
    local rc, cc = ClassColor("focusReadyColor", "focusReadyClassColor"), S.Get("focusCooldownColor")
    local color = C_CurveUtil.EvaluateColorFromBoolean(ready, CreateColor(rc.r, rc.g, rc.b, 1),
        CreateColor(cc.r, cc.g, cc.b, 1))
    local notInt = NotInterruptible()
    local hasNotInt = Secret(notInt) or notInt ~= nil
    if hasNotInt and S.Get("focusColorNonInt") then
        local nc = S.Get("focusNonIntColor")
        color = C_CurveUtil.EvaluateColorFromBoolean(notInt, CreateColor(nc.r, nc.g, nc.b, 1), color)
    end
    tex:SetVertexColor(color:GetRGBA())

    if S.Get("focusHideOnCooldown") then
        frame:SetAlphaFromBoolean(ready, 1, 0)
    else
        frame:SetAlpha(1)
    end
    if hasNotInt and S.Get("focusHideNonInt") then
        frame:SetAlphaFromBoolean(notInt, 0, frame:GetAlpha())
    end
    if hasNotInt and S.Get("focusShield") then
        shield:Show()
        shield:SetAlphaFromBoolean(notInt, 1, 0)
    else
        shield:Hide()
    end
end

-- Where the interrupt comes off cooldown, fixed at the cast's start. Summed only when both
-- numbers are readable; otherwise the kick's remaining time alone, which is right at the start.
local function UpdateTick()
    local duration = casting and UnitCastingDuration("focus") or channeling and UnitChannelDuration("focus")
    local cd = interrupt and C_Spell.GetSpellCooldownDuration(interrupt)
    if not (S.Get("focusTick") and duration and cd) then
        tickBar:Hide()
        return
    end
    if tickSnapshot == nil then
        local remaining, elapsed = cd:GetRemainingDuration(), duration:GetElapsedDuration()
        if Secret(remaining) or Secret(elapsed) then
            tickSnapshot = remaining
        else
            tickSnapshot = elapsed + remaining
        end
    end
    local total = duration:GetTotalDuration()
    if not Secret(tickSnapshot) and not Secret(total) and (tickSnapshot > total or tickSnapshot < 0) then
        tickBar:Hide()
        return
    end
    tickBar:SetMinMaxValues(0, total)
    tickBar:SetReverseFill(channeling == true)
    tickBar:SetValue(tickSnapshot)
    tick:ClearAllPoints()
    if channeling then
        tick:SetPoint("RIGHT", tickBar:GetStatusBarTexture(), "LEFT")
    else
        tick:SetPoint("LEFT", tickBar:GetStatusBarTexture(), "RIGHT")
    end
    tickBar:Show()
    tickBar:SetAlphaFromBoolean(cd:IsZero(), 0, 1)
end

local function Announce()
    local mode = S.Get("focusAudio")
    if mode == "sound" then
        UI._PlayLSMSound(UI.SoundPathFor(S.Get("focusSound")))
    elseif mode == "tts" and C_VoiceChat and C_VoiceChat.SpeakText and S.Get("focusSpeech") ~= "" then
        local voice = S.Get("focusVoice")
        if voice == "" then voice = ns.TTSVoiceID() end
        C_VoiceChat.SpeakText(voice, S.Get("focusSpeech"), S.Get("focusRate"), S.Get("focusVolume"), true)
    end
end

local function Stop()
    if fadeTimer then fadeTimer:Cancel(); fadeTimer = nil end
    casting, channeling, tickSnapshot = false, false, nil
    tickBar:Hide()
    shield:Hide()
    targetText:SetText("")
    if not unlocked then frame:Hide() end
end

local function FriendlyFocus()
    local friend = UnitIsFriend("player", "focus")
    return not Secret(friend) and friend
end

local function Start(isChannel, announce)
    if S.Get("focusHideFriendly") and FriendlyFocus() then return end
    local _, text, texture
    if isChannel then
        _, text, texture = UnitChannelInfo("focus")
    else
        _, text, texture = UnitCastingInfo("focus")
    end
    if fadeTimer then fadeTimer:Cancel(); fadeTimer = nil end
    casting, channeling, tickSnapshot = not isChannel, isChannel, nil
    icon.tex:SetTexture(texture)
    nameText:SetText(text)

    targetText:SetText("")
    if S.Get("focusTarget") and not isChannel then
        local target = UnitSpellTargetName("focus")
        if Secret(target) or target then
            targetText:SetText(WrapClass(target, UnitSpellTargetClass("focus")))
        end
    end

    local duration = isChannel and UnitChannelDuration("focus") or UnitCastingDuration("focus")
    if duration then
        bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
            isChannel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
    end
    Colors()
    UpdateTick()
    frame:Show()
    if announce then Announce() end
end

-- Holds the bar where it stopped, in the interrupted colour, for the fade time.
local function Interrupted(by)
    local fade = S.Get("focusFadeTime")
    if fade <= 0 then
        Stop()
        return
    end
    local timer, value = bar:GetTimerDuration(), nil
    if timer then
        if channeling then
            value = timer:GetRemainingPercent()
        else
            value = timer:GetElapsedPercent()
        end
    end
    if not Secret(value) and value == nil then value = 1 end
    if bar.ClearTimerDuration then bar:ClearTimerDuration() end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(value)
    casting, channeling = false, false
    local label = "Interrupted"
    if S.Get("focusInterrupter") and (Secret(by) or (by and by ~= "")) then
        local name = UnitNameFromGUID(by)
        if Secret(name) or name then
            label = label .. ": " .. WrapClass(name, select(2, GetPlayerInfoByGUID(by)))
        end
    end
    nameText:SetText(label)
    targetText:SetText("")
    timeText:SetText("")
    shield:Hide()
    tickBar:Hide()
    Colors(true)
    frame:Show()
    if fadeTimer then fadeTimer:Cancel() end
    fadeTimer = C_Timer.NewTimer(fade, function()
        fadeTimer = nil
        Stop()
    end)
end

local function Check()
    if not UnitExists("focus") then
        Stop()
    elseif UnitCastingDuration("focus") then
        Start(false)
    elseif UnitChannelDuration("focus") then
        Start(true)
    else
        Stop()
    end
end

local function Preview()
    if bar.ClearTimerDuration then bar:ClearTimerDuration() end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.5)
    icon.tex:SetTexture(136243)
    nameText:SetText("Focus Cast")
    targetText:SetText(S.Get("focusTarget") and WrapClass("Target", "WARRIOR") or "")
    timeText:SetText("1.5")
    local c = ClassColor("focusReadyColor", "focusReadyClassColor")
    bar:GetStatusBarTexture():SetVertexColor(c.r, c.g, c.b, 1)
    frame:SetAlpha(1)
    frame:Show()
end

local function OnUpdate(_, elapsed)
    acc = acc + elapsed
    if acc < THROTTLE then return end
    acc = 0
    if not (casting or channeling) then return end
    Colors()
    if S.Get("focusTime") then
        local duration = casting and UnitCastingDuration("focus") or UnitChannelDuration("focus")
        if duration then timeText:SetFormattedText("%.1f", duration:GetRemainingDuration()) end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, _, _, _, interruptedBy)
    if event == "SPELLS_CHANGED" then
        FindInterrupt()
        return
    end
    if unlocked then return end
    if event == "PLAYER_FOCUS_CHANGED" then
        Check()
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        Start(false, event == "UNIT_SPELLCAST_START")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        Start(true, event == "UNIT_SPELLCAST_CHANNEL_START")
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        Interrupted(interruptedBy)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- interruptedBy can be secret, so it is never tested for truth directly.
        if Secret(interruptedBy) or (interruptedBy and interruptedBy ~= "") then
            Interrupted(interruptedBy)
        elseif not fadeTimer then
            Stop()
        end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        if not fadeTimer then Stop() end
    elseif (casting or channeling) then
        Colors()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not (On() or unlocked) then
        if frame then
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
        end
        return
    end
    if not frame then Build() end
    Place()
    Layout()
    FindInterrupt()
    frame.mover:SetShown(unlocked == true)
    frame:SetScript("OnUpdate", OnUpdate)
    if unlocked then
        Preview()
        return
    end
    events:RegisterEvent("PLAYER_FOCUS_CHANGED")
    events:RegisterEvent("SPELLS_CHANGED")
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
        events:RegisterUnitEvent(event, "focus")
    end
    Check()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^focus") and key ~= "focusCastBarPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
