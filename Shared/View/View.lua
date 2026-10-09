-- View.lua: the row engine a module draws a page with (ns.Shared.View): pooled rows of kinds, cards and their grid, one redraw per burst.
local ns = _G.NaowhForever
local Shared = ns.Shared
local View = Shared.View
local St = Shared.Style

local Refuse = Shared.Items.Refuse

local CARD_PAD, CARD_GAP, CARD_BOTTOM = St.CARD_PAD, St.CARD_GAP, St.CARD_BOTTOM
local CARD_MIN_W, MAX_COLUMNS, BORDER_RGB = St.CARD_MIN_W, St.MAX_COLUMNS, St.BORDER_RGB
local REDRAW_DELAY = 0.15
local SCROLL_MARGIN = 40
local ITEM_INFO = "GET_ITEM_INFO_RECEIVED"

local Engine = {}

local function TurnOn(addon)
    ns.TurnOnModule(addon)
end

local function CardWidth(width, columns)
    return math.floor((width - CARD_GAP * (columns - 1)) / columns)
end

local function CloseOwnTooltip(view)
    local owner = GameTooltip:GetOwner()
    while owner do
        if owner == view then
            GameTooltip:Hide()
            return
        end
        if owner:IsForbidden() then return end
        owner = owner:GetParent()
    end
end

local function NewPools(view, kinds)
    view.pools = {}
    for kind in pairs(Shared.Kinds) do view.pools[kind] = { used = 0 } end
    for kind in pairs(kinds) do view.pools[kind] = { used = 0 } end
end

local function DrawGridRow(view, first, last, w)
    local grid, cards = view.grid, view.rowCards
    local top, height = view.cursor, 0
    for k = first, last do
        view.cursor = top
        local card, cardHeight = view:DrawCard(grid.entry[k], grid.a[k], grid.b[k], grid.c[k],
            (k - first) * (w + CARD_GAP), w)
        cards[k - first + 1] = card
        if cardHeight > height then height = cardHeight end
    end
    for k = 1, last - first + 1 do cards[k]:SetHeight(height) end
    view.cursor = top + height + CARD_GAP
end

function Engine:Acquire(kind)
    local pool = self.pools[kind]
    pool.used = pool.used + 1
    local row = pool[pool.used]
    if not row then
        row = self.kinds[kind].New(self)
        pool[pool.used] = row
    end
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

function Engine:Find(kind, test, arg)
    local pool = self.pools[kind]
    for i = 1, pool.used do
        if test(pool[i], arg) then return pool[i] end
    end
end

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

function Engine:NeedsModule(title, text, addon, linkText)
    self:SectionLink(title, linkText, TurnOn, addon)
    return self:Note(text)
end

function Engine:OpenCard(x, w)
    self.left, self.width = x, w
    local card = self:Acquire("card")
    card:SetFrameLevel(self:GetFrameLevel())
    card.edge:SetColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
    card.note:Hide()
    self.left, self.width = x + CARD_PAD, w - CARD_PAD * 2
    return card
end

function Engine:CloseCard(card, top)
    self:Space(CARD_BOTTOM)
    self.left, self.width = 0, self:GetWidth()
    local height = self.cursor - top
    card:SetHeight(height)
    return card, height
end

function Engine:Gather(entry, a, b, c)
    local grid = self.grid
    local n = grid.n + 1
    grid.n = n
    grid.entry[n], grid.a[n], grid.b[n], grid.c[n] = entry, a, b, c
end

function Engine:DrawGrid(most)
    local grid = self.grid
    local width = self:GetWidth()
    local columns, w = View.Columns(width)
    if most and columns > most then
        columns = most
        w = CardWidth(width, columns)
    end
    local i = 1
    while i <= grid.n do
        local last = math.min(i + columns - 1, grid.n)
        DrawGridRow(self, i, last, w)
        i = last + 1
    end
    grid.n = 0
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

function Engine:Fit(events)
    self:SetHeight(math.max(self.cursor, 1))
    self:UnregisterAllEvents()
    for i = 1, #events do self:RegisterEvent(events[i]) end
    if self.waiting then self:RegisterEvent(ITEM_INFO) end
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
    if event == ITEM_INFO then
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

View.Engine = Engine

function View.NewKinds()
    return setmetatable({}, { __index = Shared.Kinds })
end

function View.Columns(width)
    local columns = math.max(1, math.min(MAX_COLUMNS, math.floor((width + CARD_GAP) / (CARD_MIN_W + CARD_GAP))))
    return columns, CardWidth(width, columns)
end

function View.New(parent, kinds, mixin)
    local view = CreateFrame("Frame", nil, parent)
    Mixin(view, Engine, mixin)
    view.kinds = kinds
    NewPools(view, kinds)
    view.waitingFor = {}
    view.grid = { n = 0, entry = {}, a = {}, b = {}, c = {} }
    view.rowCards = {}
    view.redrawFn = function() view:Redraw() end
    view.flushFn = function() view:Flush() end
    view:SetScript("OnEvent", view.OnEvent)
    view:SetScript("OnHide", view.OnHide)
    return view
end
