-------------------------------------------------------------------------------
--  NaowhForever_LootConfirm.lua -- the QoL loot confirmation skip: answers yes to roll, bind,
--  trade-timer and mail lock confirmations.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

-- event -> the confirm call, the popup it replaces, and how the event's arguments carry over.
local CONFIRMATIONS = {
    CONFIRM_LOOT_ROLL = { confirm = "ConfirmLootRoll", popup = "CONFIRM_LOOT_ROLL", forward = true },
    CONFIRM_DISENCHANT_ROLL = { confirm = "ConfirmLootRoll", popup = "CONFIRM_LOOT_ROLL", forward = true },
    LOOT_BIND_CONFIRM = { confirm = "ConfirmLootSlot", popup = "LOOT_BIND", forward = true,
        spreadExtra = true },
    MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL = { confirm = "SellCursorItem",
        popup = "CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL" },
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
    -- Automatic confirmations are retired; keep saved preferences recoverable.
    -- No events are registered, including for profiles that previously enabled it.
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "lootConfirm" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
