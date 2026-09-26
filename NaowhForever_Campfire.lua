-------------------------------------------------------------------------------
--  NaowhForever_Campfire.lua -- the AuraBuffs campfire reminder: a round camp
--  icon while Camp Benefits is up, with a countdown until it runs out, and a greyed-out
--  "Refresh Camp" reminder when it is not.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.AuraBuffSettings
local T = ns.THEME

-- Forever's Camp Benefits aura and icon, probed on the client 2026-09-19.
local CAMP_BENEFITS = 1229741
-- Area aura from being in range of a campfire, probed 2026-09-24.
local CAMPFIRE_NEARBY = 1283391
-- Camp Benefits with less than this left counts as due for a refresh.
local CAMP_LOW = 120
local CAMP_ICON = 7808144
local CIRCLE_MASK = "Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga"
local CIRCLE_RING = "Interface\\AddOns\\NaowhForever\\Media\\circle_ring.tga"
-- The time ring's colour by minutes left: green above 30, yellow above 5, red below.
local RING_STEPS = { { 1800, 0.29, 0.87, 0.5 }, { 300, 0.98, 0.8, 0.08 }, { 0, 0.97, 0.27, 0.27 } }

local TEXT_SIZE = 16

local icon, unlocked
local hasCamp       -- nil until the first read
local shownExpiry   -- the expiry the swipe was last started from
local alert
local alertGen = 0   -- invalidates an older "under 2 minutes" timer
local ringGen = 0    -- invalidates an older ring colour change
local showGen = 0    -- invalidates an older "drops under the Show Only When Low time" timer

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

    -- A black circle one pixel wider on every side, behind the icon: a 1px round border.
    icon.ring = icon:CreateTexture(nil, "BACKGROUND")
    icon.ring:SetPoint("TOPLEFT", -1, 1)
    icon.ring:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.ring:SetColorTexture(0, 0, 0, 1)
    icon.ringMask = icon:CreateMaskTexture()
    icon.ringMask:SetAllPoints(icon.ring)
    icon.ringMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon.ring:AddMaskTexture(icon.ringMask)

    icon.timer = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.timer:SetAllPoints()
    icon.timer:SetSwipeTexture(CIRCLE_MASK)
    icon.timer:SetSwipeColor(0, 0, 0, 0.65)
    icon.timer:SetDrawEdge(false)
    icon.timer:SetReverse(true)

    -- A ring just outside the border that drains with the time left, over a dim full track.
    icon.track = icon:CreateTexture(nil, "BACKGROUND")
    icon.track:SetPoint("TOPLEFT", -5, 5)
    icon.track:SetPoint("BOTTOMRIGHT", 5, -5)
    icon.track:SetTexture(CIRCLE_RING)
    icon.track:SetVertexColor(0, 0, 0, 0.6)
    icon.drain = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.drain:SetAllPoints(icon.track)
    icon.drain:SetSwipeTexture(CIRCLE_RING)
    icon.drain:SetDrawEdge(false)
    icon.drain:SetDrawBling(false)
    icon.drain:SetHideCountdownNumbers(true)

    icon.label = ns.Font(icon, TEXT_SIZE, "OUTLINE", T.accentSoft)
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    icon.label:SetText("Refresh Camp")

    icon.buffs = ns.Font(icon, TEXT_SIZE, "OUTLINE")
    icon.buffs:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    icon.buffs:SetJustifyH("CENTER")

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

-- Nothing fires as the buff runs down, so each colour change is timed.
local function ColorRing(expiry)
    ringGen = ringGen + 1
    local left = expiry - GetTime()
    for _, step in ipairs(RING_STEPS) do
        if left > step[1] or step[1] == 0 then
            icon.drain:SetSwipeColor(step[2], step[3], step[4], 1)
            if step[1] > 0 then
                local gen = ringGen
                C_Timer.After(left - step[1] + 0.1, function()
                    if gen == ringGen then ColorRing(expiry) end
                end)
            end
            return
        end
    end
end

local function ShowUp(duration, expiry, buffs)
    icon.tex:SetDesaturated(false)
    icon.label:Hide()
    icon.buffs:SetText(S.Get("campBuffs") and buffs or "")
    icon.buffs:Show()
    if S.Get("campTimer") and duration and duration > 0 then
        if shownExpiry ~= expiry then
            icon.timer:SetCooldown(expiry - duration, duration)
            icon.drain:SetCooldown(expiry - duration, duration)
            ColorRing(expiry)
            shownExpiry = expiry
        end
        icon.timer:Show()
        icon.drain:Show()
        icon.track:Show()
    else
        icon.timer:Hide()
        icon.drain:Hide()
        icon.track:Hide()
        ringGen = ringGen + 1
        shownExpiry = nil
    end
    icon:Show()
end

local function ShowMissing()
    icon.tex:SetDesaturated(true)
    icon.label:Show()
    icon.buffs:Hide()
    icon.timer:Hide()
    icon.drain:Hide()
    icon.track:Hide()
    ringGen = ringGen + 1
    shownExpiry = nil
    icon:Show()
end

