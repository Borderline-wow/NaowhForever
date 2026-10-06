-------------------------------------------------------------------------------
--  NaowhForever_Durability.lua -- the QoL low durability warning, shading from pink to red as
--  your gear wears down.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local PINK = { r = 1, g = 0.41, b = 0.71 }
local RED = { r = 1, g = 0, b = 0 }
local FLOOR_PCT = 15    -- fully red at or below this

local frame, unlocked, inCombat

local function On()
    return S.Get("enabled") and S.Get("durability")
end

local function Lowest()
    local lowest
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    return lowest
end

local function Show(pct, threshold)
    local t = math.max(0, math.min(1, (pct - FLOOR_PCT) / math.max(1, threshold - FLOOR_PCT)))
    frame.text:SetTextColor(RED.r + t * (PINK.r - RED.r), RED.g + t * (PINK.g - RED.g),
        RED.b + t * (PINK.b - RED.b), 1)
    frame.text:SetText(("Low Durability: %d%%"):format(pct))
    frame:Show()
end

local function Update()
    local threshold = S.Get("durabilityBelow")
    if unlocked then
        Show(20, threshold)
        return
    end
    local lowest = not inCombat and Lowest()
    if lowest and lowest < threshold then
        Show(math.floor(lowest), threshold)
    else
        frame:Hide()
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    Update()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverDurability", UIParent)
        frame:SetSize(300, 32)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.text = ns.Font(frame, 22, "OUTLINE")
        frame.text:SetPoint("CENTER")
        ns.AlertStack(frame, 3)
    end
    frame.text:SetFont(ns.UI.FontPath(S.Get("durabilityFont")), 22, "OUTLINE")
    inCombat = UnitAffectingCombat("player")
    events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^durability") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local function DurabilitySummary(store)
    return ("Warns below %d%%"):format(store.Get("durabilityBelow"))
end

ns.Shared.Settings.Page("QoL/Loot & Items", S):Card({
    id = "durability", name = "Durability", order = 80, switch = "durability",
    help = "Text on screen when any piece of gear drops below the threshold. Hidden in "
        .. "combat. Move it with Move Elements.",
    summary = DurabilitySummary,
    rows = {
        { key = "durabilityBelow", label = "Warn Below", slider = { 5, 100, 1 }, unit = "%" },
        { key = "durabilityFont", label = "Font", font = true },
    },
})
