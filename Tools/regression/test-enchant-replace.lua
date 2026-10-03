-- Run with Lua 5.1 from the repository root: Auto-Replace Enchants answers only the replace
-- enchant popup, only while it is on, and never while Shift is held.
local settings, shift, calls = {}, false, {}
local hook
local env = setmetatable({
    NaowhForever = { QoLSettings = { Get = function(key) return settings[key] end } },
    hooksecurefunc = function(name, fn)
        assert(name == "StaticPopup_Show")
        hook = fn
    end,
    IsShiftKeyDown = function() return shift end,
    C_Item = { ReplaceEnchant = function() calls[#calls + 1] = "replace" end },
    StaticPopup_Hide = function(which) calls[#calls + 1] = "hide " .. which end,
}, { __index = _G })
env._G = env
local chunk = assert(loadfile("QoL/NaowhForever_EnchantReplace.lua"))
setfenv(chunk, env)
chunk()

local count = 0
local function Case(name, fn)
    calls = {}
    fn()
    count = count + 1
    print("PASS " .. name)
end

Case("off by default: the popup is left to ask", function()
    hook("REPLACE_ENCHANT")
    assert(#calls == 0)
end)

Case("on: the replace popup is answered yes and closed", function()
    settings.enabled, settings.enchantReplace = true, true
    hook("REPLACE_ENCHANT")
    assert(table.concat(calls, ",") == "replace,hide REPLACE_ENCHANT", table.concat(calls, ","))
end)

Case("other popups are left alone", function()
    hook("TRADE_REPLACE_ENCHANT")
    hook("DELETE_ITEM")
    assert(#calls == 0)
end)

Case("Shift held: asked as before", function()
    shift = true
    hook("REPLACE_ENCHANT")
    shift = false
    assert(#calls == 0)
end)

Case("QoL off turns it off too", function()
    settings.enabled = false
    hook("REPLACE_ENCHANT")
    assert(#calls == 0)
end)

print(("test-enchant-replace: %d cases passed"):format(count))
