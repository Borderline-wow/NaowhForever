-------------------------------------------------------------------------------
--  NaowhForever_TalentPoints.lua -- the QoL unspent talent points reminder: text on screen
--  while you have talent points to spend. Hidden in combat.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local frame, unlocked, inCombat

local function On()
    return S.Get("enabled") and S.Get("talentPoints")
end

local function Show(points)
    frame.text:SetText(points == 1 and "1 Unspent Talent Point" or ("%d Unspent Talent Points"):format(points))
    frame:Show()
end

local function Update()
    if unlocked then
        Show(2)
        return
    end
    local unspent, classPoints, specPoints = C_ClassTalents.HasUnspentTalentPoints()
    if unspent and not inCombat then
        Show(classPoints + specPoints)
    else
        frame:Hide()
    end
end

local function Place()
    local pos = S.Get("talentPointsPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
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
        frame = CreateFrame("Frame", "NaowhForeverTalentPoints", UIParent)
        frame:SetSize(300, 32)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.text = ns.Font(frame, 22, "OUTLINE")
        frame.text:SetPoint("CENTER")
        frame.text:SetTextColor(1, 0.82, 0, 1)
        frame.mover = ns.UI.AttachMover(frame, "Talent Points", function(pos) S.Set("talentPointsPos", pos) end)
    end
    frame.text:SetFont(ns.UI.FontPath(S.Get("talentPointsFont")), 22, "OUTLINE")
    Place()
    frame.mover:SetShown(unlocked == true)
    inCombat = UnitAffectingCombat("player")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("TRAIT_CONFIG_UPDATED")
    events:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^talentPoints") and key ~= "talentPointsPos") then Apply() end
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
