-- Loot.lua: the Dungeon Journal's loot rules: what is listed, BiS ranks, upgrades and looks (J.Loot).
local ns = _G.NaowhForever

local GetItemCount = C_Item.GetItemCount
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemNameByID = C_Item.GetItemNameByID
local IsEquippedItem = C_Item.IsEquippedItem
local RequestLoadItemDataByID = C_Item.RequestLoadItemDataByID
local IsDressableItemByID = C_Item.IsDressableItemByID
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemLink = GetInventoryItemLink
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local Collection = C_TransmogCollection

local J = ns.Journal
local S = J.Settings
local Refused = ns.Shared.Items.Refused
local ClassCanUse = ns.Shared.Items.ClassCanUse
local BisSlotsFor = ns.Shared.Items.SlotsFor
local IsBisItem = ns.IsBisItem
local FACT = J.FACT

local RECIPE = J.C.ITEM_RECIPE
local ARMOR, COSMETIC = J.C.ITEM_ARMOR, 5
local SKILL_LINE = 7
local BIS_PICK = 1
local NOT_WORN = "INVTYPE_NON_EQUIP_IGNORE"
local RECIPE_SKILL = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333,
    [9] = 356, [10] = 755, [11] = 773 }

local _, playerClass = UnitClass("player")
local lowerNames = {}

local function AddSkill(skills, index)
    if not index then return end
    local line = select(SKILL_LINE, GetProfessionInfo(index))
    if line then skills[line] = true end
end

local function ReadSkills(skills)
    wipe(skills)
    local a, b, c, d, e, f = GetProfessions()
    AddSkill(skills, a)
    AddSkill(skills, b)
    AddSkill(skills, c)
    AddSkill(skills, d)
    AddSkill(skills, e)
    AddSkill(skills, f)
    return skills
end

local function Lower(itemID, name)
    if not name then return nil end
    local lower = name:lower()
    lowerNames[itemID] = lower
    return lower
end

local function Have(itemID)
    return IsEquippedItem(itemID) or GetItemCount(itemID, true) > 0
end

local Loot = {}
J.Loot = Loot

function Loot.BisOn()
    return IsBisItem ~= nil and ns.QoLSettings.Get("bis") == true
end

function Loot.ReadFilters(out)
    out.bisOn = Loot.BisOn()
    out.usableOnly = S.Get("usableOnly")
    out.myRecipes = S.Get("myRecipes")
    out.showCosmetic = S.Get("showCosmetic")
    out.skills = ReadSkills(out.skills or {})
    out.missingBis = out.bisOn and S.Get("missingBisOnly")
    out.upgradesOnly = S.Get("upgradesOnly")
    out.showAppearance = true
    return out
end

function Loot.Usable(itemID)
    local facts = J.Facts(itemID)
    return facts == nil or ClassCanUse(playerClass, facts)
end

function Loot.Rank(itemID)
    if not IsBisItem or J.IsNotYet(itemID) then return nil end
    return IsBisItem(itemID)
end
local Rank = Loot.Rank

local function WornRank(slot)
    local worn = GetInventoryItemID("player", slot)
    return worn and Rank(worn)
end

function Loot.Cosmetic(itemID)
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    return classID == ARMOR and subclassID == COSMETIC
end
local Cosmetic = Loot.Cosmetic

function Loot.BisUpgrade(itemID)
    local rank = Rank(itemID)
    if not rank or IsEquippedItem(itemID) then return false end
    local slots = BisSlotsFor(itemID)
    if not slots then return false end
    for i = 1, #slots do
        local wornRank = WornRank(slots[i])
        if not wornRank or rank < wornRank then return true end
    end
    return false
end
local BisUpgrade = Loot.BisUpgrade

local function RankUpgrade(rank, slots)
    for i = 1, #slots do
        local wornRank = WornRank(slots[i])
        if wornRank and rank < wornRank then return true end
    end
    return false
