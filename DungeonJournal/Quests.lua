-------------------------------------------------------------------------------
--  Quests.lua -- the Dungeon Journal's quests (ns.Journal.Quests): where each dungeon
--  quest stands for you (done, in your log, ready to hand in, to pick up, what to do
--  first, the level it needs), its chain, where to go for it and tracking it. Rules and
--  actions only, no frames: View/QuestRows.lua draws them. The data is Data/Quests.lua
--  and Data/QuestChains.lua, read when asked, so a test can hand in its own.
--
--  A quest has more IDs than its own (see Data/Quests.lua): alt versions, either of which
--  counts; the other steps of its chain, all of which must be done; and a lead-in, which
--  only counts while you carry it. A step is a quest ID, or a list of IDs (one per faction
--  or class), any of which counts.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal

---@alias JournalQuestKind
---| "prereq"     # a prerequisite is not done yet (Do first)
---| "prereqLog"  # the prerequisite to do next is in your log
---| "low"        # prerequisites done, your level too low to pick it up
---| "pickup"     # you can pick it up
---| "next"       # part of its chain done, the next step not picked up
---| "active"     # in your log
---| "ready"      # in your log with its objectives done
---| "done"       # handed in

---@class JournalQuest  A dungeon quest, as Data/Quests.lua lists it (read-only).
---@field [1] number questID
---@field [2] string name, from the guide
---@field [3] number level, from the guide
---@field [4] "A"|"H"|"B" side
---@field [5] boolean|"pre" shareable, or "pre" for a prerequisite chain
---@field [6] string where it starts
---@field [7]? number uiMapID of the quest giver, outside the dungeon
---@field [8]? number x, percent
---@field [9]? number y, percent
---@field class? string the class it is for (a class quest)
---@field alt? number[] its other versions
---@field steps? (number|number[])[] the rest of its chain
---@field lead? (number|number[])[] a lead-in
---@field next? ({ [1]: number, [2]: number, [3]: number, [4]: string }|false)[] where steps[i] starts

---@class JournalQuestEntry  One line of a dungeon's quest list, filled by Quests.List.
---@field quest JournalQuest
---@field kind JournalQuestKind
---@field tooHigh boolean you can pick it up, but it is five or more levels above you
---@field name string the client's title, else the guide's
---@field level? number the quest's level
---@field where string where to go: its quest giver, or what to do first
---@field inLog boolean
---@field canWaypoint boolean
---@field loggedID? number the ID of the version or step in your log
---@field party number how many of your group are on it too (0 out of a group)
---@field step? number its place in its chain
---@field steps? number its chain's length
---@field rank number its place in the list's order
---@field index number its place in the data

local IsOnQuest = C_QuestLog.IsOnQuest
local IsComplete = C_QuestLog.IsComplete
local IsDone = C_QuestLog.IsQuestFlaggedCompleted
local GetTitle = C_QuestLog.GetTitleForQuestID

local Q = {}
J.Quests = Q

-- How far along a quest's list is: prerequisites first (the one in your log after the one
-- not started), then waiting on your level, then to pick up, the next step, in your log,
-- ready to hand in, done. Data order within each.
local RANK = { prereq = 1, prereqLog = 2, low = 3, pickup = 4, next = 5, active = 6, ready = 7, done = 8 }
-- A quest you can pick up this many levels or more above yours is too high for now.
local TOO_HIGH = 5

-------------------------------------------------------------------------------
--  Steps
-------------------------------------------------------------------------------
-- The first of a step's IDs that check passes, without building a table for a lone ID.
local function StepAny(step, check)
    if type(step) ~= "table" then return check(step) and step or nil end
    for i = 1, #step do
        if check(step[i]) then return step[i] end
    end
end

local function StepDone(step)
    return StepAny(step, IsDone) ~= nil
end

-- The first step of a list that is in your log, or nil.
local function OnList(list)
    if not list then return end
    for i = 1, #list do
        local id = StepAny(list[i], IsOnQuest)
        if id then return id end
    end
