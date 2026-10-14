-- When a live copy still blocks the hourly count, and when a group is a new visit.
-- From the repo root:
--   lua5.1 Tools/regression/test-instance-tracker-copies.lua
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return source
end
local function Slice(source, a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local tracker = Read("NaowhForever_InstanceTracker/InstanceTracker.lua")
local code = Slice(tracker, "local function SamePlace(open, name, mapID, difficulty)", "\n\nlocal function LastRun")
    .. "\n"
    .. Slice(tracker, "local function CopyKey(mapID, difficulty, name)", "\n\nlocal function ByAt")
    .. "\n"
    .. Slice(tracker, "local function CopyFresh(stored, now, hour)", "\n-- end copy memory")
    .. "\n"
    .. Slice(tracker, "local function ObservedZone(seen)", "\nBeginRun = function")
    .. "\nreturn { Fresh = CopyFresh, Counts = CountsEntry, Differ = GroupsDiffer, Resume = CanResume,"
    .. " Take = TakeSameCopy, Zone = CopyParts, Keeps = KeepsVisit, Note = NoteZone, TakeBack = TakeCountBack }\n"
local env = setmetatable({ HOUR = 3600 }, { __index = _G })
local chunk = assert(loadstring(code))
setfenv(chunk, env)
local Copy = chunk()

local count = 0
local function Case(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end

local HOUR = 3600
local NOW = 100000

local function Member(name)
    return { name = name, class = "MAGE" }
end

local groupA = { Member("Alice"), Member("Bob") }
local groupB = { Member("Cara"), Member("Dan") }

Case("a stamp inside the hour is the same copy", function()
    local stored = { name = "Deadmines", at = NOW - (HOUR - 1) }
    assert(Copy.Fresh(stored, NOW, HOUR))
    assert(not Copy.Counts(stored, NOW, HOUR, true))
    assert(Copy.Fresh({ name = "Deadmines", at = NOW }, NOW, HOUR))
end)

Case("an hour-old stamp counts again", function()
    local stored = { name = "Deadmines", at = NOW - HOUR }
    assert(not Copy.Fresh(stored, NOW, HOUR))
    assert(Copy.Counts(stored, NOW, HOUR, true))
    stored.at = NOW - 86400
    assert(Copy.Counts(stored, NOW, HOUR, true))
end)

Case("a login or reload does not count", function()
    local old = { name = "Deadmines", at = NOW - 86400 }
    local fresh = { name = "Deadmines", at = NOW - 10 }
    assert(not Copy.Counts(old, NOW, HOUR, false))
    assert(not Copy.Counts(fresh, NOW, HOUR, false))
    assert(not Copy.Counts(nil, NOW, HOUR, false))
end)

Case("a clock that moved backwards does not stick", function()
    local stored = { name = "Deadmines", at = NOW + HOUR }
    assert(not Copy.Fresh(stored, NOW, HOUR))
    assert(Copy.Counts(stored, NOW, HOUR, true))
end)

Case("one shared name keeps the visit", function()
    assert(not Copy.Differ(groupA, { Member("Bob"), Member("Eve") }, true))
    assert(not Copy.Differ(groupA, { Member("Alice") }, true))
end)

Case("two empty groups are the same solo copy", function()
    assert(not Copy.Differ(nil, {}, false))
    assert(not Copy.Differ({}, {}, false))
    assert(not Copy.Differ(nil, nil, false))
    assert(not Copy.Differ({ { name = "" } }, {}, false))
end)

Case("an empty roster while grouped does not split the visit", function()
    assert(not Copy.Differ(groupA, {}, true))
    assert(not Copy.Differ(groupA, nil, true))
end)

Case("a different group is a new visit", function()
    assert(Copy.Differ(groupA, groupB, true))
    assert(Copy.Differ(groupA, {}, false))
    assert(Copy.Differ({}, { Member("Cara") }, true))
    assert(Copy.Differ(nil, { Member("Cara") }, false))
end)

Case("a stamp and a leave inside the hour can resume", function()
    local stored = { name = "Deadmines", at = NOW - (HOUR - 1) }
    assert(Copy.Resume(stored, NOW - 60, NOW, HOUR))
    assert(not Copy.Counts(stored, NOW, HOUR, true))
end)

Case("an hour-old stamp or leave does not resume", function()
    local oldStamp = { name = "Deadmines", at = NOW - HOUR }
    assert(not Copy.Resume(oldStamp, NOW - 60, NOW, HOUR))
    assert(Copy.Counts(oldStamp, NOW, HOUR, true))
    local oldLeave = { name = "Deadmines", at = NOW - (HOUR + 60) }
    assert(not Copy.Resume(oldLeave, NOW - HOUR, NOW, HOUR))
    assert(Copy.Counts(oldLeave, NOW, HOUR, true))
end)

local function Visit(group, left)
    return {
        instance = "Deadmines", mapID = 36, difficulty = "",
        entered = left - 600, left = left, group = group,
    }
end

local function World(runs, lives, current, grouped)
    local row = { runs = runs, live = lives }
    env.Mine = function()
        return row
    end
    env.time = function() return NOW end
    env.IsInGroup = function() return grouped end
    env.Secret = function() return false end
    env.CurrentGroup = function() return current end
    return row
end

-- The client's strsplit is strsplit(delimiter, subject) and returns one value per field.
local function Split(sep, text)
    local out, start = {}, 1
    while true do
        local from, to = text:find(sep, start, true)
        if not from then
            out[#out + 1] = text:sub(start)
            break
        end
        out[#out + 1] = text:sub(start, from - 1)
        start = to + 1
    end
    return unpack(out)
end
env.strsplit = Split

Case("a different group drops the stamp and counts the new copy", function()
    local stamp = { name = "Deadmines", at = NOW - 1800 }
    assert(not Copy.Counts(stamp, NOW, HOUR, true))
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    World(runs, lives, groupB, true)
    assert(Copy.Take("Deadmines", 36, "") == nil)
    assert(lives["36:"] == nil)
    assert(#runs == 1)
    assert(runs[1].group == groupA)
    assert(Copy.Counts(lives["36:"], NOW, HOUR, true))
end)

Case("a real leave clears the stamp, keeps the visit, and counts", function()
    local stamp = { name = "Deadmines", at = NOW - 1800, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    local row = World(runs, lives, { Member("Bob"), Member("Eve") }, true)
    assert(not Copy.Keeps(false))
    assert(Copy.Take("Deadmines", 36, "", false) == nil)
    assert(lives["36:"] == nil)
    assert(#runs == 1)
    assert(runs[1].group == groupA)
    assert(Copy.Counts(lives["36:"], NOW, HOUR, true))
    assert(row.reentry.copy == 1234)
    assert(row.reentry.run == runs[1])
end)

Case("a ghost leave does not clear the stamp", function()
    assert(Copy.Keeps(true))
    assert(Copy.Keeps(nil))
    assert(not Copy.Keeps(false))
    local stamp = { name = "Deadmines", at = NOW - 60, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 60) }
    World(runs, lives, groupA, true)
    assert(lives["36:"] == stamp)
    assert(lives["36:"].copy == 1234)
    assert(runs[1].left == NOW - 60)
end)

Case("a secret GUID is not split and does not resume", function()
    local calls = 0
    env.strsplit = function()
        calls = calls + 1
        error("split a secret")
    end
    env.issecretvalue = function(v) return v == "secret-guid" end
    assert(Copy.Zone("secret-guid") == nil)
    env.issecretvalue = function() return false end
    env.canaccessvalue = function() return false end
    assert(Copy.Zone("Creature-0-4613-36-1234-639-0000ABCDEF") == nil)
    assert(calls == 0)
    env.strsplit = Split
    env.issecretvalue = nil
    env.canaccessvalue = nil
    local stamp = { name = "Deadmines", at = NOW - 1800, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    World(runs, lives, groupA, true)
    assert(Copy.Take("Deadmines", 36, "", false) == nil)
    assert(lives["36:"] == nil)
    assert(#runs == 1)
end)

Case("the same zone id resumes and does not count", function()
    local stamp = { name = "Deadmines", at = NOW - 1800, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    local prior = runs[1]
    local row = World(runs, lives, { Member("Bob"), Member("Eve") }, true)
    assert(Copy.Take("Deadmines", 36, "", 1234) == prior)
    assert(#runs == 0)
    assert(lives["36:"] == stamp)
    assert(stamp.copy == 1234)
    assert(not Copy.Counts(lives["36:"], NOW, HOUR, true))
    assert(row.reentry == nil)
end)

Case("a different zone id counts", function()
    local stamp = { name = "Deadmines", at = NOW - 1800, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    local prior = runs[1]
    local row = World(runs, lives, groupA, true)
    assert(Copy.Take("Deadmines", 36, "", 9999) == nil)
    assert(lives["36:"] == nil)
    assert(#runs == 1)
    assert(runs[1] == prior)
    assert(Copy.Counts(lives["36:"], NOW, HOUR, true))
    assert(row.reentry.copy == 1234)
end)

Case("a GUID whose instance id is only the map still matches the zone id", function()
    local guid = "Creature-0-4613-36-1234-639-0000ABCDEF"
    assert(Copy.Zone(guid) == 1234)
    assert(Copy.Zone("Creature-0-1465-0-2105-448-0000000001") == nil)
    assert(Copy.Zone("Cast-0-4613-36-1234-1752-0000000002") == 1234)
    assert(Copy.Zone("Cast-0-1465-0-2105-1752-0000000003") == nil)
    assert(Copy.Zone("Player-1234-5678") == nil)
    local stamp = { name = "Deadmines", at = NOW - 1800, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    local prior = runs[1]
    World(runs, lives, groupA, true)
    assert(Copy.Take("Deadmines", 36, "", Copy.Zone(guid)) == prior)
    assert(#runs == 0)
    assert(lives["36:"] == stamp)
    assert(not Copy.Counts(stamp, NOW, HOUR, true))
end)

Case("a later matching zone id takes the count back", function()
    local stamp = { name = "Deadmines", at = NOW - 1800, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    local prior = runs[1]
    prior.loot = 3
    local row = World(runs, lives, groupA, true)
    assert(Copy.Take("Deadmines", 36, "", false) == nil)
    local back = row.reentry
    row.reentry = nil
    row.open = {
        instance = "Deadmines", mapID = 36, difficulty = "",
        entered = NOW, loot = 5, xp = 10, deaths = 1,
        reentry = back,
    }
    row.hour = { { at = NOW, name = "Deadmines", map = 36 } }
    lives["36:"] = { name = "Deadmines", at = NOW }
    Copy.Note(1234)
    assert(row.open == prior)
    assert(prior.left == nil)
    assert(prior.loot == 8)
    assert(prior.xp == 10)
    assert(prior.deaths == 1)
    assert(#runs == 0)
    assert(#row.hour == 0)
    assert(lives["36:"].copy == 1234)
    assert(lives["36:"].at == NOW - 1800)
    assert(not Copy.Counts(lives["36:"], NOW, HOUR, true))
end)

Case("a later different zone id keeps the count", function()
    local stamp = { name = "Deadmines", at = NOW - 1800, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 1800) }
    local prior = runs[1]
    local row = World(runs, lives, groupA, true)
    assert(Copy.Take("Deadmines", 36, "", false) == nil)
    local back = row.reentry
    row.reentry = nil
    row.open = {
        instance = "Deadmines", mapID = 36, difficulty = "",
        entered = NOW, loot = 0, xp = 0, deaths = 0,
        reentry = back,
    }
    row.hour = { { at = NOW, name = "Deadmines", map = 36 } }
    lives["36:"] = { name = "Deadmines", at = NOW }
    Copy.Note(9999)
    assert(row.open ~= prior)
    assert(row.open.reentry == nil)
    assert(#runs == 1)
    assert(#row.hour == 1)
    assert(lives["36:"].copy == 9999)
    assert(lives["36:"].at == NOW)
end)

Case("an empty roster on a real leave still counts", function()
    local stamp = { name = "Deadmines", at = NOW - 60, copy = 1234 }
    local lives = { ["36:"] = stamp }
    local runs = { Visit(groupA, NOW - 60) }
    World(runs, lives, {}, true)
    assert(not Copy.Differ(groupA, {}, true))
    assert(Copy.Take("Deadmines", 36, "", false) == nil)
    assert(lives["36:"] == nil)
    assert(#runs == 1)
    assert(Copy.Counts(lives["36:"], NOW, HOUR, true))
end)

print(count .. " instance tracker copy regressions passed")
