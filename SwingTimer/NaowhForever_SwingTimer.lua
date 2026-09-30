-------------------------------------------------------------------------------
--  NaowhForever_SwingTimer.lua -- one bar per weapon that can swing (Main Hand, Off Hand,
--  Ranged), driven by Forever's own PLAYER_SWING event. The server hands over each swing's
--  real duration, so parry haste, swing resets, extra attacks and haste are already in it;
--  nothing here guesses from the combat log, which addons cannot read on Forever.
--
--  On top of the bars, each off until turned on: a window at the end of the melee swing, the
--  Auto Shot cast window on a hunter's Ranged bar, a tick where the current cast ends, and a
--  Target bar estimated from the melee hits you take.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

local S = UI.ModuleSettings("swingTimer", {
    enabled = false,
    width = 220, rowHeight = 14, spacing = 2, textSize = 11,
    texture = "", bgAlpha = 0.6,
    visibility = "combat", hideWhenIdle = false,
    showMH = true, showOH = true, showR = true,
    depleteFill = false, showTime = true, showLabel = true, showSpark = true,
    rangeCheck = true, outOfRangeAlpha = 0.4,
    classColored = false,
    mhColor = { r = 0.90, g = 0.70, b = 0.27 },
    ohColor = { r = 0.90, g = 0.45, b = 0.27 },
    rColor = { r = 0.27, g = 0.73, b = 0.90 },
    queueHighlight = true,
    queueColor = { r = 1, g = 0.70, b = 0.20 },
    cleaveColor = { r = 0.95, g = 0.35, b = 0.25 },
    swingWindow = false, swingWindowTime = 0.4,
    swingWindowColor = { r = 1, g = 1, b = 1, a = 0.35 },
    windowLatency = false,
    autoShotWindow = false,
    autoShotStandColor = { r = 0.30, g = 0.85, b = 0.35, a = 0.6 },
    autoShotMovingColor = { r = 0.95, g = 0.20, b = 0.20, a = 0.6 },
    castClip = false,
    castOkColor = { r = 1, g = 1, b = 1, a = 1 },
    castBadColor = { r = 1, g = 0.15, b = 0.15, a = 1 },
    targetSwing = false,
    tgtColor = { r = 0.85, g = 0.20, b = 0.20 },
})
ns.SwingTimerSettings = S

-- Forever only: the swing event, its enum, the bar timer the fill runs on and the text
-- binding the countdown runs on.
local SUPPORTED = C_SwingTimer and Enum.PlayerSwingType and C_DurationUtil
    and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDurationTextBinding
    and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    and Enum.NumericRuleFormatRounding and Enum.StatusBarTimerDirection
    and Enum.StatusBarInterpolation and true or false

local SPARK_TEX = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FLAT_TEX = "Interface\\Buttons\\WHITE8X8"
local TEXT_PAD = 4
-- The next swing's PLAYER_SWING can land a moment after the predicted end of the last one;
-- a bar waits this long before going idle, so Hide When Idle does not blink between swings.
local END_GRACE = 0.25
-- The Target bar's key in byType; not a PlayerSwingType, so it never reaches C_SwingTimer.
local TARGET = "target"
-- Auto Shot's cast at the end of the ranged cycle; moving inside it holds the shot.
local AUTO_SHOT_CAST = 0.5
-- UNIT_COMBAT actions that mean a melee swing reached the player.
local SWING_ACTIONS = {
    WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true,
    DEFLECT = true, ABSORB = true, IMMUNE = true, EVADE = true,
}
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
}

-- On-next-swing attacks per class. While one is queued the melee bars take its colour and
-- carry its name, so the swing that will use it is plain to see.
local QUEUE_SPELLS = {
    WARRIOR = { { id = 78, key = "queueColor" }, { id = 845, key = "cleaveColor" } },  -- Heroic Strike, Cleave
    DRUID = { { id = 6807, key = "queueColor" } },    -- Maul
    HUNTER = { { id = 2973, key = "queueColor" } },   -- Raptor Strike
}

