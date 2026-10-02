-- Tests the real camp tooltip formatter with readable synthetic tooltip data.
local f = assert(io.open("AuraBuffs/NaowhForever_Campfire.lua", "r"))
local source = f:read("*a"); f:close()
local block = assert(source:match("(local EFFECT_TAGS.-)\nlocal Refresh"))
local data
local secret = "Secret: hidden text"
local env = setmetatable({
    C_TooltipInfo = { GetUnitBuffByAuraInstanceID = function() return data end },
    issecretvalue = function(value) return value == secret end,
}, { __index = _G })
local chunk = assert(loadstring(block .. "\nreturn ActiveBuffs")); setfenv(chunk, env)
local format = chunk()
local function check(rows, expected)
    data = { lines = {{ leftText = "Camp Benefits" }} }
    for _, row in ipairs(rows) do data.lines[#data.lines + 1] = { leftText = row } end
    assert(format({ auraInstanceID = 1 }) == expected)
end
check({"Camp Tent: You received a small amount of rest experience. You can only receive this effect once per 1 hour.",
    "Target Dummy: Critical strike chance with all spells and attacks increased by 2%."}, "+Rested\n+Crit")
check({"Dummy: Critical strike chance increased by 2.5%."}, "+Crit")
check({"Mana Well: Mana regeneration increased by 5%."}, "+MP5")
check({"Mystery Totem: An unfamiliar effect with a very long description."}, "Mystery Totem")
check({"Incense Candle: An unfamiliar effect with a very long description."}, "+INT")
check({"Faction Banner: Spirit increased by 27."}, "+Spirit")
check({"Lodestone: Melee attack power increased by 49."}, "+ATK")
check({"Enchanted Lute: Armor increased by 114 and all stats by 7."}, "+ARM")
check({"Fish Bowl: All stats increased by 8%."}, "+Stats")
check({"Fish Bowl: Strength, Agility, Stamina, Intellect and Spirit increased by 8%."}, "+Stats")
check({"Anvil: Strength increased by 20.", "Toxin Study: Stamina increased by 34."}, "+STR\n+STA")
check({"|cffffffffCamp Tent: You gained rested experience.|r", "Chair: Rested experience granted."}, "+Rested")
check({"Benefits:", "Spell ID: 1229741", "24 |4minute:minutes; remaining", secret}, "")
data = nil; assert(format({ auraInstanceID = 1 }) == "")
check({"Mana Well: 10 MP5"}, "+MP5")
print("15 campfire tooltip checks passed")
