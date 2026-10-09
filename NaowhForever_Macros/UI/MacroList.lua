-- MacroList.lua: My Macros' list in Naowh's Forge: your account and character macros and your pack's, searchable.
local ns = _G.NaowhForever
local T = ns.THEME

local M = ns.Macros
local St = M.Style
local Store = M.Store
local P = M.Parts
local F = M.Forge
local Text = ns.MacroText

local PAD, ROW_ICON, LIST_W, CODE_FONT = St.PAD, St.ROW_ICON, St.LIST_W, St.CODE_FONT
local SECTION_H, WARNING, ERROR = St.SECTION_H, St.WARNING_RGB, St.ERROR_RGB
local SMALL_SIZE, TAG_SIZE = St.SMALL_SIZE, St.TAG_SIZE
local ROW_H = 42
local TEXT_GAP, NAME_DROP, LINE_RISE = St.ICON_TEXT_GAP, 2, 2
local DOT, DOT_GAP, DOT_ROOM = 6, 6, 40
local SECTION_GAP = 4
local PACK_TAG = "  " .. St.GOLD_CODE .. "PACK|r"
local PACK_TITLE = "From Your Pack"

local GROUPS = {
    { title = "Account", rows = {}, shown = {} },
    { title = "This Character", rows = {}, shown = {} },
    { title = PACK_TITLE, rows = {}, shown = {}, note = "Your profile pack" },
}

local function DragRow(row)
    if row.macro.index and not InCombatLockdown() then PickupMacro(row.macro.index) end
end

local function RowClick(row)
    F.Open(row.macro)
    F.Render()
end

local function NewMacroRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:RegisterForDrag("LeftButton")
    P.ListRow(r)
    r.icon = P.Icon(r, ROW_ICON)
    r.icon.edge:SetPoint("LEFT", PAD, 0)
    r.name = P.Text(r)
    r.name:SetPoint("TOPLEFT", r.icon.edge, "TOPRIGHT", TEXT_GAP, -NAME_DROP)
    r.name:SetPoint("RIGHT", -PAD, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.line = P.Text(r, SMALL_SIZE, T.muted)
    r.line:SetFont(CODE_FONT, TAG_SIZE, "")
    r.line:SetPoint("BOTTOMLEFT", r.icon.edge, "BOTTOMRIGHT", TEXT_GAP, LINE_RISE)
    r.line:SetPoint("RIGHT", -PAD, 0)
    r.line:SetJustifyH("LEFT")
    r.line:SetWordWrap(false)
    r.dot = ns.Solid(r, "OVERLAY", ERROR, 1)
    r.dot:SetSize(DOT, DOT)
    r:SetScript("OnDragStart", DragRow)
    r:SetScript("OnClick", RowClick)
    return r
end

local function FirstCommand(body)
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if line:sub(1, 1) == "/" then return line end
    end
    return body:match("^([^\n]*)") or ""
end

local function Worst(body, known)
    local worst
    for _, issue in ipairs(Text.Check(body, known)) do
        if issue.kind == "error" then return ERROR end
        worst = WARNING
    end
    return worst
end

local function Collect()
    for _, g in ipairs(GROUPS) do wipe(g.rows) end
    for _, m in ipairs(Store.GameMacros()) do
        local g = m.account and GROUPS[1] or GROUPS[2]
        g.rows[#g.rows + 1] = m
    end
    local _, class = UnitClass("player")
    local pack = GROUPS[3].rows
    for _, entry in ipairs(Store.PackMacros(class)) do
        if type(entry.name) == "string" and type(entry.body) == "string" then
            pack[#pack + 1] = { name = entry.name, body = entry.body, icon = ns.MacroEntryIcon(entry), source = "pack" }
        end
    end
end

local function Matching(g, query)
    local shown = g.shown
    wipe(shown)
    for _, m in ipairs(g.rows) do
        if query == "" or (m.name .. "\n" .. m.body):lower():find(query, 1, true) then shown[#shown + 1] = m end
    end
    return shown
end

local function IsPicked(m, current)
    local draft = F.draft
    if draft == nil then return false end
    return (m.index and m.index == current) or (not m.index and draft.source == "pack" and draft.name == m.name)
end

local function PaintRow(r, m, i, known, current)
    r.macro = m
    r.icon:SetTexture(Store.ShownIcon(m.index, m.icon, m.body))
    r.name:SetText(m.name .. (m.source == "pack" and PACK_TAG or ""))
    r.line:SetText(FirstCommand(m.body))
    local worst = Worst(m.body, known)
    r.dot:SetShown(worst ~= nil)
    r.dot:ClearAllPoints()
    r.dot:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), LIST_W - 2 * PAD - ROW_ICON - DOT_ROOM)
        + DOT_GAP, 0)
    if worst then r.dot:SetColorTexture(worst.r, worst.g, worst.b, 1) end
    r.stripe:SetShown(i % 2 == 0)
    P.Pick(r, IsPicked(m, current) and true or false)
end

local function Place(frame, body, y)
    frame:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    frame:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
end

F.NewMacroRow = NewMacroRow

function F.DrawList()
    local view = F.window.list
    view.rows.Release()
    view.sections.Release()
    local query = strtrim(F.window.search:GetText() or ""):lower()
    local known = ns.MacroKnownCommands()
    Collect()
    local current = F.Current()
    local y = 0
    for _, g in ipairs(GROUPS) do
        local shown = Matching(g, query)
        if #shown > 0 or (query == "" and g.title ~= PACK_TITLE) then
            local h = view.sections.Take()
            Place(h, view.body, y)
            P.SetSection(h, g.title, #shown, g.note)
            y = y - SECTION_H - SECTION_GAP
            for i, m in ipairs(shown) do
                local r = view.rows.Take()
                Place(r, view.body, y)
                PaintRow(r, m, i, known, current)
                y = y - ROW_H
            end
        end
    end
    view.body:SetHeight(math.max(1, -y))
end
