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
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemNameByID = C_Item.GetItemNameByID
local IsEquippedItem = C_Item.IsEquippedItem
local RequestLoadItemDataByID = C_Item.RequestLoadItemDataByID
local IsDressableItemByID = C_Item.IsDressableItemByID
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemLink = GetInventoryItemLink
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local IsBisItem = ns.IsBisItem
local ClassCanUse = ns.ClassCanUse
local BisSlotsFor = ns.BisSlotsFor
local Collection = C_TransmogCollection

local _, playerClass = UnitClass("player")

local RECIPE = 9   -- the game's item class for recipes; the subclass is the profession
-- A recipe's subclass -> its profession's skill line, as GetProfessionInfo names it. A book
-- (0) is no profession's: it is listed whatever yours are.
local RECIPE_SKILL = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333,
    [9] = 356, [10] = 755, [11] = 773 }

-- Adds the profession at the index to skills, by its skill line.
local function AddSkill(skills, index)
    if not index then return end
    local _, _, _, _, _, _, line = GetProfessionInfo(index)
    if line then skills[line] = true end
end

---@class JournalFilters  What is listed, read once per draw by Loot.ReadFilters.
---@field usableOnly boolean My Class Only
---@field myRecipes boolean My Professions Only
---@field showCosmetic boolean Show Cosmetic Items
---@field skills table<number, boolean> your professions, by skill line
---@field missingBis boolean Missing BiS Only, with the BiS List on
---@field upgradesOnly boolean Upgrades Only
---@field showAppearance boolean
---@field bisOn boolean the BiS List module is on

local Loot = {}
J.Loot = Loot

-- The BiS List module is on: without it there are no ranks or missing BiS, and upgrades go
-- by item level alone.
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
    out.myRecipes = S.Get("myRecipes")
    out.showCosmetic = S.Get("showCosmetic")
    -- Your professions' skill lines, for My Professions Only: GetProfessions answers each slot
    -- (first, second, then the secondary ones) with its index, or nil.
    local skills = out.skills or {}
    out.skills = wipe(skills)
    local a, b, c, d, e, f = GetProfessions()
    AddSkill(skills, a)
    AddSkill(skills, b)
    AddSkill(skills, c)
    AddSkill(skills, d)
    AddSkill(skills, e)
    AddSkill(skills, f)
    out.missingBis = out.bisOn and S.Get("missingBisOnly")
    out.upgradesOnly = S.Get("upgradesOnly")
    out.showAppearance = true   -- always: the hanger and the looks' counts are not a switch
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
-- have on. Missing BiS Only goes by this.
function Loot.BisUpgrade(itemID)
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
local BisUpgrade = Loot.BisUpgrade

-- The Upgrade mark: whether the item beats what you wear in a slot it fits. One on your BiS
-- list, when it is a higher pick than the piece of your list you wear there (with none of
-- your list there, its star says enough). One off it, when you can wear it now (your class,
-- your level) and its item level is higher than what you wear there, or the slot is empty;
-- never over a piece of your list. Never for an item you have on, nor a cosmetic one.
function Loot.Upgrade(itemID)
    if IsEquippedItem(itemID) then return false end
    local slots = BisSlotsFor(itemID)
    if not slots or Loot.Cosmetic(itemID) then return false end
    local rank = Rank(itemID)
    if rank then
        for i = 1, #slots do
            local worn = GetInventoryItemID("player", slots[i])
            local wornRank = worn and Rank(worn)
            if wornRank and rank < wornRank then return true end
        end
        return false
    end
    local facts = J.Items[itemID]
    local level = facts and facts[J.FACT.ITEM_LEVEL]
    if not level or (facts[J.FACT.REQUIRED] or 0) > UnitLevel("player") or not Loot.Usable(itemID) then
        return false
    end
    for i = 1, #slots do
        local worn = GetInventoryItemID("player", slots[i])
        if not worn then return true end
        if not Rank(worn) then
            local link = GetInventoryItemLink("player", slots[i])
            local wornLevel = link and GetDetailedItemLevelInfo(link)
            if wornLevel and level > wornLevel then return true end
        end
    end
    return false
end

-- Missing BiS: higher on your BiS list than what you wear, and not in your bags or bank.
function Loot.Missing(itemID)
    return BisUpgrade(itemID) and GetItemCount(itemID, true) == 0
end

-- A recipe's profession, as its subclass (0 a book, of none); nil for what is not a recipe.
---@return number? subclass
function Loot.Recipe(itemID)
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    if classID == RECIPE then return subclassID end
end
local Recipe = Loot.Recipe

