-------------------------------------------------------------------------------
--  View/View.lua -- draws one dungeon of the Dungeon Journal (ns.Journal.View): its header,
--  your quests there, then each wing's bosses in kill order as cards, two or three across
--  where there is room, each with its loot, your BiS marked, and the bosses with nothing for
--  you as chips at the end. One component, used by the Journal's window, the panel beside
--  the world map and the boss loot popup.
--
--  View.New(parent) makes one; view:Draw(dungeon) draws it at the view's width and sets the
--  view's height to fit. The rows it draws are kinds (View.Kinds), each in its own file:
--  Parts (section titles, notes), Header, QuestRows, BossCards and ItemRows; how they look
--  is View/Style.lua. Rows are pooled per kind and reused on every draw. A kind is
--  { New(view) -> frame, made once; Set(row, ...) -> height, waiting? }, Set left out for a
--  kind only placed (a card).
--
--  While a draw runs, a row reads its view (row:GetParent()) for what holds for the whole
--  draw, read once in Begin: view.compact (narrower than COMPACT_W: the map panel),
--  view.playerLevel, view.filters (JournalFilters), view.showChance, view.showTips,
--  view.showKills, view.tight (each quest on one line: the quest tracker), view.bare (items
--  as what they are only: no marks, level, In Bag; set by
--  its caller after Begin), view.striped (the rows added now lie on a faint band, as every
--  other row of a list; set by its caller around them) and view.redrawFn (draws again, after a BiS change from an item's
--  menu).
--
--  Only while it is shown, a view listens: for the item names it is waiting on, for your
--  quest log when it shows your quests, and for your gear, bags, level and looks. Events
--  in a burst make one redraw, REDRAW_DELAY later; a quest log update redraws only when a
--  quest's state changed.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local Loot = J.Loot
local Quests = J.Quests
local S = J.Settings

local St = J.Style
local CARD_PAD, CARD_GAP, CARD_BOTTOM = St.CARD_PAD, St.CARD_GAP, St.CARD_BOTTOM
local CARD_MIN_W, MAX_COLUMNS, COMPACT_W = St.CARD_MIN_W, St.MAX_COLUMNS, St.COMPACT_W
local SECTION_SPACE, FADED, BORDER_RGB = St.SECTION_SPACE, St.FADED, St.BORDER_RGB

local View = { Kinds = {}, Parts = {} }
J.View = View
local Kinds = View.Kinds

---@class JournalView: Frame
local ViewMixin = {}

local REDRAW_DELAY = 0.15   -- seconds: events in a burst make one redraw
local BOSS_LOOT_GAP = 4     -- between a boss's header and its first item
local EMPTY = {}

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

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
function ViewMixin:Acquire(kind)
    local pool = self.pools[kind]
    pool.used = pool.used + 1
    local row = pool[pool.used]
    if not row then
        row = Kinds[kind].New(self)
        pool[pool.used] = row
    end
    -- Sized now, not only anchored, so wrapped text measures at the right width. Inside a
    -- card, left and width are the card's inside.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.left, -self.cursor)
    row:SetWidth(self.width)
    row:Show()
    return row
end

-- Places a row of the kind at the cursor, fills it and moves the cursor past it.
function ViewMixin:Add(kind, ...)
    local row = self:Acquire(kind)
    local height, waiting = Kinds[kind].Set(row, ...)
    row:SetHeight(height)
    self.cursor = self.cursor + height
    if waiting then self.waiting = true end
    return row
end

function ViewMixin:Space(height)
    self.cursor = self.cursor + height
end

-- A section's title over a line, with a muted count after it.
function ViewMixin:Section(title, count)
    return self:Add("section", title, count)
end

-- A section that opens and closes: a chevron before its title, a click anywhere on it.
function ViewMixin:SectionToggle(title, count, open, onToggle)
    return self:Add("section", title, count, open, onToggle)
end

-- A section with a link on its right: onLink(linkArg) when clicked.
function ViewMixin:SectionLink(title, linkText, onLink, linkArg)
    return self:Add("section", title, nil, nil, nil, linkText, onLink, linkArg)
end

function ViewMixin:Note(text)
    return self:Add("note", text)
end

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

-- How many of the boss's items are listed.
function ViewMixin:ShownCount(boss, query)
    local loot, shown = boss.loot, 0
    for i = 1, loot and #loot or 0 do
        if self:Listed(loot[i], query) then shown = shown + 1 end
    end
    return shown
end

