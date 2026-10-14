-- Bag ownership must exclude equipped items while preserving bank counts.
local bagStacks = {
    [0] = { { itemID = 100, stackCount = 2 } },
    [1] = { { itemID = 100, stackCount = 1 }, { itemID = 200, stackCount = 4 } },
}

rawset(_G, "wipe", function(t) for key in pairs(t) do t[key] = nil end return t end)
rawset(_G, "NUM_BAG_SLOTS", 4)
rawset(_G, "C_Container", {
    GetContainerNumSlots = function(bag) return #(bagStacks[bag] or {}) end,
    GetContainerItemInfo = function(bag, slot) return (bagStacks[bag] or {})[slot] end,
})
rawset(_G, "C_Item", {
    GetItemCount = function(itemID, includeBank)
        if itemID ~= 100 then return 0 end
        return includeBank and 6 or 4
    end,
})
rawset(_G, "C_TradeSkillUI", {})

local ns = {
    L = function(text) return text end,
    ProfBagChanges = 0,
    Professions = {
        Settings = { DB = function() return {} end },
        State = {},
        Links = { Viewing = function() return false end },
    },
}
_G.NaowhForever = ns

dofile("NaowhForever_Professions/Recipes.lua")
local recipes = ns.Professions.Recipes

assert(recipes.ItemCount(100) == 4, "general owned count should include the equipped item")
assert(recipes.BagCount(100) == 3, "bag count included equipped or bank items")
assert(recipes.BankCount(100) == 2, "bank count changed while excluding equipped items from bags")

bagStacks[0][1].stackCount = 4
assert(recipes.BagCount(100) == 3, "bag count cache changed before a bag update")
ns.ProfBagChanges = ns.ProfBagChanges + 1
assert(recipes.BagCount(100) == 5, "bag count cache did not refresh after a bag update")

print("Bag-only ownership regression test: PASS")
