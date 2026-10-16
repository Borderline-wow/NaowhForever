-- ShoppingVendor.lua: Shopping List materials sold by the open merchant, with click-to-buy controls.
local ns = _G.NaowhForever

local T = ns.THEME
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local P = ns.Professions
local S = P.Settings
local V = P.Vendors
local Shopping = P.Shopping
local Text = P.Text
local Style = P.Style
local Widgets = P.Widgets

local PAGE = "Professions/Settings"
local WIDTH = 380
local MAX_VISIBLE = 8
local HEADER, PAD, FOOTER, SCROLLBAR = St.WINDOW_HEADER, St.WINDOW_PAD, St.WINDOW_FOOTER, St.SCROLLBAR
local INSET = St.CONTENT_INSET
local CARD_INSET = 6
local BOTTOM_H = 34
local SCROLL_GAP = 4
local ROW_H = 24
local ROW_SHRINK = 2
local ICON_SHRINK = Style.ROW_ICON_SHRINK
local NAME_GAP, NOTE_GAP = Style.ICON_NAME_GAP, Style.NOTE_GAP
local BUY_W, BUY_ALL_W = 52, 126
local BUTTON_H = 24
local VENDOR_GAP = 8
local SHOW_DELAY = 0
local TEXT_TITLE = ns.L("Buy from Vendor")
local TEXT_SUBTITLE = ns.L("Shopping List materials sold here.")
local TEXT_BUY = ns.L("Buy")
local TEXT_BUY_ALL = ns.L("Buy All (%s)")
local TEXT_ROW = "%dx %s"
local TEXT_ITEM = ns.L("item ")
local TEXT_TOTAL = ns.L("Total: %s")
local TEXT_ONLY = ns.L("Only %d of %d available; %s")
local TEXT_BUNDLE = ns.L("Buys %d; %s")
local TIP_BUY_HELP = ns.L("Buys this Shopping List shortage from the current vendor.")
local TIP_BUY_ALL_HELP = ns.L("Buys every Shopping List shortage sold by this vendor.")

local View = {}
P.ShoppingVendorView = View

local window, scroll, content, totalText, buyAll
local rows = {}
local dismissed, hiding = false, false
local Render

local function On()
    return S.Get("enabled") and S.Get("shoppingList") and S.Get("shoppingVendor")
end

local function ProgrammaticHide()
    if not window then return end
    hiding = true
    window:Hide()
    hiding = false
end

local function Place()
    if not (window and _G.MerchantFrame) then return end
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", VENDOR_GAP, 0)
end

local function OnRowEnter(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.item)
    GameTooltip:Show()
end

local function Purchase(itemID)
    if V.Waiting() then return end
    V.BuyShoppingItem(itemID)
    Render()
end

local function PurchaseAll()
    if V.Waiting() then return end
    V.BuyShoppingAll()
    Render()
end

local function NewRow(index)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H - ROW_SHRINK)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_H)
    row:EnableMouse(true)
    row.icon = Widgets.Crop(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetSize(ROW_H - ICON_SHRINK, ROW_H - ICON_SHRINK)
    row.icon:SetPoint("LEFT")
    row.buy = ns.Button(row, TEXT_BUY, BUY_W, ROW_H - ROW_SHRINK, function()
        if row.item then Purchase(row.item) end
    end)
    row.buy:SetPoint("RIGHT")
    ns.Tooltip(row.buy, TEXT_BUY, TIP_BUY_HELP)
    row.note = ns.Font(row, Style.FONT_SMALL, nil, T.muted)
    row.note:SetPoint("RIGHT", row.buy, "LEFT", -NOTE_GAP, 0)
    row.note:SetJustifyH("RIGHT")
    row.note:SetWordWrap(false)
    row.name = ns.Font(row, Style.FONT, nil)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", NAME_GAP, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -NAME_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[index] = row
    return row
end

local function Fill(list)
    for index = 1, math.max(#list, #rows) do
        local entry = list[index]
        local row = (entry or rows[index]) and (rows[index] or NewRow(index))
        if entry then
            local name = Shopping.ItemName(entry.itemID) or (TEXT_ITEM .. entry.itemID)
            row.item = entry.itemID
            row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemID))
            row.name:SetText(TEXT_ROW:format(entry.want, name))
            local cost = Text.Short(entry.cost)
            if entry.short then
                row.note:SetText(Style.ALERT_CODE .. TEXT_ONLY:format(entry.count, entry.want, cost) .. "|r")
            elseif entry.count > entry.want then
                row.note:SetText(TEXT_BUNDLE:format(entry.count, cost))
            else
                row.note:SetText(cost)
            end
            Widgets.EnableButton(row.buy, not V.Waiting() and GetMoney() >= entry.cost)
            row:Show()
        elseif row then
            row.item = nil
            row:Hide()
        end
    end
