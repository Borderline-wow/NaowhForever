-------------------------------------------------------------------------------
--  NaowhForever_GcdTracker.lua -- the QoL GCD tracker: your recent casts as scrolling icons over
--  a bar of busy time and gaps. Only the player's own casts are read, and those are never secret.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

-- The blue glow and border while a cast runs; ns.ThemeTint swaps in the player's Accent.
local GCD_BLUE = { r = 0.01, g = 0.56, b = 0.91 }

-- A baseline spell per class with no cooldown of its own, so any cooldown it shows is the
-- global cooldown. Forever has no dedicated global cooldown spell.
local GCD_SPELLS = {
    WARRIOR = 6673, PALADIN = 635, HUNTER = 1978, ROGUE = 1752, PRIEST = 585,
    SHAMAN = 403, MAGE = 133, WARLOCK = 686, DRUID = 5176,
}

function ns.GCDSpell()
    return GCD_SPELLS[select(2, UnitClass("player"))]
end
local STACK_WINDOW = 0.3    -- casts this close together stack in lanes
local DEDUP_WINDOW = 0.15
local TIMELINE_GAP = 3
local UPDATE_INTERVAL = 0.025
local LOGIN_QUIET = 5       -- login and loading screens fire casts of their own

local DIRECTIONS = {
    LEFT = { x = -1, y = 0, px = 0, py = -1 }, RIGHT = { x = 1, y = 0, px = 0, py = -1 },
    UP = { x = 0, y = 1, px = 1, py = 0 }, DOWN = { x = 0, y = -1, px = 1, py = 0 },
}
local ZONE_KEYS = { party = "gcdDungeon", raid = "gcdRaid", pvp = "gcdPvP", arena = "gcdPvP" }

local frame, unlocked, inCombat, zoneAllowed = nil, false, false, true
local history, segments = {}, {}
local iconPool, segPool = {}, {}
local byGUID, lastBySpell, lastByName = {}, {}, {}
local channelName, quietUntil = nil, 0
local wasActive = false
local combatStart, downtime, idleSince, downtimeTicker = 0, 0, nil, nil
local blocked = {}
local acc = 0

local function On()
    return S.Get("enabled") and S.Get("gcdTracker")
end

local function Blocked(spellID)
    return blocked[spellID]
end

local function GCDActive()
    local info = C_Spell.GetSpellCooldown(ns.GCDSpell())
    return info and info.isOnGCD == true
end

local function Busy()
    return GCDActive() or UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

local function Fade(fraction)
    local start = S.Get("gcdFadeStart")
    if fraction <= start then return 1 end
    return math.max(0.05, 1 - (fraction - start) / (1 - start))
end

local function NewIcon()
    local f = CreateFrame("Frame", nil, frame)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    ns.PixelInset(f.glow, -1)
    local blue = ns.ThemeTint("accent", GCD_BLUE)
    f.glow:SetColorTexture(blue.r, blue.g, blue.b, 0.7)
    f.border = f:CreateTexture(nil, "BORDER")
    ns.PixelInset(f.border, -1)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return f
end

local function NewSeg()
    local f = CreateFrame("Frame", nil, frame)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    return f
end

