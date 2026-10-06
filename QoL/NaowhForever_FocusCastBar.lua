-------------------------------------------------------------------------------
--  NaowhForever_FocusCastBar.lua -- the QoL focus cast bar, coloured by whether your interrupt
--  is ready. Focus casts are secret, so they only ever reach setters that accept secrets.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI
local T = ns.THEME

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
local INTERRUPTED = "Interrupted"
local SAMPLE_SPELL, SAMPLE_NAME, SAMPLE_ICON = 116, "Frostbolt", 135846
local SAMPLE_TOTAL, SAMPLE_LEFT, SAMPLE_KICK, SAMPLE_STOPPED = 2.5, 1.4, 2, 0.6

local frame, bar, tickBar, icon, shield, nameText, targetText, timeText
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

local Look = {}

function Look.New(f)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(BAR)
    ns.Border(f, { r = 0, g = 0, b = 0 })

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetAllPoints()
    f.bar:SetStatusBarTexture(BAR)
    f.bar:SetMinMaxValues(0, 1)

    f.tickBar = CreateFrame("StatusBar", nil, f)
    f.tickBar:SetAllPoints(f.bar)
    f.tickBar:SetStatusBarTexture(BAR)
    f.tickBar:SetStatusBarColor(0, 0, 0, 0)
    f.tickBar:Hide()
    f.tick = f.tickBar:CreateTexture(nil, "OVERLAY")
    f.tick:SetTexture(BAR)
    f.tick:SetWidth(2)

    f.icon = CreateFrame("Frame", nil, f)
    f.icon.tex = f.icon:CreateTexture(nil, "ARTWORK")
    f.icon.tex:SetAllPoints()
    f.icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Border(f.icon, { r = 0, g = 0, b = 0 })

    f.shield = f:CreateTexture(nil, "OVERLAY")
    f.shield:SetAtlas("ui-castingbar-shield")
    f.shield:SetSize(29, 33)
    f.shield:SetPoint("TOP", f, "BOTTOM", 0, 4)
    f.shield:Hide()

    local text = CreateFrame("Frame", nil, f)
    text:SetAllPoints(f.bar)
    text:SetFrameLevel(f:GetFrameLevel() + 5)
    f.nameText = ns.Font(text, 12, "OUTLINE")
    f.nameText:SetPoint("LEFT", 4, 0)
    f.nameText:SetJustifyH("LEFT")
    f.nameText:SetWordWrap(false)
    f.targetText = ns.Font(text, 12, "OUTLINE")
    f.targetText:SetJustifyH("LEFT")
    f.targetText:SetWordWrap(false)
    f.timeText = ns.Font(text, 12, "OUTLINE")
    f.timeText:SetPoint("RIGHT", -4, 0)
    f.timeText:SetJustifyH("RIGHT")
end

function Look.Layout(f)
    local w, h = S.Get("focusWidth"), S.Get("focusHeight")
    f:SetSize(w, h)
    local c = S.Get("focusBgColor")
    f.bg:SetVertexColor(c.r, c.g, c.b, S.Get("focusBgAlpha"))

    local spell = f.icon
    spell:ClearAllPoints()
    spell:SetSize(h, h)
    local side = S.Get("focusIconSide")
    if side == "RIGHT" then
        spell:SetPoint("LEFT", f, "RIGHT", 1, 0)
    elseif side == "TOP" then
        spell:SetPoint("BOTTOM", f, "TOP", 0, 1)
    elseif side == "BOTTOM" then
        spell:SetPoint("TOP", f, "BOTTOM", 0, -1)
    else
        spell:SetPoint("RIGHT", f, "LEFT", -1, 0)
    end
    spell:SetShown(S.Get("focusIcon"))

    local font, size = UI.FontPath(S.Get("focusFont")), S.Get("focusFontSize")
    local tc = ClassColor("focusTextColor", "focusTextClassColor")
    for _, fs in ipairs({ f.nameText, f.targetText, f.timeText }) do
        fs:SetFont(font, size, "OUTLINE")
        fs:SetTextColor(tc.r, tc.g, tc.b, 1)
    end
    local chars = S.Get("focusNameLength")
    f.nameText:SetWidth(chars > 0 and chars * size * 0.6 or 0)
    f.nameText:SetShown(S.Get("focusSpellName"))
    f.targetText:ClearAllPoints()
    if S.Get("focusSpellName") then
        f.targetText:SetPoint("LEFT", f.nameText, "RIGHT", 4, 0)
    else
        f.targetText:SetPoint("LEFT", f.bar, "LEFT", 4, 0)
    end
    f.timeText:SetShown(S.Get("focusTime"))
    f.tick:SetHeight(h)
    local t = ClassColor("focusTickColor", "focusTickClassColor")
    f.tick:SetVertexColor(t.r, t.g, t.b, 0.9)
