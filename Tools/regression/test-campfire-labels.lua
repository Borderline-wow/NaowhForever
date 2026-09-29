-- Tests the real camp tooltip formatter with readable synthetic tooltip data.
local f = assert(io.open("AuraBuffs/NaowhForever_Campfire.lua", "r"))
local source = f:read("*a"); f:close()
local block = assert(source:match("(local function ShortCampBuff.-)\nlocal Refresh"))
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
check({"Camp Chair: You received a small amount of rest experience. You can only receive this effect once per 1 hour.",
    "Target Dummy: Critical strike chance with all spells and attacks increased by 2%."}, "Rested XP\nCrit Strike 2%")
check({"Dummy: Critical strike chance increased by 2.5%."}, "Crit Strike 2.5%")
check({"Fish Bowl: Mana regeneration increased by 5%."}, "Mana Regen 5%")
check({"Incense Candle: An unfamiliar effect with a very long description."}, "Incense Candle")
check({"|cffffffffCamp Chair: You gained rested experience.|r", "Chair: Rested experience granted."}, "Rested XP")
check({"Benefits:", "Spell ID: 1229741", "24 |4minute:minutes; remaining", secret}, "")
data = nil; assert(format({ auraInstanceID = 1 }) == "")
check({"Mana Well: 10 MP5"}, "10 MP5")
print("8 campfire tooltip checks passed")
