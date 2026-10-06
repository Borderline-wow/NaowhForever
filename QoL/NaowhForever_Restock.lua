-------------------------------------------------------------------------------
--  NaowhForever_Restock.lua -- the QoL restock module: a reminder in rested areas when low on
--  reagents, ammo or food, and buying, selling junk and repairing at a vendor.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

-- Class spells that use a vendor reagent on Forever, from its SpellReagents data
-- (build 1.60.1.69913). Each family lists its ranks from lowest; the highest rank you know
-- sets the reagent, so a rank 2 Prayer of Fortitude asks for Sacred Candles, not Holy.
local FAMILIES = {
    { class = "DRUID", { 20484, 17034 }, { 20739, 17035 }, { 20742, 17036 }, { 20747, 17037 },
      { 20748, 17038 } },                                         -- Rebirth
    { class = "DRUID", { 21849, 17021 }, { 21850, 17026 } },      -- Gift of the Wild
    { class = "MAGE", { 23028, 17020 } },                         -- Arcane Brilliance
    { class = "MAGE", { 3561, 17031 }, { 3562, 17031 }, { 3563, 17031 }, { 3565, 17031 },
      { 3566, 17031 }, { 3567, 17031 }, { 1297659, 17031 } },     -- Teleports
    { class = "MAGE", { 10059, 17032 }, { 11416, 17032 }, { 11417, 17032 }, { 11418, 17032 },
      { 11419, 17032 }, { 11420, 17032 } },                       -- Portals
    { class = "PALADIN", { 19752, 17033 } },                      -- Divine Intervention
    { class = "PALADIN", { 25782, 21177 }, { 25916, 21177 }, { 25890, 21177 }, { 25894, 21177 },
      { 25918, 21177 }, { 25895, 21177 }, { 25898, 21177 } },     -- Greater Blessings
    { class = "PRIEST", { 21562, 17028 }, { 21564, 17029 } },     -- Prayer of Fortitude
    { class = "PRIEST", { 27681, 17029 } },                       -- Prayer of Spirit
    { class = "PRIEST", { 27683, 17029 } },                       -- Prayer of Shadow Protection
    { class = "SHAMAN", { 20608, 17030 }, { 21169, 17030 }, { 27740, 17030 } }, -- Reincarnation
    { class = "WARLOCK", { 18540, 16583 } },                      -- Ritual of Doom
    { class = "WARLOCK", { 1122, 5565 }, { 24670, 5565 } },       -- Inferno
    { class = "ROGUE", { 1856, 5140 }, { 1857, 5140 }, { 27617, 5140 }, { 457437, 5140 },
      { 1285372, 5140 } },                                        -- Vanish
}

-- How many of each reagent to carry, unless the player sets their own.
local TARGETS = {
    [17034] = 5, [17035] = 5, [17036] = 5, [17037] = 5, [17038] = 5,
    [17021] = 20, [17026] = 20,
    [17020] = 20, [17031] = 10, [17032] = 10,
    [17033] = 5, [21177] = 100,
    [17028] = 20, [17029] = 20,
    [17030] = 5,
    [16583] = 5, [5565] = 5,
    [5140] = 20,
}

local AMMO_SLOT = 0
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5   -- Consumable: Food & Drink

local alert, flash
local wasResting
local pendingItems = {}

local function On()
    return S.Get("enabled") and S.Get("restock")
end

local function ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

local function Target(itemID)
    return S.Get("restockTarget" .. itemID) or TARGETS[itemID]
end

-- itemID -> quantity wanted: the reagents for the spells you know, plus your equipped ammo.
local function Wanted()
    local want = {}
    if S.Get("restockReagents") then
        for _, family in ipairs(FAMILIES) do
            local item
            for _, rank in ipairs(family) do
                if C_SpellBook.IsSpellKnown(rank[1]) then item = rank[2] end
            end
            if item and Target(item) > 0 then want[item] = Target(item) end
        end
    end
    -- Forever reports an empty ammo slot as item 0, not nil.
    local ammo = S.Get("restockAmmo") and GetInventoryItemID("player", AMMO_SLOT)
    if ammo and ammo > 0 then want[ammo] = S.Get("restockAmmoTarget") end
    return want
end

