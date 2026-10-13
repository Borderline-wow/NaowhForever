-- Run with Lua 5.1 from the repository root: Disband always asks, and the dialog's Yes is covered by a secure
-- button running /uninvite for everyone else, because UninviteUnit is protected for addons.
local asked, removed, printed = 0, {}, {}
local NOTHING = function() end
local function Frame()
    return setmetatable({ attrs = {}, shown = false }, { __index = function(self, key)
        if key == "SetAttribute" then return function(_, k, v) self.attrs[k] = v end end
        if key == "Show" then return function() self.shown = true end end
        if key == "Hide" then return function() self.shown = false end end
        if key == "CreateTexture" then return function() return Frame() end end
        if key == "GetEffectiveScale" then return function() return 1 end end
        if key:match("^%u") then return NOTHING end
    end })
end
local yes, dimmer, onYes, hooked = Frame(), Frame(), nil, nil
yes.GetLeft, yes.GetBottom, yes.GetWidth, yes.GetHeight = function() return 100 end, function() return 50 end,
    function() return 80 end, function() return 20 end
yes.IsMouseOver = function() return false end
yes.HookScript = function(_, script, fn) hooked = { script = script, fn = fn } end
local cover
local ns = { L = function(t) return t end,
    Print = function(t) printed[#printed + 1] = t end,
    Confirm = function(_, accept, close)
        asked = asked + 1
        onYes, dimmer.onClose = accept, close
        return yes, dimmer
    end }
local env = setmetatable({
    NaowhForever = ns,
    UIParent = Frame(),
    CreateFrame = function() cover = Frame(); return cover end,
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
assert(asked == 1 and #removed == 0, "asks first by default, and the protected call is never made")
assert(hooked and hooked.script == "OnEnter", "Yes is covered when the mouse reaches it")
hooked.fn(yes)
assert(cover and cover.shown and cover.attrs.type == "macro", "a secure button over Yes")
assert(cover.attrs.macrotext == "/uninvite party2\n/uninvite party1", "it uninvites every other member by name")
onYes()
assert(#removed == 0 and #printed == 1, "a Yes that was not covered says to try again and removes nobody")
ns.DisbandGroup()
assert(asked == 2 and #removed == 0, "there is no way to disband without asking")
print("test-disband: 6 checks passed")