end

function Look.StateColour(state)
    if state == "ready" then return ClassColor("focusReadyColor", "focusReadyClassColor") end
    if state == "cooldown" then return S.Get("focusCooldownColor") end
    if state == "nonint" then return S.Get("focusNonIntColor") end
    return S.Get("focusInterruptedColor")
end

function Look.Paint(f, c)
    f.bar:GetStatusBarTexture():SetVertexColor(c.r, c.g, c.b, 1)
end

function Look.Tick(f, total, at, channel)
    local ticker, mark = f.tickBar, f.tick
    ticker:SetMinMaxValues(0, total)
    ticker:SetReverseFill(channel == true)
    ticker:SetValue(at)
    mark:ClearAllPoints()
    if channel then
        mark:SetPoint("RIGHT", ticker:GetStatusBarTexture(), "LEFT")
    else
        mark:SetPoint("LEFT", ticker:GetStatusBarTexture(), "RIGHT")
    end
    ticker:Show()
end

function Look.Interrupter(name, classToken)
    return INTERRUPTED .. ": " .. WrapClass(name, classToken)
end

function Look.Sample(f, state)
    local _, class = UnitClass("player")
    local you = UnitName("player")
    if f.bar.ClearTimerDuration then f.bar:ClearTimerDuration() end
    f.bar:SetMinMaxValues(0, 1)
    f.icon.tex:SetTexture(C_Spell.GetSpellTexture(SAMPLE_SPELL) or SAMPLE_ICON)
    f.shield:Hide()
    f.tickBar:Hide()
    f:SetAlpha(1)
    if state == "interrupted" then
        f.bar:SetValue(SAMPLE_STOPPED)
        f.nameText:SetText(S.Get("focusInterrupter") and Look.Interrupter(you, class) or INTERRUPTED)
        f.targetText:SetText("")
        f.timeText:SetText("")
        Look.Paint(f, Look.StateColour("interrupted"))
        if S.Get("focusFadeTime") <= 0 then return "Interrupted Fade is 0: the bar hides at once." end
        return nil
    end
    f.bar:SetValue((SAMPLE_TOTAL - SAMPLE_LEFT) / SAMPLE_TOTAL)
    f.nameText:SetText(C_Spell.GetSpellName(SAMPLE_SPELL) or SAMPLE_NAME)
    f.targetText:SetText(S.Get("focusTarget") and WrapClass(you, class) or "")
    f.timeText:SetFormattedText("%.1f", SAMPLE_LEFT)
    local colour, note = Look.StateColour("ready"), nil
    if state == "cooldown" then
        colour = Look.StateColour("cooldown")
        if S.Get("focusTick") then
            Look.Tick(f, SAMPLE_TOTAL, SAMPLE_KICK, false)
            f.tickBar:SetAlpha(1)
        end
        if S.Get("focusHideOnCooldown") then
            f:SetAlpha(0)
            note = "Hide While Interrupt Is on Cooldown is on: the bar stays hidden."
        end
    elseif state == "nonint" then
        if S.Get("focusColorNonInt") then colour = Look.StateColour("nonint") end
        if S.Get("focusShield") then
            f.shield:Show()
            f.shield:SetAlpha(1)
        end
        if S.Get("focusHideNonInt") then
            f:SetAlpha(0)
            note = "Hide Uninterruptible Casts is on: the bar stays hidden."
        end
    end
    Look.Paint(f, colour)
    return note
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverFocusCastBar", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    Look.New(frame)
    bar, tickBar, icon, shield = frame.bar, frame.tickBar, frame.icon, frame.shield
    nameText, targetText, timeText = frame.nameText, frame.targetText, frame.timeText

    frame.mover = UI.AttachMover(frame, "Focus Cast Bar", function(pos) S.Set("focusCastBarPos", pos) end, "QoL/Combat", "QoL/Combat:focusCastBar")
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