-- Food and drink carried, junk to sell and free bag slots, in one pass over the bags.
local function ScanBags()
    local food, drink, junk, free = 0, 0, 0, 0
    local drinkSpell = C_Item.GetItemSpell(159) -- Refreshing Spring Water; localized Drink spell name.
    for bag = 0, NUM_BAG_SLOTS do
        -- Quivers, ammo pouches and soul bags do not count as room.
        local slots, bagType = C_Container.GetContainerNumFreeSlots(bag)
        if bagType == 0 then free = free + slots end
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                if info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                    junk = junk + 1
                end
                local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
                if classID == FOOD_CLASS and subclassID == FOOD_SUBCLASS then
                    local _, _, _, _, level = C_Item.GetItemInfo(info.itemID)
                    if not level then
                        if not pendingItems[info.itemID] then
                            pendingItems[info.itemID] = true
                            C_Item.RequestLoadItemDataByID(info.itemID)
                        end
                    elseif level >= (S.Get("restockFoodMinLevel") or 0)
                        and level <= (S.Get("restockFoodMaxLevel") or 60) then
                        local spell = C_Item.GetItemSpell(info.itemID)
                        if drinkSpell and spell == drinkSpell then
                            drink = drink + info.stackCount
                        else
                            food = food + info.stackCount
                        end
                    end
                end
            end
        end
    end
    return food, junk, free, drink
end

