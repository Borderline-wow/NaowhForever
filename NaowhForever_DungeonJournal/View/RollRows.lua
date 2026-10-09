-- RollRows.lua: under an item in a boss's history: everyone's roll in two columns, or a line when no one rolled.
local ns = _G.NaowhForever

local T = ns.THEME
local J = ns.Journal
local Kinds, Parts = J.View.Kinds, J.View.Parts
local St = J.Style
local CHECK, HAVE_RGB, ICON, STRIPE, SMALL_SIZE = St.CHECK, St.HAVE_RGB, St.ICON, St.STRIPE, St.SMALL_SIZE

local ROLLS_GAP = 8
local ROLLS_PAD = 6
local GRID_LINE = 18
local GRID_INSET = 6
local GRID_GAP = 16
local GRID_COLUMNS = 2
local STRIPE_EVERY = J.C.STRIPE_EVERY
local CELL_GAP = 6
local ROLL_ICON = 14
local ROLL_GAP = 4
local ROLL_DIGITS = 3
local CHECK_ICON = 12
local ROLL_ATLAS = { [0] = "lootroll-icon-need", [1] = "lootroll-icon-need", [2] = "lootroll-icon-transmog",
    [3] = "lootroll-icon-greed", [5] = "lootroll-icon-pass" }

local function Band(row, line)
    local band = row.bands[line]
    if not band then
        band = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
        band:SetHeight(GRID_LINE)
        row.bands[line] = band
    end
    return band
end

local function NewCell(row)
    local cell = {}
    cell.number = Parts.Cells(row, SMALL_SIZE, T.muted, ROLL_DIGITS)
    cell.icon = row:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ROLL_ICON, ROLL_ICON)
    cell.check = row:CreateTexture(nil, "ARTWORK")
    cell.check:SetTexture(CHECK)
    cell.check:SetSize(CHECK_ICON, CHECK_ICON)
    cell.check:SetVertexColor(HAVE_RGB.r, HAVE_RGB.g, HAVE_RGB.b)
    cell.check:SetPoint("RIGHT", cell.icon, "LEFT", -ROLL_GAP, 0)
    cell.name = ns.Font(row, SMALL_SIZE)
    cell.name:SetJustifyH("LEFT")
    cell.name:SetWordWrap(false)
    cell.name:SetPoint("RIGHT", cell.check, "LEFT", -CELL_GAP, 0)
    row.cells[#row.cells + 1] = cell
    return cell
end

local function PlaceBands(row, lines, left)
    for line = 1, math.max(lines, #row.bands) do
        local band = Band(row, line)
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", left, -(line - 1) * GRID_LINE)
        band:SetPoint("TOPRIGHT", 0, -(line - 1) * GRID_LINE)
        band:SetShown(line <= lines and line % STRIPE_EVERY == 1)
    end
end

local function SetCell(row, cell, i, roll, column, isMe)
    local band = row.bands[math.ceil(i / GRID_COLUMNS)]
    local x = GRID_INSET + ((i - 1) % GRID_COLUMNS) * (column + GRID_GAP)
    local number = cell.number
    number[1]:ClearAllPoints()
    number[1]:SetPoint("RIGHT", band, "LEFT", x + column, 0)
    number:SetText(roll.roll or "")
    local result = roll.winner and HAVE_RGB or T.muted
    number:SetTextColor(result.r, result.g, result.b)
    cell.icon:ClearAllPoints()
    cell.icon:SetPoint("RIGHT", band, "LEFT", x + column - number.widths.digit * ROLL_DIGITS - ROLL_GAP, 0)
    local atlas = ROLL_ATLAS[roll.state]
    cell.icon:SetShown(atlas ~= nil)
    if atlas then cell.icon:SetAtlas(atlas) end
    cell.check:SetShown(roll.winner)
    cell.name:ClearAllPoints()
    cell.name:SetPoint("LEFT", band, "LEFT", x, 0)
    cell.name:SetPoint("RIGHT", cell.check, "LEFT", -CELL_GAP, 0)
    local color = Parts.ClassColor(roll.class)
    cell.name:SetText(isMe(roll.name) and roll.name .. Parts.YOU or roll.name)
    cell.name:SetTextColor(color.r, color.g, color.b)
    cell.name:Show()
end

local function HideCell(cell)
    cell.name:Hide()
    cell.icon:Hide()
    cell.check:Hide()
    cell.number:SetText("")
end

Kinds.rollGrid = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.cells, row.bands = {}, {}
        row.stripe = Parts.CardBand(row, STRIPE)
        return row
    end,
    Set = function(row, list, isMe)
        row.stripe:SetShown(row:GetParent().striped)
        local left = ICON + ROLLS_GAP
        local column = (row:GetWidth() - left - GRID_INSET * 2 - GRID_GAP) / GRID_COLUMNS
        local lines = math.ceil(#list / GRID_COLUMNS)
        PlaceBands(row, lines, left)
        for i, roll in ipairs(list) do SetCell(row, row.cells[i] or NewCell(row), i, roll, column, isMe) end
        for i = #list + 1, #row.cells do HideCell(row.cells[i]) end
        return lines * GRID_LINE + ROLLS_PAD
    end,
}

Kinds.rolls = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.stripe = Parts.CardBand(row, STRIPE)
        row.text = ns.Font(row, SMALL_SIZE, nil, T.muted)
        row.text:SetPoint("TOPLEFT", ICON + ROLLS_GAP, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        return row
    end,
    Set = function(row, text)
        row.stripe:SetShown(row:GetParent().striped)
        row.text:SetWidth(row:GetWidth() - ICON - ROLLS_GAP)
        row.text:SetText(text)
        return math.ceil(row.text:GetStringHeight()) + ROLLS_PAD
    end,
}
