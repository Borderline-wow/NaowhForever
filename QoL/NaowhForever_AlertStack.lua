-------------------------------------------------------------------------------
--  NaowhForever_AlertStack.lua -- the one Alerts group: Camp Nearby, Talent Points, Durability,
--  Restock and Pet Tracker stack upward from its spot, whichever are on screen at the time, and
--  move together under one Unlock Mode mover. The group frame is the bottom slot; the mover
--  covers the whole stack, so anchors measure what the player sees.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local GAP = 6
local SLOT_W, SLOT_H = 300, 32
local DEFAULT_Y = 150
-- Before the group each alert had a spot of its own. The first one a player had moved, from
-- the bottom of the stack up, becomes the group's.
local OLD_POSITIONS = { "campAlertPos", "talentPointsPos", "durabilityPos", "restockPos", "petTrackerPos" }

local members = {}
local group, unlocked

local function OldPosition()
    for _, key in ipairs(OLD_POSITIONS) do
        local settings = S
        if key == "campAlertPos" then settings = ns.AuraBuffSettings end
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
    -- Members belong to different modules, so the plate follows whichever previews are up.
    group.mover:SetShown(unlocked == true and any)
end

local function Build()
    group = CreateFrame("Frame", "NaowhForeverAlerts", UIParent)
    group:SetSize(SLOT_W, SLOT_H)
    group:SetMovable(true)
    group:SetClampedToScreen(true)
    group.mover = ns.UI.AttachMover(group, "Alerts", function(pos) S.Set("alertsPos", pos) end, "QoL/Loot & Items",
        "QoL/Loot & Items:durability")
    group.mover:ClearAllPoints()
    group.mover:SetPoint("BOTTOM", group, "BOTTOM")
    Place()
end

-- Order 1 is the bottom of the stack.
function ns.AlertStack(frame, order)
    if not group then Build() end
    frame.alertOrder = order
    members[#members + 1] = frame
    table.sort(members, function(a, b) return a.alertOrder < b.alertOrder end)
    frame:HookScript("OnShow", Layout)
    frame:HookScript("OnHide", Layout)
    frame:HookScript("OnSizeChanged", Layout)
    hooksecurefunc(frame, "SetScale", Layout)
    Layout()
end

hooksecurefunc(ns, "Apply", function()
    if group then Place() end
end)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = true
    if group then Layout() end
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if group then Layout() end
end)
