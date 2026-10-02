-------------------------------------------------------------------------------
--  Journal.lua -- the Dungeon Journal's core (ns.Journal): its settings, every dungeon and
--  faction, and the questions the rest of the module asks about them. Each dungeon is its
--  own file in Data/Dungeons/ and hands itself to AddDungeon, each faction its own in
--  Data/Factions/ to AddFaction; this joins the dungeons with the quest data (instance,
--  levels, quests: Data/Quests.lua) and with the factions earned in them. No frames here.
--
--  Everything the module shares hangs off ns.Journal: Settings, Items, Tips, Loot, Quests,
--  Style and View. Only the entry points the rest of the addon calls are on ns
--  (OpenJournalWindow, ToggleJournalWindow, BuildJournalSettingsPage), and
--  ns.JournalSettings, which the options window finds its settings by.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

---@class JournalBoss  A boss, as its dungeon's file lists it (shared, read-only).
---@field npc? number its NPC ID; nil where Wowhead has none yet
---@field name string
---@field rare? boolean a rare, which does not spawn every run
---@field loot? number[] item IDs, most likely first
---@field chance? number[] each item's drop chance in percent, 0 where not known
---@field encounters? number[] the encounter IDs ENCOUNTER_END names it by (one per difficulty); nil for a rare
---@field with? string the boss whose fight it falls in, when the game runs none for it (Sneed's
---Shredder, which Sneed climbs out of): its encounters are that fight's, and its kills that boss's

---@class JournalWing
---@field name? string
---@field bosses JournalBoss[] in kill order

---@class JournalDungeon  A dungeon (shared, read-only once joined).
---@field key string
---@field name string
---@field zone? string the zone its entrance is in
---@field new? boolean new in WoW Forever, not in the classic game
---@field raid? number a raid: how many players it is for
---@field note? string a line at the top of its page (what is not known yet)
---@field territory? "Alliance"|"Horde"|"Contested" whose ground that zone is
---@field entrance? { map: number, x: number, y: number } where a source matches Forever's map
---@field wings JournalWing[]
---@field quests? table its Data/Quests.lua entry: { name, map?, levels?, quests }
---@field factions? JournalFaction[] the factions whose reputation is earned there

---@class JournalTier  A faction's rewards at one standing.
---@field standing number the game's reaction it needs: 4 Neutral to 8 Exalted
---@field items number[] item IDs, the best first
---@field faction JournalFaction whose rewards they are

