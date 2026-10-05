-------------------------------------------------------------------------------
--  View/View.lua -- draws one page of the Dungeon Journal (ns.Journal.View). A dungeon: its
--  header, your quests there, then each wing's bosses in kill order as cards, two or three
--  across where there is room, each with its loot, your BiS marked, and the bosses with
--  nothing for you as chips at the end. A faction: your standing, then a card of rewards
--  for each standing, with their prices. The PvP rank: your progress this season, then a
--  card for each rank's rewards. One component, used by the Journal's window, the panel
--  beside the world map and the boss loot popup.
--
--  View.New(parent) makes one, on the shared engine (ns.Shared.View: pooled rows, cards,
--  the grid, one redraw per burst of events); view:Draw(dungeon) draws it at the view's
--  width. Its own kinds (View.Kinds, over the shared section, note and card) are in
--  Header, QuestRows, BossCards, ItemRows and FactionRows; how they look is View/Style.lua.
--
--  While a draw runs, a row reads its view (row:GetParent()) for what holds for the whole
--  draw, read once in Begin: view.compact (narrower than COMPACT_W: the map panel),
--  view.playerLevel, view.filters (JournalFilters), view.showChance, view.showTips,
--  view.showKills, view.column (the items' right column: nil the drop chance, "price" or
--  "none"; set by its caller around them), view.tight (each quest on one line: the quest
--  tracker), view.bare (items
--  as what they are only: no marks, level, In Bag; set by
--  its caller after Begin), view.striped (the rows added now lie on a faint band, as every
--  other row of a list; set by its caller around them) and view.redrawFn (draws again, after a BiS change from an item's
--  menu). The window sets
--  view.navigate(page), which opens a dungeon or a faction: the links
--  between them show only where it is set.
--
--  Only while it is shown, a view listens: for the item names it is waiting on, for your
--  quest log when it shows your quests, for your standing on a faction's page (or while
--  view.watchFactions: the window's faction list), for your rank and honor on the rank's,
--  and for your gear, bags, level and looks. Events
--  in a burst make one redraw, REDRAW_DELAY later; a quest log update redraws only when a
--  quest's state changed.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local Loot = J.Loot
local GetItemCount = C_Item.GetItemCount
local IsEquippedItem = C_Item.IsEquippedItem
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString
local GetTitleForQuestID = C_QuestLog.GetTitleForQuestID
local GetQuestDifficultyLevel = C_QuestLog.GetQuestDifficultyLevel
local Quests = J.Quests
local Rep = J.Reputation
local S = J.Settings

local Shared = ns.Shared

local St = J.Style
local COMPACT_W, SECTION_SPACE, FADED, BORDER_RGB = St.COMPACT_W, St.SECTION_SPACE, St.FADED, St.BORDER_RGB
local PLACE_DOT = St.PLACE_DOT

local View = { Kinds = Shared.View.NewKinds(), Parts = setmetatable({}, { __index = Shared.Parts }) }
J.View = View
View.Columns = Shared.View.Columns

---@class JournalView: Frame
local ViewMixin = {}

local BOSS_LOOT_GAP = 4     -- between a boss's header and its first item
local EMPTY_BODY = 28       -- a boss card's body with nothing listed: room for its centred line
local EMPTY = {}
local FACTION_TABS = { "reputation", "pvp" }

-- Only while shown. The quest events only while the view shows quests; item names only
-- while it waits on one.
local STATE_EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "TRANSMOG_COLLECTION_SOURCE_ADDED",
    "ENCOUNTER_END",   -- a kill: J.Kills counts it, and the coalesced redraw shows it
}
local QUEST_EVENTS = { QUEST_LOG_UPDATE = true, QUEST_DATA_LOAD_RESULT = true }
-- Your group and its members' quest logs, for who is on your quests: a redraw, as the
-- quests' own state (QUEST_EVENTS' signature) does not change with them.
local GROUP_EVENTS = { GROUP_ROSTER_UPDATE = true, UNIT_QUEST_LOG_CHANGED = true }
-- On the rank's page: a rank up, and your honor and rank points.
local RANK_EVENTS = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "CURRENCY_DISPLAY_UPDATE" }

-------------------------------------------------------------------------------
--  Per draw: each item's answers, worked out once
-------------------------------------------------------------------------------
-- Listed by the filters (My Class Only, Missing BiS Only).
function ViewMixin:ItemShown(itemID)
    local shown = self.shownCache[itemID]
    if shown == nil then
        shown = Loot.Shown(itemID, self.filters)
        self.shownCache[itemID] = shown
    end
    return shown
end

---@return number? rank its pick number on your BiS list
function ViewMixin:ItemRank(itemID)
    local rank = self.rankCache[itemID]
    if rank == nil then
        rank = Loot.Rank(itemID) or false
        self.rankCache[itemID] = rank
    end
    return rank or nil
end

function ViewMixin:ItemUpgrade(itemID)
    local upgrade = self.upgradeCache[itemID]
    if upgrade == nil then
        upgrade = Loot.Upgrade(itemID)
        self.upgradeCache[itemID] = upgrade
    end
    return upgrade
