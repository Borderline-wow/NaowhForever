-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Campfire.lua -- the AuraBuffs campfire reminder: a round camp
--  icon while Camp Benefits is up, with a countdown until it runs out, and a greyed-out
--  "Refresh Camp" reminder when it is not.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.AuraBuffSettings
local T = ns.THEME

-- Forever's Camp Benefits aura and icon, probed on the client 2026-09-19.
local CAMP_BENEFITS = 1229741
local CAMP_ICON = 7808144
local CIRCLE_MASK = "Interface\\AddOns\\NaowhSmartReminders\\Media\\circle_mask.tga"

local icon, unlocked
local hasCamp       -- nil until the first read
local shownExpiry   -- the expiry the swipe was last started from

local function On()
    return S.Get("enabled") and S.Get("campfire")
end

-- Camp Benefits is earned in the open world, so dungeons, raids and battlegrounds never
-- nag about it.
local function InOpenWorld()
    local inInstance = IsInInstance()
    return not inInstance
end

local function Build()
    icon = CreateFrame("Frame", "NaowhForeverCampfire", UIParent)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexture(C_Spell.GetSpellTexture(CAMP_BENEFITS) or CAMP_ICON)
    icon.mask = icon:CreateMaskTexture()
    icon.mask:SetAllPoints()
    icon.mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon.tex:AddMaskTexture(icon.mask)

    icon.timer = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.timer:SetAllPoints()
    icon.timer:SetSwipeTexture(CIRCLE_MASK)
    icon.timer:SetSwipeColor(0, 0, 0, 0.65)
    icon.timer:SetDrawEdge(false)
    icon.timer:SetReverse(true)

    icon.label = ns.Font(icon, 13, "OUTLINE", T.accentSoft)
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    icon.label:SetText("Refresh Camp")

    icon.mover = ns.UI.AttachMover(icon, "Campfire", function(pos) S.Set("campPos", pos) end)
    icon:Hide()
end

local function Place()
    local pos = S.Get("campPos")
    icon:ClearAllPoints()
    if pos then
        icon:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        icon:SetPoint("CENTER", UIParent, "CENTER", -260, 120)
    end
end

local function ShowUp(duration, expiry)
    icon.tex:SetDesaturated(false)
    icon.label:Hide()
    if S.Get("campTimer") and duration and duration > 0 then
        if shownExpiry ~= expiry then
            icon.timer:SetCooldown(expiry - duration, duration)
            shownExpiry = expiry
        end
        icon.timer:Show()
    else
        icon.timer:Hide()
        shownExpiry = nil
    end
    icon:Show()
end

local function ShowMissing()
    icon.tex:SetDesaturated(true)
    icon.label:Show()
    icon.timer:Hide()
    shownExpiry = nil
    icon:Show()
end

-- The client hides the player's auras from addons during combat, where this read comes back
-- empty with the buff up, so the icon keeps whatever it last showed until the fight ends.
local function Refresh()
    if not icon then return end
    if unlocked then
        ShowUp(3600, GetTime() + 2400)
        return
    end
    if not (On() and InOpenWorld()) then
        icon:Hide()
        return
    end
    if InCombatLockdown() then return end

    local aura = C_UnitAuras.GetPlayerAuraBySpellID(CAMP_BENEFITS)
    local had = hasCamp
    hasCamp = aura ~= nil
    if aura then
        local duration, expiry = aura.duration, aura.expirationTime
        if issecretvalue and (issecretvalue(duration) or issecretvalue(expiry)) then
            duration, expiry = nil, nil
        end
        ShowUp(duration, expiry)
    else
        ShowMissing()
        if had and S.Get("campSound") then
            ns.UI._PlayLSMSound(ns.UI.SoundPathFor(S.Get("campSoundKey")))
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Refresh)

local function Apply()
    if not On() then
        events:UnregisterAllEvents()
        hasCamp = nil
        if icon and not unlocked then icon:Hide() end
        if not unlocked then return end
    end
    if not icon then Build() end
    local size = S.Get("campIconSize")
    icon:SetSize(size, size)
    Place()
    icon.mover:SetShown(unlocked == true)
    if On() then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    shownExpiry = nil
    Refresh()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^camp") and key ~= "campPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if icon then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
