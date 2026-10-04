-------------------------------------------------------------------------------
--  Quests.lua -- the quests that reward a pick on your list you do not have yet (ns.BiS.Quests),
--  by the zone they start in. The quests are the Dungeon Journal's records (its
--  Data/BiSQuests.lua), so its rules (what to do first, the level one needs, its chain, where
--  to go, tracking) work on them as on a dungeon's. The Journal loads after the BiS List, so
--  it is read when asked.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local Items = ns.Shared.Items

local Q = {}
B.Quests = Q

local ELSEWHERE = "Elsewhere"
-- Your race's bit in a quest's races mask (ChrRaces.PlayableRaceBit), by race ID: the
-- classic eight, and Forever's Skyborne.
local RACE_BITS = { [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 7, [95] = 32, [96] = 33 }

---@class BisQuestZone
---@field name string the zone the quests start in
---@field data { quests: JournalQuest[] } its quests, as a dungeon's quest data
---@field level number its lowest quest level, to order the zones
---@field out JournalQuestEntry[] its listed quests, the page's own
---@field pool JournalQuestEntry[]

local zones = {}     -- name -> BisQuestZone, reused
local shown = {}     -- the zones with a quest for you, in level order
local picked = {}    -- item ID -> on your list, this read
local picks = {}
local races = {}     -- questID -> the races that can take it, where it is limited
local zoneOf = {}    -- questID -> the zone it starts in, worked out once
local dungeonOf = {} -- questID -> the dungeon the Journal lists it under
local swapped = false

-- A quest the Journal lists already is its record there, with its versions, steps and the
-- spots they start at; its race limit is kept aside, as the Journal's rules know none.
local function Swap(J)
    swapped = true
    local byID = {}
    for _, dungeon in ipairs(J.QuestData) do
        for _, quest in ipairs(dungeon.quests) do
            byID[quest[1]], dungeonOf[quest[1]] = quest, dungeon.name
        end
    end
    local quests = J.BiSQuestData.quests
    for i, quest in ipairs(quests) do
        races[quest[1]] = quest.races
        quests[i] = byID[quest[1]] or quest
    end
end

-- Where it starts: the zone Wowhead maps its quest giver in, else the map of the Journal's
-- quest giver, else the dungeon it starts inside.
local function ZoneOf(J, quest)
    local id = quest[1]
    local zone = zoneOf[id]
    if not zone then
        local info = quest[7] and C_Map.GetMapInfo(quest[7])
        zone = J.BiSQuestZones[id] or info and info.name or dungeonOf[id] or ELSEWHERE
        zoneOf[id] = zone
    end
    return zone
end

-- Whether your race can take it: a race the mask does not know of is let through.
local function ForYourRace(questID, raceBit)
    local mask = races[questID]
    return not (mask and raceBit) or math.floor(mask / 2 ^ raceBit) % 2 == 1
end

---@return boolean available whether the Journal's quests are loaded
function Q.Available()
    local J = ns.Journal
    return J ~= nil and J.BiSQuestData ~= nil and J.Quests ~= nil
end

---@param questID number
---@return number[] items the ranked items it rewards
function Q.Rewards(questID)
    return ns.Journal.BiSQuestRewards[questID]
end

---@param questID number
---@return boolean choice whether they are a choice among its rewards
function Q.Choice(questID)
    return ns.Journal.BiSQuestChoices[questID] == true
end

---@param itemID number
---@return boolean wanted on your list (as read by the last Zones) and not yours yet
function Q.Wanted(itemID)
    return picked[itemID] == true and not Items.Owned(itemID)
end
local Wanted = Q.Wanted

local function Gives(questID)
    for _, id in ipairs(Q.Rewards(questID)) do
        if Wanted(id) then return true end
    end
    return false
end

local function ByLevel(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.name < b.name
end

--- The zones with a quest for your race that rewards a pick on the list you do not have yet,
--- lowest first, each with those quests as quest data for the Journal's rules. Tables reused:
--- the caller's until the next call.
---@param list table a BiS list
---@return BisQuestZone[]
function Q.Zones(list)
    wipe(shown)
    if not Q.Available() then return shown end
    local J = ns.Journal
    if not swapped then Swap(J) end
    wipe(picked)
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        for _, id in ipairs(B.Picks(list, gear[1], picks)) do picked[id] = true end
    end
    for _, zone in pairs(zones) do wipe(zone.data.quests) end
    local raceBit = RACE_BITS[select(3, UnitRace("player"))]
    for _, quest in ipairs(J.BiSQuestData.quests) do
        local id = quest[1]
        if ForYourRace(id, raceBit) and Gives(id) then
            local name = ZoneOf(J, quest)
            local zone = zones[name]
            if not zone then
                zone = { name = name, data = { quests = {} }, out = {}, pool = {} }
                zones[name] = zone
            end
            local quests = zone.data.quests
            if #quests == 0 then
                zone.level = quest[3]
                shown[#shown + 1] = zone
            end
            quests[#quests + 1] = quest
            if quest[3] < zone.level then zone.level = quest[3] end
        end
    end
    table.sort(shown, ByLevel)
    return shown
end

--- How many of those quests are for you to pick up or in your log, as the page lists them.
---@param list table
---@return number count
function Q.Count(list)
    local count = 0
    for _, zone in ipairs(Q.Zones(list)) do
        local toPickUp, inLog = ns.Journal.Quests.Count(zone.data)
        count = count + toPickUp + inLog
    end
    return count
end
