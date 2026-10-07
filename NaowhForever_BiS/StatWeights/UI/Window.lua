-------------------------------------------------------------------------------
--  StatWeights/UI/Window.lua -- the Stat Weights window (ns.OpenStatWeightsWindow: the scales on
--  the BiS List's title bar and on the character panel, Edit Weights on its settings card). Under
--  the title bar a switch between your class's specs and what the tooltip line looks like; on the
--  left what a point of each stat is worth to the spec, only the stats it uses, each as a bar and
--  a number to type over (percents and weapon dps apart, as one of them is worth far more than a
--  point of a stat; a stat at 0 drops off, Add a stat puts one on at 0); on the right your BiS
--  list's best upgrades by these weights, so a change shows what it does. Import, Export and
--  Reset on the title bar. Sized to what it shows.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local SW = ns.StatWeights

local WIDTH, MIN_H, MAX_H = 860, 440, 760
local CARD, CARD_GAP = 6, 10
local CARD_TITLE_H, CARD_INSET, CARD_BOTTOM = 40, 16, 12
local ROW_H, GROUP_H, ADD_H = 28, 30, 34
local NAME_X, NAME_W, VALUE_W, VALUE_GAP, BAR_H = 14, 140, 52, 10, 6
local RESET_SIZE, RESET_GAP = 16, 6
local DOT_SIZE = 6
local UP_ROW_H, UP_ICON, UP_GAP, UP_MAX = 44, 30, 10, 10
local GAIN_W, GAIN_BAR_W, GAIN_BAR_H = 70, 60, 4
local NOTE_GAP = 16
local OFF_ALPHA = 0.35
local TITLE_SIZE, LABEL_SIZE, SMALL_SIZE = 13, 12, 11
local PAGE = "BiS List/Settings"
local DOT = "  \194\183  "
-- Worth a percent or a weapon point: too big for the points' bars.
local BIG = { hit = true, shit = true, crit = true, haste = true, scrit = true, dodge = true, block = true,
    threat = true, dps = true, dmg = true }
local GROUP_TITLES = { "PER POINT", "PER 1% OR WEAPON DPS" }
local UPGRADE_RGB = { r = 0.12, g = 1, b = 0 }

local byStat = {}
for _, stat in ipairs(SW.STATS) do byStat[stat[1]] = stat end

local window, editing
local adding = {}   -- stats put on the list by Add a stat, still at 0
local focus         -- the stat whose box takes the cursor on the next draw
local Draw, QueueDraw

-------------------------------------------------------------------------------
--  Typing a weight
-------------------------------------------------------------------------------
local function Apply(box)
    local row = box:GetParent()
    local value = tonumber((box:GetText():gsub(",", ".")))
    if value and value >= 0 and value < 1000 then
        adding[row.stat] = nil
        SW.Set(row.spec, row.stat, value)
        QueueDraw()
    else
        box:SetText(("%g"):format(row.value))
    end
end

local function BoxEnter(box) box:ClearFocus() end
local function BoxEscape(box)
    box:SetText(("%g"):format(box:GetParent().value))
    box:ClearFocus()
end

local function RowEnter(row)
    local spec = SW.Spec(row.spec)
    if not ns.Shared.Parts.Tip(row, "ANCHOR_RIGHT") then return end
    GameTooltip:SetText(("1 %s is worth %g to %s."):format(byStat[row.stat][2], row.value, spec.name), 1, 1, 1)
    GameTooltip:AddLine(("Default %g. Type a new number, or 0 to leave it out."):format(SW.Default(row.spec, row.stat)),
        T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function ResetStat(button)
    local row = button:GetParent()
    SW.Set(row.spec, row.stat, nil)
end

local function NewRow(parent)
    local Parts = ns.Shared.Parts
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetTexture(ns.Shared.Style.ROUND, nil, nil, "TRILINEAR")
    row.dot:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1)
    row.dot:SetSize(DOT_SIZE, DOT_SIZE)
    row.dot:SetPoint("LEFT", 0, 0)
    row.name = ns.Font(row, LABEL_SIZE, nil, T.fg)
    row.name:SetPoint("LEFT", NAME_X, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")
    row.reset = Parts.IconButton(row, ResetStat, ns.Shared.Style.CROSS, 0, "Back to the default")
    row.reset:SetSize(RESET_SIZE, RESET_SIZE)
    row.reset.icon:SetSize(RESET_SIZE, RESET_SIZE)
    row.reset:SetPoint("RIGHT", 0, 0)
    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(VALUE_W, ROW_H - 6)
    box:SetPoint("RIGHT", -(RESET_SIZE + RESET_GAP), 0)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetJustifyH("CENTER")
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(box)
    box:SetScript("OnEnterPressed", BoxEnter)
    box:SetScript("OnEscapePressed", BoxEscape)
    box:SetScript("OnEditFocusLost", Apply)
    row.box = box
    row.track = ns.Solid(row, "BACKGROUND", T.line, 1)
    row.track:SetPoint("LEFT", NAME_X + NAME_W, 0)
    row.track:SetPoint("RIGHT", box, "LEFT", -VALUE_GAP, 0)
    row.track:SetHeight(BAR_H)
    row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.bar:SetPoint("LEFT", row.track, "LEFT")
    row.bar:SetHeight(BAR_H)
    return row
end

-------------------------------------------------------------------------------
--  Import, Export, Reset and Add a stat
-------------------------------------------------------------------------------
local function Import()
    local key = editing
    ns.PromptText(("Import weights for %s\n%s"):format(SW.Spec(key).name, ns.Color("muted",
        "A Naowh weights line, or a WoWSims EP export (in WoWSims: Stat Weights, Copy to Current EP, Export)")),
        "", 0, function(text)
            local _, message = SW.Import(text, key)
            ns.Print(message)
        end)
end

local function Export()
    ns.ShowCopyLine(("Your %s weights"):format(SW.Spec(editing).name), SW.Export(editing))
end

local function Reset()
    local key = editing
    ns.Confirm(("Put every %s weight back to the defaults?"):format(SW.Spec(key).name), function()
        SW.Reset(key)
    end)
end

-- On the list at 0, its box ready for your number: no made-up weight in the meantime.
local function AddStat(key)
    adding[key], focus = true, key
    Draw()
end

-- The stats the spec uses, in the editor's order, split points / percents and weapons; and
-- the rest, for Add a stat.
local points, big, rest = {}, {}, {}
local function Split(weights)
    wipe(points); wipe(big); wipe(rest)
    for _, stat in ipairs(SW.STATS) do
        local key = stat[1]
        if (weights[key] or 0) > 0 or adding[key] then
            local list = BIG[key] and big or points
            list[#list + 1] = key
        else
            rest[#rest + 1] = key
        end
    end
end

local function AddMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Add a stat")
        for _, key in ipairs(rest) do
            root:CreateButton(byStat[key][2], function() AddStat(key) end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Your best upgrades by these weights
-------------------------------------------------------------------------------
local upgrades, gainOf, slotOf = {}, {}, {}
local function ByGain(a, b) return gainOf[a] > gainOf[b] end

-- Your BiS list's picks you do not wear yet, by how much stronger each makes you, best first.
local function BestUpgrades(weights)
    wipe(upgrades)
    wipe(gainOf)
    wipe(slotOf)
    local B = ns.BiS
    local list = B and B.On and B.On() and B.Lists.List()
    if not list then return upgrades end
    local Items = ns.Shared.Items
    local power = SW.Power(weights)
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        local id = list.slots[slot]
        if id and not gainOf[id] and not Items.Wearing(slot, id) then
            local gain = SW.Gain(id, slot, weights, power)
            if gain and gain >= 0.5 then
                gainOf[id], slotOf[id] = gain, slot
                upgrades[#upgrades + 1] = id
            end
        end
    end
    table.sort(upgrades, ByGain)
    return upgrades
end

local function ItemLink(id)
    local _, link = C_Item.GetItemInfo(id)
    return link
end

local function UpgradeEnter(row)
    row.hover:Show()
    if not ns.Shared.Parts.Tip(row, "ANCHOR_RIGHT") then return end
    GameTooltip:SetItemByID(row.id)
    GameTooltip:Show()
end

local function UpgradeLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local function UpgradeClick(row)
    if not IsModifiedClick() then return end
    local link = ItemLink(row.id)
    if link then HandleModifiedItemClick(link) end
end

local function NewUpgrade(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(UP_ROW_H)
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.04)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.icon = ns.Shared.Parts.ItemIcon(row, UP_ICON)
    row.icon:SetPoint("LEFT", 0, 0)
    row.gain = ns.Font(row, LABEL_SIZE, nil, UPGRADE_RGB)
    row.gain:SetPoint("TOPRIGHT", 0, -(UP_ROW_H - UP_ICON) / 2)
    row.gain:SetWidth(GAIN_W)
    row.gain:SetJustifyH("RIGHT")
    row.track = ns.Solid(row, "BACKGROUND", T.line, 1)
    row.track:SetPoint("BOTTOMRIGHT", 0, (UP_ROW_H - UP_ICON) / 2)
    row.track:SetSize(GAIN_BAR_W, GAIN_BAR_H)
    row.bar = ns.Solid(row, "ARTWORK", UPGRADE_RGB, 1)
    row.bar:SetPoint("LEFT", row.track, "LEFT")
    row.bar:SetHeight(GAIN_BAR_H)
    row.name = ns.Font(row, LABEL_SIZE, nil, T.fg)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", UP_GAP, 0)
    row.name:SetPoint("RIGHT", row.gain, "LEFT", -UP_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.slot = ns.Font(row, SMALL_SIZE, nil, T.muted)
    row.slot:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", UP_GAP, 0)
    row:SetScript("OnEnter", UpgradeEnter)
    row:SetScript("OnLeave", UpgradeLeave)
    row:SetScript("OnClick", UpgradeClick)
    return row
end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
local function Group(card, i, title, y)
    local text = card.groups[i]
    if not text then
        text = ns.Font(card.child, SMALL_SIZE, nil, T.accentSoft)
        card.groups[i] = text
    end
    text:SetText(title)
    text:ClearAllPoints()
    text:SetPoint("BOTTOMLEFT", card.child, "TOPLEFT", 0, -(y + GROUP_H - 8))
    text:Show()
    return y + GROUP_H
end

local function FillStats(card, keys, weights, used, y)
    local spec = editing
    local top = 0
    for _, key in ipairs(keys) do top = math.max(top, weights[key] or 0) end
    local width = card.child:GetWidth()
    for _, key in ipairs(keys) do
        used = used + 1
        local row = card.rows[used] or NewRow(card.child)
        card.rows[used] = row
        local value = weights[key] or 0
        local changed = SW.Changed(spec, key)
        row.spec, row.stat, row.value = spec, key, value
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetWidth(width)
        row.name:SetText(byStat[key][2])
        local track = width - NAME_X - NAME_W - VALUE_GAP - VALUE_W - RESET_SIZE - RESET_GAP
        row.bar:SetWidth(math.max(1, top > 0 and track * value / top or 1))
        row.dot:SetShown(changed)
        row.reset:SetShown(changed)
        local color = changed and T.accent or T.fg
        row.box:SetText(("%g"):format(value))
        row.box:SetTextColor(color.r, color.g, color.b)
        row:Show()
        if focus == key then
            focus = nil
            row.box:SetFocus()
            row.box:HighlightText()
        end
        y = y + ROW_H
    end
    return used, y
end

local function FillWeights(card, weights)
    Split(weights)
    for _, text in ipairs(card.groups) do text:Hide() end
    local used, y, g = 0, 0, 0
    for i, keys in ipairs({ points, big }) do
        if #keys > 0 then
            g = g + 1
            y = Group(card, g, GROUP_TITLES[i], y)
            used, y = FillStats(card, keys, weights, used, y)
        end
    end
    for i = used + 1, #card.rows do card.rows[i]:Hide() end
    card.add:ClearAllPoints()
    card.add:SetPoint("LEFT", card.child, "TOPLEFT", 0, -(y + ADD_H / 2))
    card.add:SetShown(#rest > 0)
    return y + ADD_H
end

local function FillUpgrades(card, weights)
    local Items = ns.Shared.Items
    local ids = BestUpgrades(weights)
    local shown = math.min(#ids, UP_MAX)
    local most = shown > 0 and gainOf[ids[1]] or 1
    local width = card.child:GetWidth()
    for i = 1, shown do
        local id = ids[i]
        local row = card.rows[i] or NewUpgrade(card.child)
        card.rows[i] = row
        row.id = id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * UP_ROW_H))
        row:SetWidth(width)
        row.icon.texture:SetTexture(C_Item.GetItemIconByID(id))
        ns.Shared.Parts.MarkForever(row.icon, id)
        row.name:SetText(Items.QualityHex(id) .. Items.Name(id) .. "|r")
        row.slot:SetText(ns.L(Items.SLOT_NAME[slotOf[id]] or ""))
        row.gain:SetText("+" .. math.floor(gainOf[id] + 0.5) .. "%")
        row.bar:SetWidth(math.max(1, GAIN_BAR_W * gainOf[id] / most))
        row:Show()
    end
    for i = shown + 1, #card.rows do card.rows[i]:Hide() end
    card.note:SetShown(shown == 0)
    card.note:SetText(ns.BiS and ns.BiS.On and ns.BiS.On() and "Everything on your BiS list is yours, or no better."
        or "Turn on the BiS List and pick your BiS to see your best upgrades here.")
    card.count:SetText(shown > 0 and (#ids > shown and ("%d of %d"):format(shown, #ids) or tostring(shown)) or "")
    return shown > 0 and shown * UP_ROW_H or UP_ROW_H
end

local function SpecTabs()
    local items = {}
    for _, spec in ipairs(SW.ClassSpecs()) do
        items[#items + 1] = { key = spec.key, label = spec.name:match("^(.-)%s+%S+$") or spec.name,
            tip = "The weights for " .. spec.name .. "." }
    end
    return items
end

local function Paint()
    local alpha = ns.QoLSettings and ns.QoLSettings.Get("bisWindowAlpha") or 1
    window.backdrop:Paint(alpha)
    window.opacity._refreshValue()
end

function Draw()
    local Parts = ns.Shared.Parts
    local spec = SW.Spec(editing)
    local weights = SW.For(editing)
    local changed = 0
    for _, stat in ipairs(SW.STATS) do
        if SW.Changed(editing, stat[1]) then changed = changed + 1 end
    end
    Parts.PaintTabs(window.specs, editing)
    window.reset:SetAlpha(changed > 0 and 1 or OFF_ALPHA)
    window.reset:EnableMouse(changed > 0)
    local listH = FillWeights(window.weights, weights)
    local upH = FillUpgrades(window.upgrades, weights)
    local id = upgrades[1]
    window.sample:SetText("On gear that is an upgrade:  " .. Parts.UpgradeLine(id and gainOf[id] or 9, spec.name))
    window.note.text:SetText(changed > 0 and ("Your weights" .. DOT .. "%d changed"):format(changed)
        or "Default weights" .. DOT .. ns.StatWeightDefaultsUpdated)
    window.note:SetWidth(math.max(1, math.ceil(window.note.text:GetStringWidth())))
    window.weights.child:SetHeight(listH)
    window.upgrades.child:SetHeight(upH)
    local h = window.cardsTop + CARD_TITLE_H + math.max(listH, upH) + CARD_BOTTOM + window.footerH
    window:SetHeight(math.min(MAX_H, math.max(MIN_H, h)))
end

local queued = false
local function Flush()
    queued = false
    if window and window:IsShown() then Draw() end
end

function QueueDraw()
    if queued or not (window and window:IsShown()) then return end
    queued = true
    C_Timer.After(0, Flush)
end

local function PickSpec(key)
    editing = key
    wipe(adding)
    Draw()
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function Card(left, right, top, bottom, title)
    local St = ns.Shared.Style
    window.backdrop:Card(left, top, right, bottom)
    local card = { rows = {}, groups = {} }
    card.title = ns.Font(window, TITLE_SIZE, nil, T.fg)
    card.title:SetPoint("TOPLEFT", left + CARD_INSET, -(top + CARD_INSET))
    card.title:SetText(title)
    card.count = ns.Font(window, SMALL_SIZE, nil, T.muted)
    card.count:SetPoint("TOPRIGHT", -(right + CARD_INSET), -(top + CARD_INSET + 2))
    card.scroll = ns.UI.SlimScroll(window)
    card.scroll:SetPoint("TOPLEFT", left + CARD_INSET, -(top + CARD_TITLE_H))
    card.scroll:SetPoint("BOTTOMRIGHT", -(right + CARD_INSET + St.SCROLLBAR - 6), bottom + CARD_BOTTOM)
    card.child = CreateFrame("Frame", nil, card.scroll)
    card.child:SetWidth(WIDTH - left - right - CARD_INSET * 2 - St.SCROLLBAR + 6)
    card.scroll:SetScrollChild(card.child)
    card.note = ns.Font(card.child, LABEL_SIZE, nil, T.muted)
    card.note:SetPoint("TOPLEFT", 0, -NOTE_GAP / 2)
    card.note:SetPoint("RIGHT")
    card.note:SetJustifyH("LEFT")
    card.note:Hide()
    return card
end

local function Build()
    local Shared = ns.Shared
    local Parts, St = Shared.Parts, Shared.Style
    local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
    window = Parts.Window(WIDTH, MIN_H, "statWeightsWindow")

    local close = Parts.TitleBar(window, "Stat Weights", "What a point of each stat is worth to your spec.", PAGE)
    local opacityIcon
    opacityIcon, window.opacity = Parts.Opacity(window, close,
        function() return math.floor((ns.QoLSettings.Get("bisWindowAlpha") or 1) * 100 + 0.5) end,
        function(value) ns.QoLSettings.Set("bisWindowAlpha", value / 100) end)
    window.reset = Parts.BarButton(window, St.CROSS, "Reset to Default",
        "Puts every weight of this spec back to the defaults. Asks first.", Reset)
    window.reset:SetPoint("RIGHT", opacityIcon, "LEFT", -18, 0)
    local export = Parts.BarButton(window, St.EXPORT, "Export these weights", "A line to share them with.", Export)
    export:SetPoint("RIGHT", window.reset, "LEFT", -St.BAR_GAP, 0)
    local import = Parts.BarButton(window, St.IMPORT, "Import weights",
        "A Naowh weights line, or a WoWSims EP export.", Import)
    import:SetPoint("RIGHT", export, "LEFT", -St.BAR_GAP, 0)
    Parts.FooterBrand(window, PAGE)
    window.note = Parts.FooterNote(window, "")

    local top = HEADER + PAD
    local specs = SpecTabs()
    window.specs = Parts.Tabs(window, 1, specs, PickSpec)
    Parts.FitTabs(window.specs, specs, CARD_INSET)
    window.specs:SetPoint("TOPLEFT", CARD + PAD, -top)
    window.sample = ns.Font(window, SMALL_SIZE, nil, T.muted)
    window.sample:SetPoint("LEFT", window.specs, "RIGHT", NOTE_GAP, 0)
    window.sample:SetPoint("RIGHT", -(CARD + PAD), 0)
    window.sample:SetJustifyH("RIGHT")
    window.sample:SetWordWrap(false)

    window.cardsTop = top + St.TAB_H + PAD
    window.footerH = FOOTER + CARD
    local half = math.floor((WIDTH - CARD * 2 - CARD_GAP) / 2)
    window.weights = Card(CARD, WIDTH - CARD - half, window.cardsTop, window.footerH, "Weights")
    window.weights.add = Parts.Link(window.weights.child, AddMenu)
    Parts.SetLink(window.weights.add, "+ Add a stat")
    window.upgrades = Card(CARD + half + CARD_GAP, CARD, window.cardsTop, window.footerH, "Best Upgrades")

    SW.OnChange(QueueDraw)
    if ns.BiS and ns.BiS.OnListChange then ns.BiS.OnListChange(QueueDraw) end
    ns.QoLSettings.OnChange(function(key)
        if key == "bisWindowAlpha" and window:IsShown() then Paint() end
    end)
end

function ns.OpenStatWeightsWindow()
    if not window then Build() end
    editing = editing or SW.ActiveSpec()
    window:SetScale(ns.UIScale())
    window:Show()
    Paint()
    Draw()
end

function ns.ToggleStatWeightsWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenStatWeightsWindow() end
end
