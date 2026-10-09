-- Bars.lua: the Swing Timer bars on screen, driven by Forever's PLAYER_SWING, with their timing aids.
local ns = _G.NaowhForever

local UI = ns.UI
local Parts = ns.Shared.Parts
local ST = ns.SwingTimer
local S = ST.Settings
local C, Look, SPELLS = ST.C, ST.Look, ST.SPELLS
local Color, Plain, On = ST.Color, ST.Plain, ST.On
local SUPPORTED, TARGET = ST.SUPPORTED, ST.TARGET

local FLAT_TEX = C.FLAT_TEX
local AUTO_SHOT_CAST = C.AUTO_SHOT_CAST
local END_GRACE = 0.25
local SEAL_SECONDS = 30
local MAX_AURAS = 40
local MS = 1000
local CAST_END = 5
local DEFAULT_SWING = 2
local SAMPLE_TIME = "1.2"
local TIME_STEP, TIME_FORMAT = 0.1, "%.1f"
local PARRY_HIGH, PARRY_CUT, PARRY_LOW = 0.6, 0.4, 0.2
local PHYSICAL = 1
local HOME_Y = -180
local STRATA = "MEDIUM"
local CARD = C.PAGE .. ":bars"
local TEXT_MOVER = "Swing Timer"
local SWING_ACTIONS = {
    WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true,
    DEFLECT = true, ABSORB = true, IMMUNE = true, EVADE = true,
}
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local SWING, DIR, IMMEDIATE
if SUPPORTED then
    SWING = Enum.PlayerSwingType
    DIR = Enum.StatusBarTimerDirection
    IMMEDIATE = Enum.StatusBarInterpolation.Immediate
end

local frame, unlockActive, unlocked, inCombat, pendingApply, timeFormat
local rows, byType = {}, {}
local live = 0
local queueColorKey, queued = {}, false
local sealByName, seal = {}, false
local sealTimer, sealSeconds = nil, SEAL_SECONDS
local isHunter, moving, latency, castEnd = false, false, 0, nil
local swingSpeeds = {}
local events = CreateFrame("Frame")
local UpdateVisibility

local function Direction()
    return S.Get("depleteFill") and DIR.RemainingTime or DIR.ElapsedTime
end

local function WeaponSpeed(row)
    local unit = row.slot == TARGET and "target" or "player"
    local speed = select(C.SPEED_RETURN[row.label], UnitAttackSpeed(unit))
    if Plain(speed) then
        row.speed = type(speed) == "number" and speed > 0 and speed or nil
    end
    return row.speed
end

local function Wanted(row)
    if not S.Get(row.switch) then return false end
    if row.slot == SWING.MainHand then return true end
    if row.slot == TARGET then
        local hostile, dead = UnitCanAttack("player", "target"), UnitIsDead("target")
        if not (Plain(hostile) and hostile and Plain(dead) and not dead) then return false end
    end
    return WeaponSpeed(row) ~= nil
end

local function BuildRow(label)
    local row = Look.Row(frame, label)
    row.dur = C_DurationUtil.CreateDuration()
    local text = C_DurationUtil.CreateDurationTextBinding()
    text:SetFontString(row.time)
    text:SetDuration(row.dur)
    text:SetFormatter(timeFormat)
    text:SetZeroDurationText("")
    text:SetExpiredText("")
    text:SetEnabled(false)
    row.text = text
    row.far = false
    return row
end

local function RowColor(row)
    if row.hand and queued then return Color(queueColorKey[queued]) end
    if row.hand and seal then return Color(seal.key) end
    return Look.BarColor(row)
end

local function PaintRow(row)
    row.bar:GetStatusBarTexture():SetVertexColor(RowColor(row))
    Look.Tag(row, row.hand and queued)
end

local function PaintHands()
    for i = 1, #rows do
        if rows[i].hand then PaintRow(rows[i]) end
    end
end

local function PaintRange(row)
    Look.Range(row, row.far and not unlocked)
end

local function SetFar(row, far)
    row.far = far
    PaintRange(row)
end

local function SetRangeCheck(row, on)
    row.rangeOn = on and row.slot ~= TARGET
    if row.rangeOn then C_SwingTimer.EnableRangeCheck(row.slot, true) end
end

local function ReadRange(row)
    local within
    if row.rangeOn then within = C_SwingTimer.IsTargetWithinSwingRange(row.slot) end
    SetFar(row, Plain(within) and within == false)
end

local function WindowSeconds(row)
    local sec
    if row.hand then
        if not S.Get("swingWindow") then return nil end
        sec = S.Get("swingWindowTime")
    elseif row.slot == SWING.Ranged then
        if not (S.Get("autoShotWindow") and isHunter) then return nil end
        sec = AUTO_SHOT_CAST
    else
        return nil
    end
    if S.Get("windowLatency") then sec = sec + latency end
    return sec
