-- Text.lua: text made once and kept (ns.Shared.Parts): counts, money in coins, plain where-lines, numbers lined up to the pixel and rows of labels.
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Parts = Shared.Parts
local St = Shared.Style

local PLACE_DOT = St.PLACE_DOT
local COINS_KEPT = 500
local GOLD, SILVER, COPPER = 10000, 100, 1
local COLOR_CODE = "|c%x%x%x%x%x%x%x%x"
local COLOR_END = "|r"
local PLACE_DASH = "%s*%-%s+"
local CELL_MARKS = { "-", "/" }
local CELL_MARK_PAD = 2
local LAST_DIGIT = 9

local fractions = {}
local coins, coinsKept = {}, 0
local plain = {}
local cellWidths = {}

local Cells = {}
Cells.__index = Cells

local function CellWidths(parent, size)
    local widths = cellWidths[size]
    if widths then return widths end
    local probe = ns.Font(parent, size)
    local digit = 0
    for d = 0, LAST_DIGIT do
        probe:SetText(d)
        digit = math.max(digit, math.ceil(probe:GetStringWidth()))
    end
    widths = { digit = digit }
    for _, mark in ipairs(CELL_MARKS) do
        probe:SetText(mark)
        widths[mark] = math.ceil(probe:GetStringWidth()) + CELL_MARK_PAD
    end
    probe:Hide()
    cellWidths[size] = widths
    return widths
end

function Cells:SetText(text)
    text = tostring(text)
    local n, widths = #text, self.widths
    for i = 1, #self do
        local cell = self[i]
        if i <= n then
            local char = text:sub(n - i + 1, n - i + 1)
            cell:SetWidth(widths[char] or widths.digit)
            cell:SetText(char)
            cell:Show()
        else
            cell:Hide()
        end
    end
    return self[math.max(1, math.min(n, #self))]
end

function Cells:SetTextColor(r, g, b)
    for i = 1, #self do self[i]:SetTextColor(r, g, b) end
end

local function RowItem(row, i)
    local label = row.labels[i]
    if label then return label end
    label = ns.Font(row, row.size, row.flags, row.color)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    row.labels[i] = label
    if row.iconSize then
        local icon = Parts.ItemIcon(row, row.iconSize)
        icon:Hide()
        row.icons[i] = icon
    end
    if row.sep and i > 1 then
        local sep = ns.Font(row, row.size, row.flags, row.sepColor)
        sep:SetText(row.sep)
        row.seps[i] = sep
    end
    return label
end

local function ShowLabel(row, i, list, icons)
    local label = RowItem(row, i)
    local icon, sep = row.icons[i], row.seps[i]
    label:SetText(list[i])
    label:Show()
    if icon then
        local texture = icons and icons[i]
        if texture then icon.texture:SetTexture(texture) end
        icon:SetShown(texture and true or false)
    end
    if sep then sep:Show() end
    return label:GetStringWidth()
end

local function HideLabel(row, i)
    local label, icon, sep = row.labels[i], row.icons[i], row.seps[i]
    label:Hide()
    if icon then icon:Hide() end
    if sep then sep:Hide() end
end

local function RowSetLabels(row, list, n, icons)
    local widest = 0
    for i = 1, math.max(n, #row.labels) do
        if i <= n then
            local w = ShowLabel(row, i, list, icons)
            if w > widest then widest = w end
        else
            HideLabel(row, i)
        end
    end
    row.count = n
    return widest
end

local function RowSpread(row, width)
    row:SetWidth(width)
    local n = row.count
    if n == 0 then return end
    local share = width / n
    local labels = row.labels
    for i = 1, n do
        labels[i]:ClearAllPoints()
        labels[i]:SetPoint("CENTER", row, "LEFT", share * (i - 0.5), 0)
    end
end

local function RowPack(row)
    local x, gap = 0, row.gap
    for i = 1, row.count do
        local sep, icon, label = row.seps[i], row.icons[i], row.labels[i]
        if i > 1 then x = x + gap end
        if sep then
            sep:ClearAllPoints()
            sep:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + sep:GetStringWidth()
        end
        if icon and icon:IsShown() then
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", row, "LEFT", x, -row.iconDrop)
            x = x + row.iconSize + row.iconGap
        end
        label:ClearAllPoints()
        label:SetPoint("LEFT", row, "LEFT", x, 0)
        x = x + label:GetStringWidth()
    end
    row:SetWidth(math.max(1, x))
    return x
end

local function RowTextSize(row, size)
    if size == row.size then return end
    row.size = size
    row:SetHeight(size)
    if row.iconGrow then row.iconSize = size + row.iconGrow end
    local font, labels, seps, icons = ns.UIFontPath(), row.labels, row.seps, row.icons
    for i = 1, #labels do
        labels[i]:SetFont(font, size, row.flags or "")
        if seps[i] then seps[i]:SetFont(font, size, row.flags or "") end
        if icons[i] then icons[i]:SetSize(row.iconSize, row.iconSize) end
    end
end

local function RowColor(row, color)
    row.color = color
    local labels = row.labels
    for i = 1, #labels do labels[i]:SetTextColor(color.r, color.g, color.b) end
end

local function RowOptions(row, size, opts)
    row.gap = opts.gap or 0
    row.iconGrow = opts.iconGrow
    row.iconSize = opts.icon or (opts.iconGrow and size + opts.iconGrow)
    row.iconGap, row.iconDrop = opts.iconGap or St.GAP, opts.iconDrop or 0
    row.sep, row.sepColor = opts.separator, opts.separatorColor or T.muted
end

function Parts.Fraction(part, whole)
    local byWhole = fractions[whole]
    if not byWhole then
        byWhole = {}
        fractions[whole] = byWhole
    end
    local text = byWhole[part]
    if text then return text end
    text = part .. "/" .. whole
    byWhole[part] = text
    return text
end

function Parts.Coins(copper, compact)
    if compact then
        local unit = copper >= GOLD and GOLD or copper >= SILVER and SILVER or COPPER
        copper = math.floor(copper / unit + 0.5) * unit
    end
    local text = coins[copper]
    if text then return text end
    if coinsKept >= COINS_KEPT then
        wipe(coins)
        coinsKept = 0
    end
    text = C_CurrencyInfo.GetCoinTextureString(copper)
    coins[copper] = text
    coinsKept = coinsKept + 1
    return text
end

function Parts.Plain(text)
    local out = plain[text]
    if out then return out end
    out = text:gsub(COLOR_CODE, ""):gsub(COLOR_END, ""):gsub(PLACE_DASH, PLACE_DOT)
    plain[text] = out
    return out
end

function Parts.Cells(parent, size, color, count)
    local cells = setmetatable({ widths = CellWidths(parent, size) }, Cells)
    for i = 1, count do
        local cell = ns.Font(parent, size, nil, color)
        cell:SetJustifyH("CENTER")
        if i > 1 then cell:SetPoint("RIGHT", cells[i - 1], "LEFT", 0, 0) end
        cells[i] = cell
    end
    return cells
end

function Parts.LabelRow(parent, size, flags, color, opts)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(size)
    row.size, row.flags, row.color = size, flags, color or T.fg
    row.labels, row.icons, row.seps, row.count, row.gap = {}, {}, {}, 0, 0
    if opts then RowOptions(row, size, opts) end
    row.SetLabels, row.Spread, row.Pack, row.SetColor = RowSetLabels, RowSpread, RowPack, RowColor
    row.SetTextSize = RowTextSize
    return row
end
