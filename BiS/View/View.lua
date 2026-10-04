-------------------------------------------------------------------------------
--  View/View.lua -- draws a page of the BiS List (ns.BiS.View) on the shared engine: your
--  list as your progress, a filter, where to run next and a row per slot with its backups
--  opened under it; or one slot's picker: your picks, then the ranking for your spec, then
--  the dungeon drops your class can use. Its rows are View/Rows.lua's. Redraws when your
--  list, your gear or your bags change.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local L, R = B.Lists, B.Rankings
local Shared = ns.Shared
local Items = Shared.Items

local St = B.Style
local SECTION_SPACE = St.SECTION_SPACE

local View = { Kinds = Shared.View.NewKinds() }
B.View = View

local EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP" }

local GROUPS = {
    { title = "Armor", slots = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8 } },
    { title = "Jewelry", slots = { 11, 12, 13, 14 } },
    { title = "Weapons", slots = { 16, 17, 18 } },
}

-- What each filter keeps: every slot, the BiS you have yet to get, the ones to put on, and
-- what you wear that takes a better enchant.
local FILTERS = {
    all = function() return true end,
    get = function(_, bis) return bis ~= nil and not Items.Owned(bis) end,
    wear = function(slot, bis) return bis ~= nil and Items.Owned(bis) and not Items.Wearing(slot, bis) end,
    enchant = function(slot) return B.Enchants.ToDo(slot) end,
}

local NOTHING_LEFT = {
    get = "Every BiS on your list is yours.",
    wear = "Nothing to put on: you wear every BiS you have.",
    enchant = "Everything you wear has the best enchant for your level.",
}

-- "1 of 10 yours", made once each.
local yoursText = {}

local function Yours(have, total)
    local byTotal = yoursText[total]
    if not byTotal then
        byTotal = {}
        yoursText[total] = byTotal
    end
    local text = byTotal[have]
    if not text then
        text = ("%d of %d yours"):format(have, total)
        byTotal[have] = text
    end
    return text
end

---@class BisView: Frame
local ViewMixin = {}

-- What holds for the whole draw, read once.
function ViewMixin:Begin()
    self:Clear()
    self.playerLevel = UnitLevel("player")
    self.striped = false
end

-------------------------------------------------------------------------------
--  Your list
-------------------------------------------------------------------------------
-- How many slots each filter keeps, for its switch.
function ViewMixin:Count()
    local counts, slots = self.counts, self.list.slots
    for key in pairs(FILTERS) do counts[key] = 0 end
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        for key, keep in pairs(FILTERS) do
            if keep(slot, slots[slot]) then counts[key] = counts[key] + 1 end
        end
    end
end