-- A target slider for each reagent your class uses, for the options page.
function ns.RestockReagentSliders()
    local class = select(2, UnitClass("player"))
    local sliders, seen = {}, {}
    for _, family in ipairs(FAMILIES) do
        if family.class == class then
            for _, rank in ipairs(family) do
                local item = rank[2]
                if not seen[item] then
                    seen[item] = true
                    local slider = S.Slider("restockTarget" .. item, ItemName(item), 0, 200, 1,
                        "How many to carry. 0 stops reminding you about it.", "restockReagents")
                    slider.getValue = function() return Target(item) end
                    sliders[#sliders + 1] = slider
                end
            end
        end
    end
    return sliders
end

local function Lines()
    local lines = {}
    for itemID, target in pairs(Wanted()) do
        local have = C_Item.GetItemCount(itemID)
        if have < target then
            lines[#lines + 1] = ("%s  %d / %d"):format(ItemName(itemID), have, target)
        end
    end
    table.sort(lines)
    local food, junk, free, drink = ScanBags()
    if S.Get("restockFood") and food < S.Get("restockFoodBelow") then
        lines[#lines + 1] = ("Food  %d left"):format(food)
    end
    local class = select(2, UnitClass("player"))
    if S.Get("restockFood") and class ~= "WARRIOR" and class ~= "ROGUE"
        and drink < S.Get("restockFoodBelow") then
        lines[#lines + 1] = ("Drink  %d left"):format(drink)
    end
    if S.Get("restockVendor") then
        if junk > 0 then lines[#lines + 1] = ("Junk to sell  %d"):format(junk) end
        if free < S.Get("restockBagsBelow") then
            lines[#lines + 1] = ("Bags nearly full  %d free"):format(free)
        end
    end
    return lines
end

-------------------------------------------------------------------------------
--  The reminder
-------------------------------------------------------------------------------
local function BuildAlert()
    alert = CreateFrame("Frame", "NaowhForeverRestock", UIParent)
    alert:SetMovable(true)
    alert:SetClampedToScreen(true)
    alert.title = ns.Font(alert, 22, "OUTLINE", T.accent)
    alert.title:SetPoint("TOP", 0, -4)
    alert.title:SetText("Restock")
    alert.text = ns.Font(alert, 16, "OUTLINE")
    alert.text:SetPoint("TOP", alert.title, "BOTTOM", 0, -4)
    alert.text:SetJustifyH("CENTER")
    alert.mover = ns.UI.AttachMover(alert, "Restock", function(pos) S.Set("restockPos", pos) end, "QoL/Loot & Items", "QoL/Loot & Items:restock")

    -- Pulses a few times when it appears, then stays solid until it is dealt with.
    flash = alert:CreateAnimationGroup()
    flash:SetLooping("BOUNCE")
    flash:SetScript("OnLoop", function(self)
        self.loops = self.loops + 1
        if self.loops >= 6 then self:Stop() end
    end)
    local pulse = flash:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.35)
    pulse:SetDuration(0.6)

    local pos = S.Get("restockPos")
    if pos then
        alert:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        alert:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    end
    alert:Hide()
end

local function HideAlert()
    if alert then
        flash:Stop()
        alert:Hide()
    end
end

local function ShowAlert(lines)
    if not alert then BuildAlert() end
    alert.text:SetText(table.concat(lines, "\n"))
    alert:SetSize(math.max(alert.title:GetStringWidth(), alert.text:GetStringWidth()) + 16,
        alert.title:GetStringHeight() + alert.text:GetStringHeight() + 12)
    -- Refreshed as bags change; only a new appearance pulses.
    if not alert:IsShown() then
        alert:Show()
        flash.loops = 0
        flash:Play()
    end
end

-- Shown on reaching a rested area, and again after a vendor if anything is still short.
local function Check()
    if not On() or not IsResting() or InCombatLockdown() or IsInInstance()
        or (MerchantFrame and MerchantFrame:IsShown()) then
        HideAlert()
        return
    end
    local lines = Lines()
    if #lines > 0 then ShowAlert(lines) else HideAlert() end
end

-------------------------------------------------------------------------------
--  At the vendor
-------------------------------------------------------------------------------
-- Returns what it spent: GetMoney() does not drop until the server answers.
local function Repair()
    if not (S.Get("autoRepair") and CanMerchantRepair()) then return 0 end
    local cost, canRepair = GetRepairAllCost()
    if not (canRepair and cost > 0) then return 0 end
    if GetMoney() < cost then
        ns.Print("Not enough gold to repair (" .. C_CurrencyInfo.GetCoinTextureString(cost) .. ").")
        return 0
    end
    RepairAllItems()
    ns.Print("Repaired for " .. C_CurrencyInfo.GetCoinTextureString(cost))
    return cost
end

local function SellJunk()
    if S.Get("sellJunk") and C_MerchantFrame.IsSellAllJunkEnabled()
        and C_MerchantFrame.GetNumJunkItems() > 0 then
        C_MerchantFrame.SellAllJunkItems()
    end
end

-- Buys each wanted item this vendor sells for gold, up to its target. A vendor that sells in
-- bundles (arrows by 200) only takes whole bundles, so the amount rounds up to one.
local function Buy(alreadySpent)
    if not S.Get("restockBuy") then return end
    local want = Wanted()
    local money = GetMoney() - alreadySpent
    local spent, bought = 0, {}
    for index = 1, GetMerchantNumItems() do
        local itemID = tonumber((GetMerchantItemLink(index) or ""):match("item:(%d+)"))
        local target = itemID and want[itemID]
        local info = target and C_MerchantFrame.GetItemInfo(index)
        if info and info.isPurchasable and not info.hasExtendedCost then
            local bundle = math.max(info.stackCount, 1)
            local bundles = math.ceil((target - C_Item.GetItemCount(itemID)) / bundle)
            if info.numAvailable and info.numAvailable >= 0 then
                bundles = math.min(bundles, info.numAvailable)
            end
            if info.price > 0 then bundles = math.min(bundles, math.floor(money / info.price)) end
            if bundles > 0 then
                local perBuy = math.max(math.floor(GetMerchantItemMaxStack(index) / bundle), 1)
                local left = bundles
                while left > 0 do
                    local take = math.min(left, perBuy)
                    BuyMerchantItem(index, take * bundle)
                    left = left - take
                end
                money = money - bundles * info.price
                spent = spent + bundles * info.price
                bought[#bought + 1] = bundles * bundle .. "x " .. ItemName(itemID)
            end
        end
    end
    if #bought > 0 then
        ns.Print("Restocked " .. table.concat(bought, ", ") .. " for "
            .. C_CurrencyInfo.GetCoinTextureString(math.floor(spent)))
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, itemID)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not pendingItems[itemID] then return end
        pendingItems[itemID] = nil
    end
    if event == "MERCHANT_SHOW" then
        HideAlert()
        SellJunk()
        local spent = Repair()
        if On() then Buy(spent) end
    elseif event == "MERCHANT_CLOSED" then
        -- Bags settle a moment after the last purchase or sale.
        C_Timer.After(0.5, Check)
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideAlert()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_REGEN_ENABLED"
        or event == "GET_ITEM_INFO_RECEIVED" then
        -- Restocked from the bank, mail or a trade: the list follows while it is up.
        Check()
    else
        local resting = IsResting()
        if resting and not wasResting then Check() end
        if not resting then HideAlert() end
        wasResting = resting
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    -- Auto Repair and Auto Sell Junk work at the vendor whether or not the reminder is on.
    if S.Get("enabled") and (S.Get("restock") or S.Get("autoRepair") or S.Get("sellJunk")) then
        events:RegisterEvent("MERCHANT_SHOW")
    end
    if not On() then
        HideAlert()
        return
    end
    -- Cached ahead so the reminder can name reagents the client has not seen this session.
    for itemID in pairs(TARGETS) do C_Item.RequestLoadItemDataByID(itemID) end
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:RegisterEvent("MERCHANT_CLOSED")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    pendingItems[159] = true
    C_Item.RequestLoadItemDataByID(159)
    wasResting = IsResting()
    Check()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "sellJunk" or key == "autoRepair"
        or (key:find("^restock") and key ~= "restockPos") then
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if not On() then return end
    ShowAlert({ "Arcane Powder  3 / 20", "Rough Arrow  150 / 1000", "Junk to sell  6" })
    alert.mover:Show()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if alert then
        alert.mover:Hide()
        HideAlert()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Group = ns.Shared.Settings.Group
local CARRY_HELP = "How many to carry. 0 stops reminding you about it."
local CHECKS = { { "restockReagents", "reagents" }, { "restockAmmo", "ammo" }, { "restockFood", "food & drink" },
    { "restockVendor", "junk & bags" } }

local loot = ns.Shared.Settings.Page("QoL/Loot & Items", S)

loot:Card({
    id = "vendors", name = "Vendors", order = 20,
    help = "What happens when you open a vendor. Both work whether or not the Restock Reminder is on.",
    rows = {
        { key = "autoRepair", label = "Auto Repair", toggle = true,
          help = "Repairs all gear when you open a vendor who can." },
        { key = "sellJunk", label = "Auto Sell Junk", toggle = true, help = "Sells grey items when you open a vendor." },
    },
})

local FIXED = {
    Group("Reagents & Ammo"),
    { key = "restockReagents", label = "Class Reagents", toggle = true,
      help = "The reagents your known spells use, such as Arcane Powder, candles, seeds, Symbols "
          .. "of Kings and Flash Powder, matched to the highest rank you know." },
    { key = "restockBuy", label = "Buy at Vendors", toggle = true,
      help = "At a vendor who sells them, tops your class reagents and ammo up to what you carry, "
          .. "and prints what it spent. Off by default: it spends gold for you." },
    { key = "restockAmmo", label = "Ammo", toggle = true, help = "The arrows or shot in your ammo slot." },
    { key = "restockAmmoTarget", label = "Ammo to Carry", slider = { 200, 4000, 100 }, needs = "restockAmmo" },
    Group("Food & Drink"),
    { key = "restockFood", label = "Food & Drink", toggle = true,
      help = "Counts food and drink separately across all stacks. Warriors and rogues do not need drink." },
    { key = "restockFoodBelow", label = "Food & Drink Below", slider = { 1, 40, 1 }, needs = "restockFood" },
    { key = "restockFoodMinLevel", label = "Food Minimum Required Level", slider = { 0, 60, 1 }, needs = "restockFood",
      help = "Only count food and drink whose required level is within this range." },
    { key = "restockFoodMaxLevel", label = "Food Maximum Required Level", slider = { 0, 60, 1 }, needs = "restockFood",
      help = "The same required-level filter applies to every stack, not each item separately." },
    Group("Bags"),
    { key = "restockVendor", label = "Junk & Full Bags", toggle = true,
      help = "Reminds you to vendor junk, and when your bags are nearly full." },
    { key = "restockBagsBelow", label = "Free Slots Below", slider = { 1, 20, 1 }, needs = "restockVendor" },
}
local CARRY_GROUP = Group("Reagents to Carry")

local restockRows, reagentRows, seenReagents = {}, {}, {}

local function ReagentRow(item)
    local row = reagentRows[item]
    if not row then
        local key = "restockTarget" .. item
        row = { key = key, slider = { 0, 200, 1 }, help = CARRY_HELP, needs = "restockReagents",
            get = function() return Target(item) end,
            set = function(v) S.Set(key, v) end }
        reagentRows[item] = row
    end
    row.label = ItemName(item)
    return row
end

local function RestockRows()
    wipe(restockRows)
    wipe(seenReagents)
    for i = 1, #FIXED do restockRows[i] = FIXED[i] end
    local class = select(2, UnitClass("player"))
    local grouped = false
    for _, family in ipairs(FAMILIES) do
        if family.class == class then
            for _, rank in ipairs(family) do
                local item = rank[2]
                if not seenReagents[item] then
                    seenReagents[item] = true
                    if not grouped then
                        restockRows[#restockRows + 1] = CARRY_GROUP
                        grouped = true
                    end
                    restockRows[#restockRows + 1] = ReagentRow(item)
                end
            end
        end
    end
    return restockRows
end

local function RestockSummary(store)
    local text
    for _, pair in ipairs(CHECKS) do
        if store.Get(pair[1]) then text = text and (text .. ", " .. pair[2]) or pair[2] end
    end
    if not text then return "Nothing to check" end
    text = text:sub(1, 1):upper() .. text:sub(2)
    return store.Get("restockBuy") and (text .. "; buys at vendors") or text
end

loot:Card({
    id = "restock", name = "Restock Reminder", order = 50, switch = "restock",
    help = "When you reach a city or inn, a flashing list in the middle of the screen of what "
        .. "you are short on. It stays up until you have what you need or leave. Move it "
        .. "in Layout Mode.",
    summary = RestockSummary,
    rows = RestockRows,
})
