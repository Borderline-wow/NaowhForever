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

local function Place()
    local pos = S.Get("durabilityPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
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
        frame.mover = ns.UI.AttachMover(frame, "Durability", function(pos) S.Set("durabilityPos", pos) end, "QoL/Combat & Alerts", "QoL/Combat & Alerts:Low Durability Warning")
    end
    frame.text:SetFont(ns.UI.FontPath(S.Get("durabilityFont")), 22, "OUTLINE")
    Place()
    frame.mover:SetShown(unlocked == true)
    inCombat = UnitAffectingCombat("player")
    events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^durability") and key ~= "durabilityPos") then Apply() end
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
