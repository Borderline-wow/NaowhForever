-------------------------------------------------------------------------------
--  Journal.lua -- the Dungeon Journal's core (ns.Journal): its settings, every dungeon, and
--  the questions the rest of the module asks about them. Each dungeon is its own file in
--  Data/Dungeons/ and hands itself to AddDungeon; this joins them with the quest data
--  (instance, levels, quests: Data/Quests.lua). No frames here.
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

local S = ns.UI.ModuleSettings("journal", {
    enabled = false,
    mapPanel = true,
    usableOnly = true,
    showRare = true,
    showChance = true,
    showAppearance = false,
    showTips = true,
    showKills = true,
    questsOpen = false,
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
        { key = "missingBisOnly", label = "Missing BiS Only", hides = true, needsBis = true,
          tooltip = "Only the loot you still need from your BiS list: higher on it than what "
              .. "you wear, and not in your bags or bank." },
        { key = "showRare", label = "Rare Bosses", hides = false,
          tooltip = "The rare bosses too, which do not spawn every run." },
    } },
    { title = "What it shows", options = {
        { key = "showChance", label = "Drop Chance",
          tooltip = "How often each item drops, from the kills Wowhead has recorded." },
        { key = "showAppearance", label = "Appearances",
          tooltip = "A hanger on each item whose look you do not have yet for transmog, and how "
              .. "many of the dungeon's looks you have under its name." },
        { key = "showTips", label = "Naowh's Tips",
          tooltip = "An (i) after each boss: hover it for Naowh's tip, click it to share the "
              .. "tip in chat." },
        { key = "showKills", label = "Kill Count",
          tooltip = "A skull on each boss with how many times this character has killed it; "
              .. "hover it for when, click it for each kill: who was with you, what dropped and "
              .. "who won it. Kills and loot count while the Dungeon Journal is on." },
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

-- Each file in Data/Dungeons/ hands its dungeon over once, at load.
---@param key string
---@param dungeon JournalDungeon
function J.AddDungeon(key, dungeon)
    dungeon.key = key
    ordered[#ordered + 1] = dungeon
    byKey[key] = dungeon
end

local function Join()
    byMap, byName = {}, {}
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