-------------------------------------------------------------------------------
--  Boss cards and their grid
-------------------------------------------------------------------------------
-- One boss's card at x, width w, from the cursor: its header, then its listed loot (only the
-- items with query in their name, in a search). Returns the card and its height; the cursor
-- ends under it.
function ViewMixin:DrawBoss(boss, number, shown, query, x, w)
    local top = self.cursor
    self.left, self.width = x, w
    local card = self:Acquire("card")
    card:SetFrameLevel(self:GetFrameLevel())
    self.left, self.width = x + CARD_PAD, w - CARD_PAD * 2
    local loot, chance = boss.loot or EMPTY, boss.chance
    local header = self:Add("boss", boss, number, shown)
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
    -- Its name lights its BiS and upgrades only when it has some, and something else to fade.
    header:EnableMouse(kept > 0 and faded > 0)
    self:Space(CARD_BOTTOM)
    self.left, self.width = 0, self:GetWidth()
    local height = self.cursor - top
    card:SetHeight(height)
    return card, height
end

-- The bosses gathered for a grid, drawn as many across as fit, up to MAX_COLUMNS, or one
-- under the other in a narrow view; the cards in a row share the tallest one's height.
function ViewMixin:Gather(boss, number, shown, query)
    local grid = self.grid
    local n = grid.n + 1
    grid.n = n
    grid.boss[n], grid.number[n], grid.shown[n], grid.query[n] = boss, number, shown, query
end

-- How many cards fit across a view this wide, up to MAX_COLUMNS and at least one, and each
-- card's width.
---@param width number
---@return number columns
---@return number cardWidth
function View.Columns(width)
    local columns = math.max(1, math.min(MAX_COLUMNS, math.floor((width + CARD_GAP) / (CARD_MIN_W + CARD_GAP))))
    return columns, math.floor((width - CARD_GAP * (columns - 1)) / columns)
end
local Columns = View.Columns

function ViewMixin:DrawGrid()
    local grid, cards = self.grid, self.rowCards
    local columns, w = Columns(self:GetWidth())
    local i = 1
    while i <= grid.n do
        local top, height = self.cursor, 0
        local last = math.min(i + columns - 1, grid.n)
        for k = i, last do
            self.cursor = top
            local card, cardHeight = self:DrawBoss(grid.boss[k], grid.number[k], grid.shown[k], grid.query[k],
                (k - i) * (w + CARD_GAP), w)
            cards[k - i + 1] = card
            if cardHeight > height then height = cardHeight end
        end
        for k = 1, last - i + 1 do cards[k]:SetHeight(height) end
        self.cursor = top + height + CARD_GAP
        i = last + 1
    end
    grid.n = 0
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
-- Closes the tooltip when one of this view's rows owns it: the redraw reuses that row for
-- something else.
local function CloseOwnTooltip(view)
    local owner = GameTooltip:GetOwner()
    while owner do
        if owner == view then
            GameTooltip:Hide()
            return
        end
        owner = owner:GetParent()
    end
end

-- Every draw starts here: all rows back in their pools, the per-draw answers cleared, and
-- what holds for the whole draw read once.
function ViewMixin:Begin(dungeon, boss, query)
    -- A clicked boss stays clicked through a redraw of the same page, not onto another.
    if dungeon ~= self.dungeon or boss ~= self.boss or query ~= self.query then self.pinned = nil end
    self.dungeon, self.boss, self.query = dungeon, boss, query
    self.cursor, self.left, self.width = 0, 0, self:GetWidth()
    self.waiting, self.questsDrawn = false, false
    self.compact = self.width < COMPACT_W
    self.playerLevel = UnitLevel("player")
    Loot.ReadFilters(self.filters)
    self.showChance, self.showTips = S.Get("showChance"), S.Get("showTips")
    self.showKills = S.Get("showKills")
    self.bare, self.striped, self.tight = false, false, false
    wipe(self.shownCache)
    wipe(self.rankCache)
    wipe(self.upgradeCache)
    wipe(self.waitingFor)
    CloseOwnTooltip(self)
    for _, pool in pairs(self.pools) do
        for i = 1, pool.used do pool[i]:Hide() end
        pool.used = 0
    end
end

-- And ends here: the view as tall as what it drew, and listening for what can change it.
function ViewMixin:Finish()
    self:SetHeight(math.max(self.cursor, 1))
    self:UnregisterAllEvents()
    for i = 1, #STATE_EVENTS do self:RegisterEvent(STATE_EVENTS[i]) end
    if self.waiting then self:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    if self.questsDrawn then
        for event in pairs(QUEST_EVENTS) do self:RegisterEvent(event) end
        for event in pairs(GROUP_EVENTS) do self:RegisterEvent(event) end
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

