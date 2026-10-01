-------------------------------------------------------------------------------
--  Loot.lua -- what the Dungeon Journal's loot means for you (ns.Journal.Loot): whether your
--  class can use an item, where it sits on your BiS list, whether it beats what you wear,
--  whether you have its look, and how much of that a boss or a whole dungeon holds. Rules
--  only, no frames. The class rules and your BiS list are the BiS List module's (loaded
--  before this). What is listed follows filters the caller reads once (ReadFilters), not
--  the settings per item.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings

local GetItemCount = C_Item.GetItemCount
local GetItemNameByID = C_Item.GetItemNameByID
local IsEquippedItem = C_Item.IsEquippedItem
local RequestLoadItemDataByID = C_Item.RequestLoadItemDataByID
local IsDressableItemByID = C_Item.IsDressableItemByID
local GetInventoryItemID = GetInventoryItemID
local IsBisItem = ns.IsBisItem
local ClassCanUse = ns.ClassCanUse
local BisSlotsFor = ns.BisSlotsFor
local Collection = C_TransmogCollection

local _, playerClass = UnitClass("player")

---@class JournalFilters  What is listed, read once per draw by Loot.ReadFilters.
---@field usableOnly boolean My Class Only
---@field missingBis boolean Missing BiS Only, with the BiS List on
---@field showRare boolean
---@field showAppearance boolean
---@field bisOn boolean the BiS List module is on

local Loot = {}
J.Loot = Loot

-- The BiS List module is on: without it there are no ranks, upgrades or missing BiS.
function Loot.BisOn()
    return ns.QoLSettings.Get("bis") == true
end

-- Fills out with what is listed now, from the settings, and returns it. The caller owns out
-- and reuses it.
---@param out JournalFilters
---@return JournalFilters out
function Loot.ReadFilters(out)
    out.bisOn = Loot.BisOn()
    out.usableOnly = S.Get("usableOnly")
    out.missingBis = out.bisOn and S.Get("missingBisOnly")
    out.showRare = S.Get("showRare")
    out.showAppearance = S.Get("showAppearance")
    return out
end

-- True when your class can use it, or when the Journal knows nothing about the item.
function Loot.Usable(itemID)
    local facts = J.Items[itemID]
    return facts == nil or ClassCanUse(playerClass, facts)
end

---@return number? rank its pick number on your BiS list (1 is BiS); nil with the BiS List off
function Loot.Rank(itemID)
    return IsBisItem(itemID)
end
local Rank = Loot.Rank

-- True when the item is higher on your BiS list than what you wear in a slot it fits: that
-- slot is empty, or holds something not on the list or a lower pick. Never for an item you
-- have on.
function Loot.Upgrade(itemID)
    local rank = Rank(itemID)
    if not rank or IsEquippedItem(itemID) then return false end
    local slots = BisSlotsFor(itemID)
    if not slots then return false end
    for i = 1, #slots do
        local worn = GetInventoryItemID("player", slots[i])
        local wornRank = worn and Rank(worn)
        if not wornRank or rank < wornRank then return true end
    end
    return false
end
local Upgrade = Loot.Upgrade

-- Missing BiS: higher on your BiS list than what you wear, and not in your bags or bank.
function Loot.Missing(itemID)
    return Upgrade(itemID) and GetItemCount(itemID, true) == 0
end

---@param filters JournalFilters
---@return boolean listed My Class Only and Missing BiS Only, as the filters say
function Loot.Shown(itemID, filters)
    if filters.usableOnly and not Loot.Usable(itemID) then return false end
    if filters.missingBis and not Loot.Missing(itemID) then return false end
    return true
end
local Shown = Loot.Shown

-- Whether you have the item's look: true when you have it, from this item or another with
-- the same look; false when you do not; nil for an item with no look to collect (rings,
-- trinkets).
--
-- The game has no appearance for some items you can wear (Prison Shank on Forever 1.60.1:
-- GetItemInfo returns nothing, yet the item is dressable); for those, whether you have the
-- item's own look is all it can say.
---@return boolean?
function Loot.Appearance(itemID)
    local _, sourceID = Collection.GetItemInfo(itemID)
    local info = sourceID and Collection.GetAppearanceInfoBySource(sourceID)
    if info then return info.appearanceIsCollected or info.sourceIsCollected end
    if IsDressableItemByID(itemID) then return Collection.PlayerHasTransmogByItemInfo(itemID) end
    return nil
end
local Appearance = Loot.Appearance

-- The item's name in the player's language, or nil while the client has yet to load it; the
-- load is asked for, and GET_ITEM_INFO_RECEIVED brings it.
function Loot.Name(itemID)
    local name = GetItemNameByID(itemID)
    if not name then RequestLoadItemDataByID(itemID) end
    return name
end

-- The name in lower case, for search: kept once made, as a name does not change.
local lowerNames = {}

function Loot.LowerName(itemID)
    local lower = lowerNames[itemID]
    if lower then return lower end
    local name = Loot.Name(itemID)
    if not name then return nil end
    lower = name:lower()
    lowerNames[itemID] = lower
    return lower
end

---@param filters JournalFilters
function Loot.BossShown(boss, filters)
    return not boss.rare or filters.showRare
end

-- Whether you have the item: worn, or in your bags or bank.
local function Have(itemID)
    return IsEquippedItem(itemID) or GetItemCount(itemID, true) > 0
end

-- How many of your BiS (pick 1) the boss drops, and how many of those you have.
---@return number count
---@return number have
function Loot.BossBis(boss)
    local loot = boss.loot
    if not loot then return 0, 0 end
    local count, have = 0, 0
    for i = 1, #loot do
        if Rank(loot[i]) == 1 then
            count = count + 1
            if Have(loot[i]) then have = have + 1 end
        end
    end
    return count, have
end

-- How many of your BiS the dungeon's listed bosses drop, and how many of those you have.
---@param filters JournalFilters
---@return number count
---@return number have
function Loot.DungeonBis(dungeon, filters)
    local count, have = 0, 0
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            if Loot.BossShown(boss, filters) then
                local c, h = Loot.BossBis(boss)
                count, have = count + c, have + h
            end
        end
    end
    return count, have
end

-- How many looks you do not have yet among the loot the dungeon lists for you, and how many
-- of its items have a look to collect at all.
---@param filters JournalFilters
---@return number new
---@return number looks
function Loot.DungeonNewLooks(dungeon, filters)
    local count, looks = 0, 0
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            local loot = boss.loot
            if loot and Loot.BossShown(boss, filters) then
                for i = 1, #loot do
                    if Shown(loot[i], filters) then
                        local look = Appearance(loot[i])
                        if look ~= nil then looks = looks + 1 end
                        if look == false then count = count + 1 end
                    end
                end
            end
        end
    end
    return count, looks
end
