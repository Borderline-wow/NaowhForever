-- Run with Lua 5.1 from the repository root: Blessings Auto-Assign. One blessing per paladin per
-- class, never the same blessing twice in a class, nothing a paladin has not learned, Salvation
-- never on warriors or druids, the most wanted blessings first, one aura each, and a paladin who
-- knows little is served before one who knows everything.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local f = assert(io.open("NaowhForever_Blessings/AutoAssign.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local first = assert(source:find("local WANTED = {", 1, true))
local last = assert(source:find("local function ApplyPlans(plans)", first, true))
local chunk = source:sub(first, last - 1) .. "return AutoPlans"

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local mine = {}
local others = {}
local env = {
    CLASSES = CLASSES,
    BLESSINGS = { { key = "might" }, { key = "wisdom" }, { key = "kings" }, { key = "salvation" }, { key = "light" } },
    AURAS = { { key = "devotion" }, { key = "retribution" }, { key = "concentration" } },
    IsPaladin = function() return true end,
    Learned = function(entry) return mine[entry.key] end,
    MyName = function() return "Glyadin Skywolf" end,
}
env.others = others
local fn = assert(loadstring(chunk))
setfenv(fn, setmetatable(env, { __index = _G }))
local AutoPlans = fn()

local function Set(...)
    local t = {}
    for _, k in ipairs({ ... }) do t[k] = true end
    return t
end

-- You know everything; another paladin knows only Might and Devotion.
mine = Set("might", "wisdom", "kings", "salvation", "light", "devotion", "retribution", "concentration")
others["Bram Hollow"] = { known = Set("might", "devotion") }
local plans = AutoPlans(false)
local me, bram = plans["Glyadin Skywolf"], plans["Bram Hollow"]
check("the paladin who knows only Might gives warriors Might", bram.classes.WARRIOR == "might")
check("you then give warriors the next one, Kings", me.classes.WARRIOR == "kings")
check("the scarce paladin gets the only aura they know", bram.aura == "devotion")
check("you get the next aura", me.aura == "retribution")

for _, class in ipairs(CLASSES) do
    local a, b = me.classes[class], bram.classes[class]
    check(class .. ": never the same blessing twice", not (a and b and a == b))
    check(class .. ": nothing the other paladin has not learned", b == nil or b == "might")
end

-- Raid: Salvation leads for casters, never reaches warriors or druids.
others["Bram Hollow"] = nil
plans = AutoPlans(true)
me = plans["Glyadin Skywolf"]
check("raid: a lone paladin gives mages Salvation first", me.classes.MAGE == "salvation")
check("raid: warriors get Might, not Salvation", me.classes.WARRIOR == "might")
check("raid: druids never get Salvation", me.classes.DRUID ~= "salvation")
for _, raid in ipairs({ true, false }) do
    local p = AutoPlans(raid)["Glyadin Skywolf"]
    check("paladins never get Salvation", p.classes.PALADIN ~= "salvation")
end
plans = AutoPlans(false)
check("party: a lone paladin gives mages Wisdom", plans["Glyadin Skywolf"].classes.MAGE == "wisdom")

print(("test-blessing-autoassign: %d checks passed"):format(checks))