end

-- Listed: passes the filters and, in a search for items, has the search in its name. A name
-- not loaded yet does not match; the view waits on it and draws again once it has loaded.
function ViewMixin:Listed(itemID, query)
    if not self:ItemShown(itemID) then return false end
    if not query then return true end
    local name = Loot.LowerName(itemID)
    if not name then
        self.waitingFor[itemID] = true
        self.waiting = true
        return false
    end
    return name:find(query, 1, true) ~= nil
end

-- Whether you know the recipe: its tooltip says so ("Already known"), as the game's own does.
-- Asked once per draw: learning a recipe uses the item up, and the bags' update redraws.
function ViewMixin:RecipeKnown(itemID)
    local known = self.knownCache[itemID]
    if known == nil then
        known = false
        local data = C_TooltipInfo.GetItemByID(itemID)
        local lines = data and data.lines or EMPTY
        for i = 1, #lines do
            local text = lines[i].leftText
            if text == ITEM_SPELL_KNOWN and not issecretvalue(text) then known = true end
        end
        self.knownCache[itemID] = known
    end
    return known
end

-- How many of the items are listed.
function ViewMixin:ListCount(items, query)
    local shown = 0
    for i = 1, #items do
        if self:Listed(items[i], query) then shown = shown + 1 end
    end
    return shown
end

-- How many of the boss's items are listed.
function ViewMixin:ShownCount(boss, query)
    return boss.loot and self:ListCount(boss.loot, query) or 0
end

-------------------------------------------------------------------------------
--  Boss cards and their grid
-------------------------------------------------------------------------------
-- One boss's card at x, width w, from the cursor: its header, then its listed loot (only the
-- items with query in their name, in a search). Returns the card and its height; the cursor
-- ends under it.
function ViewMixin:DrawBoss(boss, number, shown, query, x, w)
    local top = self.cursor
    local card = self:OpenCard(x, w)
    local loot, chance = boss.loot or EMPTY, boss.chance
    -- What the filters hide of its loot (not in a search, where the rest just does not match).
    local hidden = not query and #loot - shown or 0
    local header = self:Add("boss", boss, number, shown, hidden)
    header.card = card
    if shown > 0 then self:Space(BOSS_LOOT_GAP) end
    local kept, faded = 0, 0
    for i = 1, #loot do
        local id = loot[i]
        if self:Listed(id, query) then
            local item = self:Add("item", id, chance and chance[i], self:ItemRank(id), self:ItemUpgrade(id))
            item.boss = boss
            if item.keep then kept = kept + 1 else faded = faded + 1 end
        end
    end
    -- Its name lights its BiS and upgrades only when it has some, and something else to fade;
    -- it always takes a right-click, for its Wowhead link.
    header.canPin = kept > 0 and faded > 0
    header:EnableMouse(true)
    -- Nothing listed: why, in the middle of its body (room for the line when its whole row
    -- is as empty).
    card.note:SetText(View.Parts.BossEmptyText(shown, boss))
    card.note:SetShown(shown == 0)
    if shown == 0 then self:Space(EMPTY_BODY) end
    return self:CloseCard(card, top)
end

-------------------------------------------------------------------------------
--  A faction's standing and a rank, as cards
-------------------------------------------------------------------------------
-- A standing's rewards come in three kinds, drawn in this order: gear, recipes, the rest.
local GEAR, RECIPES, OTHER = 1, 2, 3
local KIND_TITLES = { "Gear", "Recipes", "Other" }

local function RewardKind(itemID)
    if Loot.Wearable(itemID) then return GEAR end
    if Loot.Recipe(itemID) then return RECIPES end
    return OTHER
end

-- Opens or folds a standing's recipes (the "group" row's click), and draws again.
local function ToggleRecipes(row)
    local view = row:GetParent()
    view.openRecipes[row.tier] = not view.openRecipes[row.tier]
    view:Redraw()
end

-- One standing's rewards, as a boss's loot: the standing (reached, or how far off when it is
-- the next), then its listed items with their prices, each kind under its own small title,
-- even a card's only one, so cards side by side line up; its recipes beside gear fold to a
-- count until opened.
function ViewMixin:DrawTier(tier, shown, query, x, w)
    local top = self.cursor
    local card = self:OpenCard(x, w)
    local faction = tier.faction
    local reaction, value, max = Rep.Standing(faction)
    local reached = reaction ~= nil and reaction >= tier.standing
    local right
    if reaction and tier.standing == reaction + 1 then right = BreakUpLargeNumbers(max - value) .. " to go" end
    self:Add("tier", Rep.Label(tier.standing), Rep.Color(tier.standing), reached, right, shown)
    if shown > 0 then self:Space(BOSS_LOOT_GAP) end
    self.column = "price"
    local items, counts = tier.items, self.kindCounts
    counts[GEAR], counts[RECIPES], counts[OTHER] = 0, 0, 0
    for i = 1, #items do
        if self:Listed(items[i], query) then
            local kind = RewardKind(items[i])
            counts[kind] = counts[kind] + 1
        end
    end
    for kind = GEAR, OTHER do
        if counts[kind] > 0 then
            local open = true
            local folds = kind == RECIPES and counts[GEAR] > 0 and not query
            if folds then open = self.openRecipes[tier] == true end
            local group = self:Add("group", kind, KIND_TITLES[kind], counts[kind], folds and open, folds and ToggleRecipes)
            group.tier = tier
            if open then
                for i = 1, #items do
                    local id = items[i]
                    if RewardKind(id) == kind and self:Listed(id, query) then
                        local item = self:Add("item", id, nil, self:ItemRank(id), self:ItemUpgrade(id),
                            Rep.Price(faction, id))
                        item.boss = nil
                        if not reached then
                            item.needs = tier.standing
                            item.toGo, item.exact = Rep.ToGo(tier.standing, reaction, value, max)
                        end
                    end
                end
            end
        end
    end
    self.column = nil
    return self:CloseCard(card, top)
