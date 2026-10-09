-- Run with Lua 5.1 from the repository root: the Blessings roster on Forever, where names carry a
-- surname. UnitName gives the first name only, UnitFullName and addon senders the whole one, and
-- a group header matches its nameList against UnitName (party) or GetRaidRosterInfo (raid). Each
-- member's names must include what the header sees, without a first name two members share.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local f = assert(io.open("NaowhForever_Blessings/Group.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local first = assert(source:find("local function Readable(v)", 1, true))
local roster = assert(source:find("local function Roster()", first, true))
local last = assert(source:find("\nend\n", roster, true))
local chunk = source:sub(first, last + 4) .. "return Roster"

-- unit -> { full name, first name, server (UnitName's), class, roster name in a raid }
local units, raid = {}, false
local env = {
    NAME_SLOTS = tonumber((assert(source:match("\nlocal NAME_SLOTS = (%d+)\n"), "NAME_SLOTS is missing"))),
    Secret = function() return false end,
    IsInRaid = function() return raid end,
    GetNumGroupMembers = function() local n = 0 for k in pairs(units) do if k:find("^raid") then n = n + 1 end end return n end,
    GetNumSubgroupMembers = function() local n = 0 for k in pairs(units) do if k:find("^party") then n = n + 1 end end return n end,
    GetNormalizedRealmName = function() return "Forever" end,
    UnitFullName = function(unit) return units[unit] and units[unit][1] end,
    UnitName = function(unit) local u = units[unit] if u then return u[2], u[3] end end,
    UnitClass = function(unit) local u = units[unit] if u then return u[4], u[4] end end,
    UnitGUID = function(unit) return units[unit] and ("Player-" .. unit) end,
    GetRaidRosterInfo = function(i) local u = units["raid" .. i] return u and u[5] end,
}
local fn = assert(loadstring(chunk))
setfenv(fn, setmetatable(env, { __index = _G }))
local Roster = fn()

local function Member(list, who)
    for _, member in ipairs(list) do if member.who == who then return member end end
end

local function Names(list, who)
    for _, member in ipairs(list) do
        if member.who == who then
            local set = {}
            for name in member.names:gmatch("[^,]+") do set[name] = true end
            return set
        end
    end
end

units = {
    player = { "Glyadin Skywolf", "Glyadin", nil, "PALADIN" },
    party1 = { "Mara Stone", "Mara", nil, "WARRIOR" },
}
local list = Roster()
check("party: the sender name is the full name", list[1].who == "Glyadin Skywolf")
local mine = Names(list, "Glyadin Skywolf")
check("party: the header's UnitName first name is listed", mine["Glyadin"])
check("party: the full name is listed", mine["Glyadin Skywolf"] and mine["Glyadin Skywolf-Forever"])
check("party: the other member's first name too", Names(list, "Mara Stone")["Mara"])
check("party: the header can find both", Member(list, "Glyadin Skywolf").targetable and Member(list, "Mara Stone").targetable)

units.party2 = { "Mara Vale", "Mara", nil, "MAGE" }
list = Roster()
check("party: a first name two members share is left out", not Names(list, "Mara Stone")["Mara"]
    and not Names(list, "Mara Vale")["Mara"])
check("party: a unique first name is still listed", Names(list, "Glyadin Skywolf")["Glyadin"])

units = {
    player = { "Bob", "Bob", nil, "PALADIN" },
    party1 = { "Bob Smith", "Bob", nil, "WARRIOR" },
}
list = Roster()
check("party: a surname-less name clashes with another's first name", not Names(list, "Bob Smith")["Bob"])
check("party: so the surname-less one does not claim it either", not Names(list, "Bob")["Bob"])
check("party: and the header cannot find either", not Member(list, "Bob").targetable and not Member(list, "Bob Smith").targetable)

units = {
    raid1 = { "Glyadin Skywolf", "Glyadin", nil, "PALADIN", "Glyadin" },
    raid2 = { "Mara Stone", "Mara", nil, "WARRIOR", "Mara Stone" },
    raid3 = { "Tor Ashby", "Tor", "Elsewhere", "PRIEST", "Tor-Elsewhere" },
}
raid = true
list = Roster()
check("raid: a first name read twice for one member still counts once", Names(list, "Glyadin Skywolf")["Glyadin"])
check("raid: GetRaidRosterInfo's full name is listed", Names(list, "Mara Stone")["Mara Stone"])
check("raid: the header can find them by it", Member(list, "Mara Stone").targetable and Member(list, "Glyadin Skywolf").targetable)
local tor = Names(list, "Tor Ashby")
check("raid: a server from UnitName is joined to the first name", tor["Tor-Elsewhere"])

-- Two from the same other realm with one first name look alike to the header, whatever it reads.
units = {
    player = { "Glyadin Skywolf", "Glyadin", nil, "PALADIN" },
    party1 = { "Bob Smith-Elsewhere", "Bob", "Elsewhere", "WARRIOR" },
    party2 = { "Bob Jones-Elsewhere", "Bob", "Elsewhere", "MAGE" },
}
raid = false
list = Roster()
check("cross-realm namesakes: neither claims Bob-Elsewhere", not Names(list, "Bob Smith-Elsewhere")["Bob-Elsewhere"]
    and not Names(list, "Bob Jones-Elsewhere")["Bob-Elsewhere"])
check("cross-realm namesakes: the header cannot find either", not Member(list, "Bob Smith-Elsewhere").targetable
    and not Member(list, "Bob Jones-Elsewhere").targetable)

units = { raid1 = { "Mara Stone", "Mara", nil, "WARRIOR", nil } }
raid = true
check("raid: a member whose roster entry has not loaded is not findable", not Roster()[1].targetable)

print(("test-blessing-names: %d checks passed"):format(checks))
