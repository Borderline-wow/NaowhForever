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
    classColored = false, themeColors = false,
    mhColor = { r = 0.90, g = 0.70, b = 0.27 },
    ohColor = { r = 0.90, g = 0.45, b = 0.27 },
    rColor = { r = 0.27, g = 0.73, b = 0.90 },
    queueHighlight = true,
    queueColor = { r = 1, g = 0.70, b = 0.20 },
    cleaveColor = { r = 0.95, g = 0.35, b = 0.25 },
    sealColors = false,
    sealRighteousColor = { r = 0.95, g = 0.85, b = 0.40 },
    sealCrusaderColor = { r = 0.95, g = 0.55, b = 0.20 },
    sealCommandColor = { r = 0.75, g = 0.35, b = 0.95 },
    sealJusticeColor = { r = 0.60, g = 0.65, b = 0.75 },
    sealLightColor = { r = 1, g = 0.95, b = 0.70 },
    sealWisdomColor = { r = 0.35, g = 0.65, b = 1 },
    sealFuryColor = { r = 0.95, g = 0.25, b = 0.20 },
    sealMartyrdomColor = { r = 0.90, g = 0.40, b = 0.70 },
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

-- Paladin seals by their first rank: every rank shares the seal's name, which is what is
-- matched. Seal of Fury is Forever's own. Judgement uses the seal up.
-- A seal lasts 30 seconds, 34 with the Seal Duration Increase item effect; a seal buff that can
-- be read replaces this with its real length.
local SEALS = {
    { id = 20154, key = "sealRighteousColor" },  -- Seal of Righteousness
    { id = 21082, key = "sealCrusaderColor" },   -- Seal of the Crusader
    { id = 20375, key = "sealCommandColor" },    -- Seal of Command
    { id = 20164, key = "sealJusticeColor" },    -- Seal of Justice
    { id = 20165, key = "sealLightColor" },      -- Seal of Light
    { id = 20166, key = "sealWisdomColor" },     -- Seal of Wisdom
    { id = 1311649, key = "sealFuryColor" },     -- Seal of Fury
    { id = 407798, key = "sealMartyrdomColor" },  -- Seal of Martyrdom
}
local JUDGEMENT = 20271

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
local sealByName, seal, judgementName = {}, false, nil
local sealTimer, sealSeconds = nil, 30
local isHunter, moving, latency, castEnd = false, false, 0, nil

local function On()
    return SUPPORTED and S.Get("enabled")
end

-- A restricted answer from the swing API or a unit query is "no information", never a value.
local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

-- Apply Theme to Bar Colours: the main hand bar in the theme's Accent, the off hand bar in its
-- lighter Accent and the ranged bar in a deeper shade of it, so the three stay apart.
local function ThemedBar(key)
    if key == "mhColor" then return T.accent.r, T.accent.g, T.accent.b, 1 end
    if key == "ohColor" then return T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1 end
    if key == "rColor" then return T.accent.r * 0.6, T.accent.g * 0.6, T.accent.b * 0.6, 1 end
end

local function Color(key)
    if S.Get("themeColors") then
        local r, g, b, a = ThemedBar(key)
        if r then return r, g, b, a end
    end
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

local Look = {}

function Look.Row(parent, def)
    local row = CreateFrame("Frame", nil, parent)
    row.def = def
    row.bg = ns.Solid(row, "BACKGROUND", T.bg, 0.6)
    row.bg:SetAllPoints()
    row.border = ns.Border(row)

    local bar = CreateFrame("StatusBar", nil, row)
    ns.PixelInset(bar, 1)
    bar:SetStatusBarTexture(FLAT_TEX)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar

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
    return row
end

