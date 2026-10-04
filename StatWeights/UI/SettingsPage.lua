-------------------------------------------------------------------------------
--  StatWeights/UI/SettingsPage.lua -- the module's page, kept short: one switch for the
--  tooltip line and your spec (Automatic: your talents'); what the tooltip line looks like;
--  then what a point of each stat is worth to the spec, only the stats it uses, each as a bar
--  (how much it counts next to the others) and a number to type over. Percents and weapon
--  dps sit in their own column, as one of them is worth far more than a point of a stat. A
--  stat at 0 drops off the list; Add a stat puts one on at 0 with its box ready for your
--  number (left at 0, it drops off again). Under them, your BiS list's best upgrades by these
--  weights, so a change shows what it does. Reset, Import (a Naowh line or a WoWSims export)
--  and Export (your weights as a line) on the title.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local SW = ns.StatWeights
local S = SW.Settings

local ROW_H, HEAD_H, COLUMN_HEAD_H, FOOT_H = 26, 56, 24, 44
local PREVIEW_GAP, PREVIEW_ROWS, PREVIEW_ICON = 18, 5, 18
local AUTO = "auto"
local NAME_W, VALUE_W, COLUMN_GAP, BAR_H = 150, 52, 40, 6
-- Worth a percent or a weapon point: too big for the points' bars.
local BIG = { hit = true, crit = true, haste = true, scrit = true, dodge = true, block = true, threat = true,
    dps = true, dmg = true }
local COLUMN_TITLES = { "PER POINT", "PER 1% OR WEAPON DPS" }
local CHOOSE = "_"

local byStat = {}
for _, stat in ipairs(SW.STATS) do byStat[stat[1]] = stat end

local function Refresh()
    ns.UI:RefreshPage(true)
end

-------------------------------------------------------------------------------
--  Typing a weight
-------------------------------------------------------------------------------
local function Apply(box)
    local row = box:GetParent()
    local value = tonumber((box:GetText():gsub(",", ".")))
    if value and value >= 0 and value < 1000 then
        row:GetParent():GetParent().adding[row.stat] = nil   -- the block's: added, now set
        SW.Set(row.spec, row.stat, value)
        C_Timer.After(0, Refresh)   -- not from inside the box's own script
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

local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row.name = ns.Font(row, 12, nil, T.fg)
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")
    row.track = ns.Solid(row, "BACKGROUND", T.line, 1)
    row.track:SetPoint("LEFT", NAME_W, 0)
    row.track:SetPoint("RIGHT", -(VALUE_W + 12), 0)
    row.track:SetHeight(BAR_H)
    row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.bar:SetPoint("LEFT", row.track, "LEFT")
    row.bar:SetHeight(BAR_H)
    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(VALUE_W, ROW_H - 6)
    box:SetPoint("RIGHT", 0, 0)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetJustifyH("CENTER")
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(box)
    box:SetScript("OnEnterPressed", BoxEnter)
    box:SetScript("OnEscapePressed", BoxEscape)
    box:SetScript("OnEditFocusLost", Apply)
    row.box = box
    return row
end

-------------------------------------------------------------------------------
--  The block: title, two columns, Add a stat
-------------------------------------------------------------------------------
local function Import(link)
    local key = link:GetParent().spec
    ns.PromptText(("Import weights for %s\n%s"):format(SW.Spec(key).name, ns.Color("muted",
        "A Naowh weights line, or a WoWSims EP export (in WoWSims: Stat Weights, Copy to Current EP, Export)")),
        "", 0, function(text)
            local _, message = SW.Import(text, key)
            ns.Print(message)
            Refresh()
        end)
end

local function Export(link)
    local key = link:GetParent().spec
    ns.ShowCopyLine(("Your %s weights"):format(SW.Spec(key).name), SW.Export(key))
end

local function Reset(link)
    local key = link:GetParent().spec
    ns.Confirm(("Put every %s weight back to the defaults?"):format(SW.Spec(key).name), function()
        SW.Reset(key)
        Refresh()
    end)
end

local function MakeBlock(parent)
    local Parts = ns.Shared.Parts
    local block = CreateFrame("Frame", nil, parent)
    block.title = ns.Font(block, 13, nil, T.fg)
    block.title:SetPoint("TOPLEFT", 0, -6)
    block.export = Parts.Link(block, Export)
    block.export:SetPoint("TOPRIGHT", 0, -4)
    Parts.SetLink(block.export, "Export")
    block.import = Parts.Link(block, Import)
    block.import:SetPoint("RIGHT", block.export, "LEFT", -16, 0)
    Parts.SetLink(block.import, "Import")
    block.reset = Parts.Link(block, Reset)
    block.reset:SetPoint("RIGHT", block.import, "LEFT", -16, 0)
    Parts.SetLink(block.reset, "Reset")
    block.status = ns.Font(block, 12, nil, T.muted)
    block.status:SetPoint("RIGHT", block.reset, "LEFT", -16, 0)
    block.sample = ns.Font(block, 12, nil, T.muted)
    block.sample:SetPoint("TOPLEFT", 0, -28)
    block.adding = {}   -- stats put on the list by Add a stat, still at 0
    block.columns = {}
    for i = 1, 2 do
        local column = CreateFrame("Frame", nil, block)
        column.title = ns.Font(column, 11, nil, T.muted)
        column.title:SetPoint("TOPLEFT", 0, 0)
        column.title:SetText(COLUMN_TITLES[i])
        column.rows = {}
        block.columns[i] = column
    end
    block.preview = CreateFrame("Frame", nil, block)
    block.preview.title = ns.Font(block.preview, 11, nil, T.muted)
    block.preview.title:SetPoint("TOPLEFT", 0, 0)
    block.preview.note = ns.Font(block.preview, 12, nil, T.muted)
    block.preview.note:SetPoint("TOPLEFT", 0, -COLUMN_HEAD_H)
    block.preview.rows = {}
    block.addLabel = ns.Font(block, 12, nil, T.muted)
    block.addLabel:SetText("Add a stat")
    block.addLabel:SetPoint("BOTTOMLEFT", 0, 16)
    return block
end

-- On the list at 0, its box ready for your number: no made-up weight in the meantime.
local function AddStat(block, key)
    if key == CHOOSE then return end
    block.adding[key], block.focus = true, key
    Refresh()
end

-- The stats the spec uses, in the editor's order, split points / percents and weapons; and
-- the rest, for Add a stat.
local function Split(weights, adding)
    local points, big, rest, restOrder = {}, {}, { [CHOOSE] = "Choose a stat" }, { CHOOSE }
    for _, stat in ipairs(SW.STATS) do
        local key = stat[1]
        if (weights[key] or 0) > 0 or adding[key] then
            local list = BIG[key] and big or points
            list[#list + 1] = key
        else
            rest[key] = stat[2]
            restOrder[#restOrder + 1] = key
        end
    end
    return points, big, rest, restOrder
end

local function FillColumn(block, column, keys, weights, width)
    local spec = block.spec
    local top = 0
    for _, key in ipairs(keys) do top = math.max(top, weights[key] or 0) end
    for i, key in ipairs(keys) do
        local row = column.rows[i] or NewRow(column)
        column.rows[i] = row
        local value = weights[key] or 0
        row.spec, row.stat, row.value = spec, key, value
        row:SetPoint("TOPLEFT", 0, -(COLUMN_HEAD_H + (i - 1) * ROW_H))
        row:SetWidth(width)
        row.name:SetText(byStat[key][2])
        local track = width - NAME_W - VALUE_W - 12
        row.bar:SetWidth(math.max(1, top > 0 and track * value / top or 1))
        local color = SW.Changed(spec, key) and T.accent or T.fg
        row.box:SetText(("%g"):format(value))
        row.box:SetTextColor(color.r, color.g, color.b)
        row:Show()
        if block.focus == key then
            block.focus = nil
            row.box:SetFocus()
            row.box:HighlightText()
        end
    end
    for i = #keys + 1, #column.rows do column.rows[i]:Hide() end
    column:SetShown(#keys > 0)
end

-------------------------------------------------------------------------------
--  Your best upgrades by these weights
-------------------------------------------------------------------------------
local upgrades, gainOf = {}, {}
local function ByGain(a, b) return gainOf[a] > gainOf[b] end

-- Your BiS list's picks you do not wear yet, by how much stronger each makes you, best first.
local function BestUpgrades(weights)
    wipe(upgrades)
    wipe(gainOf)
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
                gainOf[id] = gain
                upgrades[#upgrades + 1] = id
            end
        end
    end
    table.sort(upgrades, ByGain)
    return upgrades
end

local function PreviewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(PREVIEW_ICON, PREVIEW_ICON)
    row.icon:SetPoint("LEFT", 0, 0)
    row.name = ns.Font(row, 12, nil, T.fg)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.gain = ns.Font(row, 12, nil, T.fg)
    row.gain:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    return row
end

-- Returns its height.
local function FillPreview(preview, weights, specName)
    local Items, St = ns.Shared.Items, ns.Shared.Style
    local ids = BestUpgrades(weights)
    preview.title:SetText(("YOUR BEST UPGRADES AS %s, BY THESE WEIGHTS"):format(specName:upper()))
    local shown = math.min(#ids, PREVIEW_ROWS)
    preview.note:SetShown(shown == 0)
    preview.note:SetText(ns.BiS and ns.BiS.On and ns.BiS.On() and "Everything on your BiS list is yours, or no better."
        or "Turn on the BiS List and pick your BiS to see your best upgrades here.")
    for i = 1, shown do
        local id = ids[i]
        local row = preview.rows[i] or PreviewRow(preview)
        preview.rows[i] = row
        row:SetPoint("TOPLEFT", 0, -(COLUMN_HEAD_H + (i - 1) * ROW_H))
        row:SetPoint("RIGHT")
        row.icon:SetTexture(C_Item.GetItemIconByID(id))
        row.name:SetText(Items.QualityHex(id) .. Items.Name(id) .. "|r")
        row.gain:SetText(St.UPGRADE_CODE .. "+" .. math.floor(gainOf[id] + 0.5) .. "%|r")
        row:Show()
    end
    for i = shown + 1, #preview.rows do preview.rows[i]:Hide() end
    return COLUMN_HEAD_H + math.max(shown, 1) * ROW_H
end

-- What the tooltip line looks like, on your best upgrade (else a made-up one).
local function Sample(specName)
    local id = upgrades[1]
    return "On gear that is an upgrade:  " .. ns.Shared.Parts.UpgradeLine(id and gainOf[id] or 9, specName)
end

-- Your spec's weights; returns the block's height.
local function FillBlock(block, width)
    local key = SW.ActiveSpec()
    local spec = SW.Spec(key)
    local weights = SW.For(key)
    if block.spec ~= key then wipe(block.adding) end
    block.spec = key
    local changed = 0
    for _, stat in ipairs(SW.STATS) do
        if SW.Changed(key, stat[1]) then changed = changed + 1 end
    end
    block.title:SetText(("What a point of each stat is worth to %s"):format(spec.name))
    block.status:SetText(changed > 0 and ("Your weights" .. "  \194\183  %d changed"):format(changed)
        or "Default weights  \194\183  " .. ns.StatWeightDefaultsUpdated)
    block.reset:SetShown(changed > 0)
    local points, big, rest, restOrder = Split(weights, block.adding)
    local half = (width - COLUMN_GAP) / 2
    for i, keys in ipairs({ points, big }) do
        local column = block.columns[i]
        column:SetPoint("TOPLEFT", (i - 1) * (half + COLUMN_GAP), -HEAD_H)
        column:SetSize(half, COLUMN_HEAD_H + #keys * ROW_H)
        FillColumn(block, column, keys, weights, half)
    end
    local add = block.add
    if not add then
        add = ns.UI.BuildDropdownControl(block, 220, nil, rest, restOrder, function() return CHOOSE end,
            function(stat) AddStat(block, stat) end)
        add:SetPoint("LEFT", block.addLabel, "RIGHT", 16, 0)
        block.add = add
    end
    add._values, add._order = rest, restOrder
    add._refreshLabel()
    local columnsH = COLUMN_HEAD_H + math.max(#points, #big) * ROW_H
    local preview = block.preview
    preview:SetPoint("TOPLEFT", 0, -(HEAD_H + columnsH + PREVIEW_GAP))
    preview:SetPoint("RIGHT")
    local previewH = FillPreview(preview, weights, spec.name)
    preview:SetHeight(previewH)
    block.sample:SetText(Sample(spec.name))
    return HEAD_H + columnsH + PREVIEW_GAP + previewH + FOOT_H
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
local function SpecRow()
    local talents = SW.TalentSpec()
    local values, order = { [AUTO] = talents and ("Automatic (%s)"):format(SW.Spec(talents).name)
        or "Automatic" }, { AUTO }
    for _, spec in ipairs(SW.ClassSpecs()) do
        values[spec.key] = spec.name
        order[#order + 1] = spec.key
    end
    return { type = "dropdown", text = "Your Spec", values = values, order = order,
        tooltip = "The spec your gear is weighed for. Automatic follows your talents: the tree with "
            .. "the most points (a druid's Feral is weighed for damage; pick Feral Tank for a bear).",
        getValue = function() return S.Get("spec") or AUTO end,
        setValue = function(key)
            S.Set("spec", key ~= AUTO and key or nil)
            Refresh()
        end }
end

function ns.BuildStatWeightsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:SectionHeader(parent, "STAT WEIGHTS" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("enabled", "Upgrades on Tooltips", "On gear that is an upgrade for your spec, a line saying by "
            .. "how much (\"+9% upgrade\"). The BiS List uses these "
            .. "weights either way."),
        SpecRow()); y = y - h
    if UI.searchScan then
        UI.ScanLabels({ "Stat weights", "Reset", "Import weights", "Export weights", "Add a stat" }, "What a point of each stat is worth to your spec.")
        return y
    end
    local block = UI.Keep(parent, "statWeightsBlock", MakeBlock)
    local width = parent:GetWidth() - UI.CONTENT_PAD * 2
    local height = FillBlock(block, width > 0 and width or 900)
    block:SetHeight(height)
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y - 8)
    block:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y - 8)
    return y - 8 - height
end
