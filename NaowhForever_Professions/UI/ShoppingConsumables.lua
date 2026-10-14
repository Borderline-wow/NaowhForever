-- ShoppingConsumables.lua: the Consumables picker beside the Shopping List: food, flasks, elixirs and more that suit you, put on the list by the amount.
local ns = _G.NaowhForever

local T = ns.THEME
local Shared = ns.Shared
local Parts, Items = Shared.Parts, Shared.Items

local P = ns.Professions
local Shopping = P.Shopping
local Consumables = P.Consumables
local Text = P.Text
local Style = P.Style
local Widgets = P.Widgets

local ROW_H = 20
local ROW_SHRINK = 2
local ICON_SHRINK = Style.ROW_ICON_SHRINK
local NAME_GAP = Style.ICON_NAME_GAP
local SMALL_BUTTON = 16
local QTY_W, QTY_H = 44, 18
local QTY_LETTERS = #tostring(P.C.MAX_ITEMS)
local STEP_GAP, NOTE_GAP = 2, 6
local HEAD_X, HEAD_STEP, GROUP_GAP, TOP_GAP = 4, 18, 8, 2
local CHECK_GAP, TITLE_GAP = 6, 8
local FULL_OPACITY = 1
local SEPARATOR = "  "
local LATER_CODE, BEST_CODE, END_CODE = Text.Hex(Style.RED_RGB), Text.Hex(Style.READY_RGB), "|r"
local EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP" }
local TEXT_TITLE = ns.L("Consumables")
local TEXT_MINE = ns.L("Only for my class")
local TEXT_EMPTY = ns.L("No consumables to show yet.")
local TEXT_BEST = ns.L("Best")
local TEXT_LEVEL = ns.L("Lv %d")
local TEXT_OWNED = ns.L("(%d owned)")
local GROUP_NAMES = {
    food = ns.L("Food & Drink"), flask = ns.L("Flasks"), elixir = ns.L("Elixirs"), potion = ns.L("Potions"),
    scroll = ns.L("Scrolls"), weapon = ns.L("Weapon Enhancements"), bandage = ns.L("Bandages"),
}
local TIP_MINE, TIP_MINE_HELP = ns.L("Only for My Class"),
    ns.L("Shows what suits your class and level, or everything when off.")
local TIP_MORE, TIP_MORE_HELP = ns.L("One More"), ns.L("Puts one more on the shopping list.")
local TIP_FEWER, TIP_FEWER_HELP = ns.L("One Fewer"), ns.L("Takes one off the shopping list.")
local TIP_QTY, TIP_QTY_HELP = ns.L("How Many"), ns.L("How many the shopping list buys.")

local panel, body, empty, only, events
local rows, heads = {}, {}
local shownRows = 0
local queued, repick, newLevel = false, false, nil

local function Opacity()
    return FULL_OPACITY
end

local function NewBody(scroll)
    body = CreateFrame("Frame", nil, scroll)
    return body
end

local function Listed(id)
    return Shopping.Manual()[id] or 0
end

local function OnRowEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.id)
    GameTooltip:Show()
end

local function OnlyMine()
    return not ns.AccountSettings().profShopAllConsumables
end

local function OnQtyEnter(box)
    local id = box:GetParent().id
    box:ClearFocus()
    Shopping.SetItem(id, tonumber(box:GetText()) or 0)
    box:SetText(tostring(Listed(id)))
end

local function OnQtyEscape(box)
    box:SetText(tostring(Listed(box:GetParent().id)))
    box:ClearFocus()
end

