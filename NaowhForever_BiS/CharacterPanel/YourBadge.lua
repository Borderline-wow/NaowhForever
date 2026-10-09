-- YourBadge.lua: your supporter badge in the character panel's left pane, over your head slot.
local ns = _G.NaowhForever

local S = ns.QoLSettings
local CP = ns.CharacterPanel
local C = CP.C

local INSET = C.BADGE_INSET
local EMBLEM = C.EMBLEM
local SLOT_GAP = 3
local PLATE_LIFT = 60
local BADGES_LIVE = ns.BADGES_LIVE

local mine, installed

local function BadgeOn()
    local wanted = S.Get("characterPanelBadge")
    if ns.FEATURE_BADGES ~= BADGES_LIVE then wanted = S.Default("characterPanelBadge") end
    if not (CP.On() and wanted == true) then return false end
    return ns.BadgeOf(UnitGUID("player")) ~= nil
end

local function Center()
    local slot = CharacterHeadSlot
    local paneTop, slotTop = CharacterFrame.LeftPaneHost:GetTop(), slot and slot:GetTop()
    if not (paneTop and slotTop) then return end
    mine:ClearAllPoints()
    mine:SetPoint("BOTTOM", slot, "TOP", 0, math.max(0, (paneTop - slotTop - EMBLEM) / 2))
end

local function Paint()
    CP.PaintBadgePlate(mine, UnitGUID("player"))
    Center()
end

local function Build()
    local left = CharacterFrame.LeftPaneHost
    mine = CP.BadgePlate(PaperDollFrame or left, true)
    if CharacterHeadSlot then
        mine:SetPoint("BOTTOM", CharacterHeadSlot, "TOP", 0, SLOT_GAP)
    else
        mine:SetPoint("TOPLEFT", INSET, -INSET)
    end
    mine:SetFrameLevel(left:GetFrameLevel() + PLATE_LIFT)
    mine:SetScript("OnShow", Paint)
    CP.supportBadge = mine
end

local function Apply()
    local on = BadgeOn()
    if on and not installed and CharacterFrame then
        installed = true
        Build()
        CharacterFrame.LeftPaneHost:HookScript("OnShow", Apply)
    end
    if not installed then return end
    mine:SetShown(on)
    if on and mine:IsVisible() then Paint() end
end

local function OnSetting(key)
    if key == "enabled" or key:find("^characterPanel") then Apply() end
end

S.OnChange(OnSetting)
hooksecurefunc(ns, "Apply", Apply)