end

-- One rank's rewards: the rank and its title (reached, or how far off when it is the next),
-- then each reward, an item as an item and the rest (a title, a mount) as what it is.
function ViewMixin:DrawRankCard(entry, x, w)
    local top = self.cursor
    local card = self:OpenCard(x, w)
    local info, rank = self.rankInfo, entry.rank
    local right
    if rank == info.renownLevel + 1 then
        right = BreakUpLargeNumbers(info.renownLevelThreshold - info.renownReputationEarned) .. " to go"
    end
    local rewards = entry.rewards
    self:Add("tier", "Rank " .. rank .. PLACE_DOT .. Rep.RankTitle(rank), ns.THEME.fg, info.renownLevel >= rank,
        right, #rewards)
    self:Space(BOSS_LOOT_GAP)
    self.column = "none"
    for i = 1, #rewards do
        local reward = rewards[i]
        if reward.itemID then
            local item = self:Add("item", reward.itemID, nil, self:ItemRank(reward.itemID),
                self:ItemUpgrade(reward.itemID))
            item.boss = nil
        else
            self:Add("reward", reward)
        end
    end
    self.column = nil
    return self:CloseCard(card, top)
end

-- What the grid gathered (Gather(entry, number, shown, query)): a boss, a standing's
-- rewards, or a rank's.
function ViewMixin:DrawCard(entry, number, shown, query, x, w)
    if entry.standing then return self:DrawTier(entry, shown, query, x, w) end
    if entry.rewards then return self:DrawRankCard(entry, x, w) end
    return self:DrawBoss(entry, number, shown, query, x, w)
end

-------------------------------------------------------------------------------
--  A clicked boss
-------------------------------------------------------------------------------
-- The clicked boss's BiS and upgrades as they are and its other items faded, its name and
-- card edge in the accent; every other item as it is, and each boss's name lit while hovered.
function ViewMixin:ApplyPin()
    local T = ns.THEME
    local pinned = self.pinned
    local items = self.pools.item
    for i = 1, items.used do
        local row = items[i]
        row:SetAlpha(pinned ~= nil and row.boss == pinned and not row.keep and FADED or row.rest)
    end
    local bosses = self.pools.boss
    for i = 1, bosses.used do
        local row = bosses[i]
        local isPinned = row.boss == pinned
        local color = isPinned and T.accent or row.hovered and T.accentSoft or T.fg
        row.name:SetTextColor(color.r, color.g, color.b)
        local edge = isPinned and T.accent or BORDER_RGB
        row.card.edge:SetColor(edge.r, edge.g, edge.b, 1)
    end
end

-- Clicking a boss's name keeps its BiS and upgrades lit; clicking it again lets go.
function ViewMixin:Pin(boss)
    self.pinned = self.pinned ~= boss and boss or nil
    self:ApplyPin()
end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
-- Every draw starts here: all rows back in their pools, the per-draw answers cleared, and
-- what holds for the whole draw read once.
function ViewMixin:Begin(dungeon, boss, query, page)
    -- A clicked boss stays clicked through a redraw of the same page, not onto another.
    if dungeon ~= self.dungeon or boss ~= self.boss or query ~= self.query or page ~= self.page then
        self.pinned = nil
    end
    self.dungeon, self.boss, self.query, self.page = dungeon, boss, query, page
    self:Clear()
    self.questsDrawn = false
    self.compact = self.width < COMPACT_W
    self.playerLevel = UnitLevel("player")
    Loot.ReadFilters(self.filters)
    -- Drop chances, Naowh's tips and kill counts always show; a caller may turn one off after
    -- Begin (a boss's history shows no chances, the quest panel's rewards neither).
    self.showChance, self.showTips, self.showKills = true, true, true
    self.bare, self.striped, self.tight, self.column = false, false, false, nil
    self.factionLinks, self.watchMoney = false, false
    self.watchQuestLog = false
    wipe(self.shownCache)
    wipe(self.rankCache)
    wipe(self.upgradeCache)
    wipe(self.knownCache)
end

-- And ends here: the view as tall as what it drew, and listening for what can change it.
function ViewMixin:Finish()
    self:Fit(STATE_EVENTS)
    if self.questsDrawn then
        for event in pairs(QUEST_EVENTS) do self:RegisterEvent(event) end
        for event in pairs(GROUP_EVENTS) do self:RegisterEvent(event) end
    elseif self.watchQuestLog then
        for event in pairs(QUEST_EVENTS) do self:RegisterEvent(event) end
    end
    local page = self.page
    if page or self.watchFactions or self.factionLinks then self:RegisterEvent("UPDATE_FACTION") end
    if self.watchMoney then self:RegisterEvent("PLAYER_MONEY") end
    if page and page.rank then
        for i = 1, #RANK_EVENTS do self:RegisterEvent(RANK_EVENTS[i]) end
    end
    self:ApplyPin()
    if self.onResize then self.onResize(self.cursor) end
end

local function OpenQuests()
    S.Set("questsOpen", not S.Get("questsOpen"))
end

local function OpenTracker(dungeon)
    ns.OpenQuestTracker(dungeon)
end

local function OpenMap(dungeon, link)
    J.OpenDungeonMap(dungeon, link)
end

-- Closed until you open it, so the loot comes first; its title says how many there are, and
-- Tracker on its right opens them in a small window of their own.
function ViewMixin:DrawQuests(list)
    local open = S.Get("questsOpen")
    self:Add("section", "Dungeon Quests", #list, open, OpenQuests, "Tracker", OpenTracker, self.dungeon)
    if open then
        for i = 1, #list do self:Add("quest", list[i], i) end
    end
    self:Space(SECTION_SPACE)
end

local function OpenBisList()
    ns.OpenBisWindow()
end

-- Without the BiS List, a word on what it adds; with it but empty, a link to it, to pick them.
function ViewMixin:DrawBisNote()
    if not self.filters.bisOn then
        self:Note("Turn on the BiS List module to see your BiS marked here.")
    elseif ns.BisListIsEmpty() then
        self:SectionLink("Your BiS list is empty", "Open BiS List", OpenBisList)
    end
end

-- One boss and its loot, for the boss loot window.
-- A boss's own page: its name and kill count on top, Naowh's tip written out under it (so no
-- (i) on its name), then the Quests that need it, its Abilities and its Loot; each, the tip
-- too, under a title that opens and closes it (kept: bossTipOpen and the rest; Loot opens
-- again on the next boss) and left out where there is none.
function ViewMixin:DrawBossLoot(boss, dungeon)
    self:Begin(dungeon, boss)
    local tip = self.showTips and J.Tip(boss)
    self.showTips = false
    self:DrawBossName(boss)
    if tip and self:OpenDetailCard("Naowh's Tip") then
        self:Add("tip", boss, tip)
        self:CloseCard(self.detailCard, self.detailTop)
    end
    self:DrawBossDetails(boss)
    self:DrawBossItems(boss)
    self:Finish()
end

-- Its name, kill count and what it is, on top as a dungeon's page has its own: the sections
-- go under it.
function ViewMixin:DrawBossName(boss)
    self:Add("bossHeader", boss)
end

-- A section's title, opened and closed by a click (the setting key keeps which); true while
-- open, with its card opened for its rows.
-- Loot is "loot", not a setting: it opens on every boss, and closing it lasts for that boss
-- only (view.lootClosed is the boss it was closed on).
local SECTION_KEYS = { ["Naowh's Tip"] = "bossTipOpen", Loot = "loot", Quests = "bossQuestsOpen",
    Abilities = "bossAbilitiesOpen" }

function ViewMixin:SectionOpen(key)
    if key == "loot" then return self.lootClosed ~= self.boss end
    return S.Get(key)
end

function ViewMixin:ToggleFor(title)
    self.toggles = self.toggles or {}
    local toggle = self.toggles[title]
    if not toggle then
        local key = SECTION_KEYS[title]
        toggle = function()
            if key == "loot" then
                self.lootClosed = self:SectionOpen(key) and self.boss or nil
            else
                S.Set(key, not S.Get(key))
            end
            self:Redraw()
        end
        self.toggles[title] = toggle
    end
    return toggle
end

-- A section title over a card, its rows added after (View/BossDetails.lua); a space above it
-- when something is drawn there already. One of the boss's sections (SECTION_KEYS) opens and
-- closes by its title: closed, no card, and false.
function ViewMixin:OpenDetailCard(title, count)
    if self.cursor > 0 then self:Space(SECTION_SPACE) end
    local key = SECTION_KEYS[title]
    local open = not key or self:SectionOpen(key)
    if key then
        self:SectionToggle(title, count, open, self:ToggleFor(title))
    else
        self:Section(title, count)
    end
    if not open then return false end
    self:Space(SECTION_SPACE)
    self.detailTop = self.cursor
    self.detailCard = self:OpenCard(0, self:GetWidth())
    -- As much room over its first row as CloseCard leaves under its last.
    self:Space(St.CARD_BOTTOM)
    return true
end

function ViewMixin:DetailCard(title, count, kind, list)
    if not self:OpenDetailCard(title, count) then return end
    for i = 1, #list do self:Add(kind, list[i]) end
    self:CloseCard(self.detailCard, self.detailTop)
end

-- Its loot as the filters show it, or why none is listed.
function ViewMixin:DrawBossItems(boss)
    local loot = boss.loot or EMPTY
    if #loot == 0 then return end
    local shown = self:ShownCount(boss)
    if not self:OpenDetailCard("Loot", shown) then return end
    local chance = boss.chance
    for i = 1, #loot do
        local id = loot[i]
        if self:Listed(id) then
            local item = self:Add("item", id, chance and chance[i], self:ItemRank(id), self:ItemUpgrade(id))
            item.boss = boss
        end
    end
    if shown == 0 then self:Note(View.Parts.BossEmptyText(shown, boss)) end
    self:CloseCard(self.detailCard, self.detailTop)
end

-- The quests that need it (for you, done ones too) and what it does in the fight.
function ViewMixin:DrawBossDetails(boss)
    local ids = boss.npc and J.BossQuests[boss.npc]
    if ids then
        local list = self.bossQuests or {}
        self.bossQuests = list
        wipe(list)
        for i = 1, #ids do
            local quest = Quests.ByID(ids[i])
            if quest and Quests.ForMe(quest) then list[#list + 1] = quest end
        end
        if #list > 0 then
            self:DetailCard("Quests", #list, "bossQuest", list)
            self.watchQuestLog = true   -- drawn again as they move on
        end
    end
    local spells = boss.npc and J.Abilities[boss.npc]
    if spells then self:DetailCard("Abilities", #spells, "ability", spells) end
end

-- "1 Rhahk'Zor": a folded boss's label, the same on every draw, so made once. Bosses are
-- the Journal's data, kept for the session, so these never grow past one per boss.
local chipLabels = {}

local function ChipLabel(boss, number, wing)
    local label = chipLabels[boss]
    if not label then
        label = (wing and wing .. " " or "") .. (number and number .. " " or "") .. boss.name
        chipLabels[boss] = label
    end
    return label
end

-- A dungeon's quests alone, each on one line: the quest tracker's.
---@param dungeon JournalDungeon
function ViewMixin:DrawTracker(dungeon)
    self:Begin(dungeon, nil)
    self.tight = true
    local list = EMPTY
    if dungeon.quests then
        list = Quests.List(dungeon.quests, self.questList, self.questPool)
        self.questSignature = Quests.Signature(dungeon.quests)
        self.questsDrawn = true
    end
    if #list == 0 then self:Note(Quests.NoneWhy(dungeon.quests) or "No quests here.") end
    for i = 1, #list do self:Add("quest", list[i], i) end
    self:Finish()
end

---@param dungeon JournalDungeon
-- The title over the bosses with nothing listed, by the filter that hid their loot.
local SKIPPED_TITLE = { missingBisOnly = "Nothing you're missing", upgradesOnly = "Nothing that beats your gear",
    usableOnly = "Nothing for your class" }

function ViewMixin:Draw(dungeon)
    self:Begin(dungeon, nil)
    local list = EMPTY
    if dungeon.quests then
        list = Quests.List(dungeon.quests, self.questList, self.questPool)
        self.questSignature = Quests.Signature(dungeon.quests)
        self.questsDrawn = true
    end
    self:Add("header", dungeon)
    if dungeon.note then self:Note(dungeon.note) end
    -- The factions earned here, each a link to its page.
    if self.navigate and dungeon.factions then
        self:Add("links", "Reputation", dungeon.factions)
        self:Space(SECTION_SPACE)
        self.factionLinks = true
    end
    if #list > 0 then
        self:DrawQuests(list)
    elseif dungeon.quests then
        -- None listed for you: the title still, and why, so the dungeon does not look empty.
        local why = Quests.NoneWhy(dungeon.quests)
        if why then
            self:Section("Dungeon Quests", 0)
            self:Note(why)
            self:Space(SECTION_SPACE)
        end
    end
    if not J.HasBosses(dungeon) then
        self:Note("No boss data for this dungeon yet. It fills in with a later version "
            .. "of the addon.")
    end
    -- Bosses with nothing listed for you share one row at the very end, after every wing,
    -- each still with its tip; in a dungeon with wings each is named with its wing, whose
    -- numbers start again.
    local skipped, skippedBoss = self.skipped, self.skippedBoss
    wipe(skipped)
    wipe(skippedBoss)
    for i, wing in ipairs(dungeon.wings) do
        -- Numbered in kill order; a rare, an optional boss, a chest and the trash have no
        -- number, and neither a chest nor the trash counts as a boss.
        local number, cards = 0, 0
        for _, boss in ipairs(wing.bosses) do
            local ordered = not (boss.rare or boss.optional or boss.chest or boss.trash)
            if ordered then number = number + 1 end
            local kill = ordered and number or nil
            local shown = self:ShownCount(boss)
            if shown == 0 and boss.loot then
                skipped[#skipped + 1] = ChipLabel(boss, kill, wing.name)
                skippedBoss[#skippedBoss + 1] = boss
            else
                self:Gather(boss, kill, shown)
                if not (boss.trash or boss.chest) then cards = cards + 1 end
            end
        end
        local title = wing.name or (i == 1 and "Bosses")
        -- Map on the first title's right: the dungeon's map, in a small window; muted, and
        -- "Coming soon" on hover, for one with no map yet. Beside the world map only once the
        -- dungeon's map stepped aside there (another map shown): it brings it back.
        local count = cards > 0 and cards or nil
        if title and i == 1 and (not self.onWorldMap or J.DungeonMapAway()) then
            if J.Maps[dungeon.key] then
                self:Add("section", title, count, nil, nil, "Map", OpenMap, dungeon)
            else
                self:Add("section", title, count, nil, nil, "Map", nil, nil, "Coming soon", "No map of this dungeon yet.")
            end
            self:Space(SECTION_SPACE)
        elseif title then
            self:Section(title, count)
            self:Space(SECTION_SPACE)
        end
        self:DrawGrid()
    end
    self:DrawBisNote()
    -- Always last: the bosses with nothing listed for you, as chips that keep their tips.
    if #skipped > 0 then
        self:Space(BOSS_LOOT_GAP)
        local filters = self.filters
        local key = filters.missingBis and "missingBisOnly" or filters.upgradesOnly and "upgradesOnly" or "usableOnly"
        self:Add("skipped", SKIPPED_TITLE[key], key, skippedBoss, skipped)
        self:Space(BOSS_LOOT_GAP)
    end
    self:Finish()
end

-- A faction: its header and your standing, the dungeons it is earned in, then a card of
-- rewards for each standing, lowest first.
---@param faction JournalFaction
function ViewMixin:DrawFaction(faction)
    self:Begin(nil, nil, nil, faction)
    self:Add("page", faction)
    -- Your standing as a track, each standing with how many rewards it unlocks for you.
    local reaction, value, max = Rep.Standing(faction)
    local counts = wipe(self.trackCounts)
    for _, tier in ipairs(faction.tiers) do counts[tier.standing] = self:ListCount(tier.items) end
    self:Add("track", reaction, value, max, counts)
    self:DrawSpend(faction, reaction)
    if self.navigate and faction.linked and #faction.linked > 0 then
        self:Add("links", "Earned in", faction.linked)
        self:Space(SECTION_SPACE)
    end
    self:DrawRepQuests(faction)
    local tiers, total = faction.tiers, 0
    for i = 1, #tiers do
        local shown = self:ListCount(tiers[i].items)
        if shown > 0 then
            total = total + shown
            self:Gather(tiers[i], nil, shown)
        end
    end
    self:Section("Rewards", total)
    self:Space(SECTION_SPACE)
    self:DrawGrid()
    if total == 0 then self:Note(self:HiddenWhy(faction)) end
    self:DrawBisNote()
    self:Finish()
end

-- Why none of a faction's rewards is listed: each filter hiding some, with how many and the
-- switch that shows them. The filters are tried in the order Loot.Shown tries them, so each
-- reward counts once, against the first that hides it.
function ViewMixin:HiddenWhy(faction)
    local filters = self.filters
    local class, cosmetic, recipes, bis, upgrades = 0, 0, 0, 0, 0
    for _, tier in ipairs(faction.tiers) do
        for _, id in ipairs(tier.items) do
            if filters.usableOnly and not Loot.Usable(id) then
                class = class + 1
            elseif not filters.showCosmetic and Loot.Cosmetic(id) then
                cosmetic = cosmetic + 1
            elseif filters.myRecipes and Loot.Recipe(id) and not Loot.RecipeYours(Loot.Recipe(id), filters) then
                recipes = recipes + 1
            elseif filters.missingBis and not Loot.Missing(id) then
                bis = bis + 1
            elseif filters.upgradesOnly and not Loot.Upgrade(id) then
                upgrades = upgrades + 1
            end
        end
    end
    local why = {}
    if recipes > 0 then
        why[#why + 1] = ("%d %s for professions you do not have (My Professions Only)"):format(recipes,
            recipes == 1 and "is a recipe" or "are recipes")
    end
    if class > 0 then
        why[#why + 1] = ("%d %s not for your class (My Class Only)"):format(class, class == 1 and "is" or "are")
    end
    if cosmetic > 0 then
        why[#why + 1] = ("%d %s cosmetic (Show Cosmetic Items, off)"):format(cosmetic, cosmetic == 1 and "is" or "are")
    end
    if bis > 0 then
        why[#why + 1] = ("%d %s not BiS you are missing (Missing BiS Only)"):format(bis, bis == 1 and "is" or "are")
    end
    if upgrades > 0 then
        why[#why + 1] = ("%d %s not an upgrade over what you wear (Upgrades Only)"):format(upgrades,
            upgrades == 1 and "is" or "are")
    end
    if #why == 0 then
        return ("WoW Forever's build %s has no rewards for it yet: they show here once a build has them.")
            :format(J.DATA_BUILD or "")
    end
    return "Nothing here for you: of its rewards, " .. table.concat(why, ", ")
        .. ". Turn " .. (#why == 1 and "that filter" or "those filters") .. " off in Filters to see them."
end

-- What the rewards your standing has unlocked would cost, those you have not got yet (not in
-- your bags or bank, not worn, not a recipe you know), against your gold: red when short.
local SPEND_ICON = "Interface\\Icons\\INV_Misc_Coin_02"

function ViewMixin:DrawSpend(faction, reaction)
    if not reaction then return end
    local count, copper = 0, 0
    for _, tier in ipairs(faction.tiers) do
        if tier.standing <= reaction then
            for _, id in ipairs(tier.items) do
                local price = Rep.Price(faction, id)
                if price and self:ItemShown(id) and GetItemCount(id, true) == 0 and not IsEquippedItem(id)
                    and not (Loot.Recipe(id) and self:RecipeKnown(id)) then
                    count, copper = count + 1, copper + price
                end
            end
        end
    end
    if count == 0 then return end
    local money = GetMoney()
    local have = "you have " .. GetCoinTextureString(money)
    self.watchMoney = true
    self:Add("line", SPEND_ICON, ("Unlocked and not yours yet: %d %s, %s"):format(count,
        count == 1 and "reward" or "rewards", GetCoinTextureString(copper)),
        money < copper and J.Style.RED_CODE .. have .. "|r" or have)
end

-- How to raise it, in the dungeon quests' rows, under a title that opens and closes: the
-- quests in your log that give its reputation (the game names what a quest gives only once
-- you have it), then its repeatable hand-ins: who takes each and where, with a waypoint,
-- what one gives, and a ? once your bags hold enough. Nothing when it has neither.
local IN_LOG_TEXT = "In your quest log"
local REP_CODE = St.QUEST_CODE.done

local function OpenRepQuests()
    S.Set("repQuestsOpen", not S.Get("repQuestsOpen"))
end

-- Your log's quests as quest records (ID, name, level, side, shareable, where), reused.
function ViewMixin:LogQuestData(log)
    local data = self.repLogData
    local quests = data.quests
    for i = 1, #log do
        local id = log[i]
        local quest = quests[i] or {}
        quests[i] = quest
        quest[1], quest[2], quest[3], quest[4], quest[5], quest[6] = id, GetTitleForQuestID(id) or ("Quest " .. id),
            GetQuestDifficultyLevel(id), "B", true, IN_LOG_TEXT
    end
    for i = #log + 1, #quests do quests[i] = nil end
    return data
end

function ViewMixin:DrawRepQuests(faction)
    local log, signature = Rep.LogQuests(faction, self.repLog)
    self.repSignature, self.watchQuestLog = signature, true
    local logged = Quests.List(self:LogQuestData(log), self.repLogList, self.repLogPool)
    local handIns = faction.questData and Quests.List(faction.questData, self.repList, self.repPool) or EMPTY
    for i = 1, #handIns do
        local entry = handIns[i]
        local turnin = entry.quest.turnin
        entry.turnin, entry.held = turnin, Rep.TurnInsHeld(turnin)
        -- Enough in your bags: the game's ? to hand it in, as a quest ready in your log.
        if entry.held > 0 and not entry.inLog then entry.kind = "ready" end
        entry.name = entry.name .. "  " .. REP_CODE .. "+" .. turnin.rep .. " rep|r"
    end
    local count = #logged + #handIns
    if count == 0 then return end
    local open = S.Get("repQuestsOpen")
    self:SectionToggle("Quests", count, open, OpenRepQuests)
    if open then
        for i = 1, #logged do self:Add("quest", logged[i], i) end
        for i = 1, #handIns do self:Add("quest", handIns[i], #logged + i) end
    end
    self.questsDrawn = true
    self:Space(SECTION_SPACE)
end

-- Your PvP rank this season: the rank, the season and your honor, how far to the next rank
-- and this week's cap, then a card for each rank that gives something, from the game.
function ViewMixin:DrawRank()
    self:Begin(nil, nil, nil, J.RANK)
    local info = Rep.Rank()
    self.rankInfo = info
    self:Add("page", J.RANK, info)
    if not info then
        self:Note("The game has no PvP rank for you yet. It shows once the season has started.")
        self:Finish()
        return
    end
    local top = info.maxLevel
    self:Add("rankTrack", info)
    local entries, count = self.rankEntries, 0
    for rank = 1, top do
        local rewards = Rep.RankRewards(rank)
        if rewards and #rewards > 0 then
            count = count + 1
            local entry = entries[count]
            if not entry then
                entry = {}
                entries[count] = entry
            end
            entry.rank, entry.rewards = rank, rewards
            self:Gather(entry, nil, #rewards)
        end
    end
    self:Section("Rank Rewards", count)
    self:Space(SECTION_SPACE)
    self:DrawGrid()
    if count == 0 then self:Note("The game lists no rank rewards for this season yet.") end
    self:Finish()
end

-- A boss's or a faction's name in lower case, for search, made once.
local lowerNames = {}

local function LowerName(boss)
    local lower = lowerNames[boss]
    if not lower then
        lower = boss.name:lower()
        lowerNames[boss] = lower
    end
    return lower
end

-- A search for item, boss and faction names: every boss whose name has it, with all its
-- loot, or whose loot has it, with those items, by dungeon, each with Open to go to that
-- dungeon; then the same for the factions' rewards. onOpen(page) is the caller's. query is
-- lower case.
function ViewMixin:DrawSearch(query, onOpen)
    self:Begin(nil, nil, query)
    self.onOpen = onOpen
    local found = 0
    for _, dungeon in ipairs(J.Dungeons()) do
        local wings = J.FactionShown(dungeon) and dungeon.wings or EMPTY
        for _, wing in ipairs(wings) do
            for _, boss in ipairs(wing.bosses) do
                local byName = LowerName(boss):find(query, 1, true) ~= nil
                local itemQuery = not byName and query or nil
                local shown = self:ShownCount(boss, itemQuery)
                if byName or shown > 0 then
                    found = found + 1
                    self:Gather(boss, nil, shown, itemQuery)
                end
            end
        end
        if self.grid.n > 0 then
            self:SectionLink(dungeon.name, "Open", onOpen, dungeon)
            self:Space(SECTION_SPACE)
            self:DrawGrid()
        end
    end
    -- Then the factions: every reward of one whose name has it, else the rewards that do.
    for t = 1, #FACTION_TABS do
        for _, faction in ipairs(J.Factions(FACTION_TABS[t])) do
            if Rep.Shown(faction) then
                local itemQuery = LowerName(faction):find(query, 1, true) == nil and query or nil
                for _, tier in ipairs(faction.tiers) do
                    local shown = self:ListCount(tier.items, itemQuery)
                    if shown > 0 then
                        found = found + 1
                        self:Gather(tier, nil, shown, itemQuery)
                    end
                end
                if self.grid.n > 0 then
                    self:SectionLink(faction.name, "Open", onOpen, faction)
                    self:Space(SECTION_SPACE)
                    self:DrawGrid()
                end
            end
        end
    end
    if found == 0 then
        self:Note(self.waiting and "Searching..." or ("Nothing in the journal matches " .. query .. "."))
    end
    self:Finish()
end

-- Draws the page again as it is: the search, the boss or the dungeon.
function ViewMixin:Redraw()
    if not self:IsVisible() then return end
    if self.tracker then
        if self.dungeon then self:DrawTracker(self.dungeon) end
    elseif self.query then
        self:DrawSearch(self.query, self.onOpen)
    elseif self.page then
        if self.page.rank then self:DrawRank() else self:DrawFaction(self.page) end
    elseif self.boss then
        self:DrawBossLoot(self.boss, self.dungeon)
    elseif self.dungeon then
        self:Draw(self.dungeon)
    end
end

-------------------------------------------------------------------------------
--  Events: one redraw for a burst, and none for what does not change the page
-------------------------------------------------------------------------------
function ViewMixin:Flush()
    self.flushQueued = false
    local questsOnly = self.questsDirty and not self.dirty
    self.dirty, self.questsDirty = false, false
    if not self:IsVisible() then return end
    -- A quest log update that changed no quest's state (an objective ticking up) changes
    -- nothing on the page; the hover card reads the progress when it opens.
    if questsOnly and self.dungeon and self.dungeon.quests
        and Quests.Signature(self.dungeon.quests) == self.questSignature then
        return
    end
    -- On a faction's page, the same for the quests in your log that raise it.
    if questsOnly and self.watchQuestLog and self.page then
        local _, signature = Rep.LogQuests(self.page, self.repLog)
        if signature == self.repSignature then return end
    end
    self:Redraw()
end

function ViewMixin:OnEvent(event, arg)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not self.waitingFor[arg] then return end
    elseif QUEST_EVENTS[event] then
        self.questsDirty = true
        return self:QueueFlush()
    elseif event == "UNIT_QUEST_LOG_CHANGED" and arg == "player" then
        return   -- yours: QUEST_LOG_UPDATE covers it
    end
    self:QueueRedraw()
end

function ViewMixin:OnHide()
    self:UnregisterAllEvents()
    self.dirty, self.questsDirty = false, false
end

---@param parent Frame
---@return JournalView view
function View.New(parent)
    local view = Shared.View.New(parent, View.Kinds, ViewMixin)
    view.filters = {}                                   ---@type JournalFilters
    view.shownCache, view.rankCache, view.upgradeCache = {}, {}, {}
    view.knownCache = {}                                -- recipe ID -> you know it, this draw
    view.rankEntries = {}                               -- the rank page's cards, reused
    view.kindCounts = {}                                -- a standing's rewards of each kind, per card
    view.repLog = {}                                    -- a faction page's quests in your log
    view.repLogData = { quests = {} }                   -- and as quest records, reused
    view.repLogList, view.repLogPool = {}, {}           -- their rows' entries
    view.repList, view.repPool = {}, {}                 -- its hand-ins' rows' entries
    view.trackCounts = {}                               -- standing -> its rewards listed, for the track
    view.openRecipes = {}                               -- tier -> its folded recipes opened, this session
    view.questList, view.questPool = {}, {}             -- this view's own quest entries
    view.skipped, view.skippedBoss = {}, {}             -- the folded bosses' labels and bosses
    return view
end
