-------------------------------------------------------------------------------
--  NaowhForever_FoodBar.lua -- the Food & Drink Bar: one button for the best food and one for
--  the best drink in your bags, food only for classes without mana. Also ns.BestFoodAndDrink,
--  which the Macros module's NF Food uses.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local S = ns.QoLSettings

local CONJURED = {
    [8079] = true, [8078] = true, [8077] = true, [3772] = true, [2136] = true, [2288] = true,
    [5350] = true, [22895] = true, [8076] = true, [8075] = true, [1487] = true, [1114] = true,
    [1113] = true, [5349] = true,
}
local FOOD_SPELL, DRINK_SPELL = 433, 430
local EMPTY = { { icon = 133971, text = "No food in your bags" },
    { icon = 132794, text = "No drink in your bags" } }
local GAP = 4
local BUTTON_NAMES = { "NaowhForeverFoodBarFood", "NaowhForeverFoodBarDrink" }
-- The bar was on the Macros page until 0.5.24; a profile's settings for it move here once.
local MOVED = { "foodBar", "foodBarSize", "foodBarPos" }

local bar, moving, pending
local events = CreateFrame("Frame")

-- Key Bindings > Naowh Forever (Bindings.xml). The buttons exist once the bar is switched on.
_G["BINDING_NAME_CLICK NaowhForeverFoodBarFood:LeftButton"] = "Use Best Food"
_G["BINDING_NAME_CLICK NaowhForeverFoodBarDrink:LeftButton"] = "Use Best Drink"

-- Best food and best drink in the bags: conjured first, then the highest required level.
local function BestFoodAndDrink()
    local foodName, drinkName = C_Spell.GetSpellName(FOOD_SPELL), C_Spell.GetSpellName(DRINK_SPELL)
    local food, drink, foodScore, drinkScore
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            local spell = id and C_Item.GetItemSpell(id)
            if spell and (spell == foodName or spell == drinkName) then
                local s = (CONJURED[id] and 1000 or 0) + (select(5, C_Item.GetItemInfo(id)) or 0)
                if spell == foodName then
                    if not foodScore or s > foodScore then food, foodScore = id, s end
                elseif not drinkScore or s > drinkScore then
                    drink, drinkScore = id, s
                end
            end
        end
    end
    return food, drink
end
ns.BestFoodAndDrink = BestFoodAndDrink

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
    ns.PixelInset(button.icon, 1)
    button.count = ns.Font(button, 12, "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    ns.Border(button, { r = 0, g = 0, b = 0 })
    return button
end

function Look.Layout(frame, size)
    local shown = Drinks() and 2 or 1
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
        button:SetAttribute("item1", id and ("item:" .. id) or nil)
    end
    Look.Fill(button, i, id and (C_Item.GetItemIconByID(id) or EMPTY[i].icon), id and C_Item.GetItemCount(id))
end

local function Fill()
    local food, drink = BestFoodAndDrink()
    FillButton(bar.buttons[1], 1, food)
    FillButton(bar.buttons[2], 2, Drinks() and drink or nil)
end

local function Build()
    bar = CreateFrame("Frame", "NaowhForeverFoodBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar.buttons = {}
    for i = 1, 2 do
        local button = Look.NewButton(bar, "SecureActionButtonTemplate", BUTTON_NAMES[i])
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID then
                GameTooltip:SetItemByID(self.itemID)
            else
                GameTooltip:SetText(EMPTY[i].text)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.buttons[i] = button
    end
    bar.mover = UI.AttachMover(bar, "Food & Drink", function(pos) S.Set("foodBarPos", pos) end,
        "QoL/Loot & Items", "QoL/Loot & Items:foodBar")
end

-- The buttons are secure, so the bar is built, shown, hidden and pointed at items out of combat.
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
    bar:ClearAllPoints()
    local pos = S.Get("foodBarPos")
    if pos then bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -210) end
    Fill()
    bar.mover:SetShown(moving == true)
    bar:Show()
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not pending then return end
    elseif event == "BAG_UPDATE_DELAYED" and bar and bar:IsShown() and not InCombatLockdown() then
        Fill()
        return
    end
    Apply()
end)
events:RegisterEvent("PLAYER_ENTERING_WORLD")
hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^foodBar") and key ~= "foodBarPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function() moving = true; Apply() end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function() moving = false; Apply() end)

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

local function Summary(store)
    return ("%d px buttons"):format(store.Get("foodBarSize"))
end

Settings.Page("QoL/Loot & Items", S):Card({
    id = "foodBar", name = "Food & Drink Bar", order = 55, switch = "foodBar",
    help = "Buttons for the best food and drink in your bags, conjured first; food only if you have "
        .. "no mana. Move it in the HUD Editor.",
    summary = Summary,
    studio = { height = 100, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "foodBarSize", label = "Icon Size", slider = { 20, 70, 1 },
          help = "How big each button is." },
        Group("Key Bindings"),
        { label = "Use Best Food", binding = "CLICK NaowhForeverFoodBarFood:LeftButton",
          help = "Eats the food on the bar." },
        { label = "Use Best Drink", binding = "CLICK NaowhForeverFoodBarDrink:LeftButton",
          hidden = function() return not Drinks() end, help = "Drinks the drink on the bar." },
    },
})
