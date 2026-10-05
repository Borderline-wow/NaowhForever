-------------------------------------------------------------------------------
--  View.lua -- the engine a module draws a page with (ns.Shared.View): rows of kinds, placed
--  top down and pooled per kind, reused on every draw; cards, and a grid of them as many
--  across as fit; and one redraw for a burst of events, only while shown.
--
--  A kind is { New(view) -> frame, made once; Set(row, ...) -> height, waiting? }; Set is
--  left out for a kind only placed (a card). A module keeps its kinds in a table that falls
--  back on the shared ones (View.NewKinds()), and makes a view with View.New(parent, kinds,
--  mixin): its mixin draws (Begin with Clear, rows, Fit) and redraws (Redraw).
--
--  While a draw runs, a row reads its view (row:GetParent()): view.left and view.width are
--  where rows go (inside a card, its inside), view.waitingFor holds the items whose names
--  it waits on (Set returns waiting = true for one), view.redrawFn draws again.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Shared = ns.Shared
local View = Shared.View

local St = Shared.Style
local Refuse = Shared.Items.Refuse
local CARD_PAD, CARD_GAP, CARD_BOTTOM = St.CARD_PAD, St.CARD_GAP, St.CARD_BOTTOM
local CARD_MIN_W, MAX_COLUMNS, BORDER_RGB = St.CARD_MIN_W, St.MAX_COLUMNS, St.BORDER_RGB

local REDRAW_DELAY = 0.15   -- seconds: events in a burst make one redraw

local Engine = {}
View.Engine = Engine

function View.NewKinds()
    return setmetatable({}, { __index = Shared.Kinds })
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
function Engine:Acquire(kind)
    local pool = self.pools[kind]
    pool.used = pool.used + 1
    local row = pool[pool.used]
    if not row then
        row = self.kinds[kind].New(self)
        pool[pool.used] = row
    end
    -- Sized now, not only anchored, so wrapped text measures at the right width. Its top is
    -- kept, to scroll to it (ScrollToRow).
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.left, -self.cursor)
    row.top = self.cursor
    row:SetWidth(self.width)
    row:Show()
    return row
end

function Engine:Add(kind, ...)
    local row = self:Acquire(kind)
    local height, waiting = self.kinds[kind].Set(row, ...)
    row:SetHeight(height)
    self.cursor = self.cursor + height
    if waiting then self.waiting = true end
    return row
end

-- The first drawn row of a kind that test(row, arg) picks, or nil.
function Engine:Find(kind, test, arg)
    local pool = self.pools[kind]
    for i = 1, pool.used do
        if test(pool[i], arg) then return pool[i] end
    end
end

-- Scrolls the scroll frame the view is the child of so a row sits near its top. The view's
-- height is set as it draws (Fit), so the furthest it can go is known before the layout.
local SCROLL_MARGIN = 40