end

local function WindowKey(row)
    if row.hand then return "swingWindowColor" end
    if moving then return "autoShotMovingColor" end
    return "autoShotStandColor"
end

local function UpdateWindow(row)
    local sec = (row.live or unlocked) and WindowSeconds(row)
    if not sec then row.window:Hide() return end
    Look.Window(row, sec / (row.swing or DEFAULT_SWING), Color(WindowKey(row)))
end

local function UpdateCastTick()
    local row = byType[SWING.MainHand]
    if not row then return end
    local tick = row.tick
    if not (S.Get("castClip") and castEnd and row.live and not unlocked) then
        tick:Hide()
        return
    end
    Look.Tick(row, (castEnd - (row.ends - row.swing)) / row.swing,
        Color(castEnd > row.ends and "castBadColor" or "castOkColor"))
end

local function ReadCast()
    local e = select(CAST_END, UnitCastingInfo("player"))
    if Plain(e) and not e then e = select(CAST_END, UnitChannelInfo("player")) end
    castEnd = (Plain(e) and e) and e / MS or nil
end

local function IdleRow(row)
    if row.live then
        row.live = nil
        live = live - 1
        if live == 0 and S.Get("hideWhenIdle") then UpdateVisibility() end
    end
    if row.endTimer then
        row.endTimer:Cancel()
        row.endTimer = nil
    end
    row.ends = nil
    Parts.StopTimer(row.bar, row.dur)
    row.text:SetEnabled(false)
    row.time:SetText("")
    row.spark:Hide()
    row.window:Hide()
    if row.tick then row.tick:Hide() end
end

local function ScheduleEnd(row)
    if row.endTimer then row.endTimer:Cancel() end
    if not row.onEnd then
        row.onEnd = function()
            row.endTimer = nil
            IdleRow(row)
        end
    end
    row.endTimer = C_Timer.NewTimer(math.max(row.ends - GetTime(), 0) + END_GRACE, row.onEnd)
end

local function RunRow(row)
    row.dur:SetTimeFromStart(row.ends - row.swing, row.swing)
    row.bar:SetTimerDuration(row.dur, IMMEDIATE, Direction())
    row.text:SetEnabled(S.Get("showTime"))
    row.spark:SetShown(S.Get("showSpark"))
end

local function ReadLatency()
    if not S.Get("windowLatency") then return end
    local _, _, _, world = GetNetStats()
    latency = (world or 0) / MS
end

local function StartRow(row, dur)
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    row.ends, row.swing = GetTime() + dur, dur
    local wasIdle = live == 0
    if not row.live then
        row.live = true
        live = live + 1
    end
    RunRow(row)
    ScheduleEnd(row)
    ReadLatency()
    UpdateWindow(row)
    if row.tick then UpdateCastTick() end
    if wasIdle and S.Get("hideWhenIdle") then UpdateVisibility() end
end

local function ParryHaste(row)
    local now, dur = GetTime(), row.swing
    local rem = row.ends - now
    if rem > PARRY_HIGH * dur then
        rem = rem - PARRY_CUT * dur
    elseif rem > PARRY_LOW * dur then
        rem = PARRY_LOW * dur
    else
        return
    end
    row.ends = now + rem
    RunRow(row)
    ScheduleEnd(row)
end

local function Queued()
    for name in pairs(queueColorKey) do
        local waiting = C_Spell.IsCurrentSpell(name)
        if Plain(waiting) and waiting then return name end
    end
    return false
end

local function StopSealTimer()
    if not sealTimer then return end
    sealTimer:Cancel()
    sealTimer = nil
end

local function SetSeal(s)
    if not s then StopSealTimer() end
    if s == seal then return end
    seal = s
    PaintHands()
end

local function SealRanOut()
    sealTimer = nil
    SetSeal(false)
end

local function RunOutIn(seconds)
    if sealTimer then sealTimer:Cancel() end
    sealTimer = C_Timer.NewTimer(seconds, SealRanOut)
end

local function SealAura(aura)
    local s = Plain(aura.name) and sealByName[aura.name]
    if not s then return nil end
    local ends, length = aura.expirationTime, aura.duration
    if Plain(length) and type(length) == "number" and length > 0 then sealSeconds = length end
    if Plain(ends) and type(ends) == "number" and ends > 0 then
        RunOutIn(math.max(ends - GetTime(), 0))
    end
    return s
end

local function ReadSeal()
    if inCombat or C_Secrets.ShouldAurasBeSecret() then return end
    local found = false
    for i = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local s = SealAura(aura)
        if s then
            found = s
            break
        end
    end
    SetSeal(found)
end

