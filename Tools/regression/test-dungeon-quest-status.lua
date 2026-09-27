-- Dungeon Quests: a quest in your log reads Complete once the log says its objectives are
-- done, whichever of its IDs is the one you carry; the rest keep their old statuses. A quest
-- is grey exactly when the quest log would colour its level grey.
local f = assert(io.open(arg[1] or "DungeonQuests/NaowhForever_DungeonQuests.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

-- on: quest IDs in the log; complete: logged IDs with objectives done; done: turned in.
local function Fixture(on, complete, done)
    local set = function(t)
        local out = {}
        for _, id in ipairs(t or {}) do out[id] = true end
        return out
    end
    on, complete, done = set(on), set(complete), set(done)
    local env = setmetatable({
        C_QuestLog = {
            IsOnQuest = function(id) return on[id] == true end,
            IsComplete = function(id) return complete[id] == true end,
            IsQuestFlaggedCompleted = function(id) return done[id] == true end,
        },
    }, { __index = _G })
    local code = Slice("local DONE, ACTIVE, MISSING", "\n-- Instance ID")
        .. Slice("-- Part of a chain done", "\n-- Your faction's quests")
        .. "\nreturn { Status = Status, InLog = InLog, DONE = DONE, ACTIVE = ACTIVE,"
        .. " READY = READY, MISSING = MISSING, NEXT = NEXT }"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    return chunk()
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

local plain = { 100, "Plain", 20, "B", true, "" }
local chain = { 200, "Chain", 20, "B", true, "", steps = { 201, { 202, 203 } } }
local alt = { 300, "Alt", 20, "B", true, "", alt = { 301 } }
local lead = { 400, "Lead", 20, "B", true, "", lead = { 401 } }

Case("a quest in the log with objectives left is In log", function()
    local m = Fixture({ 100 })
    assert(m.Status(plain) == m.ACTIVE)
    assert(m.InLog(m.Status(plain)))
end)
Case("a quest in the log with its objectives done is Complete", function()
    local m = Fixture({ 100 }, { 100 })
    assert(m.Status(plain) == m.READY)
    assert(m.READY:find("Complete", 1, true) and not m.READY:find("Completed", 1, true))
    assert(m.InLog(m.Status(plain)))
end)
Case("Complete follows the logged step, alt or lead-in, not the first ID", function()
    local m = Fixture({ 203, 301, 401 }, { 203, 401 }, { 200, 201 })
    assert(m.Status(chain) == m.READY)
    assert(m.Status(alt) == m.ACTIVE)
    assert(m.Status(lead) == m.READY)
end)
Case("IsComplete on a quest that is not in the log does not count", function()
    local m = Fixture({}, { 100 })
    assert(m.Status(plain) == m.MISSING)
end)
Case("turned in, part done and missing are unchanged", function()
    local m = Fixture({}, {}, { 100, 200, 301 })
    assert(m.Status(plain) == m.DONE)
    assert(m.Status(chain) == m.NEXT)
    assert(m.Status(alt) == m.DONE)
    assert(m.Status(lead) == m.MISSING)
    assert(not m.InLog(m.DONE) and not m.InLog(m.NEXT) and not m.InLog(m.MISSING))
end)

-- The quest log's colouring (DifficultyUtil.GetRelativeDifficultyColor), for a player of
-- this level with this trivial range.
local function GreyFixture(player, range, levels)
    local colors = { trivial = {}, standard = {}, difficult = {}, verydifficult = {}, impossible = {} }
    local env = setmetatable({
        QuestDifficultyColors = colors,
        GetQuestDifficultyColor = function(level)
            local diff = level - player
            if diff >= 5 then return colors.impossible
            elseif diff >= 3 then return colors.verydifficult
            elseif diff >= -4 then return colors.difficult
            elseif -diff <= range then return colors.standard
            end
            return colors.trivial
        end,
        C_QuestLog = {
            GetQuestDifficultyLevel = function(id) return levels[id] or 0 end,
            RequestLoadQuestByID = function() end,
        },
    }, { __index = _G })
    local code = Slice("local requested = {}", "\n-- The quest's line") .. "\nreturn Grey"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    return chunk()
end

Case("grey follows the quest log's own colour for the game's quest level", function()
    local Grey = GreyFixture(30, 8, { [1] = 21, [2] = 22, [3] = 26, [4] = 40 })
    assert(Grey({ 1, "", 25 }))
    assert(not Grey({ 2, "", 10 }))
    assert(not Grey({ 3, "", 10 }))
    assert(not Grey({ 4, "", 10 }))
end)
Case("an unloaded quest is judged by the data file's level until the game has it", function()
    local Grey = GreyFixture(30, 8, {})
    assert(Grey({ 5, "", 15 }))
    assert(not Grey({ 6, "", 28 }))
    assert(not Grey({ 7, "" }))
end)
print(count .. " dungeon quest status regressions passed")