local SWING, DIR, IMMEDIATE, ROWS
if SUPPORTED then
    SWING = Enum.PlayerSwingType
    DIR = Enum.StatusBarTimerDirection
    IMMEDIATE = Enum.StatusBarInterpolation.Immediate
    ROWS = {
        { type = SWING.MainHand, key = "mh", tag = "MH", show = "showMH", melee = true },
        { type = SWING.OffHand, key = "oh", tag = "OH", show = "showOH", melee = true },
        { type = SWING.Ranged, key = "r", tag = "R", show = "showR" },
        { type = TARGET, key = "tgt", tag = "TGT", target = true },
    }
end

-- unlockActive: Unlock Mode is open; unlocked: it is and this module is on.
local frame, unlockActive, unlocked, inCombat, pendingApply, timeFormat
local rows, byType = {}, {}
local live = 0
local queueSpells, queued = {}, false
local isHunter, moving, latency, castEnd = false, false, 0, nil

local function On()
    return SUPPORTED and S.Get("enabled")
end

-- A restricted answer from the swing API or a unit query is "no information", never a value.
local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

local function Color(key)
    local c = S.Get(key)
    return c.r, c.g, c.b, c.a or 1
end

local function Direction()
    return S.Get("depleteFill") and DIR.RemainingTime or DIR.ElapsedTime
end

-------------------------------------------------------------------------------
--  Which bars exist
-------------------------------------------------------------------------------
-- Main Hand always swings; Off Hand and Ranged while their slot reports a speed. A speed
-- that reads restricted (a haste proc in combat) is "unknown", not "no weapon", so the bar
-- keeps what it last knew.
local function CanSwing(def, row)
    local t = def.type
    if t == SWING.MainHand then return true end
    local speed
    if t == TARGET then
        local hostile, dead = UnitCanAttack("player", "target"), UnitIsDead("target")
        if not (Plain(hostile) and hostile and Plain(dead) and not dead) then return false end
        speed = UnitAttackSpeed("target")
        -- The last readable speed times the bar while the live one reads restricted.
        if Plain(speed) and type(speed) == "number" and speed > 0 then row.targetSpeed = speed end
    else
        local _, oh, ranged = UnitAttackSpeed("player")
        if t == SWING.OffHand then speed = oh else speed = ranged end
    end
    if not Plain(speed) then return row and row.canSwing or false end
    local can = type(speed) == "number" and speed > 0
    if row then row.canSwing = can end
    return can
end

local function Wanted(def, row)
    if def.target then
        if not S.Get("targetSwing") then return false end
    elseif not S.Get(def.show) then
        return false
    end
    return CanSwing(def, row)
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function TexturePath()
    local name = S.Get("texture")
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return (LSM and name ~= "" and LSM:Fetch("statusbar", name, true)) or FLAT_TEX
end

local function BuildRow(def)
    local row = CreateFrame("Frame", nil, frame)
    row.def = def
    row.bg = ns.Solid(row, "BACKGROUND", T.bg, 0.6)
    row.bg:SetAllPoints()
    row.border = ns.Border(row)

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(FLAT_TEX)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar
    row.dur = C_DurationUtil.CreateDuration()

    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints()
    over:SetFrameLevel(bar:GetFrameLevel() + 2)
    row.window = over:CreateTexture(nil, "ARTWORK")
    row.window:Hide()
    -- Anchored to the fill texture in Style, after each texture change.
    row.spark = over:CreateTexture(nil, "OVERLAY", nil, 1)
    row.spark:SetTexture(SPARK_TEX)
    row.spark:SetBlendMode("ADD")
    row.spark:Hide()
    if def.type == SWING.MainHand then
        row.tick = over:CreateTexture(nil, "OVERLAY", nil, 2)
        row.tick:SetWidth(2)
        row.tick:Hide()
    end
    row.tag = ns.Font(over, 11, "OUTLINE")
    row.tag:SetPoint("LEFT", row, "LEFT", TEXT_PAD, 0)
    row.tag:SetText(def.tag)
    row.time = ns.Font(over, 11, "OUTLINE")
    row.time:SetPoint("RIGHT", row, "RIGHT", -TEXT_PAD, 0)
    row.time:SetText("")
    -- The client writes the countdown from the row's duration; no Lua runs per frame.
    local text = C_DurationUtil.CreateDurationTextBinding()
    text:SetFontString(row.time)
    text:SetDuration(row.dur)
    text:SetFormatter(timeFormat)
    text:SetZeroDurationText("")
    text:SetExpiredText("")
    text:SetEnabled(false)
    row.text = text
    row.outOfRange = false
    return row