local function Release(pool, f)
    f:Hide()
    f:ClearAllPoints()
    pool[#pool + 1] = f
end

-- casting: glowing blue while the cast runs. failed: red and greyed out.
local function Paint(f, entry, onGCD)
    if entry.casting or onGCD then
        f.glow:Show()
        f.tex:SetDesaturated(false)
        f.tex:SetVertexColor(1, 1, 1)
        local blue = ns.ThemeTint("accent", GCD_BLUE)
        f.border:SetColorTexture(blue.r, blue.g, blue.b, 0.8)
    elseif entry.failed then
        f.glow:Hide()
        f.tex:SetDesaturated(true)
        f.tex:SetVertexColor(1, 0.3, 0.3)
        f.border:SetColorTexture(0.8, 0.1, 0.1, 0.9)
    else
        f.glow:Hide()
        f.tex:SetDesaturated(false)
        f.tex:SetVertexColor(1, 1, 1)
        f.border:SetColorTexture(0, 0, 0, 0.8)
    end
end

local function Layout()
    local now = GetTime()
    local duration = S.Get("gcdDuration")
    local size, spacing = S.Get("gcdIconSize"), S.Get("gcdSpacing")
    local dir = DIRECTIONS[S.Get("gcdDirection")] or DIRECTIONS.RIGHT
    local speed = (size + spacing) * 1.5
    local gcdActive = GCDActive()

    while history[1] and now - history[1].time > duration do
        local entry = table.remove(history, 1)
        if entry.frame then Release(iconPool, entry.frame) end
        if entry.guid then byGUID[entry.guid] = nil end
    end

    local reach, lanes = 0, 0
    for _, entry in ipairs(history) do
        local f = entry.frame
        if not f then
            f = table.remove(iconPool) or NewIcon()
            f.tex:SetTexture(entry.icon)
            entry.frame = f
        end
        local age = now - entry.time
        local offset, lane = age * speed, entry.lane * (size + spacing)
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("CENTER", frame, "CENTER", dir.x * offset + dir.px * lane, dir.y * offset + dir.py * lane)
        Paint(f, entry, not entry.casting and not entry.failed and gcdActive and age < 2)
        f:SetAlpha(Fade(age / duration))
        f:Show()
        reach = math.max(reach, offset)
        lanes = math.max(lanes, entry.lane)
    end

    -- Activity bar: a segment per second of casting or global cooldown.
    local active = gcdActive or UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
    local last = segments[#segments]
    if active then
        if not last or last.stop or now - last.start >= 1 then
            if last and not last.stop then last.stop = now end
            segments[#segments + 1] = { start = now }
        end
    elseif wasActive and last and not last.stop then
        last.stop = now
    end
    wasActive = active

    while segments[1] and now - segments[1].start > duration do
        local seg = table.remove(segments, 1)
        if seg.frame then Release(segPool, seg.frame) end
    end

    local height = S.Get("gcdTimelineHeight")
    local c = S.Get("gcdTimelineColor")
    local perp = size / 2 + TIMELINE_GAP + height / 2
    for _, seg in ipairs(segments) do
        local startAge = math.min(now - seg.start, duration)
        local startOff, stopOff = startAge * speed, (seg.stop and now - seg.stop or 0) * speed
        local length, mid = math.max(1, startOff - stopOff), (startOff + stopOff) / 2
        local f = seg.frame
        if not f then
            f = table.remove(segPool) or NewSeg()
            seg.frame = f
        end
        f.tex:SetColorTexture(c.r, c.g, c.b, 0.6)
        f:ClearAllPoints()
        if dir.x ~= 0 then
            f:SetSize(length, height)
            f:SetPoint("CENTER", frame, "CENTER", dir.x * mid, -perp)
        else
            f:SetSize(height, length)
            f:SetPoint("CENTER", frame, "CENTER", perp, dir.y * mid)
        end
        f:SetAlpha(Fade(startAge / duration))
        f:Show()
    end
end

local function Visible()
    if unlocked then return true end
    if not On() then return false end
    if S.Get("gcdCombatOnly") and not inCombat then return false end
    return zoneAllowed
end

local function Add(spellID, casting, guid)
    local now = GetTime()
    local prev = history[#history]
    local lane = (S.Get("gcdStack") and prev and now - prev.time <= STACK_WINDOW) and prev.lane + 1 or 0
    local entry = { spellID = spellID, icon = C_Spell.GetSpellTexture(spellID) or 136243,
        time = now, lane = lane, casting = casting, guid = guid }
    history[#history + 1] = entry
    if guid then byGUID[guid] = entry end
end

local function OnSucceeded(guid, spellID)
    local tracked = guid and byGUID[guid]
    if tracked then
        tracked.casting = false
        return
    end
    if Blocked(spellID) then return end
    local now = GetTime()
    local name = C_Spell.GetSpellName(spellID)
    -- A channel's ticks come back as casts of the same name.
    if channelName and name == channelName then return end
    if (lastBySpell[spellID] and now - lastBySpell[spellID] < DEDUP_WINDOW)
        or (name and lastByName[name] and now - lastByName[name] < DEDUP_WINDOW) then
        return
    end
    lastBySpell[spellID] = now
    if name then lastByName[name] = now end
    Add(spellID, false, guid)
end

local function TrackDowntime()
    local busy = Busy()
    if not busy and not idleSince then
        idleSince = GetTime()
    elseif busy and idleSince then
        downtime = downtime + GetTime() - idleSince
        idleSince = nil
    end
end

local function CombatStart()
    inCombat = true
    if S.Get("gcdDowntime") then
        combatStart, downtime = GetTime(), 0
        idleSince = not Busy() and combatStart or nil
        if downtimeTicker then downtimeTicker:Cancel() end
        downtimeTicker = C_Timer.NewTicker(0.033, TrackDowntime)
    end
end

local function CombatEnd()
    inCombat = false
    if downtimeTicker then
        downtimeTicker:Cancel()
        downtimeTicker = nil
        if idleSince then downtime = downtime + GetTime() - idleSince end
        idleSince = nil
        local length = GetTime() - combatStart
        if length > 15 then
            ns.Print(("Downtime: %.1fs (%.1f%% of the fight)"):format(downtime, downtime / length * 100))
        end
    end
    wipe(lastBySpell)
    wipe(lastByName)
    local last = segments[#segments]
    if last and not last.stop then last.stop = GetTime() end
    wasActive = false
end

local function RefreshZone()
    local _, kind = IsInInstance()
    zoneAllowed = S.Get(ZONE_KEYS[kind] or "gcdWorld")
end

local function Place()
    local pos = S.Get("gcdTrackerPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, guid, spellID)
    if event == "PLAYER_REGEN_DISABLED" then
        CombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        CombatEnd()
    elseif event == "PLAYER_ENTERING_WORLD" then
        quietUntil = GetTime() + LOGIN_QUIET
        RefreshZone()
    elseif GetTime() >= quietUntil and Visible() then
        if event == "UNIT_SPELLCAST_START" then
            if not Blocked(spellID) then Add(spellID, true, guid) end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnSucceeded(guid, spellID)
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            local tracked = guid and byGUID[guid]
            if tracked then
                tracked.casting, tracked.failed = false, true
                byGUID[guid] = nil
            end
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            channelName = C_Spell.GetSpellName(spellID)
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            channelName = nil
        end
    end
    frame:SetShown(Visible())
end)

local function Apply()
    events:UnregisterAllEvents()
    if not (On() or unlocked) then
        if frame then frame:Hide() end
        if downtimeTicker then downtimeTicker:Cancel(); downtimeTicker = nil end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverGcdTracker", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:SetSize(200, 40)
        frame.mover = UI.AttachMover(frame, "GCD Tracker", function(pos) S.Set("gcdTrackerPos", pos) end)
        frame:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc < UPDATE_INTERVAL then return end
            acc = 0
            Layout()
        end)
    end
    Place()
    frame.mover:SetShown(unlocked == true)
    wipe(blocked)
    for id in S.Get("gcdBlocklist"):gmatch("%d+") do blocked[tonumber(id)] = true end
    inCombat = UnitAffectingCombat("player")
    RefreshZone()
    if On() then
        for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
            events:RegisterEvent(event)
        end
        for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
            "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
            events:RegisterUnitEvent(event, "player")
        end
    end
    frame:SetShown(Visible())
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^gcd") and key ~= "gcdTrackerPos") then Apply() end
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
boot:SetScript("OnEvent", function()
    quietUntil = GetTime() + LOGIN_QUIET
    Apply()
end)
