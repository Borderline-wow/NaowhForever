-- LootConfirm.lua: the retired loot confirmation skip, kept inert so saved choices stay.
local ns = _G.NaowhForever

local S = ns.QoLSettings

local CONFIRMATIONS = {
    CONFIRM_LOOT_ROLL = { confirm = "ConfirmLootRoll", popup = "CONFIRM_LOOT_ROLL", forward = true },
    CONFIRM_DISENCHANT_ROLL = { confirm = "ConfirmLootRoll", popup = "CONFIRM_LOOT_ROLL", forward = true },
    LOOT_BIND_CONFIRM = { confirm = "ConfirmLootSlot", popup = "LOOT_BIND", forward = true,
        spreadExtra = true },
    MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL = { confirm = "SellCursorItem",
        popup = "CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL" },
    MAIL_LOCK_SEND_ITEMS = { confirm = "RespondMailLockSendItem", appendTrue = true },
}

local function Answer(entry, arg1, arg2)
    local fn = _G[entry.confirm]
    if not fn then return false end
    if entry.appendTrue then
        fn(arg1, true)
    elseif entry.forward then
        fn(arg1, arg2)
    else
        fn()
    end
    return true
end

local function OnEvent(_, event, arg1, arg2, ...)
    local entry = CONFIRMATIONS[event]
    if not Answer(entry, arg1, arg2) or not entry.popup then return end
    if entry.spreadExtra then
        StaticPopup_Hide(entry.popup, ...)
    else
        StaticPopup_Hide(entry.popup)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", OnEvent)

local function Apply()
    events:UnregisterAllEvents()
end

local function OnSettingChanged(key)
    if key == "enabled" or key == "lootConfirm" then Apply() end
end

hooksecurefunc(S, "Set", OnSettingChanged)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