end

local function RowColor(row)
    local def = row.def
    if def.melee and queued then return Color(queued.key) end
    if S.Get("classColored") and not def.target then
        local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        if c then return c.r, c.g, c.b, 1 end
    end
    return Color(def.key .. "Color")
end

local function PaintRow(row)
    row.bar:GetStatusBarTexture():SetVertexColor(RowColor(row))
    if row.def.melee and queued then
        row.tag:SetText(row.def.tag .. " - " .. queued.name)
    else
        row.tag:SetText(row.def.tag)
    end
end

-- Out of range: the whole bar dims and its text turns red, as Blizzard's own timer does.
local function PaintRange(row)
    local oor = row.outOfRange and not unlocked
    row:SetAlpha(oor and S.Get("outOfRangeAlpha") or 1)
    local r, g, b = 1, 1, 1
    if oor then r, g, b = 1, 0.1, 0.1 end
    row.tag:SetTextColor(r, g, b)
    row.time:SetTextColor(r, g, b)
end

local function SetOutOfRange(row, oor)
    oor = oor and true or false
    if row.outOfRange == oor then return end
    row.outOfRange = oor
    PaintRange(row)
end

-- The engine keeps one range flag per swing type, shared with Blizzard's own timer, which
-- only re-sends its flag when its own state changes. So this only ever turns the flag on
-- (re-sent on every refresh, in case Blizzard's timer turned it off); a bar that does not
-- want range just ignores the range events.
local function SetRangeCheck(row, on)
    row.rangeOn = on and not row.def.target
    if row.rangeOn then C_SwingTimer.EnableRangeCheck(row.def.type, true) end
end

local function ReadRange(row)
    if not row.rangeOn then SetOutOfRange(row, false) return end
    -- nil means no check could be made (no target, no weapon), which is not out of range.
    local inRange = C_SwingTimer.IsTargetWithinSwingRange(row.def.type)
    SetOutOfRange(row, Plain(inRange) and inRange == false)
end

-------------------------------------------------------------------------------
--  Timing aids
-------------------------------------------------------------------------------
-- The window sits at the end the swing lands on: the right while filling, the left while
-- depleting. Sized on the swing edges only.
local function WindowSeconds(row)
    local def = row.def
    local sec
    if def.melee then
        if not S.Get("swingWindow") then return nil end
        sec = S.Get("swingWindowTime")
    elseif def.type == SWING.Ranged then
        if not (S.Get("autoShotWindow") and isHunter) then return nil end
        sec = AUTO_SHOT_CAST
    else
        return nil
    end
    if S.Get("windowLatency") then sec = sec + latency end
    return sec
end

local function UpdateWindow(row)
    local win = row.window
    local sec = (row.live or unlocked) and WindowSeconds(row)
    if not sec then win:Hide() return end
    local w = (S.Get("width") - 2) * math.min(sec / (row.swing or 2), 1)
    local side = S.Get("depleteFill") and "LEFT" or "RIGHT"
    win:ClearAllPoints()
    win:SetPoint("TOP" .. side, row.bar, "TOP" .. side, 0, 0)
    win:SetPoint("BOTTOM" .. side, row.bar, "BOTTOM" .. side, 0, 0)
    win:SetWidth(math.max(w, 1))
    local key
    if row.def.melee then key = "swingWindowColor"
    elseif moving then key = "autoShotMovingColor"
    else key = "autoShotStandColor" end
    win:SetColorTexture(Color(key))
    win:Show()
end

-- Where the current cast ends on the Main Hand swing in flight, pinned to the end in the
-- clip colour when the cast will still be going as the swing comes due.
local function UpdateCastTick()
    local row = byType[SWING.MainHand]
    if not row then return end
    local tick = row.tick
    if not (S.Get("castClip") and castEnd and row.live and not unlocked) then
        tick:Hide()
        return
    end
    local frac = (castEnd - (row.ends - row.swing)) / row.swing
    if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
    if S.Get("depleteFill") then frac = 1 - frac end
    local x = (S.Get("width") - 2) * frac
    tick:ClearAllPoints()
    tick:SetPoint("TOP", row.bar, "TOPLEFT", x, 0)
    tick:SetPoint("BOTTOM", row.bar, "BOTTOMLEFT", x, 0)
    tick:SetColorTexture(Color(castEnd > row.ends and "castBadColor" or "castOkColor"))
    tick:Show()
end

local function ReadCast()
    local e = select(5, UnitCastingInfo("player"))
    if Plain(e) and not e then e = select(5, UnitChannelInfo("player")) end
    castEnd = (Plain(e) and e) and e / 1000 or nil
end

-------------------------------------------------------------------------------
--  Swings
-------------------------------------------------------------------------------
local UpdateVisibility

-- Idle: the bar timer parks on a finished RemainingTime duration, which paints a static empty
-- bar; a plain SetValue does not repaint a bar the timer owns.
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
    row.dur:SetTimeFromStart(GetTime() - 1, 1)
    row.bar:SetTimerDuration(row.dur, IMMEDIATE, DIR.RemainingTime)
    row.text:SetEnabled(false)
    row.time:SetText("")
    row.spark:Hide()
    row.window:Hide()
    if row.tick then row.tick:Hide() end
end

-- The engine animates the fill and the countdown from the duration object; the only Lua
-- left is one timer per swing to catch its end.
local function ScheduleEnd(row)
    if row.endTimer then row.endTimer:Cancel() end
    row.endTimer = C_Timer.NewTimer(math.max(row.ends - GetTime(), 0) + END_GRACE, function()
        row.endTimer = nil
        IdleRow(row)
    end)
end

local function RunRow(row)
    row.dur:SetTimeFromStart(row.ends - row.swing, row.swing)
    row.bar:SetTimerDuration(row.dur, IMMEDIATE, Direction())
    row.text:SetEnabled(S.Get("showTime"))
    row.spark:SetShown(S.Get("showSpark"))
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
    if S.Get("windowLatency") then
        local _, _, _, world = GetNetStats()
        latency = (world or 0) / 1000
    end
    UpdateWindow(row)
    if row.tick then UpdateCastTick() end
    if wasIdle and S.Get("hideWhenIdle") then UpdateVisibility() end
end

-- Parry haste on the target: with more than 60% of its swing left a parry takes 40% of the
-- swing off; between 20% and 60% the rest drops to 20%.
local function ParryHaste(row)
    local now, dur = GetTime(), row.swing
    local rem = row.ends - now
    if rem > 0.6 * dur then
        rem = rem - 0.4 * dur
    elseif rem > 0.2 * dur then
        rem = 0.2 * dur
    else
        return
    end
    row.ends = now + rem
    RunRow(row)
    ScheduleEnd(row)
end

local function QueuedSpell()
    for i = 1, #queueSpells do
        local cur = C_Spell.IsCurrentSpell(queueSpells[i].name)
        if Plain(cur) and cur then return queueSpells[i] end
    end
    return false
end

local function PaintQueue()
    local q = S.Get("queueHighlight") and QueuedSpell() or false
    if q == queued then return end
    queued = q
    for i = 1, #rows do
        if rows[i].def.melee then PaintRow(rows[i]) end
    end
end

-------------------------------------------------------------------------------
--  Frame
-------------------------------------------------------------------------------
local function RefreshRows()
    local h, sp, w = S.Get("rowHeight"), S.Get("spacing"), S.Get("width")
    local range = S.Get("rangeCheck")
    local n = 0
    for i = 1, #rows do
        local row = rows[i]
        if Wanted(row.def, row) then
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
            SetOutOfRange(row, false)
        end
    end
    n = math.max(n, 1)
    frame:SetSize(w, n * h + (n - 1) * sp)
end

-- Whether any bar would appear or disappear; most attack speed changes move neither.
local function RowsChanged()
    for i = 1, #rows do
        local row = rows[i]
        if (Wanted(row.def, row) and true or false) ~= row:IsShown() then return true end
    end
    return false
end

local function Style()
    local tex, size, bgA = TexturePath(), S.Get("textSize"), S.Get("bgAlpha")
    local h = S.Get("rowHeight")
    for i = 1, #rows do
        local row = rows[i]
        row.bar:SetStatusBarTexture(tex)
        row.spark:ClearAllPoints()
        row.spark:SetPoint("CENTER", row.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
        row.bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, bgA)
        row.spark:SetSize(8, h * 2)
        row.tag:SetFont(ns.UIFontPath(), size, "OUTLINE")
        row.time:SetFont(ns.UIFontPath(), size, "OUTLINE")
        row.tag:SetShown(S.Get("showLabel"))
        row.time:SetShown(S.Get("showTime"))
        PaintRow(row)
        PaintRange(row)
    end
end

-- Unlock Mode shows every bar full with a sample time so there is something to drag. A
-- running swing is parked first, or its end would empty the sample under the mover.
local function PaintSample()
    for i = 1, #rows do
        local row = rows[i]
        if row.live then IdleRow(row) end
        row.dur:SetTimeFromStart(GetTime() - 1, 1)
        row.bar:SetTimerDuration(row.dur, IMMEDIATE, DIR.ElapsedTime)
        row.time:SetText(S.Get("showTime") and "1.2" or "")
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
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverSwingTimer", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    -- Tenths of a second, rounded up so the last moment of a swing never reads 0.0.
    timeFormat = C_StringUtil.CreateNumericRuleFormatter()
    timeFormat:AddBreakpoint({ threshold = 0, step = 0.1,
        rounding = Enum.NumericRuleFormatRounding.Up, format = "%.1f" })
    for i = 1, #ROWS do
        local row = BuildRow(ROWS[i])
        rows[i], byType[ROWS[i].type] = row, row
        IdleRow(row)
    end
    frame.mover = UI.AttachMover(frame, "Swing Timer", function(pos) S.Set("swingPos", pos) end)
    local _, classFile = UnitClass("player")
    isHunter = classFile == "HUNTER"
    for _, q in ipairs(QUEUE_SPELLS[classFile] or {}) do
        local name = C_Spell.GetSpellName(q.id)
        if Plain(name) and name then
            q.name = name
            queueSpells[#queueSpells + 1] = q
        end
    end
    Place()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
    if event == "PLAYER_SWING" then
        -- a1 = swingDuration, a2 = swingType
        if not (Plain(a1) and Plain(a2)) then return end
        local row = byType[a2]
        if row then
            -- A swing proves its slot can swing, even while its speed reads restricted.
            if not row:IsShown() and S.Get(row.def.show) and not row.canSwing then
                row.canSwing = true
                RefreshRows()
            end
            if row:IsShown() and not unlocked then StartRow(row, a1) end
            -- Blizzard's own timer may have switched the shared range flag off since the last
            -- refresh; each swing puts ours back and re-reads.
            if row.rangeOn then
                C_SwingTimer.EnableRangeCheck(row.def.type, true)
                ReadRange(row)
            end
        end
        PaintQueue()
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        PaintQueue()
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        -- a1 = swingType, a2 = isInRange, a3 = checksRange
        if not (Plain(a1) and Plain(a2) and Plain(a3)) then return end
        local row = byType[a1]
        if row and row.rangeOn then SetOutOfRange(row, a3 == true and a2 == false) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        local tr = byType[TARGET]
        if tr.live then IdleRow(tr) end
        tr.canSwing, tr.targetSpeed = nil, nil
        RefreshRows()
    elseif event == "UNIT_COMBAT" then
        -- a1 = unit, a2 = action, a5 = schoolMask
        if not (Plain(a1) and Plain(a2) and Plain(a5)) then return end
        local tr = byType[TARGET]
        if not tr:IsShown() or unlocked then return end
        if a1 == "player" then
            if a5 ~= 1 or not SWING_ACTIONS[a2] then return end
            local onMe = UnitIsUnit("targettarget", "player")
            if not (Plain(onMe) and onMe) then return end
            local speed = UnitAttackSpeed("target")
            if not Plain(speed) then speed = tr.targetSpeed end
            if speed then StartRow(tr, speed) end
        elseif a2 == "PARRY" and tr.live then
            ParryHaste(tr)
        end
    elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
        moving = event == "PLAYER_STARTED_MOVING"
        UpdateWindow(byType[SWING.Ranged])
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        castEnd = nil
        UpdateCastTick()
    elseif event:find("^UNIT_SPELLCAST_") then
        ReadCast()
        UpdateCastTick()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
        UpdateVisibility()
    elseif event == "PLAYER_DEAD" then
        for i = 1, #rows do
            if rows[i].live then IdleRow(rows[i]) end
        end
        UpdateVisibility()
    elseif event == "WEAPON_SLOT_CHANGED" then
        RefreshRows()
        -- A swap restarts the swing at the new weapon's speed without a PLAYER_SWING, as
        -- Blizzard's own timer assumes too.
        local mh, oh, ranged = UnitAttackSpeed("player")
        local speeds = { [SWING.MainHand] = mh, [SWING.OffHand] = oh, [SWING.Ranged] = ranged }
        for t, speed in pairs(speeds) do
            local row = byType[t]
            if row.live and Plain(speed) then StartRow(row, speed) end
        end
    elseif event == "UNIT_ATTACK_SPEED" or event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
        if RowsChanged() then RefreshRows() end
    else
        -- PLAYER_ENTERING_WORLD
        RefreshRows()
    end
end)

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
    -- Fires constantly in combat, so only while there is a queued attack to watch for.
    if S.Get("queueHighlight") and #queueSpells > 0 then
        events:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    end
    if S.Get("targetSwing") then
        events:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
        -- A duel starting, a mob turning hostile, or the target dying.
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
end

local function Apply()
    if not SUPPORTED then return end
    unlocked = unlockActive and On() == true
    if not (On() or unlocked) then
        events:UnregisterAllEvents()
        if frame then
            for i = 1, #rows do
                if rows[i].live then IdleRow(rows[i]) end
                SetRangeCheck(rows[i], false)
            end
            frame:Hide()
        end
        return
    end
    if not frame then Build() end
    inCombat = UnitAffectingCombat("player")
    RegisterEvents()
    Place()
    frame.mover:SetShown(unlocked == true)
    queued = false
    PaintQueue()
    RefreshRows()
    Style()
    if unlocked then
        PaintSample()
    else
        -- A running swing picks up a changed fill direction or window; an idle bar repaints.
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
    UpdateCastTick()
    UpdateVisibility()
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
local function ColorRow(k, text, on, hasAlpha)
    return { type = "colorpicker", text = text, hasAlpha = hasAlpha,
        getValue = function() return Color(k) end,
        setValue = function(r, g, b, a)
            S.Set(k, { r = r, g = g, b = b, a = hasAlpha and a or nil })
        end,
        disabled = function() return not (S.Get("enabled") and S.Get(on)) end }
end

-- A row that needs every one of `keys` on; S.Slider and S.Toggle take only one.
local function Needs(cfg, ...)
    local keys = { ... }
    cfg.disabled = function()
        for i = 1, #keys do
            if not S.Get(keys[i]) then return true end
        end
        return false
    end
    return cfg
end

local function TextureChoices()
    local values, order = { [""] = "Flat" }, { "" }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            values[name] = name
            order[#order + 1] = name
        end
    end
    local cur = S.Get("texture")
    if cur ~= "" and not values[cur] then
        values[cur] = cur .. " (unavailable)"
        order[#order + 1] = cur
    end
    return values, order
end

local function UnsupportedNote(parent, y)
    local _, h = UI.Widgets:Note(parent, "The swing timer needs WoW: Forever's own swing "
        .. "event, which this client does not have.", y)
    return y - h
end

function ns.BuildSwingTimerPage(parent, y)
    if not SUPPORTED then return UnsupportedNote(parent, y) end
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "One bar per weapon, timed by the game's own swing event, so parry "
        .. "haste, swing resets and haste are always right. Move it in Unlock Mode.", y); y = y - h

    _, h = W:SectionHeader(parent, "WEAPON BARS", y); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Layout" .. UI.STATUS.untested }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("width", "Width", 80, 600, 1, nil, "enabled"),
        S.Slider("rowHeight", "Bar Height", 4, 40, 1, nil, "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("spacing", "Bar Spacing", 0, 20, 1, nil, "enabled"),
        S.Slider("textSize", "Text Size", 6, 24, 1, nil, "enabled")
    ); y = y - h
    local texValues, texOrder = TextureChoices()
    _, h = W:DualRow(parent, y,
        S.Dropdown("texture", "Bar Texture", texValues, texOrder, nil, "enabled"),
        S.Slider("bgAlpha", "Background Opacity", 0, 1, 0.05, nil, "enabled")
    ); y = y - h

    _, h = W:Feature(parent, y, { type = "label", text = "Bars" }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showMH", "Main Hand", nil, "enabled"),
        S.Toggle("showOH", "Off Hand", "Shown while you have a weapon in your off hand.", "enabled")
    ); y = y - h
    local showRow = S.Dropdown("visibility", "Show", { always = "Always", combat = "In Combat" },
        { "always", "combat" }, nil, "enabled")
    showRow.setValue = function(v) S.Set("visibility", v); UI:RefreshPage(true) end
    _, h = W:DualRow(parent, y,
        S.Toggle("showR", "Ranged", "Shown while you have a bow, gun, crossbow, wand or thrown weapon.",
            "enabled"),
        showRow
    ); y = y - h
    local idleRow = S.Toggle("hideWhenIdle", "Hide When Idle", "Hide the bars while no swing is running.", "enabled")
    idleRow.disabled = function() return not S.Get("enabled") or S.Get("visibility") == "always" end
    idleRow.disabledTooltip = "Only applies when Show is set to In Combat."
    _, h = W:DualRow(parent, y,
        idleRow,
        S.Toggle("depleteFill", "Deplete Fill", "Start each bar full and drain it, instead of filling it up.",
            "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showTime", "Show Time", "Seconds left to the next swing.", "enabled"),
        S.Toggle("showLabel", "Show Weapon Label", "MH, OH, R or TGT on each bar.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showSpark", "Show Spark", "A glow on the moving edge of the fill.", "enabled"),
        S.Toggle("rangeCheck", "Range Check",
            "Dim a bar and turn its text red while your target is out of that weapon's range.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Needs(S.Slider("outOfRangeAlpha", "Out of Range Opacity", 0, 1, 0.05), "enabled", "rangeCheck"),
        S.Toggle("classColored", "Class Colors", "Color the weapon bars in your class color.", "enabled")
    ); y = y - h

    _, h = W:Feature(parent, y, { type = "label", text = "Colours" }); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("mhColor", "Main Hand", "enabled"),
        ColorRow("ohColor", "Off Hand", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("rColor", "Ranged", "enabled")
    ); y = y - h

    _, h = W:SectionHeader(parent, "QUEUED ATTACKS", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("queueHighlight", "Highlight Queued Attacks",
            "While Heroic Strike, Cleave, Maul or Raptor Strike is queued, the melee bars take "
            .. "its color and name.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("queueColor", "Heroic Strike / Maul / Raptor Strike", "queueHighlight"),
        ColorRow("cleaveColor", "Cleave", "queueHighlight")
    ); y = y - h
    return y
end

function ns.BuildSwingTimerAidsPage(parent, y)
    if not SUPPORTED then return UnsupportedNote(parent, y) end
    local W = UI.Widgets
    local _, h
    local _, classFile = UnitClass("player")
    local hunter = classFile == "HUNTER"
    _, h = W:Note(parent, "Extra marks on the bars for timing what you press against your "
        .. "swings. Each one is off until you turn it on.", y); y = y - h

    _, h = W:SectionHeader(parent, "SWING END WINDOW" .. UI.STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("swingWindow", "Swing End Window",
            "Shade the last part of each melee swing: when to twist a seal, finish a weave or "
            .. "queue an attack before the hit.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        Needs(S.Slider("swingWindowTime", "Window Length (sec)", 0.1, 2, 0.05), "enabled", "swingWindow"),
        ColorRow("swingWindowColor", "Window Color", "swingWindow", true)
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("windowLatency", "Add Latency",
            "Widen the swing and Auto Shot windows by your world latency, so they show when "
            .. "to press rather than when the server acts.", "enabled"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "AUTO SHOT" .. UI.STATUS.untested, y); y = y - h
    local autoShot = S.Toggle("autoShotWindow", "Auto Shot Window",
        "Shade Auto Shot's cast at the end of the Ranged bar. It turns red while you move, "
        .. "since moving holds the shot.", "enabled")
    if not hunter then
        autoShot.disabled = function() return true end
        autoShot.disabledTooltip = "For Hunters only."
    end
    local stand = ColorRow("autoShotStandColor", "Standing Color", "autoShotWindow", true)
    local moveRow = ColorRow("autoShotMovingColor", "Moving Color", "autoShotWindow", true)
    if not hunter then
        stand.disabled = autoShot.disabled
        moveRow.disabled = autoShot.disabled
    end
    _, h = W:Feature(parent, y, autoShot); y = y - h
    _, h = W:DualRow(parent, y, stand, moveRow); y = y - h

    _, h = W:SectionHeader(parent, "CAST CLIP" .. UI.STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("castClip", "Cast Clip Marker",
            "While you cast, mark where the cast ends on the Main Hand bar. It turns red when "
            .. "the cast will still be going as the swing comes due.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("castOkColor", "Cast Fits Color", "castClip", true),
        ColorRow("castBadColor", "Cast Clips Color", "castClip", true)
    ); y = y - h

    _, h = W:SectionHeader(parent, "TARGET" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("targetSwing", "Target Swing Timer",
            "A bar for your target's swings, restarted by each physical hit you take while it "
            .. "is targeting you, and shortened when it parries. It is an estimate: the game "
            .. "does not say who hit you or with what, so other attackers, physical specials "
            .. "and bleed ticks restart it too.", "enabled"),
        ColorRow("tgtColor", "Target Color", "targetSwing")
    ); y = y - h
    return y
end

-- A slider drag sets its key on every step; apply once on the next frame.
hooksecurefunc(S, "Set", function(key)
    if key == "swingPos" or pendingApply then return end
    pendingApply = true
    C_Timer.After(0, function()
        pendingApply = false
        Apply()
    end)
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlockActive = true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlockActive = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
