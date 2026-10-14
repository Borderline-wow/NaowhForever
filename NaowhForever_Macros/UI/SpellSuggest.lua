-- SpellSuggest.lua: the spells you know, offered under a spell box in the Forge as you type: click one, or Enter for the lit one.
local ns = _G.NaowhForever
local T = ns.THEME

local M = ns.Macros
local St = M.Style
local P = M.Parts
local F = M.Forge

local BLACK, SMALL_SIZE, TEXT_SIZE = St.BORDER_RGB, St.SMALL_SIZE, St.TEXT_SIZE
local ROWS, ROW_H, ICON, ICON_X, TEXT_GAP = 10, 22, 16, 4, 6
local DROP, LEVEL, LIT = 2, 40, 0.18
local MIN_W = 220

local TEXT_NONE = ns.L("No spell you know matches.")

local popup, owner
local spells, dirty = {}, true
local shown = {}
local offset, lit = 0, 1

local function Collect()
    wipe(spells)
    local seen = {}
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.isGuild then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive
                    and item.name and not seen[item.name] then
                    seen[item.name] = true
                    spells[#spells + 1] = { name = item.name, lower = item.name:lower(), icon = item.iconID }
                end
            end
        end
    end
    table.sort(spells, function(a, b) return a.lower < b.lower end)
    dirty = false
end

local function Match(text)
    if dirty then Collect() end
    wipe(shown)
    local query = strtrim(text or ""):lower()
    for _, s in ipairs(spells) do
        if query == "" or s.lower:sub(1, #query) == query then shown[#shown + 1] = s end
    end
    if query == "" then return end
    for _, s in ipairs(spells) do
        if s.lower:sub(1, #query) ~= query and s.lower:find(query, 1, true) then shown[#shown + 1] = s end
    end
end

local function Draw()
    for i, row in ipairs(popup.rows) do
        local s = shown[offset + i]
        row.spell = s
        row:SetShown(s ~= nil)
        if s then
            row.icon:SetTexture(s.icon)
            row.text:SetText(s.name)
            row.fill:SetShown(offset + i == lit)
        end
    end
    local count = math.min(ROWS, math.max(1, #shown - offset))
    popup.none:SetShown(#shown == 0)
    popup:SetHeight(count * ROW_H + 2)
end

local function Close()
    if popup then popup:Hide() end
    owner = nil
end

local function Pick(s)
    local box = owner
    Close()
    box:SetText(s.name)
    if box.Commit then box:Commit() end
    box:ClearFocus()
end

local function RowClick(row)
    if row.spell and owner then Pick(row.spell) end
end

local function Wheel(_, delta)
    offset = math.max(0, math.min(math.max(0, #shown - ROWS), offset - delta))
    Draw()
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, popup)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", -1, 0)
    row.fill = ns.Solid(row, "BACKGROUND", T.accent, LIT)
    row.fill:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", ICON_X, 0)
    row.text = P.Text(row, TEXT_SIZE)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", TEXT_GAP, 0)
    row.text:SetPoint("RIGHT", -ICON_X, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", RowClick)
    return row
end

local function Build()
    popup = CreateFrame("Frame", nil, F.window)
    popup:SetFrameLevel(F.window:GetFrameLevel() + LEVEL)
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    popup:SetScript("OnMouseWheel", Wheel)
    ns.Solid(popup, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(popup, BLACK)
    popup.rows = {}
    for i = 1, ROWS do popup.rows[i] = NewRow(i) end
    popup.none = P.Text(popup, SMALL_SIZE, T.muted)
    popup.none:SetPoint("LEFT", ICON_X, 0)
    popup.none:SetText(TEXT_NONE)
    popup:Hide()
    F.spellPopup = popup
    local events = CreateFrame("Frame")
    events:RegisterEvent("SPELLS_CHANGED")
    events:SetScript("OnEvent", function() dirty = true end)
end

local function Refresh(box)
    if not box.spells then return Close() end
    if not popup then Build() end
    owner = box
    offset, lit = 0, 1
    Match(box:GetText())
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -DROP)
    popup:SetWidth(math.max(MIN_W, box:GetWidth()))
    Draw()
    popup:Show()
end

function F.SuggestOpen(box)
    Refresh(box)
end

function F.SuggestTyped(box, user)
    if user and owner == box then Refresh(box) end
end

function F.SuggestHeld()
    return popup ~= nil and popup:IsShown() and popup:IsMouseOver()
end

function F.SuggestClose(box)
    if owner == box then Close() end
end

function F.SuggestAccept(box)
    if owner ~= box or not popup:IsShown() then return end
    local s = shown[lit]
    if s and s.name ~= strtrim(box:GetText() or "") then
        Close()
        box:SetText(s.name)
    end
end

function F.SuggestMove(box, key)
    if owner ~= box or #shown == 0 then return end
    lit = math.max(1, math.min(#shown, lit + (key == "UP" and -1 or key == "DOWN" and 1 or 0)))
    if lit <= offset then offset = lit - 1 elseif lit > offset + ROWS then offset = lit - ROWS end
    Draw()
end
