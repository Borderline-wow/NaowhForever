-- The hourly cap is the sum of every character still inside the hour.
-- From the repo root:
--   lua5.1 Tools/regression/test-instance-tracker-hour.lua
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return source
end
local function Slice(source, a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local tracker = Read("NaowhForever_Utilities/InstanceTracker/InstanceTracker.lua")
local code = Slice(tracker, "local function AccountHour(lists, now, hour)", "\nlocal function HourLists")
assert(not code:find("trackAlts", 1, true), "Track Alts is not an input to the account count")
code = code .. "\nreturn AccountHour\n"
local chunk = assert(loadstring(code))
setfenv(chunk, setmetatable({}, { __index = _G }))
local AccountHour = chunk()

local count = 0
local function Case(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end

local HOUR = 3600
local NOW = 100000

local function Stamp(at)
    return { at = at, name = "Deadmines" }
end

Case("two characters in the same hour add toward 10", function()
    local lists = {
        { Stamp(NOW - 10), Stamp(NOW - 20), Stamp(NOW - 30) },
        { Stamp(NOW - 40), Stamp(NOW - 50) },
    }
    local n, frees, oldest = AccountHour(lists, NOW, HOUR)
    assert(n == 5, n)
    assert(oldest == NOW - 50, oldest)
    assert(frees == HOUR - 50, frees)
end)

Case("a stamp an hour old or older drops out", function()
    local lists = {
        { Stamp(NOW - HOUR), Stamp(NOW - 10) },
        { Stamp(NOW - HOUR - 1) },
    }
    local n, frees, oldest = AccountHour(lists, NOW, HOUR)
    assert(n == 1, n)
    assert(oldest == NOW - 10, oldest)
    assert(frees == HOUR - 10, frees)
end)

Case("the next free time is the oldest stamp on either character", function()
    local mine = { Stamp(NOW - 100) }
    local alt = { Stamp(NOW - 2500), Stamp(NOW - 400) }
    local n, frees, oldest = AccountHour({ mine, alt }, NOW, HOUR)
    assert(n == 3, n)
    assert(oldest == NOW - 2500, oldest)
    assert(frees == HOUR - 2500, frees)
    local again, againFrees, againOldest = AccountHour({ alt, mine }, NOW, HOUR)
    assert(again == 3 and againOldest == NOW - 2500 and againFrees == HOUR - 2500, againFrees)
end)

Case("a list that is not a character's entries is skipped", function()
    local n = AccountHour({ "nope", { Stamp(NOW - 5) }, nil }, NOW, HOUR)
    assert(n == 1, n)
    n = AccountHour(nil, NOW, HOUR)
    assert(n == 0, n)
end)

print(count .. " account hour regressions passed")
