local file = assert(io.open("QoL/NaowhForever_PetTracker.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local first = assert(source:find("local function Apply()", 1, true))
local last = assert(source:find('hooksecurefunc(S, "Set"', first, true))
local cancelled, hidden, cleared = 0, 0, 0
local env = {
 On = function() return false end,
 events = { UnregisterAllEvents = function() cleared = cleared + 1 end },
 frame = { Hide = function() hidden = hidden + 1 end },
 dismountTimer = { Cancel = function() cancelled = cancelled + 1 end },
}
local chunk = assert(loadstring(source:sub(first, last - 1) .. "return Apply"))
setfenv(chunk, env)
local apply = chunk()
apply()
assert(cancelled == 1, "pending dismount timer must be cancelled")
assert(env.dismountTimer == nil, "cancelled timer must be cleared")
assert(hidden == 1 and cleared == 1, "disabled module must hide and unregister")
apply()
assert(cancelled == 1, "repeated disable must not cancel a stale timer")
print("4 pet tracker shutdown checks passed")