-- "Camp Nearby" in the middle of the screen when a campfire is in range and the camp needs
-- refreshing: no Camp Benefits, or less than two minutes left on it.
local function BuildAlert()
    alert = CreateFrame("Frame", "NaowhForeverCampNearby", UIParent)
    alert:SetMovable(true)
    alert:SetClampedToScreen(true)
    alert.text = ns.Font(alert, 28, "OUTLINE", T.accent)
    alert.text:SetPoint("CENTER")
    alert.text:SetText("Camp Nearby")
    alert:SetSize(alert.text:GetStringWidth() + 16, 40)
    alert.mover = ns.UI.AttachMover(alert, "Camp Nearby", function(pos) S.Set("campAlertPos", pos) end)
    local pos = S.Get("campAlertPos")
    if pos then
        alert:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        alert:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
    alert:Hide()
end

local function SetAlert(show)
    if not alert then
        if not show then return end
        BuildAlert()
    end
    alert:SetShown(show)
end

-- The camp buffs currently up, one per line. Most are hidden auras the client does not
-- hand to addons (the Camp Chair buff reads as absent while Blizzard's tooltip shows it,
-- confirmed 2026-09-24), so they are read off Camp Benefits' own tooltip, which has one
-- "Camp Chair: effect" line per benefit. Its header line ends in a bare colon and is skipped,
-- and so is the time left line, whose "|4minute:minutes;" plural code carries a colon too:
-- a camp object's name never holds a digit or an escape code.
local function ActiveBuffs(aura)
    local data = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", aura.auraInstanceID)
    local names = {}
    for i, line in ipairs(data and data.lines or {}) do
        local text = line.leftText
        if i > 1 and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            for row in text:gmatch("[^\n]+") do
                local label = row:match("^%s*([^:]+):%s*%S")
                if label and not label:find("[%d|]") then names[#names + 1] = label end
            end
        end
    end
    return table.concat(names, "\n")
end

local Refresh

-- Nothing fires as the buff's time runs down, so crossing the two-minute mark is timed.
local function UpdateAlert(aura)
    alertGen = alertGen + 1
    if not (S.Get("campNearbyAlert") and C_UnitAuras.GetPlayerAuraBySpellID(CAMPFIRE_NEARBY)) then
        SetAlert(false)
        return
    end
    local left = aura and aura.expirationTime
    if left and issecretvalue and issecretvalue(left) then left = nil end
    left = left and left > 0 and left - GetTime()
    if aura and not left then
        SetAlert(false)
        return
    end
    SetAlert(not aura or left < CAMP_LOW)
    if aura and left >= CAMP_LOW then
        local gen = alertGen
        C_Timer.After(left - CAMP_LOW + 0.1, function()
            if gen == alertGen then Refresh() end
        end)
    end
end

-- The client hides the player's auras from addons during combat, where this read comes back
-- empty with the buff up, so the icon keeps whatever it last showed until the fight ends.
-- InCombatLockdown() is still false while PLAYER_REGEN_DISABLED is handled.
function Refresh(_, event)
    if not icon then return end
    showGen = showGen + 1
    if unlocked then
        ShowUp(3600, GetTime() + 2400, "Camp Chair\nFish Bowl")
        SetAlert(S.Get("campNearbyAlert"))
        return
    end
    if not (On() and InOpenWorld()) then
        icon:Hide()
        alertGen = alertGen + 1
        SetAlert(false)
        return
    end
    if InCombatLockdown() or event == "PLAYER_REGEN_DISABLED" or C_Secrets.ShouldAurasBeSecret() then
        alertGen = alertGen + 1
        SetAlert(false)
        return
    end

    local aura = C_UnitAuras.GetPlayerAuraBySpellID(CAMP_BENEFITS)
    local had = hasCamp
    hasCamp = aura ~= nil
    if aura then
        local duration, expiry = aura.duration, aura.expirationTime
        if issecretvalue and (issecretvalue(duration) or issecretvalue(expiry)) then
            duration, expiry = nil, nil
        end
        -- Nothing fires as the camp runs down, so the moment it drops under the time is timed.
        local left = expiry and expiry > 0 and expiry - GetTime()
        local under = S.Get("campShowUnderMinutes") * 60
        if S.Get("campShowUnder") and left and left > under then
            icon:Hide()
            local gen = showGen
            C_Timer.After(left - under + 0.1, function()
                if gen == showGen then Refresh() end
            end)
        else
            ShowUp(duration, expiry, ActiveBuffs(aura))
        end
    else
        ShowMissing()
        if had and S.Get("campSound") then
            ns.UI._PlayLSMSound(ns.UI.SoundPathFor(S.Get("campSoundKey")))
        end
    end
    UpdateAlert(aura)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Refresh)

local function Apply()
    if not On() then
        events:UnregisterAllEvents()
        hasCamp = nil
        alertGen = alertGen + 1
        SetAlert(false)
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
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
    shownExpiry = nil
    Refresh()
    if alert then alert.mover:SetShown(unlocked == true) end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^camp") and key ~= "campPos" and key ~= "campAlertPos") then
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if icon then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