end

---@param quest JournalQuest
---@return number? loggedID the ID of whichever version or step of it is in your log
function Q.LoggedID(quest)
    if IsOnQuest(quest[1]) then return quest[1] end
    return OnList(quest.alt) or OnList(quest.steps) or OnList(quest.lead)
end
local LoggedID = Q.LoggedID

-- The prerequisite to do next for a quest not picked up yet, its place in the list and the
-- list's length; nil once they are all done. It is the one after the last step done: a later
-- step done means the ones before it are, even a lead-in the game never flags as completed.
local function NextPrereq(quest)
    local list = J.QuestPrereqs[quest[1]]
    if not list then return end
    local n = #list
    for i = n, 1, -1 do
        if StepDone(list[i]) then
            if i == n then return end
            return list[i + 1], i + 1, n
        end
    end
    return list[1], 1, n
end

-------------------------------------------------------------------------------
--  Where a quest stands
-------------------------------------------------------------------------------
---@param quest JournalQuest
---@return number? level the level it can be picked up at, from the data
function Q.MinLevel(quest)
    return J.QuestMinLevel[quest[1]]
end

---@param quest JournalQuest
---@return JournalQuestKind
function Q.Kind(quest)
    local id = LoggedID(quest)
    if id then return IsComplete(id) and "ready" or "active" end
    local first = IsDone(quest[1])
    local alt = quest.alt
    if alt then
        for i = 1, #alt do first = first or IsDone(alt[i]) end
    end
    local all, any = first, first
    local steps = quest.steps
    if steps then
        for i = 1, #steps do
            local done = StepDone(steps[i])
            all, any = all and done, any or done
        end
    end
    if all then return "done" end
    if any then return "next" end
    local step = NextPrereq(quest)
    if step then return StepAny(step, IsOnQuest) and "prereqLog" or "prereq" end
    local need = Q.MinLevel(quest)
    if need and UnitLevel("player") < need then return "low" end
    return "pickup"
end
local Kind = Q.Kind

---@param kind JournalQuestKind
function Q.InLog(kind)
    return kind == "active" or kind == "ready"
end
local InLog = Q.InLog

-- Not picked up yet, whether or not it can be now.
---@param kind JournalQuestKind
function Q.ToPickUp(kind)
    return kind == "pickup" or kind == "prereq" or kind == "prereqLog" or kind == "low"
end
local ToPickUp = Q.ToPickUp

-- The quest level as the game has it (the number the quest log shows). The data's level is
-- the guide's and often matches neither that nor the required level, so it is only the
-- fallback until the client has loaded the quest; the load is asked for once, and
-- QUEST_DATA_LOAD_RESULT tells a view to draw again.
local requested = {}

---@param quest JournalQuest
---@return number? level
function Q.Level(quest)
    local id = quest[1]
    local level = C_QuestLog.GetQuestDifficultyLevel(id)
    if level and level > 0 then return level end
    if not requested[id] then
        requested[id] = true
        C_QuestLog.RequestLoadQuestByID(id)
    end
    return quest[3]
end
local Level = Q.Level

---@param quest JournalQuest
---@return string name the client's title (in the player's language), else the guide's
function Q.Name(quest)
    return GetTitle(quest[1]) or quest[2]
end

-- Grey in the quest log: too far under your level to be worth picking up.
local function Grey(quest)
    local level = Level(quest)
    return level ~= nil and GetQuestDifficultyColor(level) == QuestDifficultyColors.trivial
end

-- Your faction's quests and your class's class quests.
local function ForMe(quest, class, faction)
    if quest.class and quest.class ~= class then return false end
    local side = quest[4]
    return side == "B" or (side == "A" and faction == "Alliance") or (side == "H" and faction == "Horde")
end

-- Listed: for you, not handed in, and not a grey one you have not picked up.
local function Listed(quest, kind, class, faction)
    return ForMe(quest, class, faction) and kind ~= "done" and not (ToPickUp(kind) and Grey(quest))
end

