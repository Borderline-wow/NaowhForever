-------------------------------------------------------------------------------
--  Kills.lua -- how many times this character has killed each boss, when, and who was with
--  it (ns.Journal.Kills), while the Journal is on; off, nothing is made or registered.
--
--  Counted from ENCOUNTER_END, which names the boss by an encounter ID (each boss's
--  `encounters` in Data/Dungeons/: any of them counts, and the kills are kept under the
--  first) and says how long the fight took.
--
--  A boss the game does not run as an encounter (a rare) cannot be counted: inside a
--  dungeon the game says something died (UNIT_DIED, PARTY_KILL) but keeps which creature
--  secret (seen on Forever 1.60.1 in The Deadmines, 2026-09-30), and working it out another
--  way would be recovering what the game withholds. One killed on the way into another
--  boss's fight (Sneed's Shredder, which Sneed climbs out of) has that fight's encounters in
--  the data (`with`), and shares its kills.
--
--  Each kill keeps what dropped from it: every item the group rolled for, its winner and
--  everyone's rolls, from the game's loot history (C_LootHistory, filed under the fight's
--  encounter, kept by the game until you log out). Each drop goes with the kill nearest it in
--  time, so a reload or a second run in the session changes nothing; it is kept as each roll
--  ends (LOOT_HISTORY_UPDATE_DROP), and gathered again when the boss's history is opened.
--
--  Kept per character (J.CharacterData). The game writes saved data to disk when it
--  reloads, logs out or quits; a kill since the last of those is lost if the game crashes.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings
local Team = J.Team

local KEEP = 10   -- the latest kills kept with their date and time; the count goes on past it

---@class JournalKillRecord  One boss's kills on one character (saved).
---@field n number kills counted
---@field first number when the first one counted was, as time() gives it
---@field at number[] the latest KEEP kills' times, oldest first
---@field took (number|false)[] each one's length in seconds, alongside at; false when not known
---@field team? (string|false)[] who was in your group, alongside at (Team.Now); false when not kept
---@field drops? (string|false)[] what dropped, alongside at: a line per item, its link, a tab and its
---rolls (Team.KeepRolls); false when nothing was kept
---@field best? number the fastest kill's length in seconds, kept past the latest KEEP
---@field bestAt? number when it was

local Kills = { KEEP = KEEP }
J.Kills = Kills

local byEncounter, dungeonOf   -- encounter ID -> its boss, and boss -> its dungeon; built on first use

local function BossFor(encounterID)
    if not byEncounter then
        byEncounter, dungeonOf = {}, {}
        for _, dungeon in ipairs(J.Dungeons()) do
            for _, wing in ipairs(dungeon.wings) do
                for _, boss in ipairs(wing.bosses) do
                    -- A fight names its own boss, not one killed on the way into it.
                    local ids = not boss.with and boss.encounters
                    for i = 1, ids and #ids or 0 do byEncounter[ids[i]] = boss end
                    dungeonOf[boss] = dungeon
                end
            end
        end
    end
    return byEncounter[encounterID]
end

-- This character's records, encounter ID -> JournalKillRecord; made on the first kill when
-- create is set, nil before that.
local function Mine(create)
    return J.CharacterData("journalKills", create)
end

-- Whether the Journal can count this boss's kills: only a boss the game runs as an
-- encounter says which boss died.
function Kills.Counted(boss)
    return boss.encounters ~= nil
end

---@return JournalKillRecord? record nil before the first kill, or for a boss not counted
function Kills.Record(boss)
    local id = boss.encounters and boss.encounters[1]
    local mine = id and Mine(false)
    local record = mine and mine[id]
    if type(record) == "table" and type(record.n) == "number" then return record end
end

-------------------------------------------------------------------------------
--  This run: the kills since you came into the dungeon you are in
-------------------------------------------------------------------------------
-- Back in the same dungeon this soon after leaving it (a death and the run back, a reload):
-- the same run. Kept per character (J.CharacterData), so a reload inside keeps it too. A run
-- is over once a boss of it is killed again (a reset and another go), after RUN_MAX, and at
-- a login outside (a logout and back is a new day, not the run back).
local RUN_GRACE = 15 * 60
local RUN_MAX = 4 * 60 * 60

-- A loading screen: inside a dungeon the Journal lists, a run starts now unless it is the one
-- you just left; outside, when you left it is kept, or at a login the run is over.
---@param here? JournalDungeon[] J.Current()
---@param login? boolean the login's own loading screen (not a reload's)
function Kills.NoteRun(here, login)
    local run = J.CharacterData("journalRun", true)
    if not run then return end
    local now = time()
    if here then
        local _, _, _, _, _, _, _, map = GetInstanceInfo()
        if run.map ~= map or not run.at or now - run.at > RUN_MAX
            or (run.left and (login or now - run.left > RUN_GRACE)) then
            run.map, run.at = map, now
        end
        run.left = nil
    elseif login then
        run.map, run.at, run.left = nil, nil, nil
    elseif run.at and not run.left then
        run.left = now
    end
