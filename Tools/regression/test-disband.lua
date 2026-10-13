-- Run with Lua 5.1 from the repository root: Disband removes everyone but you, asking first unless Confirm Before Disbanding is off.
local settings = { disbandConfirm = true }
local asked, removed = 0, {}
local ns = { QoLSettings = { Get = function(k) return settings[k] end }, L = function(t) return t end,
    Print = function() end, Confirm = function(_, yes) asked = asked + 1; yes() end }
local env = setmetatable({
    NaowhForever = ns,
    InCombatLockdown = function() return false end,
    IsInGroup = function() return true end,
    IsInRaid = function() return false end,
    UnitIsGroupLeader = function() return true end,
    GetNumGroupMembers = function() return 3 end,
    UnitExists = function() return true end,
    UnitIsUnit = function(unit) return unit == "party3" end,
    GetUnitName = function(unit) return unit end,
    C_PartyInfo = { UninviteUnit = function(name) removed[#removed + 1] = name end },
}, { __index = _G })
env._G = env
local chunk = assert(loadfile("NaowhForever_QoL/Questing/Disband.lua"))
setfenv(chunk, env)
chunk()

ns.DisbandGroup()
assert(asked == 1 and #removed == 2, "asks first by default, then removes the other members")
settings.disbandConfirm = false
removed = {}
ns.DisbandGroup()
assert(asked == 1 and #removed == 2, "with the switch off it removes them without asking")
print("test-disband: 2 checks passed")
