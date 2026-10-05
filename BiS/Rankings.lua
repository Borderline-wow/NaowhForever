-------------------------------------------------------------------------------
--  Rankings.lua -- what the data says (ns.BiS.Rankings): wowsrc.com's ranking per spec,
--  the dungeon drops your class can use, where an item comes from, and where to go next for
--  the BiS you do not have. Rules only, no frames.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local Items = ns.Shared.Items
local Fits, Wearing = Items.Fits, Items.Wearing

local R = {}
B.Rankings = R

local _, playerClass = UnitClass("player")
local EMPTY = {}

-------------------------------------------------------------------------------
--  wowsrc.com rankings
-------------------------------------------------------------------------------
local classSpecs

-- Your class's specs in the data, made once.
function R.ClassSpecs()
    if not classSpecs then
        classSpecs = {}
        for _, spec in ipairs(ns.BiSData.specs) do
            if spec.class == playerClass then classSpecs[#classSpecs + 1] = spec end
        end
    end
    return classSpecs
end

-- A slot's ranked items under a spec key, else under the class's first spec.
function R.Ranking(key, slot)
    for _, spec in ipairs(ns.BiSData.specs) do
        if spec.key == key then return spec.slots[slot] end
    end
    local spec = R.ClassSpecs()[1]
    return spec and spec.slots[slot]
end

local rankPos = {}
local function ByRank(a, b)
    local pa, pb = rankPos[a] or math.huge, rankPos[b] or math.huge
    if pa ~= pb then return pa < pb end
    return a < b
end

-- A set of item IDs as a list in ranked order, anything unranked last.
function R.Ranked(set, order)
    wipe(rankPos)
    order = order or EMPTY
    for i = #order, 1, -1 do rankPos[order[i]] = i end
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids, ByRank)
    return ids
end

-- The slot's ranked items the running client knows; an unknown ID never finishes loading.
function R.Candidates(slot, spec)
    local ids = {}
    for _, id in ipairs(spec and spec.slots[slot] or EMPTY) do
        if C_Item.GetItemInfoInstant(id) then ids[#ids + 1] = id end
    end
    return ids
end

-------------------------------------------------------------------------------
--  What a class can use, as in classic: an item's facts are { class, subclass, item level,
--  required level } (the Dungeon Journal's Data/Items.lua's)
-------------------------------------------------------------------------------
-- Mail and plate are learned at 40.
local ARMOR = { MAGE = 1, PRIEST = 1, WARLOCK = 1, ROGUE = 2, DRUID = 2, HUNTER = 3, SHAMAN = 3,
    WARRIOR = 4, PALADIN = 4 }