-- A recipe for one of your professions, or a book (of none).
---@param filters JournalFilters
function Loot.RecipeYours(subclass, filters)
    local skill = RECIPE_SKILL[subclass]
    return skill == nil or filters.skills[skill] == true
end

---@param filters JournalFilters
---@return boolean listed My Class Only, Show Cosmetic Items, My Professions Only, Missing BiS
---Only and Upgrades Only, as the filters say
function Loot.Shown(itemID, filters)
    if filters.usableOnly and not Loot.Usable(itemID) then return false end
    if not filters.showCosmetic and Loot.Cosmetic(itemID) then return false end
    if filters.myRecipes then
        local subclass = Recipe(itemID)
        if subclass and not Loot.RecipeYours(subclass, filters) then return false end
    end
    if filters.missingBis and not Loot.Missing(itemID) then return false end
    if filters.upgradesOnly and not Loot.Upgrade(itemID) then return false end
    return true
end
local Shown = Loot.Shown

-- Something you wear: an item with a slot (a tabard and a shirt too). A recipe or a potion
-- has none, and no look of its own to collect: asked, the game answers with the look of the
-- item a recipe makes.
function Loot.Wearable(itemID)
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end
local Wearable = Loot.Wearable

-- A cosmetic item: a look any class can wear, with no stats (the game's armor subclass 5).
local ARMOR, COSMETIC = 4, 5

function Loot.Cosmetic(itemID)
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    return classID == ARMOR and subclassID == COSMETIC
end
local Cosmetic = Loot.Cosmetic

-- Gear that can go on your BiS list: an item for one of its slots (not a tabard or a shirt),
-- and not a cosmetic one.
function Loot.BisGear(itemID)
    return BisSlotsFor(itemID) ~= nil and not Cosmetic(itemID)
end

-- Whether you have the item's look: true when you have it, from this item or another with
-- the same look; false when you do not; nil for an item with no look to collect (rings,
-- trinkets, and anything not worn).
--
-- The game has no appearance for some items you can wear (Prison Shank on Forever 1.60.1:
-- GetItemInfo returns nothing, yet the item is dressable); for those, whether you have the
-- item's own look is all it can say.
---@return boolean?
function Loot.Appearance(itemID)
    if not Wearable(itemID) then return nil end
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

-- Whether you have the item: worn, or in your bags or bank.
local function Have(itemID)
    return IsEquippedItem(itemID) or GetItemCount(itemID, true) > 0
end

-- Adds to count and have how many of the items are your BiS (pick 1), and how many of those
-- you have: a boss's loot, a faction's rewards at one standing.
---@param items number[]
---@return number count
---@return number have
function Loot.ListBis(items, count, have)
    for i = 1, #items do
        if Rank(items[i]) == 1 then
            count = count + 1
            if Have(items[i]) then have = have + 1 end
        end
    end
    return count, have
end
local ListBis = Loot.ListBis

-- How many of your BiS (pick 1) the boss drops, and how many of those you have.
---@return number count
---@return number have
function Loot.BossBis(boss)
    if not boss.loot then return 0, 0 end
    return ListBis(boss.loot, 0, 0)
end

-- How many of your BiS the dungeon's listed bosses drop, and how many of those you have.
---@param filters JournalFilters
---@return number count
---@return number have
function Loot.DungeonBis(dungeon, filters)
    local count, have = 0, 0
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            local c, h = Loot.BossBis(boss)
            count, have = count + c, have + h
        end
    end
    return count, have
end

-- Adds to new and looks how many of the items listed for you have a look you do not have
-- yet, and how many have a look to collect at all.
---@param items number[]
---@param filters JournalFilters
---@return number new
---@return number looks
function Loot.ListNewLooks(items, filters, new, looks)
    for i = 1, #items do
        if Shown(items[i], filters) then
            local look = Appearance(items[i])
            if look ~= nil then looks = looks + 1 end
            if look == false then new = new + 1 end
        end
    end
    return new, looks
end
local ListNewLooks = Loot.ListNewLooks

-- How many looks you do not have yet among the loot the dungeon lists for you, and how many
-- of its items have a look to collect at all.
---@param filters JournalFilters
---@return number new
---@return number looks
function Loot.DungeonNewLooks(dungeon, filters)
    local count, looks = 0, 0
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            if boss.loot then
                count, looks = ListNewLooks(boss.loot, filters, count, looks)
            end
        end
    end
    return count, looks
end
