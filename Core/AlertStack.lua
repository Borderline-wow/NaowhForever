-- AlertStack.lua: the Alerts group, the alerts stacked upward under one Unlock Mode mover.
local ns = _G.NaowhForever

local S = ns.QoLSettings

local GAP = 6
local SLOT_W, SLOT_H = 300, 32
local DEFAULT_Y = 150
local OLD_POSITIONS = { "campAlertPos", "talentPointsPos", "durabilityPos", "restockPos", "petTrackerPos" }
local CAMP_POSITION = "campAlertPos"
local MOVER_LABEL = "Alerts"
local SETTINGS_PAGE = "QoL/Loot & Items"
local SETTINGS_CARD = "QoL/Loot & Items:durability"

local members, choices = {}, {}
local group, unlocked

local function ByOrder(a, b)
    return a.alertOrder < b.alertOrder
end

local function ChoiceOrder(a, b)
    return a.order < b.order
end

local function OldPosition()
    for _, key in ipairs(OLD_POSITIONS) do
        local settings = S
        if key == CAMP_POSITION then settings = ns.AuraBuffSettings end
        local pos = settings and settings.Get(key)
        if type(pos) == "table" then return pos end
    end
end

local function Place()
    local pos = S.Get("alertsPos")
    if not pos then
        pos = OldPosition() or { point = "CENTER", relPoint = "CENTER", x = 0, y = DEFAULT_Y }
        S.Set("alertsPos", pos)
    end
    group:ClearAllPoints()
    group:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local function Layout()
    local y, width, any = 0, SLOT_W, false
    for _, frame in ipairs(members) do
        if frame:IsShown() then
            local ratio = frame:GetEffectiveScale() / group:GetEffectiveScale()
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOM", group, "BOTTOM", 0, y / ratio)
            y = y + frame:GetHeight() * ratio + GAP
            width = math.max(width, frame:GetWidth() * ratio)
            any = true
        end
    end
    group.mover:SetSize(width, math.max(y - GAP, SLOT_H))
    group.mover:SetShown(unlocked == true and any)
end

local function SavePosition(pos)
    S.Set("alertsPos", pos)
end

local function Build()
    group = CreateFrame("Frame", "NaowhForeverAlerts", UIParent)
    group:SetSize(SLOT_W, SLOT_H)
    group:SetMovable(true)
    group:SetClampedToScreen(true)
    group.mover = ns.UI.AttachMover(group, MOVER_LABEL, SavePosition, SETTINGS_PAGE, SETTINGS_CARD)
    ns.UI.SetMoverChoices(group.mover, choices)
    group.mover:ClearAllPoints()
    group.mover:SetPoint("BOTTOM", group, "BOTTOM")
    Place()
end

local function SetUnlocked(on)
    unlocked = on
    if group then Layout() end
end

function ns.AlertStack(frame, order, name, page, card)
    if not group then Build() end
    frame.alertOrder = order
    members[#members + 1] = frame
    table.sort(members, ByOrder)
    choices[#choices + 1] = { name = name, page = page, feature = card, order = order }
    table.sort(choices, ChoiceOrder)
    frame:HookScript("OnShow", Layout)
    frame:HookScript("OnHide", Layout)
    frame:HookScript("OnSizeChanged", Layout)
    hooksecurefunc(frame, "SetScale", Layout)
    Layout()
end

hooksecurefunc(ns, "Apply", function()
    if group then Place() end
end)
hooksecurefunc(ns, "ShowUnlockMode", function() SetUnlocked(true) end)
hooksecurefunc(ns, "HideUnlockMode", function() SetUnlocked(false) end)
