-- Marks.lua: the raid mark Mark Rare puts on a rare, and when it may (Completo.Marks).
local ns = _G.NaowhForever

local Completo = ns.Completo
local S = Completo.Settings
local R = Completo.Rares
local MARKS = Completo.RaidMarks

local KEY, INDEX, NAME = 1, 2, 3
local MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local PARTY_SIZE, RAID_SIZE = 4, 40
local CHOICE_ICON = "|T%s:14|t %s"
local TEXT_NONE = "None"

local SEEN_UNITS = { "target", "focus", "mouseover" }
for i = 1, PARTY_SIZE do SEEN_UNITS[#SEEN_UNITS + 1] = "party" .. i .. "target" end
for i = 1, RAID_SIZE do SEEN_UNITS[#SEEN_UNITS + 1] = "raid" .. i .. "target" end

local marked = {}

local Marks = {}
Completo.Marks = Marks

local function Find(key)
    for _, mark in ipairs(MARKS) do
        if mark[KEY] == key then return mark end
    end
end

local function MarkInUse(marker, guid)
    for _, unit in ipairs(SEEN_UNITS) do
        local index = GetRaidTargetIndex(unit)
        if R.IsSecret(index) then return true end
        if index == marker then
            local other = UnitGUID(unit)
            if R.IsSecret(other) or other ~= guid then return true end
        end
    end
    return false
end

function Marks.Marker()
    local mark = Find(S.Get("rareMarker"))
    return mark and mark[INDEX]
end

function Marks.Name(key)
    local mark = Find(key)
    return mark and mark[NAME]
end

function Marks.Icon(index)
    return MARK_ICON:format(index)
end

function Marks.MayMark()
    if not IsInGroup() then return true end
    if IsInInstance() or InCombatLockdown() then return false end
    if not IsInRaid() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function Marks.Mark(unit, guid, denied)
    local marker = Marks.Marker()
    if not marker or marked[guid] or not Marks.MayMark() then return nil end
    local index = GetRaidTargetIndex(unit)
    if R.IsSecret(index) or index or R.IsSecret(denied) or denied then return nil end
    if MarkInUse(marker, guid) then return nil end
    marked[guid] = true
    SetRaidTarget(unit, marker)
    return marker
end

function Marks.MarkTarget()
    local marker = Marks.Marker()
    if not marker or not Marks.MayMark() then return nil end
    local index = GetRaidTargetIndex("target")
    if R.IsSecret(index) or index == marker then return nil end
    SetRaidTarget("target", marker)
    return marker
end

function Marks.Choices()
    local values, order = { none = TEXT_NONE }, { "none" }
    for _, mark in ipairs(MARKS) do
        values[mark[KEY]] = CHOICE_ICON:format(Marks.Icon(mark[INDEX]), mark[NAME])
        order[#order + 1] = mark[KEY]
    end
    return values, order
end