local function SealCast(spellID)
    if not Plain(spellID) then return end
    local name = C_Spell.GetSpellName(spellID)
    if not Plain(name) or not name then return end
    if not sealByName[name] then return end
    SetSeal(sealByName[name])
    RunOutIn(sealSeconds)
end

local function PaintQueue()
    local q = S.Get("queueHighlight") and Queued()
    if q == queued then return end
    queued = q
    PaintHands()
end

local function RefreshRows()
    local h, sp, w = S.Get("rowHeight"), S.Get("spacing"), S.Get("width")
    local range = S.Get("rangeCheck")
    local n = 0
    for i = 1, #rows do
        local row = rows[i]
        if Wanted(row) then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -n * (h + sp))
            row:SetSize(w, h)
            row:Show()
            n = n + 1
            SetRangeCheck(row, range)
            ReadRange(row)
        else
            if row.live then IdleRow(row) end
            row:Hide()
            SetRangeCheck(row, false)
            SetFar(row, false)
        end
    end
    n = math.max(n, 1)
    frame:SetSize(w, n * h + (n - 1) * sp)
end

local function RowsChanged()
    for i = 1, #rows do
        local row = rows[i]
        if Wanted(row) ~= row:IsShown() then return true end
    end
    return false
end

local function Style()
    local tex = UI.TexturePath(S.Get("texture"), FLAT_TEX)
    for i = 1, #rows do
        local row = rows[i]
        Look.Style(row, tex)
        PaintRow(row)
        PaintRange(row)
    end
end

local function PaintSample()
    for i = 1, #rows do
        local row = rows[i]
        if row.live then IdleRow(row) end
        Parts.StopTimer(row.bar, row.dur, true)
        row.time:SetText(S.Get("showTime") and SAMPLE_TIME or "")
        row.spark:SetShown(S.Get("showSpark"))
        UpdateWindow(row)
    end
end

function UpdateVisibility()
    if not frame then return end
    local always = S.Get("visibility") == "always"
    local show = unlocked or (On() and (always or inCombat)
        and not (not always and S.Get("hideWhenIdle") and live == 0))
    frame:SetShown(show and true or false)
end