local function NewRow()
    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(ROW_H - ROW_SHRINK)
    row:EnableMouse(true)
    row.icon = Widgets.Crop(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetSize(ROW_H - ICON_SHRINK, ROW_H - ICON_SHRINK)
    row.icon:SetPoint("LEFT")
    row.plus = ns.Button(row, "+", SMALL_BUTTON, SMALL_BUTTON, function() Shopping.AddItem(row.id, 1) end)
    row.plus:SetPoint("RIGHT")
    ns.Tooltip(row.plus, TIP_MORE, TIP_MORE_HELP)
    row.qty = Widgets.QtyBox(row)
    row.qty:SetSize(QTY_W, QTY_H)
    row.qty:SetMaxLetters(QTY_LETTERS)
    row.qty:SetPoint("RIGHT", row.plus, "LEFT", -STEP_GAP, 0)
    row.qty:SetScript("OnEnterPressed", OnQtyEnter)
    row.qty:SetScript("OnEscapePressed", OnQtyEscape)
    ns.Tooltip(row.qty, TIP_QTY, TIP_QTY_HELP)
    row.minus = ns.Button(row, "-", SMALL_BUTTON, SMALL_BUTTON, function()
        Shopping.SetItem(row.id, Listed(row.id) - 1)
    end)
    row.minus:SetPoint("RIGHT", row.qty, "LEFT", -STEP_GAP, 0)
    ns.Tooltip(row.minus, TIP_FEWER, TIP_FEWER_HELP)
    row.note = ns.Font(row, Style.FONT_SMALL, nil, T.muted)
    row.note:SetJustifyH("RIGHT")
    row.note:SetPoint("RIGHT", row.minus, "LEFT", -NOTE_GAP, 0)
    row.name = ns.Font(row, Style.FONT, nil)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", NAME_GAP, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -NAME_GAP, 0)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function Head(i)
    local head = heads[i]
    if head then return head end
    head = ns.Font(body, Style.FONT, nil, Style.GOLD_RGB)
    heads[i] = head
    return head
end

local function Note(e)
    local level = TEXT_LEVEL:format(e.level)
    if e.later then level = LATER_CODE .. level .. END_CODE end
    local note = level .. SEPARATOR .. TEXT_OWNED:format(C_Item.GetItemCount(e.id, true) or 0)
    if e.best then note = BEST_CODE .. TEXT_BEST .. END_CODE .. SEPARATOR .. note end
    return note
end

local function FillCounts(row)
    local e = row.entry
    row.note:SetText(Note(e))
    local listed = Listed(e.id)
    if not row.qty:HasFocus() then row.qty:SetText(tostring(listed)) end
    Widgets.EnableButton(row.minus, listed > 0)
end

local function FillRow(row, e)
    row.id, row.entry = e.id, e
    row.icon:SetTexture(C_Item.GetItemIconByID(e.id))
    row.name:SetText(Items.QualityHex(e.id) .. Items.Name(e.id) .. END_CODE)
    FillCounts(row)
end

local function PlaceHead(head, y)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", HEAD_X, y)
    head:Show()
    return y - HEAD_STEP
end

local function PlaceRow(row, y)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:Show()
    return y - ROW_H
end

local function Repick()
    local _, class = UnitClass("player")
    local groups = Consumables.Pick(newLevel or UnitLevel("player"), class, OnlyMine(), ns.UsesMana())
    newLevel = nil
    local y, n = -TOP_GAP, 0
    for i, group in ipairs(groups) do
        if i > 1 then y = y - GROUP_GAP end
        local head = Head(i)
        head:SetText(GROUP_NAMES[group.key])
        y = PlaceHead(head, y)
        for _, e in ipairs(group.rows) do
            n = n + 1
            rows[n] = rows[n] or NewRow()
            local row = rows[n]
            FillRow(row, e)
            y = PlaceRow(row, y)
        end
    end
    for i = #groups + 1, #heads do heads[i]:Hide() end
    for i = n + 1, #rows do rows[i]:Hide() end
    shownRows = n
    body:SetHeight(math.max(1, -y))
    empty:SetShown(n == 0)
end

local function Refresh()
    for i = 1, shownRows do FillCounts(rows[i]) end
end

local function Flush()
    queued = false
    if not (panel and panel:IsShown()) then return end
    if repick then
        repick = false
        Repick()
    else
        Refresh()
    end
end

local function Queue(full)
    if not (panel and panel:IsShown()) then return end
    if full then repick = true end
    if queued then return end
    queued = true
    C_Timer.After(0, Flush)
end

local function Repicked()
    Queue(true)
end

local function Recount()
    Queue(false)
end

local function OnEvent(_, event, level)
    if event == "PLAYER_LEVEL_UP" then
        newLevel = level
        return Repicked()
    end
    Recount()
end

local function OnMine(box)
    ns.AccountSettings().profShopAllConsumables = not box:GetChecked() or nil
    panel.scroll:SetVerticalScroll(0)
    Repick()
end

local function OnShow()
    for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
end

local function OnHide()
    events:UnregisterAllEvents()
end

local function Build()
    panel = Parts.SidePanel({}, NewBody, Opacity)
    only = Widgets.CheckBox(panel)
    only.text = ns.Font(panel, Style.FONT, nil)
    only.text:SetPoint("RIGHT", panel.close, "LEFT", -TITLE_GAP, 0)
    only.text:SetText(TEXT_MINE)
    only:SetPoint("RIGHT", only.text, "LEFT", -CHECK_GAP, 0)
    only:SetChecked(OnlyMine())
    only:SetScript("OnClick", OnMine)
    ns.Tooltip(only, TIP_MINE, TIP_MINE_HELP)
    panel.title:SetText(TEXT_TITLE)
    panel.title:SetPoint("RIGHT", only, "LEFT", -TITLE_GAP, 0)
    empty = ns.Font(panel, Style.FONT, nil, T.muted)
    empty:SetPoint("CENTER", panel.scroll, "CENTER")
    empty:SetText(TEXT_EMPTY)
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", OnEvent)
    panel:HookScript("OnShow", OnShow)
    panel:HookScript("OnHide", OnHide)
    panel:Hide()
    Items.OnLoaded(Consumables.IDs(), Repicked)
end

function Shopping.ToggleConsumables(from)
    if panel and panel:IsShown() then return panel:Hide() end
    if not panel then Build() end
    Parts.ShowBeside(panel, from)
    repick = false
    Repick()
end

Shopping.OnChange(Recount)
