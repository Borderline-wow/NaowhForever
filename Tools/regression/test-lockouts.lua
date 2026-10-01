local f = assert(io.open(arg[1] or "TopBar/NaowhForever_TopBar.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

-- Saved instances as GetSavedInstanceInfo returns them: name, reset, locked, extended, total, done.
local function Fixture(saved, now, updatedAt)
    local env = {
        GetTime = function() return now end,
        GetNumSavedInstances = function() return #saved end,
        GetSavedInstanceInfo = function(i)
            local s = saved[i]
            return s[1], 1, s[2], 1, s[3], s[4], 0, false, 5, "Normal", s[5], s[6]
        end,
    }
    setmetatable(env, { __index = _G })
    local code = Slice("local lockoutsAt = 0", "\nfunction ns.LockoutsCommand")
        .. "\nlockoutsAt = " .. updatedAt .. "\nreturn Lockouts"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    return chunk()()
end
local function Lines(list)
    local out = {}
    for _, l in ipairs(list) do out[#out + 1] = l.name .. " in " .. l.reset end
    return table.concat(out, "; ")
end
local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("soonest reset first, with boss progress", function()
    local list = Fixture({
        { "Molten Core", 5 * 86400 + 3 * 3600, true, false, 10, 4 },
        { "Zul'Gurub", 2 * 3600 + 30 * 60, true, false, 10, 10 },
    }, 100, 100)
    assert(Lines(list) == "Zul'Gurub 10/10 in 2h 30m; Molten Core 4/10 in 5d 3h", Lines(list))
end)
Case("the reset counts down from the last update", function()
    local list = Fixture({ { "Onyxia's Lair", 3 * 3600, true, false, 1, 1 } }, 100 + 3600, 100)
    assert(Lines(list) == "Onyxia's Lair 1/1 in 2h 0m", Lines(list))
end)
Case("expired and unlocked instances are left out; extended ones stay", function()
    local list = Fixture({
        { "Old", 60, true, false, 0, 0 },
        { "Released", 86400, false, false, 0, 0 },
        { "Extended", 86400, false, true, 0, 0 },
    }, 500, 0)
    assert(Lines(list) == "Extended in 23h 51m", Lines(list))
end)
Case("an instance without boss counts shows just its name", function()
    local list = Fixture({ { "Dire Maul", 600, true, false, 0, 0 } }, 0, 0)
    assert(Lines(list) == "Dire Maul in 10m", Lines(list))
end)
print(count .. " lockout regressions passed")
