-- Run with Lua 5.1 from the repository root: the profession window's search matches a learned
-- recipe by its name or by any reagent's name, as Blizzard's search does. A reagent whose name
-- has not loaded yet is asked for once and matches once it arrives, and a recipe's reagents are
-- read from the game once, even when it needs none. Loads Recipes.lua and Entries.lua against stubs.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local RECIPES = {
    [1] = { recipeID = 1, name = "Copper Bracers", learned = true, categoryID = 0 },
    [2] = { recipeID = 2, name = "Rough Sharpening Stone", learned = true, categoryID = 0 },
    [3] = { recipeID = 3, name = "Smelt Copper", learned = true, categoryID = 0 },
}
local SLOTS = {
    [1] = { { reagents = { { itemID = 2840 } }, quantityRequired = 2 } },
    [2] = { { reagents = { { itemID = 2835 } }, quantityRequired = 1 } },
    [3] = {},
}
local names = { [2840] = "Copper Bar" }
local requests, schematics = {}, {}

local W = { query = "", linked = true }
local ns = { L = dofile("Tools/regression/locale_stub.lua").L }
ns.Professions = {
    State = W,
    Settings = { Get = function() end, Set = function() end },
    Filters = { Passes = function() return true end },
}

local env = setmetatable({
    NaowhForever = ns,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    C_Item = {
        GetItemNameByID = function(itemID) return names[itemID] end,
        RequestLoadItemDataByID = function(itemID) requests[itemID] = (requests[itemID] or 0) + 1 end,
    },
    C_TradeSkillUI = {
        GetAllRecipeIDs = function() return { 1, 2, 3 } end,
        GetRecipeInfo = function(id) return RECIPES[id] end,
        GetCategoryInfo = function() end,
        GetRecipeSchematic = function(id)
            schematics[id] = (schematics[id] or 0) + 1
            return { reagentSlotSchematics = SLOTS[id] }
        end,
    },
}, { __index = _G })
env._G = env

Load({ "NaowhForever_Professions/Recipes.lua", "NaowhForever_Professions/Entries.lua" }, env)
local Entries = ns.Professions.Entries
local waiting = ns.Professions.Recipes.waiting
Entries.Collect()

local function Search(text)
    W.query = text:lower()
    Entries.Build()
    local out = {}
    for _, e in ipairs(Entries.list) do
        if e.recipe then out[e.recipe.recipeID] = true end
    end
    return out
end

local shown = Search("")
check("an empty search shows every learned recipe", shown[1] and shown[2] and shown[3])

shown = Search("bracers")
check("a recipe name still matches", shown[1] and not shown[2])

shown = Search("copper bar")
check("a reagent's name finds the recipe that uses it", shown[1] and not shown[2])

shown = Search("COPPER")
check("matching ignores case", shown[1] and shown[3] and not shown[2])

shown = Search("coarse stone")
check("a reagent whose name has not loaded does not match yet", not shown[2])
check("and its name is asked for", requests[2835] == 1)
Search("coarse ston")
Search("coarse sto")
check("typing on does not ask again while it is on its way", requests[2835] == 1)

waiting[2835] = nil
names[2835] = "Coarse Stone"
shown = Search("coarse stone")
check("once the name loads the recipe matches", shown[2] and not shown[1])

check("each recipe's reagents are read from the game once", schematics[1] == 1 and schematics[2] == 1)
check("a recipe with no reagents is read once too", schematics[3] == 1)

print(("test-profession-reagent-search: %d checks passed"):format(checks))