-- A slot's row; opened, its backups under it.
function ViewMixin:DrawSlot(slot)
    local picks = B.Picks(self.list, slot, self.picks)
    local open = self.open[slot] == true and #picks > 1
    self.rowTops[slot] = self.cursor
    self.rows[slot] = self:Add("slotRow", slot, picks[1], #picks, open)
    if open then
        for rank = 2, #picks do self:Add("backup", slot, picks[rank], rank, #picks) end
    end
    if slot == 17 and picks[1] and B.OffHandIdle(self.list) then
        self:Note("Unused while your main hand's BiS is a two-hander.")
    end
end

function ViewMixin:DrawGroup(group, keep)
    local slots, shown, have, picked = self.list.slots, 0, 0, 0
    for _, slot in ipairs(group.slots) do
        local bis = slots[slot]
        if keep(slot, bis) then shown = shown + 1 end
        if bis then
            picked = picked + 1
            if Items.Owned(bis) then have = have + 1 end
        end
    end
    if shown == 0 then return 0 end
    self:Section(group.title, picked > 0 and Yours(have, picked) or nil)
    local n = 0
    for _, slot in ipairs(group.slots) do
        if keep(slot, slots[slot]) then
            n = n + 1
            self.striped = n % 2 == 1   -- every other row on a faint band, its backups with it
            self:DrawSlot(slot)
        end
    end
    self.striped = false
    self:Space(SECTION_SPACE)
    return shown
end

function ViewMixin:DrawList()
    self.page = "list"
    self:Begin()
    wipe(self.rows)
    self.list = L.List()
    self:Count()
    self.gains = B.Upgrades.Read(self.list)
    -- The biggest, for the gain bars' scale.
    local most = 0
    for _, gain in pairs(self.gains) do
        if gain > most then most = gain end
    end
    self.mostGain = most
    if self.summary then B.View.PaintSummary(self.summary, self.list, self.filter, self.counts) end
    local places = (self.filter == "all" or self.filter == "get") and R.RunNext(self.list, self.gains)
    if places and places[1] then
        self.mostPlaceGain = places[1].gain   -- the first makes you strongest
        self:Section("Run next")
        for i = 1, #places do self:Add("place", places[i]) end
        self:Space(SECTION_SPACE)
    end
    local keep, shown = FILTERS[self.filter], 0
    for _, group in ipairs(GROUPS) do shown = shown + self:DrawGroup(group, keep) end
    if shown == 0 then self:Note(NOTHING_LEFT[self.filter]) end
    self:Fit(EVENTS)
    self:Light(self.lit)
    if self.onDrawn then self.onDrawn() end
end

function ViewMixin:SetFilter(key)
    self.filter = key
    self:Redraw()
end

-- Opens or folds the slot's backups.
function ViewMixin:Toggle(slot)
    self.open[slot] = not self.open[slot] or nil
    self:Redraw()
end

-- The slot's row lit, as the paperdoll's slot under the mouse.
function ViewMixin:Light(slot)
    self.lit = slot
    for rowSlot, row in pairs(self.rows) do row.lit:SetShown(rowSlot == slot) end
end

-- Brings the slot's row into sight, when it is out of it.
function ViewMixin:ScrollTo(slot)
    local row, top = self.rows[slot], self.rowTops[slot]
    if not row then return end
    local scroll = self:GetParent()
    local y, height = scroll:GetVerticalScroll(), scroll:GetHeight()
    local bottom = top + row:GetHeight()
    if top >= y and bottom <= y + height then return end
    local target = bottom > y + height and bottom - height or top
    scroll:SetVerticalScroll(math.max(0, math.min(target, scroll:GetVerticalScrollRange())))
end

-------------------------------------------------------------------------------
--  A slot's picker
-------------------------------------------------------------------------------
local function ToggleDrops(view)
    view.allDrops = not view.allDrops
    view:Redraw()
end

-- numbered: the ranking's own order shows before each name.
function ViewMixin:DrawItems(slot, ids, mode, count, numbered)
    local picked = self.picked
    for i = 1, #ids do
        self.striped = i % 2 == 1
        self:Add("pick", slot, ids[i], picked[ids[i]], mode, count, numbered and i)
    end
    self.striped = false
end

function ViewMixin:DrawPicker(slot)
    self.page, self.slot = "picker", slot
    self:Begin()
    local picks = B.Picks(L.List(), slot, self.picks)
    local picked = wipe(self.picked)
    for rank = 1, #picks do picked[picks[rank]] = rank end
    self:Section("Your picks", #picks)
    self:DrawItems(slot, picks, "own", #picks)
    if #picks == 0 then self:Note("Nothing picked yet. Click an item below: the first is your BiS.") end
    self:Space(SECTION_SPACE)

    local spec = L.CurrentSpec()
    local ranked = R.Candidates(slot, spec)
    self:Section(spec and "Ranked for " .. spec.name or "Ranked", #ranked)
    self:DrawItems(slot, ranked, "add", nil, true)
    if #ranked == 0 then self:Note("Nothing ranked for this slot.") end
    self:Space(SECTION_SPACE)

    local all = self.allDrops
    local drops = R.DungeonDrops(slot, ranked, not all)
    self:SectionLink(all and "Dungeon drops" or "Dungeon drops near your level", all and "Near My Level" or "Show All",
        ToggleDrops, self)
    self:DrawItems(slot, drops, "add")
    if #drops == 0 then
        self:Note(all and "No dungeon drops for this slot that you can use."
            or "No dungeon drops for this slot within 10 levels of yours.")
    end
    self:Fit(EVENTS)
end

function ViewMixin:Redraw()
    if not self:IsVisible() then return end
    if self.page == "picker" then self:DrawPicker(self.slot) else self:DrawList() end
end

function View.New(parent)
    local view = Shared.View.New(parent, View.Kinds, ViewMixin)
    view.picks, view.picked, view.counts, view.open = {}, {}, {}, {}
    view.rows, view.rowTops, view.filter = {}, {}, "all"
    view.inset = St.STATUS_W   -- section titles line up with the rows' text
    B.OnListChange(view.redrawFn)
    ns.StatWeights.OnChange(view.redrawFn)
    return view
end
