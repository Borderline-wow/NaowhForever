-------------------------------------------------------------------------------
--  NaowhForever_GearSetsWindow.lua -- the Gear Sets window (/nfgear, its minimap and top bar
--  button, Open Gear Sets on its settings page): your equipment sets, the ones the character
--  sheet keeps, each with Equip, Save, Rename, Icon and Delete, and New Gear Set at the top.
--  Built from the shared window parts the first time it opens; listens only while open.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local Gear = ns.GearSets
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 680, 560
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR = St.CONTENT_INSET, St.SCROLLBAR
local PAGE = "Gear & Trinkets/Settings"
local CARD = 6
local NEW_W, NEW_H = 150, 26
local ROW_H, ICON, ICON_GAP = 52, 36, 12
local ACTION_W, ACTION_H, ACTION_GAP = 64, 22, 4
local NAME_SIZE, STATUS_SIZE, LINE_GAP = 13, 11, 3
local BLACK = { r = 0, g = 0, b = 0 }
local MISSING_RGB = { r = 0.97, g = 0.44, b = 0.44 }
local EVENTS = { "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SWAP_FINISHED" }
local NO_SETS = "No gear sets yet. New Gear Set saves what you wear now as one."

local window, scroll, view, kinds

local ACTIONS = {
    { "Equip", function(set) Gear.EquipByHand(set.id) end },
    { "Save", function(set) ns.SaveGearSet(set.id, set.name) end },
    { "Rename", function(set) ns.RenameGearSet(set.id, set.name) end },
    { "Icon", function(set) ns.ChangeGearSetIcon(set.id, set.name) end },
    { "Delete", function(set) ns.DeleteGearSet(set.id, set.name) end },
}
local ACTION_TIPS = {
    Equip = "Puts this set on. In combat, it goes on when the fight ends.",
    Save = "Saves what you are wearing now into this set.",
    Rename = "Renames the set; Wear While Mounted and Resting follow it.",
    Icon = "Picks a new icon for the set.",
    Delete = "Deletes the set. Asks first.",
}

local function Opacity()
    return math.floor((S.Get("gearWindowAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("gearWindowAlpha", value / 100)
end

local function NewSet(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.stripe = ns.Solid(row, "BACKGROUND", T.fg, St.STRIPE)
    row.stripe:SetAllPoints()
    row.icon = CreateFrame("Frame", nil, row)
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", St.INDENT, 0)
    row.icon.texture = row.icon:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(row.icon.texture, 1)
    row.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon.edge = ns.Border(row.icon, BLACK)
    row.actions = {}
    local right = nil
    for i = #ACTIONS, 1, -1 do
        local action = ACTIONS[i]
        local button = ns.Button(row, action[1], ACTION_W, ACTION_H, function() action[2](row.set) end)
        ns.Tooltip(button, action[1], ACTION_TIPS[action[1]])
        if right then
            button:SetPoint("RIGHT", right, "LEFT", -ACTION_GAP, 0)
        else
            button:SetPoint("RIGHT", -St.INDENT, 0)
        end
        right = button
        row.actions[i] = button
    end
    row.name = ns.Font(row, NAME_SIZE, nil, T.fg)
    row.name:SetPoint("BOTTOMLEFT", row.icon, "RIGHT", ICON_GAP, LINE_GAP / 2)
    row.name:SetPoint("RIGHT", right, "LEFT", -ICON_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.status = ns.Font(row, STATUS_SIZE, nil, T.muted)
    row.status:SetPoint("TOPLEFT", row.icon, "RIGHT", ICON_GAP, -LINE_GAP / 2)
    row.status:SetJustifyH("LEFT")
    return row
end

local function SetSet(row, set, stripe)
    row.set = set
    row.stripe:SetShown(stripe)
    row.icon.texture:SetTexture(set.icon)
    row.icon.texture:SetDesaturated(set.lost > 0)
    local edge = set.equipped and T.accent or BLACK
    row.icon.edge:SetColor(edge.r, edge.g, edge.b, 1)
    row.name:SetText(set.name)
    local color = T.muted
    local status = set.items == 1 and "1 item" or (set.items .. " items")
    if set.lost > 0 then
        status, color = set.lost .. " missing", MISSING_RGB
    elseif set.equipped then
        status, color = "Equipped", St.HAVE_RGB
    end
    row.status:SetText(status)
    row.status:SetTextColor(color.r, color.g, color.b)
    return ROW_H
end

local Draw = {}

function Draw:Redraw()
    self:Clear()
    local sets = Gear.Sets()
    for i, set in ipairs(sets) do self:Add("set", set, i % 2 == 0) end
    if #sets == 0 then self:Note(NO_SETS) end
    window.note.text:SetText(#sets == 1 and "1 set" or (#sets .. " sets"))
    window.note:SetWidth(math.max(1, math.ceil(window.note.text:GetStringWidth())))
    self:Fit(EVENTS)
end

local function Kinds()
    if kinds then return kinds end
    kinds = Shared.View.NewKinds()
    kinds.set = { New = NewSet, Set = SetSet }
    return kinds
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "gearSetsWindow")
    window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD)
    local close = Parts.TitleBar(window, "Gear Sets", "Your equipment sets, the same ones the character sheet keeps.",
        PAGE)
    local _, opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    window.opacity = opacity
    Parts.FooterBrand(window, PAGE)
    window.note = Parts.FooterNote(window, "")

    local left, top = CARD + INSET, HEADER + CARD + PAD
    local new = ns.AccentBorder(ns.Button(window, "New Gear Set", NEW_W, NEW_H, ns.NewGearSet))
    ns.Tooltip(new, "New Gear Set", "Saves what you are wearing now as a new set.")
    new:SetPoint("TOPLEFT", left, -top)
    top = top + NEW_H + PAD
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + 4), FOOTER + CARD + PAD)
    view = Shared.View.New(scroll, Kinds(), Draw)
    view:SetWidth(WIDTH - left - CARD - SCROLLBAR - INSET)
    scroll:SetScrollChild(view)
end

local function Paint()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
end

S.OnChange(function(key)
    if key == "gearWindowAlpha" and window and window:IsShown() then Paint() end
end)

hooksecurefunc(ns, "Apply", function()
    if window and window:IsShown() then
        Paint()
        view:Redraw()
    end
end)

function ns.OpenGearSetsWindow()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Paint()
    view:Redraw()
end

function ns.ToggleGearSetsWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenGearSetsWindow() end
end