local function Place()
    local pos = S.Get("swingPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, HOME_Y)
    end
end

local function LearnSpells(classFile)
    for _, id in ipairs(SPELLS.NEXT_SWING[classFile] or {}) do
        local name = C_Spell.GetSpellName(id)
        if Plain(name) and name then queueColorKey[name] = SPELLS.QUEUE_OWN_COLOR[id] or "queueColor" end
    end
    if classFile ~= "PALADIN" then return end
    for _, s in ipairs(SPELLS.SEALS) do
        local name = C_Spell.GetSpellName(s.id)
        if Plain(name) and name then sealByName[name] = s end
    end
end

local function SavePosition(pos)
    S.Set("swingPos", pos)
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverSwingTimer", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata(STRATA)
    timeFormat = C_StringUtil.CreateNumericRuleFormatter()
    timeFormat:AddBreakpoint({ threshold = 0, step = TIME_STEP,
        rounding = Enum.NumericRuleFormatRounding.Up, format = TIME_FORMAT })
    for i, label in ipairs(C.BAR_LABELS) do
        local row = BuildRow(label)
        rows[i], byType[row.slot] = row, row
        IdleRow(row)
    end
    frame.mover = UI.AttachMover(frame, TEXT_MOVER, SavePosition, C.PAGE, CARD)
    local _, classFile = UnitClass("player")
    isHunter = classFile == "HUNTER"
    LearnSpells(classFile)
    Place()
end

local function SwingRow(row, dur)
    if not row:IsShown() and S.Get(row.switch) and not row.speed then
        row.speed = dur
        RefreshRows()
    end
    if row:IsShown() and not unlocked then StartRow(row, dur) end
    if row.rangeOn then
        C_SwingTimer.EnableRangeCheck(row.slot, true)
        ReadRange(row)
    end
end

local function OnSwing(dur, kind)
    if not (Plain(dur) and Plain(kind)) then return false end
    local row = byType[kind]
    if row then SwingRow(row, dur) end
    return true
end

local function OnSwingRange(kind, inRange, checks)
    if not (Plain(kind) and Plain(inRange) and Plain(checks)) then return end
    local row = byType[kind]
    if row and row.rangeOn then SetFar(row, checks == true and inRange == false) end
end

local function OnTargetChanged()
    local tr = byType[TARGET]
    if tr.live then IdleRow(tr) end
    tr.speed = nil
    RefreshRows()
end

local function OnCombat(unit, action, school)
    if not (Plain(unit) and Plain(action) and Plain(school)) then return end
    local tr = byType[TARGET]
    if not tr:IsShown() or unlocked then return end
    if unit == "player" then
        if school ~= PHYSICAL or not SWING_ACTIONS[action] then return end
        local onMe = UnitIsUnit("targettarget", "player")
        if not (Plain(onMe) and onMe) then return end
        local speed = WeaponSpeed(tr)
        if speed then StartRow(tr, speed) end
    elseif action == "PARRY" and tr.live then
        ParryHaste(tr)
    end
end

local function OnWeaponSwap()
    RefreshRows()
    local mh, oh, ranged = UnitAttackSpeed("player")
    swingSpeeds[SWING.MainHand], swingSpeeds[SWING.OffHand], swingSpeeds[SWING.Ranged] = mh, oh, ranged
    for t, speed in pairs(swingSpeeds) do
        local row = byType[t]
        if row.live and Plain(speed) then StartRow(row, speed) end
    end
end

local function OnDead()
    for i = 1, #rows do
        if rows[i].live then IdleRow(rows[i]) end
    end
    UpdateVisibility()
end

local function OnCombatState(event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    UpdateVisibility()
    if not inCombat and S.Get("sealColors") and next(sealByName) then ReadSeal() end
end

local function OnEvent(_, event, a1, a2, a3, a4, a5)
    if event == "PLAYER_SWING" then
        if OnSwing(a1, a2) then PaintQueue() end
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        PaintQueue()
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        OnSwingRange(a1, a2, a3)
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    elseif event == "UNIT_COMBAT" then
        OnCombat(a1, a2, a5)
    elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
        moving = event == "PLAYER_STARTED_MOVING"
        UpdateWindow(byType[SWING.Ranged])
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        SealCast(a3)
    elseif event == "UNIT_AURA" then
        ReadSeal()
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        castEnd = nil
        UpdateCastTick()
    elseif event:find("^UNIT_SPELLCAST_") then
        ReadCast()
        UpdateCastTick()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        OnCombatState(event)
    elseif event == "PLAYER_DEAD" then
        OnDead()
    elseif event == "WEAPON_SLOT_CHANGED" then
        OnWeaponSwap()
    elseif event == "UNIT_ATTACK_SPEED" or event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
        if RowsChanged() then RefreshRows() end
    else
        RefreshRows()
    end
end

local function ListenOptional()
    if S.Get("queueHighlight") and next(queueColorKey) then
        events:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    end
    if S.Get("targetSwing") then
        events:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
        events:RegisterUnitEvent("UNIT_FACTION", "target")
        events:RegisterUnitEvent("UNIT_FLAGS", "target")
    end
    moving = false
    if S.Get("autoShotWindow") and isHunter then
        events:RegisterEvent("PLAYER_STARTED_MOVING")
        events:RegisterEvent("PLAYER_STOPPED_MOVING")
        moving = IsPlayerMoving()
    end
    castEnd = nil
    if S.Get("castClip") then
        for i = 1, #CAST_EVENTS do events:RegisterUnitEvent(CAST_EVENTS[i], "player") end
        ReadCast()
    end
    seal = false
    StopSealTimer()
    if S.Get("sealColors") and next(sealByName) then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterUnitEvent("UNIT_AURA", "player")
        ReadSeal()
    end
end

local function RegisterEvents()
    events:UnregisterAllEvents()
    if not On() then return end
    events:RegisterEvent("PLAYER_SWING")
    events:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("WEAPON_SLOT_CHANGED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_DEAD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
    ListenOptional()
end

local function Stop()
    events:UnregisterAllEvents()
    if not frame then return end
    for i = 1, #rows do
        if rows[i].live then IdleRow(rows[i]) end
        SetRangeCheck(rows[i], false)
    end
    frame:Hide()
end

local function Resume()
    for i = 1, #rows do
        local row = rows[i]
        if row.live then
            RunRow(row)
            UpdateWindow(row)
        else
            IdleRow(row)
        end
    end
end

local function Apply()
    if not SUPPORTED then return end
    unlocked = unlockActive and On() == true
    if not (On() or unlocked) then return Stop() end
    if not frame then Build() end
    inCombat = UnitAffectingCombat("player")
    RegisterEvents()
    Place()
    frame.mover:SetShown(unlocked == true)
    queued = false
    PaintQueue()
    RefreshRows()
    Style()
    if unlocked then PaintSample() else Resume() end
    UpdateCastTick()
    UpdateVisibility()
end

local function ApplyNow()
    pendingApply = false
    Apply()
end

local function OnSet(key)
    if key == "swingPos" or pendingApply then return end
    pendingApply = true
    C_Timer.After(0, ApplyNow)
end

local function OnUnlock()
    unlockActive = true
    Apply()
end

local function OnLock()
    unlockActive = false
    if frame then Apply() end
end

events:SetScript("OnEvent", OnEvent)
hooksecurefunc(S, "Set", OnSet)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", OnUnlock)
hooksecurefunc(ns, "HideUnlockMode", OnLock)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