end

local function BuildBody()
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", INSET, -(HEADER + PAD))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - SCROLL_GAP, FOOTER + PAD + BOTTOM_H)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - INSET - SCROLLBAR - SCROLL_GAP, 1)
    scroll:SetScrollChild(content)
end

local function BuildFooter()
    buyAll = ns.Button(window, TEXT_BUY_ALL:format(""), BUY_ALL_W, BUTTON_H, PurchaseAll)
    buyAll:SetPoint("BOTTOMRIGHT", -INSET, FOOTER + PAD)
    ns.AccentBorder(buyAll)
    ns.Tooltip(buyAll, TEXT_TITLE, TIP_BUY_ALL_HELP)
    totalText = ns.Font(window, Style.FONT_SMALL, nil, T.muted)
    totalText:SetPoint("LEFT", window, "BOTTOMLEFT", INSET, FOOTER + PAD + BUTTON_H / 2)
    totalText:SetPoint("RIGHT", buyAll, "LEFT", -NOTE_GAP, 0)
    totalText:SetJustifyH("LEFT")
    totalText:SetWordWrap(false)
end

local function OnHide()
    if not hiding and On() and V.Open() then dismissed = true end
end

local function Build()
    window = Parts.Window(WIDTH, HEADER + PAD * 2 + ROW_H + BOTTOM_H + FOOTER, "shoppingVendorWindow")
    window:SetFrameStrata("DIALOG")
    window.backdrop:Card(CARD_INSET, HEADER + CARD_INSET, CARD_INSET, FOOTER + CARD_INSET)
    Parts.TitleBar(window, TEXT_TITLE, TEXT_SUBTITLE, PAGE)
    Parts.FooterBrand(window, PAGE)
    BuildBody()
    BuildFooter()
    window:HookScript("OnHide", OnHide)
end

Render = function()
    if not (On() and V.Open()) or dismissed then return ProgrammaticHide() end
    local list, total = V.ShoppingNeeds()
    if #list == 0 then return ProgrammaticHide() end
    if not window then Build() end
    Fill(list)
    local visible = math.min(#list, MAX_VISIBLE)
    content:SetHeight(math.max(1, #list * ROW_H))
    window:SetHeight(HEADER + PAD * 2 + visible * ROW_H + BOTTOM_H + FOOTER)
    totalText:SetText(TEXT_TOTAL:format(Text.Short(total)))
    ns.SetButtonText(buyAll, TEXT_BUY_ALL:format(Text.Short(total)))
    Widgets.EnableButton(buyAll, not V.Waiting() and GetMoney() >= total)
    Place()
    window:SetScale(ns.UIScale())
    window:Show()
    window.backdrop:Paint(1)
end

local function OnMerchantEvent(event)
    if event == "MERCHANT_SHOW" then
        dismissed = false
        return C_Timer.After(SHOW_DELAY, Render)
    end
    if event == "MERCHANT_CLOSED" then
        dismissed = false
        return ProgrammaticHide()
    end
    Render()
end

function View.OnMerchantEvent(event)
    OnMerchantEvent(event)
end

function View.Hide()
    ProgrammaticHide()
end

Shopping.OnChange(Render)
if On() and V.Open() then C_Timer.After(SHOW_DELAY, Render) end