function Engine:ScrollToRow(scroll, row)
    local furthest = math.max(0, self:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(math.min(math.max(0, row.top - SCROLL_MARGIN), furthest))
end

function Engine:Space(height)
    self.cursor = self.cursor + height
end

function Engine:Section(title, count)
    return self:Add("section", title, count)
end

function Engine:SectionToggle(title, count, open, onToggle)
    return self:Add("section", title, count, open, onToggle)
end

function Engine:SectionLink(title, linkText, onLink, linkArg)
    return self:Add("section", title, nil, nil, nil, linkText, onLink, linkArg)
end

function Engine:Note(text)
    return self:Add("note", text)
end

-------------------------------------------------------------------------------
--  Cards and their grid
-------------------------------------------------------------------------------
-- A card at x, width w, from the cursor; the rows added after go inside it. Its edge is
-- reset: a card last used for a picked one has the accent's.
function Engine:OpenCard(x, w)
    self.left, self.width = x, w
    local card = self:Acquire("card")
    card:SetFrameLevel(self:GetFrameLevel())
    card.edge:SetColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
    card.note:Hide()
    self.left, self.width = x + CARD_PAD, w - CARD_PAD * 2
    return card
end

-- Ends the card opened at top: returns it and its height.
function Engine:CloseCard(card, top)
    self:Space(CARD_BOTTOM)
    self.left, self.width = 0, self:GetWidth()
    local height = self.cursor - top
    card:SetHeight(height)
    return card, height
end

-- How many cards fit across this width, up to MAX_COLUMNS and at least one, and each one's
-- width.
function View.Columns(width)
    local columns = math.max(1, math.min(MAX_COLUMNS, math.floor((width + CARD_GAP) / (CARD_MIN_W + CARD_GAP))))
    return columns, math.floor((width - CARD_GAP * (columns - 1)) / columns)
end
local Columns = View.Columns

-- Gathered entries are drawn by DrawGrid as the mixin's DrawCard(entry, a, b, c, x, w) ->
-- card, height; the cards in a row share the tallest one's height.
function Engine:Gather(entry, a, b, c)
    local grid = self.grid
    local n = grid.n + 1
    grid.n = n
    grid.entry[n], grid.a[n], grid.b[n], grid.c[n] = entry, a, b, c
end

function Engine:DrawGrid()
    local grid, cards = self.grid, self.rowCards
    local columns, w = Columns(self:GetWidth())
    local i = 1
    while i <= grid.n do
        local top, height = self.cursor, 0
        local last = math.min(i + columns - 1, grid.n)
        for k = i, last do
            self.cursor = top
            local card, cardHeight = self:DrawCard(grid.entry[k], grid.a[k], grid.b[k], grid.c[k],
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
--  A draw: Clear, the rows, Fit
-------------------------------------------------------------------------------
-- The redraw reuses the row the tooltip belongs to for something else.
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

function Engine:Clear()
    self.cursor, self.left, self.width = 0, 0, self:GetWidth()
    self.waiting = false
    wipe(self.waitingFor)
    CloseOwnTooltip(self)
    for _, pool in pairs(self.pools) do
        for i = 1, pool.used do pool[i]:Hide() end
        pool.used = 0
    end
end

-- As tall as what it drew, listening for events (a list of names) and the item names it
-- waits on.
function Engine:Fit(events)
    self:SetHeight(math.max(self.cursor, 1))
    self:UnregisterAllEvents()
    for i = 1, #events do self:RegisterEvent(events[i]) end
    if self.waiting then self:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
end

function Engine:QueueFlush()
    if self.flushQueued then return end
    self.flushQueued = true
    C_Timer.After(REDRAW_DELAY, self.flushFn)
end

function Engine:QueueRedraw()
    self.dirty = true
    self:QueueFlush()
end

function Engine:Flush()
    self.flushQueued, self.dirty = false, false
    if self:IsVisible() then self:Redraw() end
end

function Engine:OnEvent(event, arg, success)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not self.waitingFor[arg] then return end
        if success == false then
            Refuse(arg)
            self.waitingFor[arg] = nil
            return
        end
    end
    self:QueueRedraw()
end

function Engine:OnHide()
    self:UnregisterAllEvents()
    self.dirty = false
end

---@param kinds table the module's kinds (View.NewKinds())
---@param mixin table its drawing
function View.New(parent, kinds, mixin)
    local view = CreateFrame("Frame", nil, parent)
    Mixin(view, Engine, mixin)
    view.kinds, view.pools = kinds, {}
    for kind in pairs(Shared.Kinds) do view.pools[kind] = { used = 0 } end
    for kind in pairs(kinds) do view.pools[kind] = { used = 0 } end
    view.waitingFor = {}
    view.grid = { n = 0, entry = {}, a = {}, b = {}, c = {} }
    view.rowCards = {}
    view.redrawFn = function() view:Redraw() end
    view.flushFn = function() view:Flush() end
    view:SetScript("OnEvent", view.OnEvent)
    view:SetScript("OnHide", view.OnHide)
    return view
end