function Look.Style(row, tex)
    local size, h = S.Get("textSize"), S.Get("rowHeight")
    row.bar:SetStatusBarTexture(tex)
    row.spark:ClearAllPoints()
    row.spark:SetPoint("CENTER", row.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    row.bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, S.Get("bgAlpha"))
    row.spark:SetSize(8, h * 2)
    row.tag:SetFont(ns.UIFontPath(), size, "OUTLINE")
    row.time:SetFont(ns.UIFontPath(), size, "OUTLINE")
    row.tag:SetShown(S.Get("showLabel"))
    row.time:SetShown(S.Get("showTime"))
end

function Look.BarColor(def)
    if S.Get("classColored") and not def.target then
        local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        if c then return c.r, c.g, c.b, 1 end
    end
    return Color(def.key .. "Color")
end

function Look.Tag(row, queuedName)
    if queuedName then
        row.tag:SetText(row.def.tag .. " - " .. queuedName)
    else
        row.tag:SetText(row.def.tag)
    end
end

-- Out of range: the whole bar dims and its text turns red, as Blizzard's own timer does.
function Look.Range(row, oor)
    row:SetAlpha(oor and S.Get("outOfRangeAlpha") or 1)
    local r, g, b = 1, 1, 1
    if oor then r, g, b = 1, 0.1, 0.1 end
    row.tag:SetTextColor(r, g, b)
    row.time:SetTextColor(r, g, b)
end

function Look.Window(row, share, r, g, b, a)
    local win = row.window
    local w = (S.Get("width") - 2) * math.min(share, 1)
    local side = S.Get("depleteFill") and "LEFT" or "RIGHT"
    win:ClearAllPoints()
    win:SetPoint("TOP" .. side, row.bar, "TOP" .. side, 0, 0)
    win:SetPoint("BOTTOM" .. side, row.bar, "BOTTOM" .. side, 0, 0)
    win:SetWidth(math.max(w, 1))
    win:SetColorTexture(r, g, b, a)
    win:Show()
end

function Look.Tick(row, frac, r, g, b, a)
    local tick = row.tick
    if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
    if S.Get("depleteFill") then frac = 1 - frac end
    local x = (S.Get("width") - 2) * frac
    tick:ClearAllPoints()
    tick:SetPoint("TOP", row.bar, "TOPLEFT", x, 0)
    tick:SetPoint("BOTTOM", row.bar, "BOTTOMLEFT", x, 0)
    tick:SetColorTexture(r, g, b, a)
    tick:Show()
end

local function BuildRow(def)
    local row = Look.Row(frame, def)
    row.dur = C_DurationUtil.CreateDuration()
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
    if def.melee and seal then return Color(seal.key) end
    return Look.BarColor(def)
end

local function PaintRow(row)
    row.bar:GetStatusBarTexture():SetVertexColor(RowColor(row))
    Look.Tag(row, row.def.melee and queued and queued.name)
end

local function PaintRange(row)
    Look.Range(row, row.outOfRange and not unlocked)
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
    local sec = (row.live or unlocked) and WindowSeconds(row)
    if not sec then row.window:Hide() return end
    local key
    if row.def.melee then key = "swingWindowColor"
    elseif moving then key = "autoShotMovingColor"
    else key = "autoShotStandColor" end
    Look.Window(row, sec / (row.swing or 2), Color(key))
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
    Look.Tick(row, (castEnd - (row.ends - row.swing)) / row.swing,
        Color(castEnd > row.ends and "castBadColor" or "castOkColor"))
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

local function SetSeal(s)
    if not s and sealTimer then
        sealTimer:Cancel()
        sealTimer = nil
    end
    if s == seal then return end
    seal = s
    for i = 1, #rows do
        if rows[i].def.melee then PaintRow(rows[i]) end
    end
end

-- Nothing in combat says a seal has run out, so it is counted from the cast, or from its buff
-- when that could be read.
local function RunOutIn(seconds)
    if sealTimer then sealTimer:Cancel() end
    sealTimer = C_Timer.NewTimer(seconds, function()
        sealTimer = nil
        SetSeal(false)
    end)
end

