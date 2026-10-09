-- AuraPanel.lua: a PvP Auras panel on Blizzard's AuraContainer: its rows of aura buttons, the absorb and the focus's name (P.Panel).
local ns = _G.NaowhForever

local P = ns.PvP
local S = P.Settings
local UI = ns.UI
local St = P.Style
local Icon = P.Icon

local ICON_GAP, ROW_GAP, HEADER_PAD, NAME_GAP = St.ICON_GAP, St.ROW_GAP, St.HEADER_PAD, St.NAME_GAP
local ABSORB_TEXT, ABSORB_SIZE, ABSORB_PAD, ABSORB_RGB = St.ABSORB_TEXT, St.ABSORB_SIZE, St.ABSORB_PAD, St.ABSORB_RGB
local NAME_SIZE, NAME_RGB, CLASS_ICONS, OUTLINE = St.NAME_SIZE, St.NAME_RGB, St.CLASS_ICONS, St.OUTLINE
local WHITE8X8 = St.WHITE
local SORT_DEFAULT = 0
local ABSORB_WIDTH = 2
local ROWS, MAX_KEY, FILTER, RowOn = P.ROWS, P.MAX_KEY, P.FILTER, P.RowOn
local lists = P.AuraLists
local PAGE, CARD = "PvP/Auras", "PvP/Auras:auras"

local ROW_LAYOUT = { elementSpacing = ICON_GAP, lineSpacing = ROW_GAP, groupLineSpacing = ROW_GAP, forceNewLine = true }

local buttons = {}
local pendingResize, built

local Panel = {}
P.Panel = Panel

local function InitButton(button)
    button.aura = true
    Icon.New(button)
    button:SetIcon(button.icon)
    button:SetDurationCooldown(button.swipe)
    button:SetApplicationCount(button.countText)
    buttons[#buttons + 1] = button
end

local function NewAbsorb(holder)
    local absorb = CreateFrame("StatusBar", nil, holder)
    absorb:SetStatusBarTexture(WHITE8X8)
    absorb:SetStatusBarColor(0, 0, 0, 0)
    absorb:SetMinMaxValues(0, 1)
    absorb:SetValue(0)
    absorb.clip = CreateFrame("Frame", nil, absorb)
    absorb.clip:SetClipsChildren(true)
    absorb.clip:SetPoint("TOPLEFT", absorb:GetStatusBarTexture(), "TOPLEFT")
    absorb.clip:SetPoint("BOTTOMRIGHT", absorb:GetStatusBarTexture(), "BOTTOMRIGHT")
    absorb.text = absorb.clip:CreateFontString(nil, "OVERLAY")
    absorb.text:SetPoint("RIGHT", absorb, "RIGHT")
    absorb.text:SetJustifyH("RIGHT")
    return absorb
end

local function NewHeader(holder)
    local header = CreateFrame("Frame", nil, holder)
    header.class = header:CreateTexture(nil, "ARTWORK")
    header.class:SetTexture(CLASS_ICONS)
    header.class:SetPoint("LEFT")
    header.name = header:CreateFontString(nil, "OVERLAY")
    header.name:SetPoint("LEFT", header.class, "RIGHT", NAME_GAP, 0)
    header.name:SetJustifyH("LEFT")
    header.name:SetWordWrap(false)
    return header
end

function Panel.Build(d)
    local holder = CreateFrame("Frame", d.frame, UIParent)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    container:SetPoint("TOPLEFT")
    container:SetUnit(d.unit)
    local filters = { buffs = P.BuffFilters(), cc = lists.cc.filters, debuffs = lists.debuffs.filters }
    for _, row in ipairs(ROWS) do
        container:AddAuraGroup(row, FILTER[row], {
            maxFrameCount = S.Get(MAX_KEY[row]), sortMethod = SORT_DEFAULT, initializeFrame = InitButton,
            layout = ROW_LAYOUT, candidateFilters = filters[row],
        })
    end
    d.applied = { cc = lists.cc.version, debuffs = lists.debuffs.version }
    holder.mover = UI.AttachMover(holder, d.name, function(pos) S.Set(d.posKey, pos) end, PAGE, CARD)
    local absorb = NewAbsorb(holder)
    if d.nameKey then d.header = NewHeader(holder) end
    d.holder, d.container, d.absorb = holder, container, absorb
    built = true
end

function Panel.Built()
    return built
end

function Panel.UpdateAbsorb(d)
    local absorb = d.absorb
    if not absorb or not absorb:IsShown() then return end
    if not UnitExists(d.unit) then
        absorb:SetValue(0)
        return
    end
    local amount = UnitGetTotalAbsorbs(d.unit)
    absorb:SetValue(amount)
    absorb.text:SetFormattedText(ABSORB_TEXT, amount)
end

function Panel.UpdateHeader(d)
    local header = d.header
    if not header then return end
    local shown = S.Get(d.nameKey) == true and UnitExists(d.unit)
    header:SetShown(shown)
    if not shown then return end
    header.name:SetText(UnitName(d.unit))
    local _, classFile = UnitClass(d.unit)
    local readable = P.Readable(classFile)
    local color = readable and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] or NAME_RGB
    local coords = readable and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    header.name:SetTextColor(color.r, color.g, color.b)
    header.class:SetShown(coords ~= nil)
    if coords then Icon.SetClass(header.class, coords) end
