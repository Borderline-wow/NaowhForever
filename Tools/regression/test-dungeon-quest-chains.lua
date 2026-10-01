-- The chain list on a dungeon quest: which step of its chain a quest is, and each step's
-- state. Also checks the generated chains file against the quest data.
local root = arg[1] or "."
local function Read(path)
    local f = assert(io.open(root .. "/" .. path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end
local source = Read("DungeonQuests/NaowhForever_DungeonQuests.lua")
local function Slice(first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a + #first, true), last)
    return source:sub(a, b - 1)
end

local CHUNK = table.concat({
    "local ns = ...\nlocal ACTIVE, DONE, NOT_DONE = 'active', 'done', 'not done'\n",
    Slice("local function StepIDs(step)", "local function OnID(ids)"),
    Slice("local byID = {}", "local function OpenChain("),
    "return Chain, StepState, byID\n",
}, "\n")

local function Load(ns, onQuest, completed)
    local env = setmetatable({
        C_QuestLog = {
            IsOnQuest = function(id) return onQuest[id] == true end,
            IsQuestFlaggedCompleted = function(id) return completed[id] == true end,
        },
    }, { __index = _G })
    local chunk = assert(loadstring(CHUNK))
    setfenv(chunk, env)
    return chunk(ns)
end

local function Fixture(onQuest, completed)
    local ns = {
        DungeonQuests = { { name = "Test", quests = {
            { 5728, "Hidden Enemies" }, { 914, "Leaders of the Fang" }, { 168, "Collecting Memories" },
        } } },
        DungeonQuestChains = {
            [5728] = { 5727, 5728, 5729, 5730 },
            [914] = { 1489, { 1490, 1491 }, 914 },
        },
        DungeonQuestChainNames = {},
    }
    return Load(ns, onQuest or {}, completed or {})
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("a quest in a chain knows its step", function()
    local Chain, _, byID = Fixture()
    local chain, step = Chain(byID[5728])
    assert(#chain == 4 and step == 2)
    chain, step = Chain(byID[914])
    assert(#chain == 3 and step == 3)
end)

Case("a quest on its own has no chain", function()
    local Chain, _, byID = Fixture()
    assert(Chain(byID[168]) == nil)
end)

Case("each step is done, in the log, or not done", function()
    local _, StepState = Fixture({ [5728] = true }, { [5727] = true })
    assert(StepState(5727) == "done")
    assert(StepState(5728) == "active")
    local state, id = StepState(5729)
    assert(state == "not done" and id == 5729)
end)

Case("a step with faction versions is named by the version you have", function()
    local step = { 1490, 1491 }
    local state, id = select(2, Fixture({}, { [1491] = true }))(step)
    assert(state == "done" and id == 1491)
    state, id = select(2, Fixture({ [1491] = true }))(step)
    assert(state == "active" and id == 1491)
    state, id = select(2, Fixture())(step)
    assert(state == "not done" and id == 1490)
end)

Case("every generated chain holds its quest and names every step", function()
    local ns = {}
    local env = setmetatable({ _G = { NaowhForever = ns } }, { __index = _G })
    env.NaowhForever = ns
    for _, path in ipairs({ "DungeonQuests/NaowhForever_DungeonQuestData.lua",
                            "DungeonQuests/NaowhForever_DungeonQuestChains.lua" }) do
        local chunk = assert(loadstring(Read(path)))
        setfenv(chunk, env)
        chunk()
    end
    local Chain, _, byID = Load(ns, {}, {})
    local chained = 0
    for id in pairs(ns.DungeonQuestChains) do
        if byID[id] then
            assert(Chain(byID[id]), "quest " .. id .. " is not in its own chain")
            chained = chained + 1
        end
    end
    for _, chain in pairs(ns.DungeonQuestChains) do
        for _, step in ipairs(chain) do
            for _, id in ipairs(type(step) == "table" and step or { step }) do
                assert(ns.DungeonQuestChainNames[id] or byID[id], "no name for quest " .. id)
            end
        end
    end
    assert(chained > 0)
end)

print(("%d cases passed"):format(count))
