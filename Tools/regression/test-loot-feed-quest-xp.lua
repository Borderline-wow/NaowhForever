-- Run with Lua 5.1 from the repository root: a quest turn-in also sends its experience as a
-- combat XP message with no source named. The loot feed already shows it on the quest line, so
-- that message adds no Experience line while quest lines are on; a kill's message still does,
-- and with quest lines off the unnamed one is the only place the experience shows.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local f = assert(io.open("QoL/NaowhForever_LootFeed.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local a = assert(source:find("local UNNAMED_XP", 1, true))
local b = assert(source:find("\n", source:find(":gsub", a, true) + 1, true))
local c = assert(source:find("local function KillXP(text)", b, true))
local d = assert(source:find("\nend\n", c, true))
local chunk = source:sub(a, b) .. source:sub(c, d + 4) .. "return KillXP"

local settings, pushed = { lootFeedQuest = true }, {}
local env = {
    COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience.",
    S = { Get = function(key) return settings[key] end },
    Push = function(_, name, value) pushed[#pushed + 1] = value end,
    XP_ICON = "icon", XP_COLOR = "",
    BreakUpLargeNumbers = function(n) return tostring(n) end,
}
local fn = assert(loadstring(chunk))
setfenv(fn, setmetatable(env, { __index = _G }))
local KillXP = fn()

KillXP("You gain 6200 experience.")
check("quest lines on: the quest's own XP message adds no line", #pushed == 0)

KillXP("Kobold Miner dies, you gain 45 experience. (+22 exp Rested bonus)")
check("a kill still adds its line", #pushed == 1 and pushed[1] == "+45|r")

settings.lootFeedQuest = false
KillXP("You gain 6200 experience.")
check("quest lines off: the unnamed message is the only place it shows", #pushed == 2 and pushed[2] == "+6200|r")

print(("test-loot-feed-quest-xp: %d checks passed"):format(checks))