end

function Panel.Place(d)
    local pos = S.Get(d.posKey)
    d.holder:ClearAllPoints()
    d.holder:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local function LayoutHeader(d)
    local nameSize = Icon.TextSize(NAME_SIZE)
    d.header.name:SetFont(ns.UIFontPath(), nameSize, OUTLINE)
    d.header.class:SetSize(nameSize + HEADER_PAD, nameSize + HEADER_PAD)
    d.header:SetSize(d.holder:GetWidth(), nameSize + HEADER_PAD)
    d.header:ClearAllPoints()
    d.header:SetPoint("BOTTOMLEFT", d.holder, "TOPLEFT", 0, ROW_GAP)
end

function Panel.Layout(d)
    local size, rows, wide = Icon.Size(), 0, 1
    for _, row in ipairs(ROWS) do
        if RowOn(d, row) then rows, wide = rows + 1, math.max(wide, S.Get(MAX_KEY[row])) end
    end
    rows = math.max(rows, 1)
    d.holder:SetSize(wide * size + (wide - 1) * ICON_GAP, rows * size + (rows - 1) * ROW_GAP)
    local absorbSize = Icon.TextSize(ABSORB_SIZE)
    d.absorb.text:SetFont(ns.UIFontPath(), absorbSize, OUTLINE)
    d.absorb.text:SetTextColor(ABSORB_RGB.r, ABSORB_RGB.g, ABSORB_RGB.b)
    d.absorb:SetSize(size * ABSORB_WIDTH, absorbSize + ABSORB_PAD)
    d.absorb:ClearAllPoints()
    d.absorb:SetPoint("RIGHT", d.holder, "TOPLEFT", -NAME_GAP, -size / 2)
    if d.header then LayoutHeader(d) end
end

function Panel.Rows(d)
    for _, row in ipairs(ROWS) do
        d.container:SetAuraGroupEnabled(row, RowOn(d, row))
        d.container:SetAuraGroupMaxFrameCount(row, S.Get(MAX_KEY[row]))
    end
    d.container:SetAuraGroupCandidateFilters("buffs", P.BuffFilters())
    for list, data in pairs(lists) do
        if d.applied[list] ~= data.version then
            d.applied[list] = data.version
            d.container:SetAuraGroupCandidateFilters(list, data.filters)
        end
    end
end

function Panel.ResizeButtons()
    if InCombatLockdown() then
        pendingResize = true
        return
    end
    pendingResize = false
    for i = 1, #buttons do Icon.Style(buttons[i]) end
end

function Panel.ResizePending()
    return pendingResize
end

function Panel.Hide(d)
    if not d.holder then return end
    d.container:SetEnabled(false)
    d.holder:Hide()
    d.holder.mover:Hide()
end