-- In combat the game keeps the player's auras from addons, so there the seal is the last one
-- cast; out of combat, and off a boss pull, the auras say which is up.
local function ReadSeal()
    if inCombat or C_Secrets.ShouldAurasBeSecret() then return end
    local found = false
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local s = Plain(aura.name) and sealByName[aura.name]
        if s then
            found = s
            local ends, length = aura.expirationTime, aura.duration
            if Plain(length) and type(length) == "number" and length > 0 then sealSeconds = length end
            if Plain(ends) and type(ends) == "number" and ends > 0 then
                RunOutIn(math.max(ends - GetTime(), 0))
            end
            break
        end
    end
    SetSeal(found)
end

local function SealCast(spellID)
    if not Plain(spellID) then return end
    local name = C_Spell.GetSpellName(spellID)
    if not Plain(name) or not name then return end
    if sealByName[name] then
        SetSeal(sealByName[name])
        RunOutIn(sealSeconds)
    elseif name == judgementName then
        SetSeal(false)
    end
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
    local tex = TexturePath()
    for i = 1, #rows do
        local row = rows[i]
        Look.Style(row, tex)
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
    frame.mover = UI.AttachMover(frame, "Swing Timer", function(pos) S.Set("swingPos", pos) end, "Swing Timer/Settings",
        "Swing Timer/Settings:bars")
    local _, classFile = UnitClass("player")
    isHunter = classFile == "HUNTER"
    for _, q in ipairs(QUEUE_SPELLS[classFile] or {}) do
        local name = C_Spell.GetSpellName(q.id)
        if Plain(name) and name then
            q.name = name
            queueSpells[#queueSpells + 1] = q
        end
    end
    if classFile == "PALADIN" then
        for _, s in ipairs(SEALS) do
            local name = C_Spell.GetSpellName(s.id)
            if Plain(name) and name then sealByName[name] = s end
        end
        local name = C_Spell.GetSpellName(JUDGEMENT)
        judgementName = Plain(name) and name or nil
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
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a3 = spellID
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
        inCombat = event == "PLAYER_REGEN_DISABLED"
        UpdateVisibility()
        if not inCombat and S.Get("sealColors") and next(sealByName) then ReadSeal() end
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
    seal = false
    if sealTimer then
        sealTimer:Cancel()
        sealTimer = nil
    end
    if S.Get("sealColors") and next(sealByName) then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterUnitEvent("UNIT_AURA", "player")
        ReadSeal()
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

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group

local OFF = "Turn on the Swing Timer"
local STAGE_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN = 120, 10, 11, 16
local SAMPLE_LATENCY = 0.06
local SAMPLES = {
    melee = { mh = { 0.55, "1.2" }, oh = { 0.3, "1.3" } },
    ranged = { r = { 0.75, "0.7" } },
    range = { mh = { 0.55, "1.2" }, oh = { 0.3, "1.3" }, oor = true },
    queued = { mh = { 0.7, "0.8" }, oh = { 0.45, "1.0" }, queued = true },
    target = { mh = { 0.55, "1.2" }, tgt = { 0.4, "1.2" } },
    parry = { mh = { 0.55, "1.2" }, tgt = { 0.8, "0.4" } },
    window = { mh = { 0.8, "0.5" }, oh = { 0.6, "0.7" }, window = true },
    standing = { r = { 0.85, "0.4" }, autoShot = true },
    moving = { r = { 0.85, "0.4" }, autoShot = true, moving = true },
    castOk = { mh = { 0.3, "1.8" }, cast = 0.75 },
    castBad = { mh = { 0.6, "1.0" }, cast = 1.3 },
}
local HEROIC_STRIKE = 78
local SAMPLE_SWING = 2.6

local function Enabled() return On() and true or false end
local function ClassIs(token) return select(2, UnitClass("player")) == token end
local function Hunter() return ClassIs("HUNTER") end
local function Paladin() return ClassIs("PALADIN") end
local function Needs(key) return function() return On() and S.Get(key) and true or false end end
local function NotThemed() return On() and not S.Get("themeColors") end
local function WhenIdle() return On() and S.Get("visibility") ~= "always" end
local function HunterOn() return On() and Hunter() end
local function PaladinOn() return On() and Paladin() end

local function Themed(key)
    return function() return Color(key) end
end

local function Picked(key)
    return function(r, g, b) S.Set(key, { r = r, g = g, b = b }) end
end

local function QueueName()
    local list = QUEUE_SPELLS[select(2, UnitClass("player"))]
    local id = list and list[1].id or HEROIC_STRIKE
    local name = C_Spell.GetSpellName(id)
    return Plain(name) and name or "Heroic Strike"
end

local function PreviewWindow(row, sample)
    local def = row.def
    local sec, key
    if sample.window and def.melee and S.Get("swingWindow") then
        sec, key = S.Get("swingWindowTime"), "swingWindowColor"
    elseif sample.autoShot and def.type == SWING.Ranged and S.Get("autoShotWindow") and Hunter() then
        sec, key = AUTO_SHOT_CAST, sample.moving and "autoShotMovingColor" or "autoShotStandColor"
    end
    if not sec then
        row.window:Hide()
        return
    end
    if S.Get("windowLatency") then sec = sec + SAMPLE_LATENCY end
    Look.Window(row, sec / SAMPLE_SWING, Color(key))
end

local function PaintSampleRow(row, part, sample)
    local def = row.def
    local fill = part[1]
    row.bar:SetValue(S.Get("depleteFill") and 1 - fill or fill)
    row.time:SetText(part[2])
    row.spark:SetShown(S.Get("showSpark"))
    local queuedName = sample.queued and def.melee and QueueName()
    if queuedName then
        row.bar:GetStatusBarTexture():SetVertexColor(Color("queueColor"))
    else
        row.bar:GetStatusBarTexture():SetVertexColor(Look.BarColor(def))
    end
    Look.Tag(row, queuedName)
    Look.Range(row, sample.oor and S.Get("rangeCheck") and not def.target)
    PreviewWindow(row, sample)
    if row.tick then
        if sample.cast then
            Look.Tick(row, sample.cast, Color(sample.cast > 1 and "castBadColor" or "castOkColor"))
        else
            row.tick:Hide()
        end
    end
end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.bars = CreateFrame("Frame", nil, preview)
    preview.rows = {}
    for i = 1, #ROWS do preview.rows[i] = Look.Row(preview.bars, ROWS[i]) end
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return preview
end

local function Fit(preview, n)
    local holder = preview.bars
    local w = S.Get("width")
    local h = math.max(n * S.Get("rowHeight") + (n - 1) * S.Get("spacing"), 1)
    holder:SetSize(w, h)
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2 - NOTE_Y * 2
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h * scale > roomH then scale = roomH / h end
    holder:SetScale(scale)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", preview, "CENTER", 0, NOTE_Y / scale)
end

local function PaintPreview(preview, state)
    local sample = SAMPLES[state]
    local tex = TexturePath()
    local h, sp, w = S.Get("rowHeight"), S.Get("spacing"), S.Get("width")
    local n = 0
    for _, row in ipairs(preview.rows) do
        local def = row.def
        local part = sample[def.key]
        if part and (def.target or S.Get(def.show)) then
            Look.Style(row, tex)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", preview.bars, "TOPLEFT", 0, -n * (h + sp))
            row:SetSize(w, h)
            PaintSampleRow(row, part, sample)
            row:Show()
            n = n + 1
        else
            row:Hide()
        end
    end
    Fit(preview, math.max(n, 1))
    local note = ""
    if n == 0 then
        note = "No bar for this is switched on."
    elseif sample.autoShot and not Hunter() then
        note = "Hunters only."
    elseif state == "parry" then
        note = "A parry by your target took 40% off its swing."
    end
    preview.note:SetText(note)
end

local function Studio(states)
    return { height = STAGE_H, states = states, new = NewPreview, paint = PaintPreview }
end

local BAR_STATES = {
    { key = "melee", label = "Melee", tip = "Your weapons mid-swing." },
    { key = "ranged", label = "Ranged", tip = "Your ranged weapon between shots." },
    { key = "range", label = "Out of Range", tip = "Your target out of your weapons' reach.", needs = "rangeCheck" },
}
local QUEUE_STATES = {
    { key = "queued", label = "Queued", tip = "An on-next-swing attack queued on the melee bars." },
}
local TARGET_STATES = {
    { key = "target", label = "Target Swing", tip = "Your target's swing, restarted by its last hit on you." },
    { key = "parry", label = "Parry Haste", tip = "Your target parried, which cut its swing short." },
}
local WINDOW_STATES = {
    { key = "window", label = "Swing End", tip = "The last part of each melee swing, shaded." },
}
local AUTO_SHOT_STATES = {
    { key = "standing", label = "Standing", tip = "Auto Shot's cast while you stand still." },
    { key = "moving", label = "Moving", tip = "Moving holds the shot, so the window turns red." },
}
local CAST_STATES = {
    { key = "castOk", label = "Cast Fits", tip = "Your cast ends before the swing comes due." },
    { key = "castBad", label = "Cast Clips", tip = "Your cast will still be going as the swing comes due." },
}

local function Shown()
    local names = {}
    if S.Get("showMH") then names[#names + 1] = "Main Hand" end
    if S.Get("showOH") then names[#names + 1] = "Off Hand" end
    if S.Get("showR") then names[#names + 1] = "Ranged" end
    if S.Get("targetSwing") then names[#names + 1] = "Target" end
    return names
end

local function Headline()
    if not SUPPORTED then return "This client has no swing event" end
    if not S.Get("enabled") then return "Swing Timer is off" end
    local names = Shown()
    if #names == 0 then return "No bars switched on" end
    return "Bars for " .. table.concat(names, ", ")
end

local function Detail()
    if not SUPPORTED then return "The swing timer needs WoW: Forever's own swing event." end
    local aids = {}
    if S.Get("swingWindow") then aids[#aids + 1] = "Swing End Window" end
    if S.Get("autoShotWindow") then aids[#aids + 1] = "Auto Shot Window" end
    if S.Get("castClip") then aids[#aids + 1] = "Cast Clip Marker" end
    local shown = S.Get("visibility") == "always" and "Shown all the time." or "Shown in combat."
    if #aids == 0 then return shown .. " Move the bars with Move Elements." end
    return shown .. " With " .. table.concat(aids, ", ") .. "."
end

local function BarsSummary(store)
    return ("%d by %d, %s"):format(store.Get("width"), store.Get("rowHeight"),
        store.Get("visibility") == "always" and "always shown" or "in combat")
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

local SHOW = { { always = "Always", combat = "In Combat" }, { "always", "combat" } }

local page = Settings.Page("Swing Timer/Settings", S)

page:Window({
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "bars", name = "Bars", order = 10,
    help = "One bar per weapon, timed by the game's own swing event, so parry haste, swing resets and "
        .. "haste are always right. Move them with Move Elements.",
    summary = BarsSummary,
    studio = SUPPORTED and Studio(BAR_STATES) or nil,
    rows = {
        Group("Bars"),
        { key = "showMH", label = "Main Hand", toggle = true, needs = Enabled, why = OFF },
        { key = "showOH", label = "Off Hand", toggle = true, needs = Enabled, why = OFF,
          help = "Shown while you have a weapon in your off hand." },
        { key = "showR", label = "Ranged", toggle = true, needs = Enabled, why = OFF,
          help = "Shown while you have a bow, gun, crossbow, wand or thrown weapon." },
        { key = "visibility", label = "Show", choice = SHOW, needs = Enabled, why = OFF },
        { key = "hideWhenIdle", label = "Hide When Idle", toggle = true, needs = WhenIdle,
          why = "Only with Show In Combat", help = "Hide the bars while no swing is running." },
        Group("Layout"),
        { key = "width", label = "Width", slider = { 80, 600, 1 }, needs = Enabled, why = OFF },
        { key = "rowHeight", label = "Bar Height", slider = { 4, 40, 1 }, needs = Enabled, why = OFF },
        { key = "spacing", label = "Bar Spacing", slider = { 0, 20, 1 }, needs = Enabled, why = OFF },
        { key = "textSize", label = "Text Size", slider = { 6, 24, 1 }, needs = Enabled, why = OFF },
        { key = "texture", label = "Bar Texture", choice = TextureChoices, needs = Enabled, why = OFF },
        { key = "bgAlpha", label = "Background Opacity", slider = { 0, 100, 5 }, unit = "%", scale = 0.01,
          needs = Enabled, why = OFF },
        Group("Shown"),
        { key = "depleteFill", label = "Deplete Fill", toggle = true, needs = Enabled, why = OFF,
          help = "Start each bar full and drain it, instead of filling it up." },
        { key = "showTime", label = "Show Time", toggle = true, needs = Enabled, why = OFF,
          help = "Seconds left to the next swing." },
        { key = "showLabel", label = "Show Weapon Label", toggle = true, needs = Enabled, why = OFF,
          help = "MH, OH, R or TGT on each bar." },
        { key = "showSpark", label = "Show Spark", toggle = true, needs = Enabled, why = OFF,
          help = "A glow on the moving edge of the fill." },
        Group("Range"),
        { key = "rangeCheck", label = "Range Check", toggle = true, needs = Enabled, why = OFF,
          help = "Dim a bar and turn its text red while your target is out of that weapon's range." },
        { key = "outOfRangeAlpha", label = "Out of Range Opacity", slider = { 0, 100, 5 }, unit = "%",
          scale = 0.01, needs = Needs("rangeCheck"), why = "Needs Range Check" },
        Group("Colours"),
        { key = "classColored", label = "Class Colours", toggle = true, needs = Enabled, why = OFF,
          help = "Colour the weapon bars in your class colour." },
        { key = "themeColors", label = "Apply Theme to Bar Colours", toggle = true, needs = Enabled, why = OFF,
          help = "Colour the main hand bar with your theme's Accent, the off hand bar with its lighter Accent "
              .. "and the ranged bar with a deeper shade of it, instead of the colours picked here." },
        { key = "mhColor", label = "Main Hand Colour", colour = true, get = Themed("mhColor"),
          set = Picked("mhColor"), needs = NotThemed, why = "Apply Theme to Bar Colours is on" },
        { key = "ohColor", label = "Off Hand Colour", colour = true, get = Themed("ohColor"),
          set = Picked("ohColor"), needs = NotThemed, why = "Apply Theme to Bar Colours is on" },
        { key = "rColor", label = "Ranged Colour", colour = true, get = Themed("rColor"),
          set = Picked("rColor"), needs = NotThemed, why = "Apply Theme to Bar Colours is on" },
    },
})

page:Card({
    id = "queued", name = "Queued Attacks", order = 20, switch = "queueHighlight",
    help = "While Heroic Strike, Cleave, Maul or Raptor Strike is queued, the melee bars take its colour "
        .. "and name.",
    studio = SUPPORTED and Studio(QUEUE_STATES) or nil,
    rows = {
        { key = "queueColor", label = "Queued Attack Colour", colour = true, needs = Enabled, why = OFF,
          help = "Heroic Strike, Maul or Raptor Strike." },
        { key = "cleaveColor", label = "Cleave Colour", colour = true, needs = Enabled, why = OFF },
    },
})

page:Card({
    id = "seals", name = "Seal Colours", order = 30, switch = "sealColors",
    help = "Paladins only. The melee bars take the colour of the seal you have up. In combat that is the "
        .. "last seal you cast until a Judgement uses it up or it runs out, as the game keeps your buffs "
        .. "from addons there; out of combat it is read from your buffs.",
    rows = {
        { key = "sealRighteousColor", label = "Seal of Righteousness", colour = true, needs = PaladinOn,
          why = "Paladins only" },
        { key = "sealCrusaderColor", label = "Seal of the Crusader", colour = true, needs = PaladinOn,
          why = "Paladins only" },
        { key = "sealCommandColor", label = "Seal of Command", colour = true, needs = PaladinOn,
          why = "Paladins only" },
        { key = "sealJusticeColor", label = "Seal of Justice", colour = true, needs = PaladinOn,
          why = "Paladins only" },
        { key = "sealLightColor", label = "Seal of Light", colour = true, needs = PaladinOn,
          why = "Paladins only" },
        { key = "sealWisdomColor", label = "Seal of Wisdom", colour = true, needs = PaladinOn,
          why = "Paladins only" },
        { key = "sealFuryColor", label = "Seal of Fury", colour = true, needs = PaladinOn,
          why = "Paladins only" },
        { key = "sealMartyrdomColor", label = "Seal of Martyrdom", colour = true, needs = PaladinOn,
          why = "Paladins only" },
    },
})

page:Card({
    id = "target", name = "Target Swing Timer", order = 40, switch = "targetSwing",
    help = "A bar for your target's swings, restarted by each physical hit you take while it is targeting "
        .. "you, and shortened when it parries. It is an estimate: the game does not say who hit you or "
        .. "with what, so other attackers, physical specials and bleed ticks restart it too.",
    studio = SUPPORTED and Studio(TARGET_STATES) or nil,
    rows = {
        { key = "tgtColor", label = "Target Colour", colour = true, needs = Enabled, why = OFF },
    },
})

page:Card({
    id = "swingWindow", name = "Swing End Window", order = 50, switch = "swingWindow",
    help = "Shade the last part of each melee swing: when to twist a seal, finish a weave or queue an "
        .. "attack before the hit.",
    studio = SUPPORTED and Studio(WINDOW_STATES) or nil,
    rows = {
        { key = "swingWindowTime", label = "Window Length", slider = { 0.1, 2, 0.05 }, unit = "s",
          needs = Enabled, why = OFF },
        { key = "swingWindowColor", label = "Window Colour", colour = "alpha", needs = Enabled, why = OFF },
        { key = "windowLatency", label = "Add Latency", toggle = true, always = true, needs = Enabled, why = OFF,
          help = "Widen the swing and Auto Shot windows by your world latency, so they show when to press "
              .. "rather than when the server acts." },
    },
})

page:Card({
    id = "autoShot", name = "Auto Shot Window", order = 60, switch = "autoShotWindow",
    help = "Hunters only. Shade Auto Shot's cast at the end of the Ranged bar. It turns red while you move, "
        .. "since moving holds the shot.",
    studio = SUPPORTED and Studio(AUTO_SHOT_STATES) or nil,
    rows = {
        { key = "autoShotStandColor", label = "Standing Colour", colour = "alpha", needs = HunterOn,
          why = "Hunters only" },
        { key = "autoShotMovingColor", label = "Moving Colour", colour = "alpha", needs = HunterOn,
          why = "Hunters only" },
    },
})

page:Card({
    id = "castClip", name = "Cast Clip Marker", order = 70, switch = "castClip",
    help = "While you cast, mark where the cast ends on the Main Hand bar. It turns red when the cast will "
        .. "still be going as the swing comes due.",
    studio = SUPPORTED and Studio(CAST_STATES) or nil,
    rows = {
        { key = "castOkColor", label = "Cast Fits Colour", colour = "alpha", needs = Enabled, why = OFF },
        { key = "castBadColor", label = "Cast Clips Colour", colour = "alpha", needs = Enabled, why = OFF },
    },
})