local ARMOR_BEFORE_40 = { HUNTER = 2, SHAMAN = 2, WARRIOR = 3, PALADIN = 3 }
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIC = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }
-- Enum.ItemWeaponSubclass values each class can learn.
local WEAPONS = {
    DRUID = { 4, 5, 10, 13, 15 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    MAGE = { 7, 10, 15, 19 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    PRIEST = { 4, 10, 15, 19 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    WARLOCK = { 7, 10, 15, 19 },
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
}
for class, subs in pairs(WEAPONS) do
    local set = {}
    for _, sub in ipairs(subs) do set[sub] = true end
    WEAPONS[class] = set
end

function R.Usable(class, item)
    local itemClass, sub, req = item[1], item[2], item[4]
    if itemClass == 2 then return WEAPONS[class][sub] == true end
    if sub == 0 then return true end
    if sub == 6 then return SHIELD[class] == true end
    if RELIC[sub] then return RELIC[sub] == class end
    return sub == (req < 40 and ARMOR_BEFORE_40[class] or ARMOR[class])
end
ns.ClassCanUse = R.Usable
ns.BisSlotsFor = Items.SlotsFor

-------------------------------------------------------------------------------
--  What drops in a dungeon, and where: the Dungeon Journal's, so the BiS List and the
--  Journal always list the same items under the same bosses and dungeons. The Journal loads
--  after the BiS List: read the first time it is asked.
-------------------------------------------------------------------------------
local SOURCE_SEP = " \194\183 "   -- the middle dot wowsrc puts between boss and place
R.SOURCE_SEP = SOURCE_SEP
local TRASH = "Trash drop"

local drops     -- item ID -> "Boss . Dungeon": the boss likeliest to drop it, before trash
local dropDungeon = {}   -- item ID -> that boss's dungeon, to open it in the Journal
local dropIDs   -- every item a dungeon drops, in the Journal's order

local function Drops()
    if drops then return drops end
    local J = ns.Journal
    if not (J and J.Dungeons) then return EMPTY end
    drops, dropIDs = {}, {}
    local best, notYet = {}, J.NotYet or EMPTY
    for _, dungeon in ipairs(J.Dungeons()) do
        for _, wing in ipairs(dungeon.wings) do
            for _, boss in ipairs(wing.bosses) do
                local who = (boss.trash and TRASH or boss.name) .. SOURCE_SEP .. dungeon.name
                for i, id in ipairs(boss.loot or EMPTY) do
                    local chance = boss.trash and -1 or boss.chance and boss.chance[i] or 0
                    if not notYet[id] then
                        if not drops[id] then dropIDs[#dropIDs + 1] = id end
                        if not drops[id] or chance > best[id] then
                            drops[id], best[id], dropDungeon[id] = who, chance, dungeon
                        end
                    end
                end
            end
        end
    end
    return drops
end

-- What the Journal knows of an item before the client loads it: { class, subclass, item
-- level, required level, quality }.
local function Facts(itemID)
    local J = ns.Journal
    return J and J.Items and J.Items[itemID]
end

local function ByLevel(a, b)
    local fa, fb = Facts(a), Facts(b)
    if fa[4] ~= fb[4] then return fa[4] > fb[4] end
    if fa[3] ~= fb[3] then return fa[3] > fb[3] end
    return a < b
end

-- Dungeon drops for the slot that your class can use and the ranking leaves out, highest
-- required level first; near keeps only those within 10 levels of yours.
function R.DungeonDrops(slot, ranked, near)
    Drops()
    local level = UnitLevel("player")
    local skip = {}
    for _, id in ipairs(ranked) do skip[id] = true end
    local ids = {}
    for _, id in ipairs(dropIDs or EMPTY) do
        local item = Facts(id)
        if item and not skip[id] and (item[1] == 2 or item[1] == 4) and item[5] >= 2
            and R.Usable(playerClass, item) and Fits(id, slot)
            and not (slot == 17 and item[1] == 2 and not DUAL_WIELD[playerClass])
            and (not near or math.abs(item[4] - level) <= 10) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, ByLevel)
    return ids
end

-------------------------------------------------------------------------------
--  Where an item comes from
-------------------------------------------------------------------------------
-- The Journal's boss and dungeon for what drops in one, else wowsrc's wording (a quest,
-- crafted, a zone).
function ns.BiSSource(itemID)
    return Drops()[itemID] or ns.BiSData.sources[itemID]
end

-- The Journal's dungeon an item drops in, or nil.
---@return JournalDungeon?
function R.DropDungeon(itemID)
    Drops()
    return dropDungeon[itemID]
end

function R.ReqLevel(itemID)
    local item = Facts(itemID)
    return item and item[4] or select(5, C_Item.GetItemInfo(itemID))
end

function R.ItemLevel(itemID)
    local item = Facts(itemID)
    return item and item[3]
end

-- The place in a source, and the boss or detail before it. Sources are the data's, so each
-- is split once.
local PLACE_PATTERN = "^(.*)" .. SOURCE_SEP .. "(.+)$"
local places, details = {}, {}

function R.Place(source)
    local place = places[source]
    if not place then
        local detail
        detail, place = source:match(PLACE_PATTERN)
        place = place or source
        places[source], details[source] = place, detail or false
    end
    return place, details[source] or nil
end

-- Sources that are not somewhere to go.
local NOT_A_PLACE = { Crafted = true, Quest = true, ["Quest (Horde)"] = true, ["Quest (Alliance)"] = true,
    ["Quest Reward"] = true, ["World drop"] = true, Reputation = true }

local function Owned(slot, id)
    return Wearing(slot, id) or C_Item.GetItemCount(id, true) > 0
end

-- How many of your BiS you have, worn or in your bags or bank, and how many there are.
function R.Had(list)
    local have, total = 0, 0
    local idle = B.OffHandIdle(list)
    for slot in pairs(Items.SLOT_NAME) do
        local id = list.slots[slot]
        if id and not (slot == 17 and idle) then
            total = total + 1
            if Items.Owned(id) then have = have + 1 end
        end
    end
    return have, total
end

-- The place that makes you strongest first, then the one with the most of your BiS.
local function ByGain(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    if a.bis ~= b.bis then return a.bis > b.bis end
    return a.name < b.name
end

local nextPlaces, byName, placePool = {}, {}, {}

-- The places with BiS you do not have yet, the ones that make you strongest first (by gains,
-- Upgrades.Read's percent per slot; without, the most BiS first), at most three, reused by
-- the next call: { name, bis, gain (percent, summed), slots (in gear order), mask (2 ^ slot
-- summed), key (a number for the items there) }.
function R.RunNext(list, gains)
    local found = wipe(nextPlaces)
    wipe(byName)
    local idle = B.OffHandIdle(list)
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        local id = not (slot == 17 and idle) and list.slots[slot]
        local source = id and ns.BiSSource(id)
        local name, detail = nil, nil
        if source then name, detail = R.Place(source) end
        -- Not a place, but somewhere a click goes all the same: a quest by its name, a craft by
        -- its profession, a faction's reward by the faction (BiS/Sources.lua). A world drop is
        -- nowhere to go.
        local kind
        if name and NOT_A_PLACE[name] then
            local target
            kind, target = B.Sources.Of(id)
            if kind == "faction" then
                name = target.name
            elseif (kind == "quest" or kind == "recipe") and detail then
                name = detail
            else
                name, kind = nil, nil
            end
        else
            kind = nil
        end
        if name and not Owned(slot, id) then
            local place = byName[name]
            if not place then
                place = placePool[#found + 1] or { slots = {} }
                placePool[#found + 1] = place
                place.name, place.bis, place.gain, place.mask, place.key = name, 0, 0, 0, 0
                place.kind, place.via = kind, kind and id or nil
                wipe(place.slots)
                byName[name] = place
                found[#found + 1] = place
            end
            place.bis = place.bis + 1
            place.gain = place.gain + (gains and gains[slot] or 0)
            place.slots[place.bis] = slot
            place.mask = place.mask + 2 ^ slot
            place.key = place.key + id * slot
        end
    end
    table.sort(found, ByGain)
    for i = #found, 4, -1 do found[i] = nil end
    return found
end
