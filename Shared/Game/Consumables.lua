-- Consumables.lua: your best food and drink (ns.BestFoodAndDrink), healthstones and healing potions, best first.
local ns = _G.NaowhForever

local CONJURED = {
    [8079] = true, [8078] = true, [8077] = true, [3772] = true, [2136] = true, [2288] = true,
    [5350] = true, [22895] = true, [8076] = true, [8075] = true, [1487] = true, [1114] = true,
    [1113] = true, [5349] = true,
}
local FOOD_SPELL, DRINK_SPELL = 433, 430
local CONJURED_BONUS = 1000
local REQUIRED_LEVEL = 5

ns.HEALTHSTONES = { 9421, 19012, 19013, 5510, 19010, 19011, 5509, 19008, 19009, 5511, 19006, 19007, 5512, 19004,
    19005 }
ns.HEALING_POTIONS = { 13446, 3928, 1710, 929, 858, 118 }

local function Score(id)
    return (CONJURED[id] and CONJURED_BONUS or 0) + (select(REQUIRED_LEVEL, C_Item.GetItemInfo(id)) or 0)
end

local function BestFoodAndDrink()
    local foodName, drinkName = C_Spell.GetSpellName(FOOD_SPELL), C_Spell.GetSpellName(DRINK_SPELL)
    local food, drink, foodScore, drinkScore
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            local spell = id and C_Item.GetItemSpell(id)
            if spell and (spell == foodName or spell == drinkName) then
                local s = Score(id)
                if spell == foodName then
                    if not foodScore or s > foodScore then food, foodScore = id, s end
                elseif not drinkScore or s > drinkScore then
                    drink, drinkScore = id, s
                end
            end
        end
    end
    return food, drink
end
ns.BestFoodAndDrink = BestFoodAndDrink