-------------------------------------------------------------------------------
--  Chains
-------------------------------------------------------------------------------
local byID   -- questID -> its quest in the data, built on first use

local function QuestByID(id)
    if not byID then
        byID = {}
        for _, dungeon in ipairs(J.QuestData) do
            for _, quest in ipairs(dungeon.quests) do byID[quest[1]] = quest end
        end
    end
    return byID[id]
end

-- The quest's whole path, first step first, and which step of it the quest is: its
-- prerequisites, then its own chain from Wowhead's Series, each step once. The Series alone
-- often starts partway, so the prerequisites come first. The data never changes, so each
-- path is worked out once; false marks a quest with neither.
local paths = {}

-- Whether a step stands for the ID.
local function Covers(step, id)
    if type(step) ~= "table" then return step == id end
    for i = 1, #step do
        if step[i] == id then return true end
    end
    return false
end

-- Adds a step to a path unless one of its IDs is on it already.
local function AddStep(steps, seen, step)
    local ids = type(step) == "table" and step or { step }
    for i = 1, #ids do
        if seen[ids[i]] then return end
    end
    for i = 1, #ids do seen[ids[i]] = true end
    steps[#steps + 1] = step
end

local function BuildPath(id)
    local prereqs, series = J.QuestPrereqs[id], J.QuestChains[id]
    if not (prereqs or series) then return false end
    local steps, seen = {}, {}
    if prereqs then
        for i = 1, #prereqs do AddStep(steps, seen, prereqs[i]) end
    end
    if series then
        for i = 1, #series do AddStep(steps, seen, series[i]) end
    end
    AddStep(steps, seen, id)
    for i = 1, #steps do
        if Covers(steps[i], id) then return { steps = steps, own = i } end
    end
    return false
end

---@param quest JournalQuest
---@return (number|number[])[]? steps its whole chain, prerequisites first
---@return number? own which step it is
function Q.Chain(quest)
    local id = quest[1]
    local path = paths[id]
    if path == nil then
        path = BuildPath(id)
        paths[id] = path
    end
    if path then return path.steps, path.own end
end
local Chain = Q.Chain

---@alias JournalStepState "active"|"done"|"todo"

-- Done, in your log or neither, and the ID of the step's version to name it by.
---@return JournalStepState state
---@return number id
function Q.StepState(step)
    local id = StepAny(step, IsOnQuest)
    if id then return "active", id end
    id = StepAny(step, IsDone)
    if id then return "done", id end
    return "todo", type(step) == "table" and step[1] or step
end
local StepState = Q.StepState

---@return string name a step's name: the client's title, else the chain data's or the quest data's
function Q.StepName(id)
    local quest = QuestByID(id)
    return GetTitle(id) or J.QuestChainNames[id] or (quest and quest[2]) or tostring(id)
end
local StepName = Q.StepName

-- Where one ID is picked up: its quest giver in the quest data, else where its quest page
-- says it starts.
local function SpotOf(id)
    local quest = QuestByID(id)
    if quest and quest[7] then return quest[7], quest[8], quest[9], " (quest giver)" end
    local start = J.QuestChainStarts[id]
    if start then return start[1], start[2], start[3], " (" .. start[4] .. ")" end
end

-- Where a step is picked up, the version the step state names first.
local function StepSpot(step, id)
    local map, x, y, note = SpotOf(id)
    if map then return map, x, y, note end
    if type(step) ~= "table" then return SpotOf(step) end
    for i = 1, #step do
        map, x, y, note = SpotOf(step[i])
        if map then return map, x, y, note end
    end
end

---@return boolean has somewhere to put a waypoint for this step
function Q.StepHasSpot(step, id)
    return StepSpot(step, id) ~= nil
end

-- The line under a quest you cannot pick up yet: the prerequisite to do next and how far
-- along the list it is. Also the step, its state and the ID of the version to name it by.
local function PrereqLine(quest)
    local step, i, n = NextPrereq(quest)
    if not step then return end
    local state, id = StepState(step)
    local text = ("Do first%s: %s (%d/%d)"):format(state == "active" and " (in your log)" or "", StepName(id), i, n)
    return text, step, state, id
end

-- With part of a chain done, where its next step starts: quest.next runs alongside
-- quest.steps, next[i] = { uiMapID, x, y, where } for steps[i], false where unknown.
local function NextSpot(quest)
    local steps, spots = quest.steps, quest.next
    if not (steps and spots) then return end
    for i = 1, #steps do
        if not StepDone(steps[i]) then return spots[i] or nil end
    end
end

-------------------------------------------------------------------------------
--  Where to go
-------------------------------------------------------------------------------
-- The where text without the guide's prerequisite note, once the prerequisites are known.
local function Where(quest)
    return J.QuestWhere[quest[1]] or quest[6]
end

-- A quest that starts inside its dungeon (an item a boss drops) has no quest giver outside:
-- its waypoint is the dungeon's entrance, where you go for it. nil where that is not known.
local dungeonOf   -- quest -> the dungeon it is listed under, built on first use

local function EntranceOf(quest)
    if not dungeonOf then
        if not J.Dungeons then return nil end
        dungeonOf = {}
        for _, dungeon in ipairs(J.Dungeons()) do
            local data = dungeon.quests
            for _, q in ipairs(data and data.quests or {}) do dungeonOf[q] = dungeon end
        end
    end
    local dungeon = dungeonOf[quest]
    return dungeon and dungeon.entrance
end

local ENTRANCE_NOTE = " (dungeon entrance)"

-- Where the waypoint goes and what the line under the quest says: the quest giver; with part
-- of the chain done, whoever gives the next step; with a prerequisite to do first, whoever
-- gives that; for one that starts inside the dungeon, the dungeon's entrance. map is nil
-- where none of those is known. note says what the spot is, for the waypoint's label.
local function Destination(quest, kind)
    if kind == "next" then
        local spot = NextSpot(quest)
        if spot then return spot[4], spot[1], spot[2], spot[3] end
    elseif kind == "prereq" or kind == "prereqLog" then
        local text, step, _, id = PrereqLine(quest)
        local map, x, y, note = StepSpot(step, id)
        return map and text .. note or text, map, x, y
    end
    if quest[7] then return Where(quest), quest[7], quest[8], quest[9] end
    local entrance = EntranceOf(quest)
    if entrance then return Where(quest), entrance.map, entrance.x, entrance.y, ENTRANCE_NOTE end
    return Where(quest)
end

-- Where the game's own navigation sends you for a quest in your log, when a waypoint can go
-- there: map, x, y in percent.
local function Navigation(id)
    local map, x, y = C_QuestLog.GetNextWaypoint(id)
    if map and x and y and ns.CanPlaceWaypoint(map) then return map, x * 100, y * 100 end
end

-- Where a step's waypoint goes: in your log, where the game's own navigation sends you; any
-- other step, where it is picked up. map, x, y, note; nil when not known.
local function StepTarget(step, state, id)
    if state == "active" then
        local map, x, y = Navigation(id)
        if map then return map, x, y end
    end
    return StepSpot(step, id)
end

---@param step number|number[]
---@param state JournalStepState
---@param id number
---@param name string
function Q.StepWaypoint(step, state, id, name)
    local map, x, y, note = StepTarget(step, state, id)
    if map then
        ns.PlaceWaypoint(name, map, x, y, note)
    else
        ns.Print(("Where %s starts is not known."):format(name))
    end
end

-- A quest in your log goes where the game's own navigation would send you (its objective or
-- turn-in); Forever has no route for many vanilla quests, so without one it falls back to
-- the turn-in NPC, then the quest giver, who for most of these also takes it back.
local function Route(quest, id)
    local map, x, y = Navigation(id)
    if map then return map, x, y end
    local turnIn = J.QuestTurnIns[id]
    if turnIn and ns.CanPlaceWaypoint(turnIn[1]) then
        return turnIn[1], turnIn[2], turnIn[3], " (turn in: " .. turnIn[4] .. ")"
    end
    if quest[7] and ns.CanPlaceWaypoint(quest[7]) then return quest[7], quest[8], quest[9], " (quest giver)" end
