-- List.lua: My Macros' list in Naowh's Forge: your account and character macros, searchable, each with its first command, its problems and whether it is open with unsaved changes.
local ns = _G.NaowhForever
local T = ns.THEME

local M = ns.Macros
local St = M.Style
local Store = M.Store
local Commands = M.Commands
local Text = M.Text
local P = M.Parts
local F = M.Forge

local PAD, ROW_ICON, LIST_W, CODE_FONT = St.PAD, St.ROW_ICON, St.LIST_W, St.CODE_FONT
local SECTION_H, WARNING, ERROR = St.SECTION_H, St.WARNING_RGB, St.ERROR_RGB
local SMALL_SIZE, TAG_SIZE = St.SMALL_SIZE, St.TAG_SIZE
local ROW_H = 42
local TEXT_GAP, NAME_DROP, LINE_RISE = St.ICON_TEXT_GAP, 2, 2
local DOT, DOT_GAP, DOT_ROOM = 6, 6, 40
local SECTION_GAP = 4
local UNSAVED = " *"

local TEXT_ACCOUNT, TEXT_CHARACTER = ns.L("Account"), ns.L("This Character")
local TEXT_NO_MATCH = ns.L("No macro matches")

local GROUPS = {
    { title = TEXT_ACCOUNT, rows = {}, shown = {} },
    { title = TEXT_CHARACTER, rows = {}, shown = {} },
}

local worstCache = {}

local function DragRow(row)
    if not InCombatLockdown() then PickupMacro(row.macro.index) end
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
    for _, line in ipairs(Text.Lines(body)) do
        if line:sub(1, 1) == "/" then return line end
    end
    return body:match("^([^\n]*)") or ""
end

local function Worst(body)
    local cached = worstCache[body]
    if cached ~= nil then return cached or nil end
    local worst = false
    for _, issue in ipairs(Text.Check(body, Commands.Known())) do
        if issue.kind == "error" then worst = ERROR break end
        worst = WARNING
    end
    worstCache[body] = worst
    return worst or nil
end

local function Collect()
    for _, g in ipairs(GROUPS) do wipe(g.rows) end
    for _, m in ipairs(Store.GameMacros()) do
        local g = m.account and GROUPS[1] or GROUPS[2]
        g.rows[#g.rows + 1] = m
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

local function PaintRow(r, m, i, current)
    r.macro = m
    local open = current ~= nil and m.index == current
    local draft = F.draft
    local unsaved = open and draft and (draft.body ~= draft.saved or draft.name ~= draft.savedName)
    local body = open and draft.body or m.body
    r.icon:SetTexture(Store.ShownIcon(m.index, m.icon, m.body))
    r.name:SetText((open and draft.name or m.name) .. (unsaved and ns.Color("accent", UNSAVED) or ""))
    r.line:SetText(FirstCommand(body))
    local worst = Worst(body)
    r.dot:SetShown(worst ~= nil)
    r.dot:ClearAllPoints()
    r.dot:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), LIST_W - 2 * PAD - ROW_ICON - DOT_ROOM)
        + DOT_GAP, 0)
    if worst then r.dot:SetColorTexture(worst.r, worst.g, worst.b, 1) end
    r.stripe:SetShown(i % 2 == 0)
    P.Pick(r, open)
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
    Collect()
    local current = F.Current()
    local y, any = 0, false
    for _, g in ipairs(GROUPS) do
        local shown = Matching(g, query)
        if #shown > 0 or query == "" then
            any = true
            local h = view.sections.Take()
            Place(h, view.body, y)
            P.SetSection(h, g.title, #shown)
            y = y - SECTION_H - SECTION_GAP
            for i, m in ipairs(shown) do
                local r = view.rows.Take()
                Place(r, view.body, y)
                PaintRow(r, m, i, current)
                y = y - ROW_H
            end
        end
    end
    view.empty:SetShown(not any)
    view.empty:SetText(TEXT_NO_MATCH)
    view.body:SetHeight(math.max(1, -y))
end

function F.DrawListMarks()
    if F.window and F.window.list and F.tab == "mine" then F.DrawList() end
end