---@class JournalFaction  A faction with rewards (shared, read-only once joined).
---@field key string
---@field id number the game's faction ID
---@field name string
---@field tab "reputation"|"pvp" the window's tab it is listed under
---@field group? string a title it is listed under with others (the Steamwheedle Cartel's towns)
---@field zone? string where its quartermaster is
---@field side? "Alliance"|"Horde" a battleground faction: only that side earns it
---@field battleground? string where it is earned
---@field new? boolean new in WoW Forever
---@field unreleased? boolean its raids are not announced for Forever: listed apart
---@field quartermaster? { name: string, map: number, x: number, y: number } entered by hand
---@field turnins? { name: string, quests: number[], rep: number, takes: number[] }[] its repeatable hand-ins, kept by hand (takes: item, count, ...)
---@field questData? { quests: JournalQuest[] } its hand-ins as quests, for the quest rows (joined)
---@field maps? number[] its zone's map IDs (UiMap), where the map panel shows it
---@field instance? number its battleground's instance ID
---@field dungeons? string[] the Journal's keys of the dungeons where it is earned
---@field tiers JournalTier[] lowest standing first
---@field prices? table<number, number> item ID -> its price in copper at the quartermaster
---@field linked? JournalDungeon[] those dungeons, joined

local S = ns.UI.ModuleSettings("journal", {
    enabled = false,
    mapPanel = true,
    mapFactions = false,
    usableOnly = true,
    myRecipes = true,
    openUnreleased = false,
    upgradesOnly = false,
    showCosmetic = true,
    questsOpen = false,
    repQuestsOpen = true,
    missingBisOnly = false,
    windowAlpha = 1,
    listHidden = false,
    closedGroup1 = false,
    closedGroup2 = false,
    closedGroup3 = false,
    closedGroup4 = false,
    showAlliance = true,
    showHorde = true,
    shareRequests = true,
    acceptShared = false,
})
ns.JournalSettings = S

local J = { Settings = S }
ns.Journal = J

---@class JournalOption  One of the Journal's switches, as every place that offers it shows it.
---@field key string its setting
---@field label string
---@field tooltip string what it does
---@field hides? boolean the value at which it hides things: a filter, counted on the window's Filters icon
---@field needsBis? boolean it only works with the BiS List module on

-- What the Journal lists and shows, defined once: the window's Filters menu and the settings
-- page are both built from these, so the two always offer the same switches in the same
-- words, and either one changes the other (they are the same settings).
---@type { title: string, options: JournalOption[] }[]
J.OPTION_GROUPS = {
    { title = "What it lists", options = {
        { key = "usableOnly", label = "My Class Only", hides = true,
          tooltip = "Only the loot your class can use. Off, the rest is listed faded." },
        { key = "myRecipes", label = "My Professions Only", hides = true,
          tooltip = "Only the recipes for the professions you have. Off, every recipe is listed." },
        { key = "missingBisOnly", label = "Missing BiS Only", hides = true, needsBis = true,
          tooltip = "Only the loot you still need from your BiS list: higher on it than what "
              .. "you wear, and not in your bags or bank." },
        { key = "upgradesOnly", label = "Upgrades Only", hides = true,
          tooltip = "Only the gear that beats what you wear: a higher pick on your BiS list, or a higher "
              .. "item level you can wear." },
        { key = "showCosmetic", label = "Show Cosmetic Items", hides = false,
          tooltip = "Cosmetic items too: looks for transmog that any class can wear, with no stats." },
    } },
}
-- Why a needsBis option is greyed out.
J.NEEDS_BIS = "Needs the BiS List module: turn it on in its page."

-- What the Journal knows about an item before the client has loaded it: Data/Items.lua
-- fills J.Items with { class, subclass, item level, required level, quality } per item ID,
-- read by these field numbers. class and subclass are the game's (2 weapon, 4 armor).
J.FACT = { CLASS = 1, SUBCLASS = 2, ITEM_LEVEL = 3, REQUIRED = 4, QUALITY = 5 }

local ordered, byKey = {}, {}
-- NPC ID -> its boss and the dungeon it is in, for the boss loot window. Built on first use.
local byNpc, dungeonOf
-- Instance ID -> the dungeons in it (Blackrock Spire holds both halves); a new dungeon whose
-- ID the client does not know yet is found by its instance name. Built on first use.
local byMap, byName

local factions, factionByKey = { reputation = {}, pvp = {} }, {}
-- Zone map ID, or battleground instance ID -> the factions earned there, for the map panel.
-- Built on first use; factions not in Forever yet left out.
local byZone, byBattleground

-- The PvP tab's first page, your rank this season: listed and drawn as a faction is, and
-- told apart by rank.
---@type { key: string, name: string, tab: string, rank: boolean }
J.RANK = { key = "PvPRank", name = "PvP Rank", tab = "pvp", rank = true }

-- Each file in Data/Dungeons/ hands its dungeon over once, at load.
---@param key string
---@param dungeon JournalDungeon
function J.AddDungeon(key, dungeon)
    dungeon.key = key
    ordered[#ordered + 1] = dungeon
    byKey[key] = dungeon
end

-- Each file in Data/Factions/ hands its faction over once, at load, after the dungeons.
---@param key string
---@param faction JournalFaction
function J.AddFaction(key, faction)
    faction.key = key
    for _, tier in ipairs(faction.tiers) do tier.faction = faction end
    local list = factions[faction.tab]
    list[#list + 1] = faction
    factionByKey[key] = faction
end

local function AddTo(index, id, faction)
    local list = index[id] or {}
    list[#list + 1] = faction
    index[id] = list
end

local function Join()
    byMap, byName, byZone, byBattleground = {}, {}, {}, {}
    -- Each faction to the dungeons it is earned in, and back; Reputation's first, so a zone
    -- lists its factions in the window's order.
    for _, tab in ipairs({ "reputation", "pvp" }) do
        for _, faction in ipairs(factions[tab]) do
            faction.linked = {}
            -- Its hand-ins as quests, kept as Data/Quests.lua keeps a dungeon's (ID, name,
            -- level, side, shareable, where, map, x, y), so its page lists them with the
            -- dungeon quests' rows; turnin says what one takes and gives.
            if faction.turnins then
                local quests = {}
                for _, turnin in ipairs(faction.turnins) do
                    for _, q in ipairs(turnin.quests) do
                        quests[#quests + 1] = { q[1], turnin.name, turnin.level, q[2], true, q[3], q[4], q[5], q[6],
                            turnin = turnin }
                    end
                end
                faction.questData = { quests = quests }
            end
            if not faction.unreleased then
                for _, id in ipairs(faction.maps or {}) do AddTo(byZone, id, faction) end
                if faction.instance then AddTo(byBattleground, faction.instance, faction) end
            end
            for _, key in ipairs(faction.dungeons or {}) do
                local dungeon = byKey[key]
                if dungeon then
                    faction.linked[#faction.linked + 1] = dungeon
                    dungeon.factions = dungeon.factions or {}
                    dungeon.factions[#dungeon.factions + 1] = faction
                end
            end
        end
    end
    local quests = {}
    for _, entry in ipairs(J.QuestData) do quests[entry.name] = entry end
    for _, dungeon in ipairs(ordered) do
        local entry = quests[dungeon.name]
        dungeon.quests = entry
        byName[dungeon.name] = { dungeon }
        if entry and entry.map then
            local list = byMap[entry.map] or {}
            list[#list + 1] = dungeon
            byMap[entry.map] = list
        end
    end
end

---@return JournalDungeon[] dungeons every dungeon in level order (the XML's), shared
function J.Dungeons()
    if not byMap then Join() end
    return ordered
end

---@return JournalDungeon?
function J.Get(key)
    if not byMap then Join() end
    return byKey[key]
end

---@param tab "reputation"|"pvp"
---@return JournalFaction[] factions the tab's factions in the data's order, shared
function J.Factions(tab)
    if not byMap then Join() end
    return factions[tab]
end

---@return JournalFaction?
function J.GetFaction(key)
    if not byMap then Join() end
    return factionByKey[key]
end

---@return { [1]: number, [2]: number }? levels the dungeon's { min, max }
function J.Levels(dungeon)
    return dungeon.quests and dungeon.quests.levels
end

---@return JournalBoss? boss the boss with this NPC ID
---@return JournalDungeon? dungeon the dungeon it is in
function J.Boss(npc)
    if not byNpc then
        byNpc, dungeonOf = {}, {}
        for _, dungeon in ipairs(ordered) do
            for _, wing in ipairs(dungeon.wings) do
                for _, boss in ipairs(wing.bosses) do
                    if boss.npc then byNpc[boss.npc], dungeonOf[boss] = boss, dungeon end
                end
            end
        end
    end
    local boss = byNpc[npc]
    if boss then return boss, dungeonOf[boss] end
end

---@return JournalDungeon[]? dungeons the dungeons of the instance you are in (usually one): a
---dungeon or a raid
function J.Current()
    local inInstance, kind = IsInInstance()
    if not (inInstance and (kind == "party" or kind == "raid")) then return end
    if not byMap then Join() end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    return byMap[id] or byName[name]
end

-- The factions earned where you are, for the map panel: in a battleground, your side's for
-- it; outside an instance, those of the zone you stand in (a cave's or a town's map counts as
-- its zone's). Put in out, wiped first, the data's order.
local ZONE = Enum.UIMapType.Zone
---@param out JournalFaction[]
---@return JournalFaction[] out
function J.FactionsHere(out)
    wipe(out)
    if not byMap then Join() end
    local list
    local inInstance, kind = IsInInstance()
    if inInstance then
        if kind ~= "pvp" then return out end
        list = byBattleground[select(8, GetInstanceInfo())]
    else
        local id = C_Map.GetBestMapForUnit("player")
        local info = id and C_Map.GetMapInfo(id)
        while info and info.mapType > ZONE and info.parentMapID and info.parentMapID > 0 do
            info = C_Map.GetMapInfo(info.parentMapID)
        end
        list = info and info.mapType == ZONE and byZone[info.mapID]
    end
    if not list then return out end
    local side = UnitFactionGroup("player")
    for i = 1, #list do
        local faction = list[i]
        if not faction.side or faction.side == side then out[#out + 1] = faction end
    end
    return out
end

---@return JournalDungeon dungeon the one you are in, else the first whose range holds your level
function J.Suggested()
    local here = J.Current()
    if here then return here[1] end
    local level = UnitLevel("player")
    for _, dungeon in ipairs(J.Dungeons()) do
        local levels = J.Levels(dungeon)
        if levels and level >= levels[1] and level <= levels[2] then return dungeon end
    end
    return ordered[1]
end

-- "13-18", or "60" when a dungeon is for one level (the raids); nil without a range.
---@return string? range
function J.LevelRange(dungeon)
    local levels = J.Levels(dungeon)
    if not levels then return nil end
    if levels[1] == levels[2] then return tostring(levels[1]) end
    return levels[1] .. "-" .. levels[2]
end

---@return string? tip Naowh's tip for the boss (Data/Tips.lua); whether to show it is the view's
function J.Tip(boss)
    return boss.npc and J.Tips[boss.npc] or nil
end

-- Whether the window lists the dungeon: one on Alliance or Horde ground only while that
-- side's half of the faction switch is on; a contested one always.
function J.FactionShown(dungeon)
    if dungeon.raid then return true end   -- a raid is for everyone, whoever's ground it is on
    local territory = dungeon.territory
    if territory == "Alliance" then return S.Get("showAlliance") end
    if territory == "Horde" then return S.Get("showHorde") end
    return true
end

function J.HasBosses(dungeon)
    return #dungeon.wings > 0
end

-- The NPC ID in a creature's GUID ("Creature-0-...-<id>-..."), or nil for a player, a pet
-- or anything else. The caller checks the GUID is not secret before.
---@param guid string
---@return number? npc
function J.NpcID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- A waypoint with the arrow on the dungeon's entrance, and the world map opened on its zone.
-- The map only opens out of combat, where the game lets addon code open it. False when the
-- entrance is not known.
---@return boolean shown
function J.ShowEntrance(dungeon)
    local entrance = dungeon.entrance
    if not entrance then return false end
    ns.PlaceWaypoint(dungeon.name, entrance.map, entrance.x, entrance.y, " (entrance)")
    if not InCombatLockdown() then C_Map.OpenWorldMap(entrance.map) end
    return true
end

-- What this character keeps under key (journalKills, journalLoot): in the addon's saved data,
-- account-wide and outside every profile, under the character's GUID (first names are not
-- unique on Forever), so a profile switch or an exported profile never carries it. Made when
-- create is set; nil before that, and before the game knows who you are.
---@param key string
---@param create? boolean
---@return table? mine
function J.CharacterData(key, create)
    local guid = UnitGUID("player")
    if not guid then return end
    local account = ns.AccountSettings()
    local all = account[key]
    if type(all) ~= "table" then
        if not create then return end
        all = {}
        account[key] = all
    end
    local mine = all[guid]
    if type(mine) ~= "table" then
        if not create then return end
        mine = {}
        all[guid] = mine
    end
    return mine
end

-- Opening the Journal (its window, Boss Loot at Cursor) turns the module on, as its settings
-- page's switch does; off, nothing of it is made until then.
function J.TurnOn()
    if S.Get("enabled") then return end
    S.Set("enabled", true)
    ns.Print("Dungeon Journal turned on. Turn it off in its settings page.")
end