end

-- Where a quest's waypoint goes, and its name: its route while it is in your log; the
-- prerequisite to do next while there is one; else where it or its chain's next step is
-- picked up. Returns name, map, x, y (percent), note; with no map, a line saying why when
-- there is one to say.
---@param quest JournalQuest
---@return string name
---@return number? map
---@return number? x
---@return number? y
---@return string? note
---@return string? why
function Q.Spot(quest)
    local logged = LoggedID(quest)
    if logged then
        local name = GetTitle(logged) or quest[2]
        local map, x, y, note = Route(quest, logged)
        return name, map, x, y, note,
            not map and ("The game has no route for %s, and its quest giver's spot is not known."):format(name) or nil
    end
    local kind = Kind(quest)
    if kind == "prereq" or kind == "prereqLog" then
        local _, step, state, id = PrereqLine(quest)
        local name = StepName(id)
        local map, x, y, note = StepTarget(step, state, id)
        return name, map, x, y, note, not map and ("Where %s starts is not known."):format(name) or nil
    end
    local _, map, x, y, note = Destination(quest, kind)
    return Q.Name(quest), map, x, y, note
end

-- The quest's waypoint, where Q.Spot says.
---@param quest JournalQuest
function Q.Waypoint(quest)
    local name, map, x, y, note, why = Q.Spot(quest)
    if map then
        ns.PlaceWaypoint(name, map, x, y, note)
    elseif why then
        ns.Print(why)
    end
