-------------------------------------------------------------------------------
--  Looted.lua -- what this character has looted in the Journal's dungeons and raids, where,
--  who was with it and how it was won (ns.Journal.Looted): the latest KEEP items, oldest
--  first. Read from the game's own "You receive loot" line (CHAT_MSG_LOOT); the rolls from
--  its loot history (C_LootHistory, the group loot rolls Blizzard's own Loot History lists),
--  which may come just before the line or just after it (LOOT_HISTORY_UPDATE_DROP).
--  Listened for only inside a dungeon or raid the Journal lists, while it is on; off,
--  nothing is made or registered.
--
--  Kept per character, like the kills (J.CharacterData).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings
local Team = J.Team

local KEEP = 20       -- the latest items kept
local UNCOMMON = 2    -- the lowest quality kept of what no boss there drops (trash, chests)
local LATE = 120      -- seconds a roll's result can come after the item and still be kept with it

---@class JournalLootRecord  One item looted (saved).
---@field id number its item ID
---@field link string its link, as the game wrote it
---@field at number when, as time() gives it
---@field dungeon string where: the Journal's key for it
---@field boss? string the boss there that drops it; nil for anything else
---@field team? string who was in your group (Team.Now)
---@field rolls? string the group's rolls for it, when it was rolled for (Team.KeepRolls)

local Looted = { KEEP = KEEP }
J.Looted = Looted

local Items = ns.Shared.Items

-- This character's list, oldest first; made on the first item when create is set, nil
-- before that.
local function Mine(create)
    return J.CharacterData("journalLoot", create)
end

local function ItemID(link)
    return tonumber(link:match("|Hitem:(%d+)"))
end

-- Whether a saved entry is whole, and of a dungeon the Journal still lists: saved data can
-- be from an older version, or edited.
local function Whole(item)
    return type(item) == "table" and type(item.id) == "number" and type(item.link) == "string"
        and type(item.at) == "number" and type(item.dungeon) == "string" and J.Get(item.dungeon) ~= nil
end

-- Whether the boss's loot holds the item.
local function Drops(boss, id)
    local loot = boss.loot
    for i = 1, loot and #loot or 0 do
        if loot[i] == id then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  Reading
-------------------------------------------------------------------------------
-- This character's latest items, newest first, at most n, into out (emptied first). They
-- are the saved entries themselves: read them, never change them.
---@param n number
---@param out JournalLootRecord[]
---@return JournalLootRecord[] out
function Looted.Latest(n, out)
    wipe(out)
    local mine = Mine(false)
    for i = mine and #mine or 0, 1, -1 do
        if #out == n then break end
        if Whole(mine[i]) then out[#out + 1] = mine[i] end
    end
    return out
end

-- Whether the item was looted from the boss: kept under its name, and in its loot (two
-- bosses of one name, in two dungeons, drop different things). The name first: it rules out
-- nearly every entry at once.
local function From(item, boss)
    return type(item) == "table" and item.boss == boss.name and Whole(item) and Drops(boss, item.id)
end

-- Every item kept from the boss, newest first, into out (emptied first).
---@param boss JournalBoss
---@param out JournalLootRecord[]
---@return JournalLootRecord[] out
function Looted.AllFrom(boss, out)
    wipe(out)
    local mine = Mine(false)
    for i = mine and #mine or 0, 1, -1 do
        if From(mine[i], boss) then out[#out + 1] = mine[i] end
    end
    return out
end

-------------------------------------------------------------------------------
--  The rolls, from the game's loot history
-------------------------------------------------------------------------------
local EMPTY = {}
local KeepRolls = Team.KeepRolls

-- Whether the drop is this item, and went to you.
local function YoursOf(drop, id)
    local winner, link = drop and drop.winner, drop and drop.itemHyperlink
    return winner ~= nil and winner.isSelf == true and type(link) == "string" and not issecretvalue(link)
        and ItemID(link) == id
end

-- The rolls for the latest drop of the item that went to you, in the game's loot history;
-- nil when it was not rolled for (yet).
local function RollsFor(id)
    if not C_LootHistory then return end
    local best
    for _, encounter in ipairs(C_LootHistory.GetAllEncounterInfos() or EMPTY) do
        for _, drop in ipairs(C_LootHistory.GetSortedDropsForEncounter(encounter.encounterID) or EMPTY) do
            if YoursOf(drop, id) and (not best or drop.startTime > best.startTime) then best = drop end
        end
    end
    return best and KeepRolls(best)
end

-- LOOT_HISTORY_UPDATE_DROP: a roll's result, after the item came: kept with the newest item
-- of it with no rolls yet, looted in the last LATE seconds.
local function RollsLate(encounterID, lootListKey)
    if issecretvalue(encounterID) or issecretvalue(lootListKey) then return end
    local drop = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)
    if not drop or not drop.winner then return end
    local mine = Mine(false)
    local now = time()
    for i = mine and #mine or 0, 1, -1 do
        local item = mine[i]
        if not Whole(item) or now - item.at > LATE then return end
        if not item.rolls and YoursOf(drop, item.id) then
            item.rolls = KeepRolls(drop)
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Keeping
-------------------------------------------------------------------------------
-- Forgets everything this character has looted.
function Looted.Forget()
    local mine = Mine(false)
    if mine then wipe(mine) end
end

-- The boss of the dungeon whose loot holds the item; nil when none does.
local function DropsFrom(dungeon, id)
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            if Drops(boss, id) then return boss end
        end
    end
end

-- The item's quality: its link's own ("|cnIQ3:"), else what the client or the Journal knows.
local function Quality(link, id)
    local quality = tonumber(link:match("^|cnIQ(%d)"))
    if quality then return quality end
    quality = C_Item.GetItemQualityByID(id)
    if quality then return quality end
    local facts = J.Items[id]
    return facts and facts[J.FACT.QUALITY]
end

-- Keeps the item, looted now in one of the dungeons of the instance you are in (here): a
-- boss's drop there, or anything else Uncommon or better; with your group, and its rolls
-- when the game's loot history has them already.
---@param here JournalDungeon[]
---@param link string
---@param id number
function Looted.Add(here, link, id)
    local dungeon, boss = here[1], nil
    for i = 1, #here do
        boss = DropsFrom(here[i], id)
        if boss then dungeon = here[i] break end
    end
    if not boss then
        local quality = Quality(link, id)
        if not (quality and quality >= UNCOMMON) then return end
    end
    local mine = Mine(true)
    if not mine then return end
    if #mine >= KEEP then table.remove(mine, 1) end
    mine[#mine + 1] = { id = id, link = link, at = time(), dungeon = dungeon.key, boss = boss and boss.name,
        team = Team.Now(), rolls = RollsFor(id) }
end

-------------------------------------------------------------------------------
--  Listening
-------------------------------------------------------------------------------
local here    -- the dungeons of the instance you are in, while it is one the Journal lists
local frame

-- Listens for loot only inside a dungeon or raid the Journal lists: a new instance always
-- comes with a loading screen, and PLAYER_ENTERING_WORLD after it.
local function Listen()
    here = J.Current()
    if here then
        frame:RegisterEvent("CHAT_MSG_LOOT")
        if C_LootHistory then frame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP") end
    else
        frame:UnregisterEvent("CHAT_MSG_LOOT")
        frame:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP")
    end
end

-- CHAT_MSG_LOOT: text, playerName, ... Its text can be secret (in an encounter): that item
-- is not kept.
local function OnEvent(_, event, text, lootListKey)
    if event == "PLAYER_ENTERING_WORLD" then return Listen() end
    if event == "LOOT_HISTORY_UPDATE_DROP" then return RollsLate(text, lootListKey) end
    if not here then return end
    local link, id = Items.YourLoot(text)
    if id then Looted.Add(here, link, id) end
end

-- Listening runs while the Journal is on: the frame is made the first time it is.
local function Sync()
    local on = S.Get("enabled") and Items.READS_LOOT
    if not (on or frame) then return end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    if on then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        Listen()
    else
        frame:UnregisterAllEvents()
        here = nil
    end
end

S.OnChange(function(key)
    if key == "enabled" then Sync() end
end)
hooksecurefunc(ns, "Apply", Sync)
