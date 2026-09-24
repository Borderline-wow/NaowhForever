-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Restock.lua -- the QoL restock module: a flashing reminder when
--  you reach a rested area low on class reagents, ammo or food and drink, or carrying junk
--  or near-full bags; and at a vendor, topping reagents and ammo up to their targets,
--  selling junk and repairing.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.QoLSettings
local T = ns.THEME

-- Class spells that use a vendor reagent on Forever, from its SpellReagents data
-- (build 1.60.1.69913). Each family lists its ranks from lowest; the highest rank you know
-- sets the reagent, so a rank 2 Prayer of Fortitude asks for Sacred Candles, not Holy.
local FAMILIES = {
    { { 20484, 17034 }, { 20739, 17035 }, { 20742, 17036 }, { 20747, 17037 }, { 20748, 17038 } },
    { { 21849, 17021 }, { 21850, 17026 } },                       -- Gift of the Wild
    { { 23028, 17020 } },                                         -- Arcane Brilliance
    { { 3561, 17031 }, { 3562, 17031 }, { 3563, 17031 }, { 3565, 17031 }, { 3566, 17031 },
      { 3567, 17031 }, { 1297659, 17031 } },                      -- Teleports
    { { 10059, 17032 }, { 11416, 17032 }, { 11417, 17032 }, { 11418, 17032 },
      { 11419, 17032 }, { 11420, 17032 } },                       -- Portals
    { { 19752, 17033 } },                                         -- Divine Intervention
    { { 25782, 21177 }, { 25916, 21177 }, { 25890, 21177 }, { 25894, 21177 },
      { 25918, 21177 }, { 25895, 21177 }, { 25898, 21177 } },     -- Greater Blessings
    { { 21562, 17028 }, { 21564, 17029 } },                       -- Prayer of Fortitude
    { { 27681, 17029 } },                                         -- Prayer of Spirit
    { { 27683, 17029 } },                                         -- Prayer of Shadow Protection
    { { 20608, 17030 }, { 21169, 17030 }, { 27740, 17030 } },     -- Reincarnation
    { { 18540, 16583 } },                                         -- Ritual of Doom
    { { 1122, 5565 }, { 24670, 5565 } },                          -- Inferno
    { { 1856, 5140 }, { 1857, 5140 }, { 27617, 5140 }, { 457437, 5140 },
      { 1285372, 5140 } },                                        -- Vanish
}

-- How many of each reagent to carry.
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

local function On()
    return S.Get("enabled") and S.Get("restock")
end

local function ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

-- itemID -> quantity wanted: the reagents for the spells you know, plus your equipped ammo.
local function Wanted()
    local want = {}
    if S.Get("restockReagents") then
        for _, family in ipairs(FAMILIES) do
            local item
            for _, rank in ipairs(family) do
                if IsPlayerSpell(rank[1]) then item = rank[2] end
            end
            if item then want[item] = TARGETS[item] end
        end
    end
    local ammo = S.Get("restockAmmo") and GetInventoryItemID("player", AMMO_SLOT)
    if ammo then want[ammo] = S.Get("restockAmmoTarget") end
    return want
end

-- Food and drink carried, junk to sell and free bag slots, in one pass over the bags.
local function ScanBags()
    local food, junk, free = 0, 0, 0
    for bag = 0, NUM_BAG_SLOTS do
        free = free + C_Container.GetContainerNumFreeSlots(bag)
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                if info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                    junk = junk + 1
                end
                local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
                if classID == FOOD_CLASS and subclassID == FOOD_SUBCLASS then
                    food = food + info.stackCount
                end
            end
        end
    end
    return food, junk, free
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
    local food, junk, free = ScanBags()
    if S.Get("restockFood") and food < S.Get("restockFoodBelow") then
        lines[#lines + 1] = ("Food & Drink  %d left"):format(food)
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
    alert.mover = ns.UI.AttachMover(alert, "Restock", function(pos) S.Set("restockPos", pos) end)

    -- Pulses while it is up, then hides after the display time.
    flash = alert:CreateAnimationGroup()
    flash:SetLooping("BOUNCE")
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

local hideGen = 0

local function HideAlert()
    hideGen = hideGen + 1
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
    alert:Show()
    flash:Play()
    hideGen = hideGen + 1
    local gen = hideGen
    C_Timer.After(S.Get("restockShowFor"), function()
        if gen == hideGen then HideAlert() end
    end)
end

-- Shown on reaching a rested area, and again after a vendor if anything is still short.
local function Check()
    if not IsResting() or InCombatLockdown() or IsInInstance() then
        HideAlert()
        return
    end
    local lines = Lines()
    if #lines > 0 then ShowAlert(lines) else HideAlert() end
end

-------------------------------------------------------------------------------
--  At the vendor
-------------------------------------------------------------------------------
local function Repair()
    if not (S.Get("autoRepair") and CanMerchantRepair()) then return end
    local cost, canRepair = GetRepairAllCost()
    if canRepair and cost > 0 and GetMoney() >= cost then
        RepairAllItems()
        ns.Print("Repaired for " .. C_CurrencyInfo.GetCoinTextureString(cost))
    end
end

local function SellJunk()
    if S.Get("sellJunk") and C_MerchantFrame.IsSellAllJunkEnabled()
        and C_MerchantFrame.GetNumJunkItems() > 0 then
        C_MerchantFrame.SellAllJunkItems()
    end
end

-- Buys each wanted item this vendor sells for gold, up to its target, a stack at a time.
local function Buy()
    if not S.Get("restockBuy") then return end
    local want = Wanted()
    local spent, bought = 0, {}
    for index = 1, GetMerchantNumItems() do
        local itemID = tonumber((GetMerchantItemLink(index) or ""):match("item:(%d+)"))
        local target = itemID and want[itemID]
        local info = target and C_MerchantFrame.GetItemInfo(index)
        if info and info.isPurchasable and not info.hasExtendedCost then
            local need = target - C_Item.GetItemCount(itemID)
            local unitPrice = info.price / math.max(info.stackCount, 1)
            local maxStack = C_Item.GetItemMaxStackSizeByID(itemID) or 20
            if info.numAvailable and info.numAvailable >= 0 then
                need = math.min(need, info.numAvailable * info.stackCount)
            end
            if unitPrice > 0 then need = math.min(need, math.floor(GetMoney() / unitPrice)) end
            if need > 0 then
                local left = need
                while left > 0 do
                    local take = math.min(left, maxStack)
                    BuyMerchantItem(index, take)
                    left = left - take
                end
                spent = spent + need * unitPrice
                bought[#bought + 1] = need .. "x " .. ItemName(itemID)
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
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        HideAlert()
        SellJunk()
        Repair()
        Buy()
    elseif event == "MERCHANT_CLOSED" then
        -- Bags settle a moment after the last purchase or sale.
        C_Timer.After(0.5, Check)
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideAlert()
    else
        local resting = IsResting()
        if resting and not wasResting then Check() end
        if not resting then HideAlert() end
        wasResting = resting
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        HideAlert()
        return
    end
    -- Cached ahead so the reminder can name reagents the client has not seen this session.
    for itemID in pairs(TARGETS) do C_Item.RequestLoadItemDataByID(itemID) end
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
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
