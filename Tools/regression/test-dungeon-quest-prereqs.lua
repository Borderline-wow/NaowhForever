-- Dungeon Quests: a quest you have not picked up says what to do first. With a prerequisite
-- not done it reads Do first and names the next one with how far along the list it is (the
-- one after the last step done); with that step in your log it is the in-log Do first; with
-- them all done but your level too low it names the level; otherwise it is to pick up. The
-- waypoint goes to the step's quest giver, or where the game routes you while it is in your
-- log. Also checks the generated prerequisite lists against the quest data.
local root = arg[1] or "."
local function Read(path)
    local f = assert(io.open(root .. "/" .. path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end
local source = Read("DungeonQuests/NaowhForever_DungeonQuests.lua")
local function Slice(a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local CHUNK = table.concat({
    Slice("local MUTED", "\n-- Instance ID"),
    Slice("-- Part of a chain done", "\n-- Your faction's quests"),
    Slice("-- With part of a chain done, where", "\n-- Marks where the quest giver"),
    Slice("local byID = {}", "-- Every quest of the chain in order"),
    "return { Status = Status, StatusText = StatusText, PrereqLine = PrereqLine, Where = Where,"
        .. " WaypointSpot = WaypointSpot, SetWaypoint = SetWaypoint, ToPickUp = ToPickUp,"
        .. " RANK = RANK, RANKS = RANKS, MISSING = MISSING, PREREQ = PREREQ,"
        .. " PREREQ_LOG = PREREQ_LOG, LOW = LOW, ACTIVE = ACTIVE, DONE = DONE }",
}, "\n")

local DEFIAS = { 65, 132, 135, 141, 142, 155 }
local function Set(t)
    local out = {}
    for _, id in ipairs(t or {}) do out[id] = true end
    return out
end

-- on: quest IDs in the log; done: turned in; level: yours. placed collects waypoints.
local function Fixture(on, done, level)
    on, done = Set(on), Set(done)
    local placed = {}
    local ns = {
        DungeonQuests = { { name = "The Deadmines", quests = {
            { 214, "Red Silk Bandanas", 17, "A", "pre",
              "Westfall, Sentinel Hill - Scout Riell Complete 6 quests, starting with The Defias "
              .. "Brotherhood (56.7, 47.4)", 1436, 56.7, 47.4 },
            { 500, "Split", 20, "B", "pre", "Somewhere", 1411, 10, 10 },
            { 600, "Plain", 20, "B", true, "Plain place", 1411, 20, 20 },
        } } },
        DungeonQuestPrereqs = { [214] = DEFIAS, [500] = { { 501, 502 }, 503 } },
        DungeonQuestMinLevel = { [214] = 14, [600] = 30 },
        DungeonQuestWhere = { [214] = "Westfall, Sentinel Hill - Scout Riell (56.7, 47.4)" },
        DungeonQuestChainNames = { [65] = "The Defias Brotherhood", [132] = "The Defias Brotherhood",
            [135] = "The Defias Brotherhood", [141] = "The Defias Brotherhood",
            [142] = "The Defias Brotherhood", [155] = "The Defias Brotherhood",
            [501] = "Alliance Start", [502] = "Horde Start", [503] = "Middle" },
        DungeonQuestChainStarts = { [141] = { 1436, 56.3, 47.5, "Gryan Stoutmantle" } },
        Print = function() end,
    }
    local env = setmetatable({
        ns = ns,
        C_QuestLog = {
            IsOnQuest = function(id) return on[id] == true end,
            IsComplete = function() return false end,
            IsQuestFlaggedCompleted = function(id) return done[id] == true end,
            GetTitleForQuestID = function() return nil end,
            GetNextWaypoint = function(id) if on[id] then return 1437, 0.25, 0.75 end end,
        },
        UnitLevel = function() return level or 20 end,
        PlaceWaypoint = function(title, map, x, y, note)
            placed[#placed + 1] = { title = title, map = map, x = x, y = y, note = note }
            return true
        end,
    }, { __index = _G })
    local chunk = assert(loadstring(CHUNK))
    setfenv(chunk, env)
    local m = chunk()
    local byID = {}
    for _, quest in ipairs(ns.DungeonQuests[1].quests) do byID[quest[1]] = quest end
    return m, byID, placed
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("nothing done: Do first names the first step, 1 of 6", function()
    local m, q = Fixture()
    assert(m.Status(q[214]) == m.PREREQ)
    assert(m.PrereqLine(q[214]) == "Do first: The Defias Brotherhood (1/6)")
    assert(m.ToPickUp(m.PREREQ))
end)

Case("some steps done: Do first names the next step with the right count", function()
    local m, q = Fixture({}, { 65, 132, 135 })
    assert(m.Status(q[214]) == m.PREREQ)
    local text, step = m.PrereqLine(q[214])
    assert(text == "Do first: The Defias Brotherhood (4/6)" and step == 141, text)
end)

Case("a later step done counts the ones before it as done", function()
    local m, q = Fixture({}, { 142 })
    local text, step = m.PrereqLine(q[214])
    assert(step == 155 and text:find("(6/6)", 1, true), text)
end)

Case("the needed step in your log is the in-log Do first", function()
    local m, q = Fixture({ 141 }, { 65, 132, 135 })
    assert(m.Status(q[214]) == m.PREREQ_LOG)
    assert(m.PrereqLine(q[214]) == "Do first (in your log): The Defias Brotherhood (4/6)")
end)

Case("a step with faction versions: either one done or in the log counts", function()
    local m, q = Fixture({}, { 502 })
    local text, step = m.PrereqLine(q[500])
    assert(step == 503 and text == "Do first: Middle (2/2)", text)
    m, q = Fixture({ 502 })
    assert(m.Status(q[500]) == m.PREREQ_LOG)
    assert(m.PrereqLine(q[500]) == "Do first (in your log): Horde Start (1/2)")
end)

Case("all done but level too low: Level N to pick up, muted", function()
    local m, q = Fixture({}, DEFIAS, 12)
    assert(m.Status(q[214]) == m.LOW)
    assert(m.StatusText(q[214], m.LOW) == "|cff9ca3afLevel 14 to pick up|r")
    assert(m.PrereqLine(q[214]) == nil)
    m, q = Fixture({}, {}, 29)
    assert(m.Status(q[600]) == m.LOW)
    assert(m.StatusText(q[600], m.LOW):find("Level 30 to pick up", 1, true))
end)

Case("all done and level high enough: to pick up", function()
    local m, q = Fixture({}, DEFIAS, 14)
    assert(m.Status(q[214]) == m.MISSING)
    assert(m.StatusText(q[214], m.MISSING) == m.MISSING)
    m, q = Fixture({}, {}, 30)
    assert(m.Status(q[600]) == m.MISSING)
end)

Case("the quest itself in the log or done ignores its prerequisites", function()
    local m, q = Fixture({ 214 })
    assert(m.Status(q[214]) == m.ACTIVE)
    m, q = Fixture({}, { 214 })
    assert(m.Status(q[214]) == m.DONE)
end)

Case("the where line drops the prerequisite note once the list is known", function()
    local m, q = Fixture()
    assert(m.Where(q[214]) == "Westfall, Sentinel Hill - Scout Riell (56.7, 47.4)")
    assert(m.Where(q[600]) == "Plain place")
end)

Case("the waypoint goes to the step's quest giver, or the game's route while in the log", function()
    local m, q, placed = Fixture({}, { 65, 132, 135 })
    local map, x, y, where = m.WaypointSpot(q[214])
    assert(map == 1436 and x == 56.3 and y == 47.5, map)
    assert(where == "Do first: The Defias Brotherhood (4/6) (Gryan Stoutmantle)", where)
    m.SetWaypoint(q[214])
    assert(#placed == 1 and placed[1].map == 1436 and placed[1].note == " (Gryan Stoutmantle)")
    m, q, placed = Fixture({ 141 }, { 65, 132, 135 })
    m.SetWaypoint(q[214])
    assert(#placed == 1 and placed[1].map == 1437 and placed[1].x == 25 and placed[1].y == 75)
    m, q, placed = Fixture({}, DEFIAS)
    m.SetWaypoint(q[214])
    assert(#placed == 1 and placed[1].map == 1436 and placed[1].x == 56.7)
end)

Case("every status has its own place in the list order", function()
    local m = Fixture()
    local seen = {}
    for _, status in ipairs({ m.PREREQ, m.PREREQ_LOG, m.LOW, m.MISSING, m.ACTIVE, m.DONE }) do
        local r = m.RANK[status]
        assert(r and r >= 1 and r <= m.RANKS and not seen[r])
        seen[r] = true
    end
    assert(m.RANK[m.PREREQ] < m.RANK[m.MISSING] and m.RANK[m.LOW] < m.RANK[m.MISSING])
end)

-- The generated lists: each step is a quest ID or a table of them, none twice, never the
-- quest itself, every step named, and no quest reachable from its own prerequisites.
Case("every generated prerequisite list is well formed and free of loops", function()
    local ns = {}
    local env = setmetatable({ _G = { NaowhForever = ns } }, { __index = _G })
    for _, path in ipairs({ "DungeonQuests/NaowhForever_DungeonQuestData.lua",
                            "DungeonQuests/NaowhForever_DungeonQuestChains.lua" }) do
        local chunk = assert(loadstring(Read(path)))
        setfenv(chunk, env)
        chunk()
    end
    local byID = {}
    for _, dungeon in ipairs(ns.DungeonQuests) do
        for _, quest in ipairs(dungeon.quests) do byID[quest[1]] = quest end
    end
    local function IDs(step)
        if type(step) == "number" then return { step } end
        assert(type(step) == "table" and #step > 0, "a step is an ID or a table of IDs")
        for _, id in ipairs(step) do assert(type(id) == "number" and id > 0, "bad ID") end
        return step
    end
    local lists = 0
    for questID, list in pairs(ns.DungeonQuestPrereqs) do
        assert(byID[questID], "prerequisites for " .. questID .. ", which is not a dungeon quest")
        assert(type(list) == "table" and #list > 0, "empty list for " .. questID)
        local seen = {}
        for _, step in ipairs(list) do
            for _, id in ipairs(IDs(step)) do
                assert(id ~= questID, questID .. " is among its own prerequisites")
                assert(not seen[id], questID .. " lists " .. id .. " twice")
                seen[id] = true
                assert(ns.DungeonQuestChainNames[id] or byID[id], "no name for quest " .. id)
            end
        end
        lists = lists + 1
    end
    -- Depth-first over quest -> each ID of its prerequisites; a quest met again while its
    -- own walk is open is a loop.
    local state = {}
    local function Walk(id)
        if state[id] == "open" then error("prerequisite loop through quest " .. id) end
        if state[id] == "done" then return end
        state[id] = "open"
        for _, step in ipairs(ns.DungeonQuestPrereqs[id] or {}) do
            for _, other in ipairs(IDs(step)) do Walk(other) end
        end
        state[id] = "done"
    end
    for questID in pairs(ns.DungeonQuestPrereqs) do Walk(questID) end
    for questID, level in pairs(ns.DungeonQuestMinLevel) do
        assert(byID[questID], "a level for " .. questID .. ", which is not a dungeon quest")
        assert(type(level) == "number" and level >= 1 and level <= 60 and level % 1 == 0)
    end
    for questID, where in pairs(ns.DungeonQuestWhere) do
        assert(ns.DungeonQuestPrereqs[questID] and type(where) == "string" and where ~= "")
    end
    -- The example the feature started from.
    local bandanas = ns.DungeonQuestPrereqs[214]
    assert(bandanas and bandanas[1] == 65 and #bandanas == 6, "Red Silk Bandanas starts with 65, 6 steps")
    assert(ns.DungeonQuestMinLevel[214] == 14)
    assert(lists > 50, "only " .. lists .. " lists")
end)

print(count .. " dungeon quest prerequisite regressions passed")
