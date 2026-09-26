-------------------------------------------------------------------------------
--  NaowhForever_LootConfirm.lua -- the QoL loot confirmation skip: answers yes to the
--  Need/Greed, disenchant and bind-on-pickup confirmations, and to the vendor trade-timer
--  and mail lock prompts, so none of them interrupt looting.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

-- event -> the confirm call, the popup it replaces, and how the event's arguments carry over.
local CONFIRMATIONS = {
    CONFIRM_LOOT_ROLL = { confirm = "ConfirmLootRoll", popup = "CONFIRM_LOOT_ROLL", forward = true },
    CONFIRM_DISENCHANT_ROLL = { confirm = "ConfirmLootRoll", popup = "CONFIRM_LOOT_ROLL", forward = true },
    LOOT_BIND_CONFIRM = { confirm = "ConfirmLootSlot", popup = "LOOT_BIND", forward = true,
        spreadExtra = true },
    MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL = { confirm = "SellCursorItem" },
    MAIL_LOCK_SEND_ITEMS = { confirm = "RespondMailLockSendItem", appendTrue = true },
}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
    local entry = CONFIRMATIONS[event]
    local fn = _G[entry.confirm]
    if not fn then return end
    if entry.appendTrue then
        fn(arg1, true)
    elseif entry.forward then
        fn(arg1, arg2)
    else
        fn()
    end
    if entry.popup then
        if entry.spreadExtra then
            StaticPopup_Hide(entry.popup, ...)
        else
            StaticPopup_Hide(entry.popup)
        end
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not (S.Get("enabled") and S.Get("lootConfirm")) then return end
    for event in pairs(CONFIRMATIONS) do events:RegisterEvent(event) end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "lootConfirm" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