local function NotInterruptible()
    if casting then return select(8, UnitCastingInfo("focus")) end
    if channeling then return select(7, UnitChannelInfo("focus")) end
end

local function Colors(interrupted)
    if interrupted then
        Look.Paint(frame, Look.StateColour("interrupted"))
        frame:SetAlpha(1)
        return
    end
    local tex = bar:GetStatusBarTexture()
    local ready = KickReady()
    local rc, cc = Look.StateColour("ready"), Look.StateColour("cooldown")
    local color = C_CurveUtil.EvaluateColorFromBoolean(ready, CreateColor(rc.r, rc.g, rc.b, 1),
        CreateColor(cc.r, cc.g, cc.b, 1))
    local notInt = NotInterruptible()
    local hasNotInt = Secret(notInt) or notInt ~= nil
    if hasNotInt and S.Get("focusColorNonInt") then
        local nc = Look.StateColour("nonint")
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
    Look.Tick(frame, total, tickSnapshot, channeling)
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
    local label = INTERRUPTED
    if S.Get("focusInterrupter") and (Secret(by) or (by and by ~= "")) then
        local name = UnitNameFromGUID(by)
        if Secret(name) or name then
            label = Look.Interrupter(name, select(2, GetPlayerInfoByGUID(by)))
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
    Look.Sample(frame, "ready")
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
    Look.Layout(frame)
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

