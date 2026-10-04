-------------------------------------------------------------------------------
--  Settings.lua -- every settings page, declared once (ns.Shared.Settings): pages, cards
--  and their settings, what was changed, reset, and the search's index. Each module declares
--  its cards next to its code; Page.lua draws them in the options window (/nf).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Shared = ns.Shared

local Settings = {}
Shared.Settings = Settings

local pages = {}
Settings.pages = pages

local KINDS = { "toggle", "slider", "choice", "colour", "font", "sound", "text", "button", "binding" }

local Page = {}
Page.__index = Page

function Settings.Page(key, store)
    local page = pages[key]
    if not page then
        page = setmetatable({ key = key, items = {}, cards = {} }, Page)
        pages[key] = page
    end
    page.store = store or page.store
    return page
end

function Settings.Group(title)
    return { group = title }
end

local function Normalise(row, card)
    row.card = card
    if row.group then
        row.kind = "group"
        return row
    end
    for _, kind in ipairs(KINDS) do
        if row[kind] ~= nil then
            row.kind = kind
            break
        end
    end
    assert(row.kind, "Settings: a row without a kind on " .. card.uid .. ": " .. tostring(row.label))
    row.store = row.store or card.store
    local store, key = row.store, row.key
    if key and store and not row.get then
        if row.kind == "colour" then
            row.get = function()
                local c = store.Get(key)
                if type(c) ~= "table" then return 1, 1, 1, 1 end
                return c.r, c.g, c.b, c.a
            end
            row.set = function(r, g, b, a)
                store.Set(key, { r = r, g = g, b = b, a = row.colour == "alpha" and a or nil })
            end
        else
            row.get = function() return store.Get(key) end
            row.set = function(v) store.Set(key, v) end
        end
    end
    local scale = row.scale
    if scale and row.get then
        local get, set = row.get, row.set
        row.get = function()
            local v = get()
            return v and math.floor(v / scale + 0.5) or nil
        end
        row.set = function(v) set(v * scale) end
    end
    return row
end

local function Switch(card)
    local switch = card.switch
    if type(switch) == "string" then
        local store = card.store
        card.switchGet = function() return store.Get(switch) end
        card.switchSet = function(v) store.Set(switch, v and true or false) end
    elseif type(switch) == "table" then
        card.switchGet, card.switchSet = switch.get, switch.set
    end
end

local function Before(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.seq < b.seq
end

local function Insert(page, item)
    item.seq = #page.items + 1
    page.items[#page.items + 1] = item
    table.sort(page.items, Before)
end

function Settings.Rows(card)
    if card.rowsFn then
        card.rows = card.rowsFn()
        for _, row in ipairs(card.rows) do
            if row.card ~= card then Normalise(row, card) end
        end
    end
    return card.rows
end

function Page:Card(spec)
    assert(spec.id and spec.name, "Settings: a card needs an id and a name")
    assert(not self.cards[spec.id], "Settings: two cards named " .. spec.id .. " on " .. self.key)
    spec.page = self
    spec.uid = self.key .. ":" .. spec.id
    spec.store = spec.store or self.store
    spec.order = spec.order or 100
    if type(spec.rows) == "function" then
        spec.rowsFn, spec.rows = spec.rows, {}
    end
    spec.rows = spec.rows or {}
    Switch(spec)
    for _, row in ipairs(spec.rows) do Normalise(row, spec) end
    self.cards[spec.id] = spec
    Insert(self, spec)
    return spec
end

function Page:Window(spec)
    spec.window = true
    spec.order = spec.order or 0
    Insert(self, spec)
    return spec
end

function Page:Info(spec)
    assert(spec.id and spec.name, "Settings: an info card needs an id and a name")
    spec.info = true
    spec.page = self
    spec.uid = self.key .. ":" .. spec.id
    spec.order = spec.order or #self.items + 1
    spec.rows = spec.lines or {}
    self.cards[spec.id] = spec
    Insert(self, spec)
    return spec
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if type(v) == "number" and type(b[k]) == "number" then
            if math.abs(v - b[k]) > 0.002 then return false end
        elseif type(v) == "table" then
            if not Same(v, b[k]) then return false end
        elseif b[k] ~= v then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = Copy(v) end
    return out
end

function Settings.Changed(row)
    local store, key = row.store, row.key
    if not (key and store and store.Raw) then return false end
    local raw = store.Raw(key)
    if raw == nil then return false end
    return not Same(raw, store.Default(key))
end

function Settings.ChangedCount(card)
    local n = 0
    for _, row in ipairs(card.rows) do
        if row.kind ~= "group" and Settings.Changed(row) then n = n + 1 end
    end
    return n
end

function Settings.ResetRow(row)
    local store, key = row.store, row.key
    if key and store and store.Default and Settings.Changed(row) then
        store.Set(key, Copy(store.Default(key)))
    end
end

function Settings.Reset(card)
    for _, row in ipairs(card.rows) do Settings.ResetRow(row) end
end

local function LabelOf(card, key)
    for _, row in ipairs(card.rows) do
        if row.key == key then return row.label end
    end
end

function Settings.Off(row)
    local card = row.card
    if card.switchGet and not row.always and not card.switchGet() then return true end
    local needs = row.needs
    if not needs then return false end
    if type(needs) == "function" then
        if needs() then return false end
        return true, row.why
    end
    local store = row.store
    if type(needs) == "string" then
        if store.Get(needs) then return false end
        local label = LabelOf(card, needs)
        return true, row.why or (label and ("Needs " .. label))
    end
    for i = 1, #needs do
        if not store.Get(needs[i]) then
            local label = LabelOf(card, needs[i])
            return true, row.why or (label and ("Needs " .. label))
        end
    end
    return false
end

local open = {}

function Settings.IsOpen(card)
    local searched = ns.UI.searchOpen
    if searched and searched[card.uid] then return true end
    local state = open[card.uid]
    if state ~= nil then return state end
    if card.info then return card.open == true end
    local cards, first = 0, nil
    for _, item in ipairs(card.page.items) do
        if not item.window then
            cards = cards + 1
            first = first or item
        end
    end
    return cards == 1 or (first == card and card.studio ~= nil)
end

function Settings.SetOpen(card, on)
    open[card.uid] = on and true or false
end

function Settings.Index(pageKey, add)
    local page = pages[pageKey]
    if not page then return false end
    for _, item in ipairs(page.items) do
        if not (item.window or item.info) then
            add(item.uid, item.name, item.help)
            local group
            for _, row in ipairs(Settings.Rows(item)) do
                if row.kind == "group" then
                    group = row.group
                elseif row.label then
                    add(item.uid, row.label, row.help, item.name, group)
                end
            end
        end
    end
    return true
end

function Settings.CardOf(uid)
    local pageKey, id = uid:match("^(.*):([^:]+)$")
    local page = pageKey and pages[pageKey]
    return page and page.cards[id]
end