end

local function LevelUpgrade(itemID, slots)
    local facts = J.Items[itemID]
    local level = facts and facts[FACT.ITEM_LEVEL]
    if not level or (facts[FACT.REQUIRED] or 0) > UnitLevel("player") or not Loot.Usable(itemID) then
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

function Loot.Upgrade(itemID)
    if IsEquippedItem(itemID) then return false end
    local slots = BisSlotsFor(itemID)
    if not slots or Cosmetic(itemID) then return false end
    local rank = Rank(itemID)
    if rank then return RankUpgrade(rank, slots) end
    return LevelUpgrade(itemID, slots)
end

function Loot.Missing(itemID)
    return BisUpgrade(itemID) and GetItemCount(itemID, true) == 0
end

function Loot.Recipe(itemID)
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    if classID == RECIPE then return subclassID end
end
local Recipe = Loot.Recipe

function Loot.RecipeYours(subclass, filters)
    local skill = RECIPE_SKILL[subclass]
    return skill == nil or filters.skills[skill] == true
end

function Loot.Shown(itemID, filters)
    if filters.usableOnly and not Loot.Usable(itemID) then return false end
    if not filters.showCosmetic and Cosmetic(itemID) then return false end
    if filters.myRecipes then
        local subclass = Recipe(itemID)
        if subclass and not Loot.RecipeYours(subclass, filters) then return false end
    end
    if filters.missingBis and not Loot.Missing(itemID) then return false end
    if filters.upgradesOnly and not Loot.Upgrade(itemID) then return false end
    return true
end
local Shown = Loot.Shown

function Loot.Wearable(itemID)
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= NOT_WORN
end
local Wearable = Loot.Wearable

function Loot.BisGear(itemID)
    return BisSlotsFor(itemID) ~= nil and not Cosmetic(itemID)
end

function Loot.Appearance(itemID)
    if J.IsNotYet(itemID) or not Wearable(itemID) then return nil end
    local _, sourceID = Collection.GetItemInfo(itemID)
    local info = sourceID and Collection.GetAppearanceInfoBySource(sourceID)
    if info then return info.appearanceIsCollected or info.sourceIsCollected end
    if IsDressableItemByID(itemID) then return Collection.PlayerHasTransmogByItemInfo(itemID) end
    return nil
end
local Appearance = Loot.Appearance

function Loot.Name(itemID)
    local notYet = J.NotYet[itemID]
    if notYet then return notYet[FACT.NAME] end
    local name = GetItemNameByID(itemID)
    if not name and not Refused(itemID) then RequestLoadItemDataByID(itemID) end
    return name
end

function Loot.LowerName(itemID)
    return lowerNames[itemID] or Lower(itemID, Loot.Name(itemID))
end

function Loot.KnownLowerName(itemID)
    local lower = lowerNames[itemID]
    if lower then return lower end
    local notYet = J.NotYet[itemID]
    if notYet then return Lower(itemID, notYet[FACT.NAME]) end
    return Lower(itemID, GetItemNameByID(itemID))
end

function Loot.ListBis(items, count, have)
    for i = 1, #items do
        if Rank(items[i]) == BIS_PICK then
            count = count + 1
            if Have(items[i]) then have = have + 1 end
        end
    end
    return count, have
end
local ListBis = Loot.ListBis

function Loot.BossBis(boss)
    if not boss.loot then return 0, 0 end
    return ListBis(boss.loot, 0, 0)
end

function Loot.DungeonBis(dungeon)
    local count, have = 0, 0
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            local c, h = Loot.BossBis(boss)
            count, have = count + c, have + h
        end
    end
    return count, have
end

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

function Loot.DungeonNewLooks(dungeon, filters)
    local count, looks = 0, 0
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            if boss.loot then count, looks = ListNewLooks(boss.loot, filters, count, looks) end
        end
    end
    return count, looks
end