local Group = ns.Shared.Settings.Group
local SIDE = { { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" }, { "LEFT", "RIGHT", "TOP", "BOTTOM" } }
local AUDIO = { { none = "None", sound = "Sound", tts = "Text to Speech" }, { "none", "sound", "tts" } }
local AUDIO_HELP = "A sound, or the Speech text read aloud, as each cast starts."
local VOICE_HELP = "Game Default speaks in the voice the rest of the addon uses."
local STAGE_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN = 150, 10, 11, 16
local STATES = {
    { key = "ready", label = "Interrupt Ready", tip = "A cast while your interrupt is ready." },
    { key = "cooldown", label = "On Cooldown", tip = "A cast while your interrupt is on cooldown, with the tick where it comes back." },
    { key = "nonint", label = "Uninterruptible", tip = "A cast you cannot interrupt, with its shield." },
    { key = "interrupted", label = "Interrupted", tip = "A cast someone interrupted, held for the fade time." },
}

local function Voices()
    return ns.TTSVoiceChoices()
end

local function OwnReadyColour() return not S.Get("focusReadyClassColor") end
local function OwnTextColour() return not S.Get("focusTextClassColor") end
local function OwnTickColour() return S.Get("focusTick") and not S.Get("focusTickClassColor") end
local function PlaysSound() return S.Get("focusAudio") == "sound" end
local function Speaks() return S.Get("focusAudio") == "tts" end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.bar = CreateFrame("Frame", nil, preview)
    Look.New(preview.bar)
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return preview
end

local function Fit(preview)
    local f = preview.bar
    local h = S.Get("focusHeight")
    local side = S.Get("focusIconSide")
    local across = S.Get("focusIcon") and (side == "LEFT" or side == "RIGHT") and h + 1 or 0
    local down = S.Get("focusIcon") and (side == "TOP" or side == "BOTTOM") and h + 1 or 0
    local x = side == "LEFT" and across / 2 or -across / 2
    local y = side == "BOTTOM" and down / 2 or -down / 2
    local width = S.Get("focusWidth") + across
    local room = preview:GetWidth() - STAGE_MARGIN * 2
    local scale = 1
    if room > 0 and width > room then scale = room / width end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", preview, "CENTER", x, y + NOTE_Y)
end

local function PaintPreview(preview, state)
    Look.Layout(preview.bar)
    Fit(preview)
    preview.note:SetText(Look.Sample(preview.bar, state) or "")
end

local function Summary(store)
    local audio = store.Get("focusAudio")
    return ("%d by %d%s"):format(store.Get("focusWidth"), store.Get("focusHeight"),
        audio == "sound" and ", plays a sound" or audio == "tts" and ", speaks" or "")
end

ns.Shared.Settings.Page("QoL/Combat", S):Card({
    id = "focusCastBar", name = "Focus Cast Bar", order = 50, switch = "focusCastBar",
    help = "Your focus target's casts on a bar of their own, coloured by whether your interrupt "
        .. "is ready, with a tick where it comes off cooldown and a shield on casts you cannot "
        .. "interrupt. Your interrupt is the first you know of Pummel, Shield Bash, Kick, "
        .. "Counterspell, Earth Shock, Silence and Feral Charge. Move it in Layout Mode.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Bar"),
        { key = "focusWidth", label = "Width", slider = { 100, 600, 5 } },
        { key = "focusHeight", label = "Height", slider = { 10, 60, 1 } },
        { key = "focusBgColor", label = "Background Colour", colour = true },
        { key = "focusBgAlpha", label = "Background Opacity", slider = { 0, 100, 5 }, unit = "%", scale = 0.01 },
        Group("Colours"),
        { key = "focusReadyClassColor", label = "Class Colour Ready", toggle = true },
        { key = "focusReadyColor", label = "Interrupt Ready Colour", colour = true, needs = OwnReadyColour,
          why = "Class colour is on" },
        { key = "focusCooldownColor", label = "Interrupt on Cooldown Colour", colour = true },
        { key = "focusInterruptedColor", label = "Interrupted Colour", colour = true },
        { key = "focusColorNonInt", label = "Colour Uninterruptible Casts", toggle = true },
        { key = "focusNonIntColor", label = "Uninterruptible Colour", colour = true, needs = "focusColorNonInt" },
        Group("Shown"),
        { key = "focusIcon", label = "Show Icon", toggle = true },
        { key = "focusIconSide", label = "Icon Side", choice = SIDE, needs = "focusIcon" },
        { key = "focusSpellName", label = "Show Spell Name", toggle = true },
        { key = "focusNameLength", label = "Name Length", slider = { 0, 40, 1 }, needs = "focusSpellName",
          help = "Cuts the name to about this many letters. 0 shows it whole." },
        { key = "focusTarget", label = "Show Cast Target", toggle = true,
          help = "Who the cast is aimed at, in their class colour." },
        { key = "focusTime", label = "Show Time Left", toggle = true },
        { key = "focusShield", label = "Uninterruptible Shield", toggle = true },
        { key = "focusInterrupter", label = "Show Who Interrupted", toggle = true },
        { key = "focusTick", label = "Interrupt Ready Tick", toggle = true,
          help = "A tick on the bar where your interrupt comes off cooldown. Hidden while it is ready." },
        { key = "focusTickClassColor", label = "Class Colour Tick", toggle = true, needs = "focusTick" },
        { key = "focusTickColor", label = "Tick Colour", colour = true, needs = OwnTickColour,
          why = "Needs Interrupt Ready Tick, class colour off" },
        Group("Hide"),
        { key = "focusHideFriendly", label = "Hide Friendly Casts", toggle = true },
        { key = "focusHideNonInt", label = "Hide Uninterruptible Casts", toggle = true },
        { key = "focusHideOnCooldown", label = "Hide While Interrupt Is on Cooldown", toggle = true },
        { key = "focusFadeTime", label = "Interrupted Fade", slider = { 0, 3, 0.05 }, unit = "s",
          help = "How long an interrupted cast stays up. 0 hides it at once." },
        Group("Text"),
        { key = "focusFont", label = "Font", font = true },
        { key = "focusFontSize", label = "Font Size", slider = { 8, 24, 1 } },
        { key = "focusTextClassColor", label = "Class Colour Text", toggle = true },
        { key = "focusTextColor", label = "Text Colour", colour = true, needs = OwnTextColour,
          why = "Class colour is on" },
        Group("Sound"),
        { key = "focusAudio", label = "Cast Start Audio", choice = AUDIO, help = AUDIO_HELP },
        { key = "focusSound", label = "Sound", sound = true, needs = PlaysSound, why = "Cast Start Audio is not Sound" },
        { key = "focusVoice", label = "Voice", choice = Voices, help = VOICE_HELP, needs = Speaks,
          why = "Needs Text to Speech" },
        { key = "focusVolume", label = "Volume", slider = { 0, 100, 1 }, needs = Speaks, why = "Needs Text to Speech" },
        { key = "focusRate", label = "Speech Rate", slider = { -10, 10, 1 }, needs = Speaks,
          why = "Needs Text to Speech" },
        { key = "focusSpeech", label = "Speech Text", text = true, needs = Speaks, why = "Needs Text to Speech",
          help = "Spoken as a cast starts." },
    },
})
