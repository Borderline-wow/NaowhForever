-------------------------------------------------------------------------------
--  Sources.lua -- where a click on an item's source takes you (ns.BiS.Sources): the dungeon
--  that drops it, open on it in the Dungeon Journal; the faction that sells it there; the
--  quest that rewards it, on the BiS List's Quests page; a waypoint on the NPC out in the
--  world who has it; its recipe in your profession window; its zone on your map; else its
--  Wowhead link to copy. Worked out once per item, from the data, the first that fits; the
--  Journal and the recipes are read when asked, as they load after the BiS List.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local R = B.Rankings
local Shared = ns.Shared
local Parts, Places = Shared.Parts, Shared.Places

local Sources = {}
B.Sources = Sources

local EMPTY = {}

---@alias BisSourceKind "dungeon"|"faction"|"quest"|"npc"|"recipe"|"zone"|"wowhead"

local kinds, targets = {}, {}   -- item ID -> its kind, and what it opens
local factionOf, questOf        -- item ID -> the faction that sells it, the quest that rewards it
local recipeOf                  -- item ID -> the recipe spell that makes it

-- The Journal's factions' rewards, and the quests' rewards, by item; once.
local function Index()
    if factionOf then return end
    factionOf, questOf, recipeOf = {}, {}, {}
    local J = ns.Journal
    if J and J.Factions then
        for _, tab in ipairs({ "reputation", "pvp" }) do
            for _, faction in ipairs(J.Factions(tab)) do
                for _, tier in ipairs(faction.tiers) do
                    for _, id in ipairs(tier.items) do factionOf[id] = factionOf[id] or faction end
                end
            end
        end
    end
    for questID, items in pairs(J and J.BiSQuestRewards or EMPTY) do
        for _, id in ipairs(items) do questOf[id] = questOf[id] or questID end
    end
    for _, profession in pairs(ns.RecipeData or EMPTY) do
        for _, recipe in ipairs(profession.recipes or EMPTY) do
            if recipe.item then recipeOf[recipe.item] = recipeOf[recipe.item] or recipe.spell end
        end
    end
end

---@return BisSourceKind kind
---@return any target the dungeon, faction, quest ID, spot, recipe spell or map
function Sources.Of(itemID)
    local kind = kinds[itemID]
    if kind then return kind, targets[itemID] end
    Index()
    local target = R.DropDungeon(itemID)
    if target then
        kind = "dungeon"
    elseif factionOf[itemID] then
        kind, target = "faction", factionOf[itemID]
    elseif questOf[itemID] then
        kind, target = "quest", questOf[itemID]
    elseif (ns.BiSSpots or EMPTY)[itemID] then
        kind, target = "npc", ns.BiSSpots[itemID]
    elseif recipeOf[itemID] then
        kind, target = "recipe", recipeOf[itemID]
    else
        local place = R.Place(ns.BiSSource(itemID) or "")
        target = Places and Places.Zone(place)
        kind = target and "zone" or "wowhead"
    end
    kinds[itemID], targets[itemID] = kind, target
    return kind, target
end

-- Its recipe opens in your profession window only if you have that profession.
local function CanOpenRecipe(spell)
    return C_TradeSkillUI.IsRecipeProfessionLearned(spell) == true
end

--- What a click does, for the source's tooltip.
function Sources.Hint(itemID)
    local kind, target = Sources.Of(itemID)
    if kind == "dungeon" then return "Click: open it in the Dungeon Journal" end
    if kind == "faction" then return "Click: open " .. target.name .. " in the Dungeon Journal" end
    if kind == "quest" then return "Click: show the quest" end
    if kind == "npc" then return "Click: a waypoint on " .. target.name end
    if kind == "recipe" then
        return CanOpenRecipe(target) and "Click: open the recipe" or "Click: copy its recipe's Wowhead link"
    end
    if kind == "zone" then return "Click: show it on your map" end
    return "Click: copy its Wowhead link"
end

--- Goes there. The BiS List steps aside for the Journal or the map, and comes back when it
--- closes.
function Sources.Go(itemID)
    local kind, target = Sources.Of(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if kind == "dungeon" or kind == "faction" then
        B.StepAside("journal")
        ns.OpenJournalWindow(target, B.BackFromJournal, "Back to BiS List", itemID)
    elseif kind == "quest" then
        if not B.ShowQuest(target) then Parts.CopyWowhead("quest", target, name) end
    elseif kind == "npc" then
        ns.PlaceWaypoint(target.name, target.map, target.x, target.y, name and " (" .. name .. ")")
        if Places.ShowMap(target.map) then B.StepAside("map") end
    elseif kind == "recipe" then
        if CanOpenRecipe(target) then
            C_TradeSkillUI.OpenRecipe(target)
        else
            Parts.CopyWowhead("spell", target, name)
        end
    elseif kind == "zone" then
        if Places.ShowMap(target) then B.StepAside("map") end
    else
        Parts.CopyWowhead("item", itemID, name)
    end
end