end

-- Selects and super-tracks the quest, and watches it, without opening the log. The quest log
-- lives on the world map in this engine, and opening it from addon code taints the map's
-- quest pins: the next time the map opens in combat their SetPassThroughButtons is blocked.
---@param id number the quest ID in your log
function Q.Track(id)
    C_QuestLog.AddQuestWatch(id)
    C_QuestLog.SetSelectedQuest(id)
    C_SuperTrack.SetSuperTrackedQuestID(id)
    ns.Print(("Tracking %s. Press L to see it in your quest log."):format(GetTitle(id) or id))
end

-------------------------------------------------------------------------------
--  Your group
-------------------------------------------------------------------------------
local PARTY = { "party1", "party2", "party3", "party4" }

---@param unit string a group member
---@return boolean on whether they are on the quest, or on the version of it in your log
function Q.UnitOnQuest(unit, quest, loggedID)
    return C_QuestLog.IsUnitOnQuest(unit, quest[1])
        or (loggedID ~= nil and C_QuestLog.IsUnitOnQuest(unit, loggedID))
end
local UnitOnQuest = Q.UnitOnQuest

---@return number count how many of your group are on the quest too
function Q.PartyCount(quest, loggedID)
    local count = 0
    for i = 1, math.min(GetNumSubgroupMembers(), #PARTY) do
        if UnitOnQuest(PARTY[i], quest, loggedID) then count = count + 1 end
    end
    return count
end
local PartyCount = Q.PartyCount

-------------------------------------------------------------------------------
--  A dungeon's list
-------------------------------------------------------------------------------
local function ByRank(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.index < b.index
end

-- Why the dungeon lists no quest for you, as a line: none for your class and side ("None for
-- you here. The rest: 3 Horde, 1 Warlock."), every one handed in, or the rest not for your
-- level yet. nil for a dungeon with no quests at all.
---@param data? table the dungeon's Data/Quests.lua entry (dungeon.quests)
---@return string? why
function Q.NoneWhy(data)
    local quests = data and data.quests
    if not quests or #quests == 0 then return nil end
    local done, total = Q.Progress(data)
    if total > 0 then
        if done == total then return "Every quest here for you is handed in." end
        return "None to pick up right now: the rest are not for your level yet."
    end
    local faction = UnitFactionGroup("player")
    local other, classes, order = 0, {}, {}
    for i = 1, #quests do
        local quest = quests[i]
        if quest.class then
            if not classes[quest.class] then order[#order + 1] = quest.class end
            classes[quest.class] = (classes[quest.class] or 0) + 1
        elseif quest[4] ~= "B" and not (quest[4] == "A" and faction == "Alliance")
            and not (quest[4] == "H" and faction == "Horde") then
            other = other + 1
        end
    end
    local parts = {}
    if other > 0 then parts[1] = ("%d %s"):format(other, faction == "Horde" and "Alliance" or "Horde") end
    for _, class in ipairs(order) do
        parts[#parts + 1] = ("%d %s"):format(classes[class], LOCALIZED_CLASS_NAMES_MALE[class] or class)
    end
    return "None for you here. The rest: " .. table.concat(parts, ", ") .. "."
end

-- How many of the dungeon's quests for your class and side you have handed in, of how many.
---@param data? table the dungeon's Data/Quests.lua entry (dungeon.quests)
---@return number done
---@return number total
function Q.Progress(data)
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local done, total = 0, 0
    local quests = data and data.quests
    for i = 1, quests and #quests or 0 do
        local quest = quests[i]
        if ForMe(quest, class, faction) then
            total = total + 1
            if Kind(quest) == "done" then done = done + 1 end
        end
    end
    return done, total
end

-- The dungeon's quests for you that are not done yet, grey ones left out, in list order.
-- Fills out (wiped first) with entries taken from pool and reused on every call: both
-- belong to the caller, so two views never share an entry. Returns out.
---@param data table the dungeon's Data/Quests.lua entry (dungeon.quests)
---@param out JournalQuestEntry[]
---@param pool JournalQuestEntry[]
---@return JournalQuestEntry[] out
function Q.List(data, out, pool)
    wipe(out)
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local level = UnitLevel("player")
    for index, quest in ipairs(data.quests) do
        local kind = Kind(quest)
        if Listed(quest, kind, class, faction) then
            local n = #out + 1
            local entry = pool[n] or {}
            pool[n] = entry
            local where, map = Destination(quest, kind)
            local questLevel = Level(quest)
            entry.quest, entry.kind, entry.index, entry.rank = quest, kind, index, RANK[kind]
            entry.name, entry.level = Q.Name(quest), questLevel
            entry.tooHigh = kind == "pickup" and questLevel ~= nil and questLevel >= level + TOO_HIGH
            entry.where, entry.inLog = where, InLog(kind)
            entry.canWaypoint = map ~= nil or kind == "prereqLog" or entry.inLog
            entry.loggedID = LoggedID(quest)
            entry.party = PartyCount(quest, entry.loggedID)
            local chain, step = Chain(quest)
            entry.step, entry.steps = step, chain and #chain
            out[n] = entry
        end
    end
    table.sort(out, ByRank)
    return out
end

-- A number that changes when any of the dungeon's quests changes state, so a view can tell
-- a quest log update that matters from one that only moved an objective. Made without a
-- table; two different states giving the same number is possible but rare, and only delays
-- a redraw to the next event.
---@param data table the dungeon's Data/Quests.lua entry
---@return number signature
function Q.Signature(data)
    local signature = 0
    for _, quest in ipairs(data.quests) do
        signature = (signature * 9 + RANK[Kind(quest)]) % 2147483647
    end
    return signature
end

-- How many of the dungeon's quests for you are still to pick up and how many are in your
-- log, counted as List lists them, without a list.
---@param data table the dungeon's Data/Quests.lua entry
---@return number toPickUp
---@return number inLog
function Q.Count(data)
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local toPickUp, inLog = 0, 0
    for _, quest in ipairs(data.quests) do
        local kind = Kind(quest)
        if Listed(quest, kind, class, faction) then
            if InLog(kind) then
                inLog = inLog + 1
            elseif ToPickUp(kind) then
                toPickUp = toPickUp + 1
            end
        end
    end
    return toPickUp, inLog
end