-- One boss and its loot, for the boss loot window.
function ViewMixin:DrawBossLoot(boss, dungeon)
    self:Begin(dungeon, boss)
    self:DrawBoss(boss, nil, self:ShownCount(boss), nil, 0, self:GetWidth())
    self:Finish()
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
        self:Note("Wowhead has no boss data for this dungeon yet. It fills in with a later version "
            .. "of the addon.")
    end
    -- Bosses with nothing listed for you share one row at the very end, after every wing,
    -- each still with its tip; in a dungeon with wings each is named with its wing, whose
    -- numbers start again.
    local skipped, skippedBoss = self.skipped, self.skippedBoss
    wipe(skipped)
    wipe(skippedBoss)
    for i, wing in ipairs(dungeon.wings) do
        local number = 0
        for _, boss in ipairs(wing.bosses) do
            if Loot.BossShown(boss, self.filters) then
                if not boss.rare then number = number + 1 end
                local kill = not boss.rare and number or nil
                local shown = self:ShownCount(boss)
                if shown == 0 and boss.loot then
                    skipped[#skipped + 1] = ChipLabel(boss, kill, wing.name)
                    skippedBoss[#skippedBoss + 1] = boss
                else
                    self:Gather(boss, kill, shown)
                end
            end
        end
        local title = wing.name or (i == 1 and "Bosses")
        if title then
            self:Section(title, self.grid.n > 0 and self.grid.n or nil)
            self:Space(SECTION_SPACE)
        end
        self:DrawGrid()
    end
    if not self.filters.bisOn then
        self:Note("Turn on the BiS List module to see your BiS marked here.")
    elseif ns.BisListIsEmpty() then
        self:SectionLink("Your BiS list is empty", "Fill My BiS List", self.fillFn)
    end
    -- Always last: the bosses with nothing listed for you, as chips that keep their tips.
    if #skipped > 0 then
        self:Space(BOSS_LOOT_GAP)
        local missing = self.filters.missingBis
        self:Add("skipped", missing and "Nothing you're missing" or "Nothing for your class",
            missing and "missingBisOnly" or "usableOnly", skippedBoss, skipped)
        self:Space(BOSS_LOOT_GAP)
    end
    self:Finish()
end

-- A boss's name in lower case, for search, made once.
local lowerNames = {}

local function LowerName(boss)
    local lower = lowerNames[boss]
    if not lower then
        lower = boss.name:lower()
        lowerNames[boss] = lower
    end
    return lower
end

-- A search for item and boss names: every boss whose name has it, with all its loot, or
-- whose loot has it, with those items, by dungeon, each with Open to go to that dungeon.
-- onOpen(dungeon) is the caller's. query is lower case.
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
    self:Redraw()
end

function ViewMixin:OnEvent(event, arg)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not self.waitingFor[arg] then return end
        self.dirty = true
    elseif QUEST_EVENTS[event] then
        self.questsDirty = true
    elseif event == "UNIT_QUEST_LOG_CHANGED" and arg == "player" then
        return   -- yours: QUEST_LOG_UPDATE covers it
    else
        self.dirty = true
    end
    if self.flushQueued then return end
    self.flushQueued = true
    C_Timer.After(REDRAW_DELAY, self.flushFn)
end

local function OnHide(self)
    self:UnregisterAllEvents()
    self.dirty, self.questsDirty = false, false
end

---@param parent Frame
---@return JournalView view
function View.New(parent)
    local view = CreateFrame("Frame", nil, parent)
    Mixin(view, ViewMixin)
    view.pools = {}
    for kind in pairs(Kinds) do view.pools[kind] = { used = 0 } end
    view.filters = {}                                   ---@type JournalFilters
    view.shownCache, view.rankCache, view.upgradeCache = {}, {}, {}
    view.waitingFor = {}                                -- item IDs whose names it waits on
    view.grid = { n = 0, boss = {}, number = {}, shown = {}, query = {} }
    view.rowCards = {}                                  -- the cards of the grid row being drawn
    view.questList, view.questPool = {}, {}             -- this view's own quest entries
    view.skipped, view.skippedBoss = {}, {}             -- the folded bosses' labels and bosses
    view.redrawFn = function() view:Redraw() end
    view.flushFn = function() view:Flush() end
    view.fillFn = function()
        ns.FillBisFromRanking()
        view:Redraw()
    end
    view:SetScript("OnEvent", view.OnEvent)
    view:SetScript("OnHide", OnHide)
    return view
end
