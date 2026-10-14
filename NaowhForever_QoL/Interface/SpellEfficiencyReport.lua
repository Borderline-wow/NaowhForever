-- SpellEfficiencyReport.lua: the Mana Efficiency window (/nf efficiency): every rank of your mana spells with its numbers, the best rank starred.
local ns = _G.NaowhForever

local T = ns.THEME
local Shared = ns.Shared
local Parts, St, View = Shared.Parts, Shared.Style, Shared.View
local S = ns.QoLSettings

local GetSpellName = C_Spell.GetSpellName
local GetSpellSubtext = C_Spell.GetSpellSubtext
local IsSpellKnown = C_SpellBook.IsSpellKnown

local PAGE = "QoL/Interface"
local WIDTH, HEIGHT = 560, 560
local HEADER, PAD, FOOTER, SCROLLBAR = St.WINDOW_HEADER, St.WINDOW_PAD, St.WINDOW_FOOTER, St.SCROLLBAR
local SEARCH_H, INSET = St.SEARCH_H, St.CONTENT_INSET
local TEXT_SIZE, SMALL_SIZE, HOVER = St.TEXT_SIZE, St.SMALL_SIZE, St.HOVER
local CARD_INSET = 6
local SEARCH_DROP = 4
local SCROLL_GAP = 4
local VIEW_SPARE = 8
local VIEW_W = WIDTH - INSET - SCROLLBAR - PAD - VIEW_SPARE
local HEAD_H = 20
local ROW_H = 20
local COLUMN_W = 72
local CELL_GAP = 6
local STAR, STAR_ROOM = 12, 18
local HEAL, DAMAGE = 1, 0
local STYLE_SHORT = "short"
local EVENTS = { "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "SPELL_DATA_LOAD_RESULT" }
local COLUMNS = { "mana", "amount", "perMana", "perSecond", "perManaSecond" }
local SHOWN_BY = { perMana = "spellEfficiencyPerMana", perSecond = "spellEfficiencyPerSecond",
    perManaSecond = "spellEfficiencyPerManaSecond" }
local WHOLE = { mana = true, amount = true, perSecond = true }
local RATES = { perMana = 1, perSecond = 2, perManaSecond = 3 }
local SHORT_LABELS = {
    [HEAL] = { "HPM", "HPS", "HPM/s" },
    [DAMAGE] = { "DPM", "DPS", "DPM/s" },
    both = { "H/DPM", "H/DPS", "H/DPM/s" },
}

local TEXT_TITLE = ns.L("Mana Efficiency")
local TEXT_SUBTITLE = ns.L("Every rank of your mana spells. The star marks the most per mana.")
local TEXT_SEARCH = ns.L("Search")
local TEXT_EMPTY = ns.L("None of your spells has Mana Efficiency numbers.")
local TEXT_NO_MATCH = ns.L("No spell matches your search.")
local TEXT_LEVEL = ns.L("Level %d")
local TEXT_NONE = "-"
local TEXT_TARGET = ns.L("/ target")
local TEXT_KINDS = { [HEAL] = ns.L("healing"), [DAMAGE] = ns.L("damage") }
local TEXT_NOTE_GAP = "  "
local TEXT_SORT = ns.L("Click to sort by this column, again to reverse it.")
local LABELS = { rank = ns.L("Rank"), mana = ns.L("Mana"), amount = ns.L("Amount"), perMana = ns.L("Per Mana"),
    perSecond = ns.L("Per Second"), perManaSecond = ns.L("Per Mana/s") }

local window, view, head
local filter = ""
local sortKey, descending = "rank", false
local byName, names, lowered
local columns = {}
local results = {}
local requested = {}
local entries, groups, kindGroups, ranksSeen = {}, {}, {}, {}
local entryCount, groupCount = 0, 0
local hasKind = {}

local function BuildIndex()
    byName, names, lowered = {}, {}, {}
    for id in pairs(ns.SpellEfficiencyData) do
        local name = GetSpellName(id)
        if name then
            if not byName[name] then
                byName[name] = {}
                names[#names + 1] = name
                lowered[name] = name:lower()
            end
            local ids = byName[name]
            ids[#ids + 1] = id
        end
    end
    table.sort(names)
    for _, ids in pairs(byName) do table.sort(ids) end
end

local function RankText(id, level)
    local text = GetSpellSubtext(id)
    if text and text ~= "" then return text end
    if not requested[id] then
        requested[id] = true
        C_Spell.RequestLoadSpellData(id)
    end
    return nil, TEXT_LEVEL:format(level)
end

local function Value(entry)
    if sortKey == "rank" then return entry.result.level end
    if sortKey == "mana" then return entry.result.mana end
    return entry.part[sortKey]
end

local function ByColumn(a, b)
    local va, vb = Value(a), Value(b)
    if va == vb then return a.id < b.id end
    if va == nil then return false end
    if vb == nil then return true end
    if descending then return va > vb end
    return va < vb
end

local function ByName(a, b)
    if a.name ~= b.name then return lowered[a.name] < lowered[b.name] end
    return a.kind > b.kind
end

local function Group(name, kind)
    local group = kindGroups[kind]
    if group then return group end
    groupCount = groupCount + 1
    group = groups[groupCount] or { entries = {} }
    groups[groupCount] = group
    group.name, group.kind, group.best, group.area = name, kind, nil, false
    wipe(group.entries)
    kindGroups[kind] = group
    return group
end

local function AddEntry(name, id, result, known, rank)
    for i = 1, result.count do
        local part = result[i]
        entryCount = entryCount + 1
        local entry = entries[entryCount] or {}
        entries[entryCount] = entry
        entry.id, entry.result, entry.part, entry.known, entry.rank = id, result, part, known, rank
        local group = Group(name, part.kind)
        group.entries[#group.entries + 1] = entry
        group.area = result.area
        hasKind[part.kind] = true
        if known and (not group.best or part.perMana > group.best.part.perMana) then group.best = entry end
    end
end

local function AddSpell(name)
    wipe(kindGroups)
    wipe(ranksSeen)
    local top
    for _, id in ipairs(byName[name]) do
        if IsSpellKnown(id) then
            results[id] = ns.SpellEfficiencyOf(id, results[id])
            local result = results[id]
            if result then
                local rank, fallback = RankText(id, result.level)
                if rank then ranksSeen[rank] = true end
                AddEntry(name, id, result, true, rank or fallback)
                if not top or result.level > top then top = result.level end
            end
        end
    end
    if not top then return end
    for _, id in ipairs(byName[name]) do
        if not IsSpellKnown(id) then
            results[id] = ns.SpellEfficiencyOf(id, results[id])
            local result = results[id]
            local rank = result and result.level > top and RankText(id, result.level)
            if rank and not ranksSeen[rank] then
                ranksSeen[rank] = true
                AddEntry(name, id, result, false, rank)
            end
        end
    end
end

local function Collect()
    if not byName then BuildIndex() end
    entryCount, groupCount = 0, 0
    wipe(hasKind)
    for _, name in ipairs(names) do
        if filter == "" or lowered[name]:find(filter, 1, true) then AddSpell(name) end
    end
    for i = groupCount + 1, #groups do groups[i] = nil end
    table.sort(groups, ByName)
    for i = 1, groupCount do table.sort(groups[i].entries, ByColumn) end
end

local function Label(key)
    local rate = RATES[key]
    if not rate or S.Get("spellEfficiencyStyle") ~= STYLE_SHORT then return LABELS[key] end
    local labels = hasKind[HEAL] and hasKind[DAMAGE] and SHORT_LABELS.both or SHORT_LABELS[hasKind[HEAL] and HEAL or DAMAGE]
    return labels[rate]
end

local function Layout()
    wipe(columns)
    for _, key in ipairs(COLUMNS) do
        if not SHOWN_BY[key] or S.Get(SHOWN_BY[key]) then columns[#columns + 1] = key end
    end
end

local function Place(cell, index)
    cell:ClearAllPoints()
    cell:SetPoint("RIGHT", cell:GetParent(), "RIGHT", -(#columns - index) * COLUMN_W, 0)
end

local function Note(group)
    local note = group.area and TEXT_TARGET or nil
    local other = group.kind == HEAL and DAMAGE or HEAL
    for i = 1, groupCount do
        local g = groups[i]
        if g ~= group and g.name == group.name and g.kind == other then
            local kind = TEXT_KINDS[group.kind]
            return note and (kind .. TEXT_NOTE_GAP .. note) or kind
        end
    end
    return note
end

local function SortClicked(button)
    if sortKey == button.key then
        descending = not descending
    else
        sortKey, descending = button.key, button.key ~= "rank"
    end
    view:Redraw()
end

local function HeadEnter(button)
    button.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
    Parts.TipLines(button, "ANCHOR_TOP", LABELS[button.key], TEXT_SORT)
end

local function PaintHeadButton(button)
    local color = sortKey == button.key and T.accent or T.muted
    button.text:SetTextColor(color.r, color.g, color.b)
end

local function HeadLeave(button)
    PaintHeadButton(button)
    GameTooltip:Hide()
end

local function HeadButton(key, justify)
    local button = CreateFrame("Button", nil, head)
    button:SetSize(COLUMN_W - CELL_GAP, HEAD_H)
    button.key = key
    button.text = ns.Font(button, SMALL_SIZE, nil, T.muted)
    button.text:SetAllPoints()
    button.text:SetJustifyH(justify)
    button:SetScript("OnClick", SortClicked)
    button:SetScript("OnEnter", HeadEnter)
    button:SetScript("OnLeave", HeadLeave)
    head.buttons[key] = button
    return button
end

local function PaintHead()
    head.buttons.rank.text:SetText(LABELS.rank)
    PaintHeadButton(head.buttons.rank)
    for _, key in ipairs(COLUMNS) do head.buttons[key]:Hide() end
    for i, key in ipairs(columns) do
        local button = head.buttons[key]
        Place(button, i)
        button.text:SetText(Label(key))
        PaintHeadButton(button)
        button:Show()
    end
end

local function RankEnter(row)
    row.hover:Show()
    if not Parts.Tip(row, "ANCHOR_RIGHT") then return end
    GameTooltip:SetSpellByID(row.spellID)
    GameTooltip:Show()
end

local function RankLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local function NewRank(parent)
    local row = CreateFrame("Button", nil, parent)
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, HOVER)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.star = row:CreateTexture(nil, "ARTWORK")
    row.star:SetTexture(St.STAR)
    row.star:SetSize(STAR, STAR)
    row.star:SetPoint("LEFT")
    row.star:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
    row.rank = ns.Font(row, TEXT_SIZE)
    row.rank:SetPoint("LEFT", STAR_ROOM, 0)
    row.rank:SetJustifyH("LEFT")
    row.cells = {}
    for i = 1, #COLUMNS do
        local cell = ns.Font(row, TEXT_SIZE)
        cell:SetWidth(COLUMN_W - CELL_GAP)
        cell:SetJustifyH("RIGHT")
        row.cells[i] = cell
    end
    row:SetScript("OnEnter", RankEnter)
    row:SetScript("OnLeave", RankLeave)
    return row
end

local function CellText(entry, key)
    local value = key == "mana" and entry.result.mana or entry.part[key]
    if not value then return TEXT_NONE end
    return ns.SpellEfficiencyNumber(value, WHOLE[key])
end

local function SetRank(row, entry, best)
    row.spellID = entry.id
    row.hover:Hide()
    row.star:SetShown(best)
    local color = entry.known and T.fg or T.muted
    row.rank:SetText(entry.rank)
    row.rank:SetTextColor(color.r, color.g, color.b)
    for i, cell in ipairs(row.cells) do
        local key = columns[i]
        cell:SetShown(key ~= nil)
        if key then
            Place(cell, i)
            cell:SetText(CellText(entry, key))
            cell:SetTextColor(color.r, color.g, color.b)
        end
    end
    return ROW_H
end

local Draw = {}

function Draw:Redraw()
    self:Clear()
    Layout()
    Collect()
    PaintHead()
    for i = 1, groupCount do
        local group = groups[i]
        self:Section(group.name, Note(group))
        for _, entry in ipairs(group.entries) do self:Add("rank", entry, entry == group.best) end
    end
    if groupCount == 0 then self:Note(filter == "" and TEXT_EMPTY or TEXT_NO_MATCH) end
    self:Fit(EVENTS)
end

local function OnSearch(text)
    filter = (text or ""):lower()
    if view then view:Redraw() end
end

local function OnSettingChanged(key)
    if window:IsShown() and type(key) == "string" and key:find("^spellEfficiency") then view:QueueRedraw() end
end

local function BuildHead(top)
    head = CreateFrame("Frame", nil, window)
    head:SetPoint("TOPLEFT", INSET, -top)
    head:SetSize(VIEW_W, HEAD_H)
    head.buttons = {}
    HeadButton("rank", "LEFT"):SetPoint("LEFT", STAR_ROOM, 0)
    for _, key in ipairs(COLUMNS) do HeadButton(key, "RIGHT") end
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "spellEfficiencyWindow")
    window.backdrop:Card(CARD_INSET, HEADER + CARD_INSET, CARD_INSET, FOOTER + CARD_INSET)
    Parts.TitleBar(window, TEXT_TITLE, TEXT_SUBTITLE, PAGE)
    Parts.FooterBrand(window, PAGE)
    local top = HEADER + PAD + SEARCH_DROP
    local search = Parts.SearchBox(window, TEXT_SEARCH, OnSearch)
    search:SetPoint("TOPLEFT", INSET, -top)
    search:SetPoint("TOPRIGHT", -INSET, -top)
    search:SetHeight(SEARCH_H)
    top = top + SEARCH_H + PAD
    BuildHead(top)
    local scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", INSET, -(top + HEAD_H))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - SCROLL_GAP, FOOTER + PAD)
    local kinds = View.NewKinds()
    kinds.rank = { New = NewRank, Set = SetRank }
    view = View.New(scroll, kinds, Draw)
    view:SetWidth(VIEW_W)
    scroll:SetScrollChild(view)
    hooksecurefunc(S, "Set", OnSettingChanged)
end

function ns.OpenSpellEfficiencyReport()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    window.backdrop:Paint(1)
    view:Redraw()
end

function ns.ToggleSpellEfficiencyReport()
    if window and window:IsShown() then window:Hide() else ns.OpenSpellEfficiencyReport() end
end

ns.RegisterMinimapFeature({
    id = "SpellEfficiency", name = "Mana Efficiency", icon = "Interface\\Icons\\Spell_Holy_LesserHeal",
    open = ns.ToggleSpellEfficiencyReport, tooltip = "Click to open or close Mana Efficiency.",
})