end

-- Killed in this run: its latest kill came after the run started, and you are in the run.
function Kills.ThisRun(boss)
    local run = J.CharacterData("journalRun")
    local record = run and run.at and not run.left and Kills.Record(boss)
    local at = record and record.at
    local last = at and at[#at]
    return type(last) == "number" and last >= run.at
end

---@return number kills on this character
function Kills.Count(boss)
    local record = Kills.Record(boss)
    return record and record.n or 0
end

---@class JournalKill  One of the latest kills, from Kills.Latest.
---@field boss JournalBoss
---@field dungeon JournalDungeon
---@field at number when, as time() gives it
---@field took number|false how long it took in seconds; false when not known

local spare = {}   -- JournalKill entries no longer in a Latest list, for the next one

-- Puts the kill in its place in out, newest first, when it is among the n newest so far:
-- one pass over every kill, keeping only n, instead of sorting them all (a player who has
-- killed every boss ten times has over two thousand).
local function Place(out, n, boss, at, took)
    local count = #out
    if count == n and at <= out[n].at then return end
    local kill
    if count == n then
        kill = out[n]
        out[n] = nil
        count = count - 1
    else
        kill = table.remove(spare) or {}
    end
    kill.boss, kill.dungeon, kill.at = boss, dungeonOf[boss], at
    kill.took = type(took) == "number" and took or false
    local i = count
    while i > 0 and out[i].at < at do
        out[i + 1] = out[i]
        i = i - 1
    end
    out[i + 1] = kill
end

-- This character's latest kills of any boss, newest first, at most n: the latest KEEP of
-- each boss are the ones with a date. Into out, which is emptied first; its entries are
-- reused by the next call.
---@param n number
---@param out JournalKill[]
---@return JournalKill[] out
function Kills.Latest(n, out)
    for i = #out, 1, -1 do
        spare[#spare + 1] = out[i]
        out[i] = nil
    end
    local mine = Mine(false)
    if not mine then return out end
    for key, record in pairs(mine) do
        local boss = BossFor(key)
        local at = boss and type(record) == "table" and record.at
        if type(at) == "table" then
            local took = type(record.took) == "table" and record.took or nil
            for i = 1, #at do
                if type(at[i]) == "number" then Place(out, n, boss, at[i], took and took[i]) end
            end
        end
    end
    return out
end

-- The record's list under key, made to run alongside its kills' times: a record kept before
-- that list was has false for each kill already there.
local function Alongside(record, key)
    local list = record[key]
    if type(list) ~= "table" then
        list = {}
        record[key] = list
    end
    for i = #list + 1, #record.at do list[i] = false end
    return list
end

-- The boss's record: the fastest kill's length in seconds and when it was; nil before a kill
-- whose length is known. Records kept before this was have it worked out from their kills.
---@param record JournalKillRecord
---@return number? seconds
---@return number? at
function Kills.Best(record)
    local best, at = record.best, record.bestAt
    if type(best) ~= "number" then best, at = nil, nil end
    local took = type(record.took) == "table" and record.took or {}
    for i = 1, #record.at do
        local length = took[i]
        if type(length) == "number" and (not best or length < best) then best, at = length, record.at[i] end
    end
    return best, at
end

-- What dropped from the kill, each item and its rolls, read back from the kept text: calls
-- each(link, rolls) per item, in the order the game listed them.
---@param text? string a JournalKillRecord's drops
---@param each fun(link: string, rolls: string)
function Kills.EachDrop(text, each)
    if type(text) ~= "string" then return end
    for line in text:gmatch("[^\n]+") do
        local link, rolls = line:match("^(.-)\t(.*)$")
        if link and link ~= "" then each(link, rolls) end
    end
end

-- Forgets every kill this character has counted: each boss starts again from 0.
function Kills.Forget()
    local mine = Mine(false)
    if mine then wipe(mine) end
end

-- Counts a kill of the boss now, with who was in your group. took: how long the fight was,
-- in seconds, or nil when not known.
---@param boss JournalBoss
---@param took? number
---@param team? string Team.Now's
local function Add(boss, took, team)
    local mine = Mine(true)
    if not mine then return end
    local key = boss.encounters[1]
    local now = time()
    local record = mine[key]
    if type(record) ~= "table" then
        record = { n = 0, first = now, at = {}, took = {} }
        mine[key] = record
    end
    local at, lengths = record.at, record.took
    local teams, drops = Alongside(record, "team"), Alongside(record, "drops")
    -- A new record: said in chat when it beats one, kept past the latest KEEP.
    local length = took and math.floor(took + 0.5)
    local best = Kills.Best(record)
    if length and (not best or length < best) then
        if best then
            ns.Print(("New record on %s: %s, was %s."):format(boss.name, J.View.Parts.FightLength(length),
                J.View.Parts.FightLength(best)))
        end
        record.best, record.bestAt = length, now
    end
    if #at >= KEEP then
        table.remove(at, 1)
        table.remove(lengths, 1)
        table.remove(teams, 1)
        table.remove(drops, 1)
    end
    -- Killed again in the same run: the dungeon was reset, and this is a new run.
    if Kills.ThisRun(boss) then
        local run = J.CharacterData("journalRun")
        if run then run.at = now end
    end
    record.n = record.n + 1
    at[#at + 1] = now
    lengths[#lengths + 1] = length or false
    teams[#teams + 1] = team or false
    drops[#drops + 1] = false
    J.RedrawDungeonMaps()   -- a map showing ticks and dims it
end
Kills.Add = Add

-------------------------------------------------------------------------------
--  Counting
-------------------------------------------------------------------------------
local pulled = {}   -- encounter ID -> GetTime() at its pull, for how long it took
local frame

-------------------------------------------------------------------------------
--  What dropped, from the game's loot history
-------------------------------------------------------------------------------
local DROP_WINDOW = 15 * 60   -- seconds a drop's roll can start from its kill, either way
local EMPTY = {}
local lines, linePool = {}, {}   -- kill index -> the lines of its drops, per gathering

-- The kill a drop came from: the one nearest it in time, within DROP_WINDOW (the Shredder's
-- loot is rolled before Sneed's fight ends, the rest after it).
local function KillNear(at, when)
    local best, gap
    for i = 1, #at do
        local d = type(at[i]) == "number" and math.abs(when - at[i])
        if d and d <= DROP_WINDOW and (not gap or d < gap) then best, gap = i, d end
    end
    return best
end

-- Every drop of the fight with a winner (or that everyone passed) in the game's loot
-- history, kept with the kill it came from. A kill the history no longer holds (from before
-- you logged in) keeps what it had.
local function Gather(encounterID)
    local boss = BossFor(encounterID)
    local record = boss and Kills.Record(boss)
    if not (record and C_LootHistory) or #record.at == 0 then return end
    -- The history's times are the game's clock (GetTime, in milliseconds); the kills', time().
    local offset = time() - GetTime()
    wipe(lines)
    for _, drop in ipairs(C_LootHistory.GetSortedDropsForEncounter(encounterID) or EMPTY) do
        local link, started = drop.itemHyperlink, drop.startTime
        if type(link) == "string" and not issecretvalue(link) and type(started) == "number"
            and (drop.winner or drop.allPassed) then
            local i = KillNear(record.at, started / 1000 + offset)
            if i then
                local list = lines[i]
                if not list then
                    list = table.remove(linePool) or {}
                    lines[i] = list
                end
                list[#list + 1] = link .. "\t" .. (Team.KeepRolls(drop) or "")
            end
        end
    end
    local drops = Alongside(record, "drops")
    for i, list in pairs(lines) do
        drops[i] = table.concat(list, "\n")
        wipe(list)
        linePool[#linePool + 1] = list
    end
end

-- Gathers the boss's drops from the game's loot history, for the kills it missed (from
-- before this was kept, or a reload while the rolls ran).
---@param boss JournalBoss
function Kills.Gather(boss)
    local ids = boss.encounters
    for i = 1, ids and #ids or 0 do Gather(ids[i]) end
end

-- ENCOUNTER_START: encounterID, name, difficultyID, groupSize.
-- ENCOUNTER_END: encounterID, name, difficultyID, groupSize, success (1 for a kill).
-- PLAYER_ENTERING_WORLD: isInitialLogin, isReloadingUi.
local function OnEvent(_, event, encounterID, _, _, _, success)
    if event == "PLAYER_ENTERING_WORLD" then
        Kills.NoteRun(J.Current(), encounterID == true)
        return
    end
    if event == "LOOT_HISTORY_UPDATE_DROP" then
        if not issecretvalue(encounterID) then Gather(encounterID) end
        return
    end
    if issecretvalue(encounterID) or issecretvalue(success) then return end
    if event == "ENCOUNTER_START" then
        pulled[encounterID] = GetTime()
        return
    end
    local started = pulled[encounterID]
    pulled[encounterID] = nil
    local boss = success == 1 and BossFor(encounterID)
    if boss then Add(boss, started and GetTime() - started, Team.Now()) end
end

-- Counting runs while the Journal is on: the frame is made the first time it is.
local function Sync()
    local on = S.Get("enabled")
    if not (on or frame) then return end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    if on then
        frame:RegisterEvent("ENCOUNTER_START")
        frame:RegisterEvent("ENCOUNTER_END")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")   -- this run's start (the dungeon map's progress)
        if C_LootHistory then frame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP") end
    else
        frame:UnregisterAllEvents()
        wipe(pulled)
    end
end

S.OnChange(function(key)
    if key == "enabled" then Sync() end
end)
hooksecurefunc(ns, "Apply", Sync)
