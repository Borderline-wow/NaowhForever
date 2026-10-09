-- Looted.lua: what this character has looted in the Journal's dungeons, where and with whom (J.Looted).
local ns = _G.NaowhForever

local J = ns.Journal
local S = J.Settings
local Team = J.Team
local Items = ns.Shared.Items
local KeepRolls = Team.KeepRolls

local KEEP = 20
local UNCOMMON = 2
local LATE = 120
local LOOT_KEY = "journalLoot"
local ITEM_ID = "|Hitem:(%d+)"
local LINK_QUALITY = "^|cnIQ(%d)"

local EMPTY = {}
local here
local frame

local function Mine(create)
    return J.CharacterData(LOOT_KEY, create)
end

local function ItemID(link)
    return tonumber(link:match(ITEM_ID))
end

local function Whole(item)
    return type(item) == "table" and type(item.id) == "number" and type(item.link) == "string"
        and type(item.at) == "number" and type(item.dungeon) == "string" and J.Get(item.dungeon) ~= nil
end

local function Drops(boss, id)
    local loot = boss.loot
    for i = 1, loot and #loot or 0 do
        if loot[i] == id then return true end
    end
    return false
end

local function From(item, boss)
    return type(item) == "table" and item.boss == boss.name and Whole(item) and Drops(boss, item.id)
end

local function YoursOf(drop, id)
    local winner, link = drop and drop.winner, drop and drop.itemHyperlink
    return winner ~= nil and winner.isSelf == true and type(link) == "string" and not issecretvalue(link)
        and ItemID(link) == id
end

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

local function DropsFrom(dungeon, id)
    for _, wing in ipairs(dungeon.wings) do
        for _, boss in ipairs(wing.bosses) do
            if Drops(boss, id) then return boss end
        end
    end
end

local function BossHere(dungeons, id)
    for i = 1, #dungeons do
        local boss = DropsFrom(dungeons[i], id)
        if boss then return dungeons[i], boss end
    end
    return dungeons[1], nil
end

local function Quality(link, id)
    local quality = tonumber(link:match(LINK_QUALITY))
    if quality then return quality end
    quality = C_Item.GetItemQualityByID(id)
    if quality then return quality end
    local facts = J.Items[id]
    return facts and facts[J.FACT.QUALITY]
end

local Looted = { KEEP = KEEP }
J.Looted = Looted

function Looted.Latest(n, out)
    wipe(out)
    local mine = Mine(false)
    for i = mine and #mine or 0, 1, -1 do
        if #out == n then break end
        if Whole(mine[i]) then out[#out + 1] = mine[i] end
    end
    return out
end

function Looted.AllFrom(boss, out)
    wipe(out)
    local mine = Mine(false)
    for i = mine and #mine or 0, 1, -1 do
        if From(mine[i], boss) then out[#out + 1] = mine[i] end
    end
    return out
end

function Looted.Forget()
    local mine = Mine(false)
    if mine then wipe(mine) end
end

function Looted.Add(dungeons, link, id)
    local dungeon, boss = BossHere(dungeons, id)
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

local function Listen()
    here = J.Current()
    if here then
        frame:RegisterEvent("CHAT_MSG_LOOT")
        if C_LootHistory then frame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP") end
        return
    end
    frame:UnregisterEvent("CHAT_MSG_LOOT")
    frame:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP")
end

local function OnEvent(_, event, text, lootListKey)
    if event == "PLAYER_ENTERING_WORLD" then return Listen() end
    if event == "LOOT_HISTORY_UPDATE_DROP" then return RollsLate(text, lootListKey) end
    if not here then return end
    local link, id = Items.YourLoot(text)
    if id then Looted.Add(here, link, id) end
end

local function Sync()
    local on = S.Get("enabled") and Items.READS_LOOT
    if not (on or frame) then return end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    if not on then
        frame:UnregisterAllEvents()
        here = nil
        return
    end
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    Listen()
end

local function OnSettingChanged(key)
    if key == "enabled" then Sync() end
end

S.OnChange(OnSettingChanged)
hooksecurefunc(ns, "Apply", Sync)
