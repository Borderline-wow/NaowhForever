-- FoodBar.lua: the Food & Drink Bar, your best food and drink on two buttons.
local ns = _G.NaowhForever

local UI = ns.UI
local S = ns.QoLSettings

local ICON_INSET = 1
local COUNT_SIZE, COUNT_INSET = 12, 2
local BLACK = ns.Shared.Style.BORDER_RGB
local DEFAULT_Y = -210
local BAR_BUTTONS = 2
local MOVER_LABEL = "Food & Drink"
local SETTINGS_PAGE, SETTINGS_CARD = "QoL/Loot & Items", "QoL/Loot & Items:foodBar"
local ITEM_LINK = "item:"
local SUMMARY = "%d px buttons"

local EMPTY = { { icon = 133971, text = "No food in your bags" },
    { icon = 132794, text = "No drink in your bags" } }
local GAP = 4
local STAGE_H = 100
local ICON_RANGE = { 20, 70, 1 }
local BUTTON_NAMES = { "NaowhForeverFoodBarFood", "NaowhForeverFoodBarDrink" }
local MOVED = { "foodBar", "foodBarSize", "foodBarPos" }

local bar, moving, pending
local events = CreateFrame("Frame")

local function Drinks()
    local class = select(2, UnitClass("player"))
    return class ~= "WARRIOR" and class ~= "ROGUE"
end

local function Migrate()
    local old, db = ns.SettingsRoot().macros, S.DB()
    if type(old) ~= "table" then return end
    for _, key in ipairs(MOVED) do
        if old[key] ~= nil and db[key] == nil then db[key] = old[key] end
        old[key] = nil
    end
end

local Look = {}

function Look.NewButton(parent, template, name)
    local button = CreateFrame("Button", name, parent, template)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(button.icon, ICON_INSET)
    button.count = ns.Font(button, COUNT_SIZE, "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", -COUNT_INSET, COUNT_INSET)
    ns.Border(button, BLACK)
    return button
end

function Look.Layout(frame, size)
    local shown = Drinks() and BAR_BUTTONS or 1
    frame:SetSize(size * shown + GAP * (shown - 1), size)
    for i, button in ipairs(frame.buttons) do
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", (i - 1) * (size + GAP), 0)
        button:SetShown(i <= shown)
    end
end

function Look.Fill(button, i, icon, count)
    button.icon:SetTexture(icon or EMPTY[i].icon)
    button.icon:SetDesaturated(not icon)
    button.count:SetText(count or "")
end

local function FillButton(button, i, id)
    if id ~= button.itemID then
        button.itemID = id
        button:SetAttribute("type1", id and "item" or nil)
        button:SetAttribute("item1", id and (ITEM_LINK .. id) or nil)
    end
    Look.Fill(button, i, id and (C_Item.GetItemIconByID(id) or EMPTY[i].icon), id and C_Item.GetItemCount(id))
end

local function Fill()
    local food, drink = ns.BestFoodAndDrink()
    FillButton(bar.buttons[1], 1, food)
    FillButton(bar.buttons[2], 2, Drinks() and drink or nil)
end

local function ButtonEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.itemID then
        GameTooltip:SetItemByID(self.itemID)
    else
        GameTooltip:SetText(EMPTY[self.emptyIndex].text)
    end
    GameTooltip:Show()
end

local function ButtonLeave()
    GameTooltip:Hide()
end

local function SavePosition(pos)
    S.Set("foodBarPos", pos)
end

local function Build()
    bar = CreateFrame("Frame", "NaowhForeverFoodBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar.buttons = {}
    for i = 1, BAR_BUTTONS do
        local button = Look.NewButton(bar, "SecureActionButtonTemplate", BUTTON_NAMES[i])
        button.emptyIndex = i
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetScript("OnEnter", ButtonEnter)
        button:SetScript("OnLeave", ButtonLeave)
        bar.buttons[i] = button
    end
    bar.mover = UI.AttachMover(bar, MOVER_LABEL, SavePosition, SETTINGS_PAGE, SETTINGS_CARD)
end

local function Place()
    bar:ClearAllPoints()
    local pos = S.Get("foodBarPos")
    if pos then bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else bar:SetPoint("CENTER", UIParent, "CENTER", 0, DEFAULT_Y) end
end

local function Apply()
    Migrate()
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pending = false
    if not (S.Get("enabled") and S.Get("foodBar")) then
        events:UnregisterAllEvents()
        if bar then bar:Hide() end
        return
    end
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    if not bar then Build() end
    Look.Layout(bar, S.Get("foodBarSize"))
    Place()
    Fill()
    bar.mover:SetShown(moving == true)
    bar:Show()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not pending then return end
    elseif event == "BAG_UPDATE_DELAYED" and bar and bar:IsShown() and not InCombatLockdown() then
        Fill()
        return
    end
    Apply()
end

local function OnSettingChanged(key)
    if key == "enabled" or (key:find("^foodBar") and key ~= "foodBarPos") then Apply() end
end

events:SetScript("OnEvent", OnEvent)
events:RegisterEvent("PLAYER_ENTERING_WORLD")
hooksecurefunc(S, "Set", OnSettingChanged)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", function() moving = true; Apply() end)
hooksecurefunc(ns, "HideUnlockMode", function() moving = false; Apply() end)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local Group = Settings.Group
local SAMPLE_COUNTS = { 12, 20 }
local STATES = {
    { key = "stocked", label = "Stocked", tip = "Your best food and drink, with how many you carry." },
    { key = "empty", label = "Nothing Carried", tip = "Greyed out while your bags hold no food or drink." },
}

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetPoint("CENTER")
    preview.buttons = { Look.NewButton(preview), Look.NewButton(preview) }
    return preview
end

local function PaintPreview(preview, state)
    Look.Layout(preview, S.Get("foodBarSize"))
    local stocked = state == "stocked"
    for i, button in ipairs(preview.buttons) do
        Look.Fill(button, i, stocked and EMPTY[i].icon or nil, stocked and SAMPLE_COUNTS[i] or nil)
    end
end

local function NoDrinks()
    return not Drinks()
end

local function Summary(store)
    return SUMMARY:format(store.Get("foodBarSize"))
end

Settings.Page("QoL/Loot & Items", S):Card({
    id = "foodBar", name = "Food & Drink Bar", order = 55, switch = "foodBar",
    help = "Buttons for the best food and drink in your bags, conjured first; food only if you have "
        .. "no mana. Move it in the HUD Editor.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "foodBarSize", label = "Icon Size", slider = ICON_RANGE,
          help = "How big each button is." },
        Group("Key Bindings"),
        { label = "Use Best Food", binding = "CLICK NaowhForeverFoodBarFood:LeftButton",
          help = "Eats the food on the bar." },
        { label = "Use Best Drink", binding = "CLICK NaowhForeverFoodBarDrink:LeftButton",
          hidden = NoDrinks, help = "Drinks the drink on the bar." },
    },
})
