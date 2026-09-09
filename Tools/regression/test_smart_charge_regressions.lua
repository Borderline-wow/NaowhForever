local path = assert(arg[1])
local file = assert(io.open(path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local begin = assert(source:find("local KNOWN_BASE_COOLDOWN = {", 1, true))
local finish = assert(source:find("local castToBase = {}", begin, true))
local chargeCode = source:sub(begin, finish - 1)
local castBegin = assert(source:find("local function NoteOwnCast(castSpellID)", finish, true))
local castEnd = assert(source:find("-- These three hang off ns", castBegin, true))
local castCode = source:sub(castBegin, castEnd - 1)
local compile = loadstring or load
local SID = 48265
local cases, failures = 0, 0
local function Fixture()
    local env = { time = 0, active = false, count = 2, plain = false,
        shape = true, recharge = 45, remaining = nil }
    local store = { clientRecharge = { [tostring(SID)] = 45 } }
    local spells = {
        GetSpellCharges = function()
            if not env.shape then return nil end
            return { maxCharges = 2, isActive = env.active, currentCharges = env.count }
        end,
        GetSpellChargeDuration = function()
            if not env.remaining then return nil end
            return { GetTotalDuration = function() return env.recharge end,
                GetRemainingDuration = function() return env.remaining end }
        end,
        GetSpellCooldownDuration = function() return nil end,
    }
    local globals = { C_Spell = spells, GetTime = function() return env.time end,
        CanNameSpellAloud = function() return env.plain end,
        issecretvalue = function(v) return v == env.secret end,
        TRDB = function() return store end, AppendLog = function() end,
        ownCastAt = {}, castToBase = { [SID] = SID }, ns = {}, readyAt = {} }
    setmetatable(globals, { __index = _G })
    local code = chargeCode .. "\nCooldownRunning = function() return false end\n"
        .. castCode .. "\nreturn EnsureChargeState, ChargesAvailable, NoteOwnCast, chargeState"
    local chunk
    if setfenv then chunk = assert(compile(code)); setfenv(chunk, globals)
    else chunk = assert(load(code, "charge production code", "t", globals)) end
    env.ensure, env.available, env.cast, env.states = chunk()
    env.ensure(SID)
    return env
end
local function Case(name, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if ok then print("PASS " .. name)
    else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function Eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
Case("first cast spends one charge, not two", function()
    local e = Fixture()
    e.active, e.remaining, e.count = true, 45, 1
    e.cast(SID)
    Eq(e.states[SID].count, 1)
    Eq(e.available(SID), 1)
end)
Case("readable post-cast count is not debited twice", function()
    local e = Fixture()
    e.plain, e.active, e.remaining, e.count = true, true, 45, 1
    e.cast(SID)
    Eq(e.states[SID].count, 1)
    Eq(e.available(SID), 1)
    Eq(e.states[SID].count, 1)
end)
Case("missing charge shape does not invent a charge", function()
    local e = Fixture()
    e.states[SID].count = 0
    e.shape = false
    Eq(e.available(SID), 0)
end)
Case("one landing inferred then observed is counted once", function()
    local e = Fixture()
    e.states[SID].count = 0
    e.active, e.remaining = true, 45
    Eq(e.available(SID), 0)
    e.time, e.remaining = 46, nil
    Eq(e.available(SID), 1)
    e.states[SID].count = 0 -- spend that recovered charge
    e.time, e.remaining = 47, 43
    Eq(e.available(SID), 0)
end)
Case("full readable stack resets the old recharge anchor", function()
    local e = Fixture()
    e.states[SID].count, e.states[SID].rechargeStart = 0, 0
    e.time, e.plain, e.count = 100, true, 2
    Eq(e.available(SID), 2)
    Eq(e.states[SID].rechargeStart, nil)
end)
Case("two spends keep the original recharge deadline", function()
    local e = Fixture()
    e.active, e.remaining = true, 45
    e.cast(SID)
    e.time, e.remaining = 10, 35
    e.cast(SID)
    Eq(e.available(SID), 0)
    Eq(e.states[SID].tick, 0)
    e.time, e.remaining = 45, 45
    Eq(e.available(SID), 1)
    Eq(e.available(SID), 1)
    e.time, e.remaining, e.active = 90, nil, false
    Eq(e.available(SID), 2)
end)
Case("cast after an unobserved refill keeps the other charge", function()
    local e = Fixture()
    e.active, e.remaining = true, 45
    e.cast(SID)
    Eq(e.available(SID), 1)
    e.time, e.remaining = 50, 45
    e.cast(SID)
    Eq(e.states[SID].count, 1)
    Eq(e.available(SID), 1)
end)
Case("exact downward correction does not hide the next real landing", function()
    local e = Fixture()
    e.active, e.remaining = true, 45
    e.states[SID].count = 1
    Eq(e.available(SID), 1)
    e.time, e.remaining, e.count, e.plain = 30, 15, 0, true
    Eq(e.available(SID), 0)
    e.time, e.remaining, e.plain = 45, 45, false
    Eq(e.available(SID), 1)
end)
Case("cold start while recharging stays conservative", function()
    local e = Fixture()
    e.states[SID] = nil
    e.time, e.active, e.remaining = 20, true, 25
    e.ensure(SID)
    Eq(e.available(SID), 0)
    e.time, e.remaining = 45, 45
    Eq(e.available(SID), 1)
end)
Case("inactive recharge still recovers a confirmed full stack", function()
    local e = Fixture()
    e.states[SID].count = 0
    e.time = 100
    Eq(e.available(SID), 2)
end)
Case("unexpected secret count is not compared", function()
    local e = Fixture()
    -- Emulate the secret classifier on a numeric result; Lua itself cannot
    -- manufacture WoW's secret-number tag outside the client.
    e.secret = 1
    e.count, e.plain = e.secret, true
    Eq(e.available(SID), 2)
end)
print(cases .. " cases; " .. failures .. " failures")
if failures > 0 then os.exit(1) end
