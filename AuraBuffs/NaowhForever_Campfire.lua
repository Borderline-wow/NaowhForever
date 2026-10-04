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
-- The 60 second aura while sitting at a campfire, before Camp Benefits lands; probed 2026-09-25.
local WELCOMING_CAMPFIRE = 1229739
local CIRCLE_MASK = "Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga"
local CIRCLE_RING = "Interface\\AddOns\\NaowhForever\\Media\\circle_ring.tga"
-- The time ring's colour by minutes left: green above 30, yellow above 5, red below.
local RING_STEPS = { { 1800, 0.29, 0.87, 0.5 }, { 300, 0.98, 0.8, 0.08 }, { 0, 0.97, 0.27, 0.27 } }

local TEXT_SIZE = 16
-- The plate behind the campfire art; ns.ThemeTint swaps in the player's Panels color.
local PLATE = { r = 0.14, g = 0.15, b = 0.16 }

local Look = {}

function Look.New(icon)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\CampfireHD.tga")
    icon.plate = icon:CreateTexture(nil, "BACKGROUND", nil, 1)
    icon.plate:SetAllPoints()
    local plate = ns.ThemeTint("panel", PLATE)
    icon.plate:SetColorTexture(plate.r, plate.g, plate.b, 1)
    icon.mask = icon:CreateMaskTexture()
    icon.mask:SetAllPoints()
    icon.mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon.tex:AddMaskTexture(icon.mask)
    icon.plate:AddMaskTexture(icon.mask)

    -- A black circle one pixel wider on every side, behind the icon: a 1px round border.
    icon.ring = icon:CreateTexture(nil, "BACKGROUND")
    ns.PixelInset(icon.ring, -1)
    icon.ring:SetColorTexture(0, 0, 0, 1)
    icon.ringMask = icon:CreateMaskTexture()
    icon.ringMask:SetAllPoints(icon.ring)
    icon.ringMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon.ring:AddMaskTexture(icon.ringMask)

    icon.timer = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.timer:SetAllPoints()
    icon.timer:SetSwipeTexture(CIRCLE_MASK)
    icon.timer:SetDrawSwipe(false)
    icon.timer:SetDrawBling(false)
    icon.timer:SetDrawEdge(false)
    icon.timer:SetReverse(true)

    -- The black disk extends past the drain on both sides, edging the time ring.
    icon.track = icon:CreateTexture(nil, "BACKGROUND")
    icon.track:SetPoint("TOPLEFT", -6, 6)
    icon.track:SetPoint("BOTTOMRIGHT", 6, -6)
    icon.track:SetTexture(CIRCLE_MASK)
    icon.track:SetVertexColor(0, 0, 0, 1)
    icon.drain = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.drain:SetPoint("TOPLEFT", -5, 5)
    icon.drain:SetPoint("BOTTOMRIGHT", 5, -5)
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
end

function Look.Layout(icon)
    local size = S.Get("campIconSize")
    icon:SetSize(size, size)
    icon.buffs:SetFont(ns.UIFontPath(), S.Get("campBuffTextSize"), "OUTLINE")
    icon.buffs:ClearAllPoints()
    local side = S.Get("campBuffSide")
    icon.buffs:SetJustifyH(side == "right" and "LEFT" or side == "left" and "RIGHT" or "CENTER")
    if side == "right" then icon.buffs:SetPoint("LEFT", icon, "RIGHT", 12, 0)
    elseif side == "left" then icon.buffs:SetPoint("RIGHT", icon, "LEFT", -12, 0)
    elseif side == "above" then icon.buffs:SetPoint("BOTTOM", icon, "TOP", 0, 12)
    else icon.buffs:SetPoint("TOP", icon, "BOTTOM", 0, -12) end
end

function Look.Step(left)
    for _, step in ipairs(RING_STEPS) do
        if left > step[1] or step[1] == 0 then return step end
    end
end

function Look.Timed(icon, on)
    icon.timer:SetShown(on)
    icon.drain:SetShown(on)
    icon.track:SetShown(on)
end

function Look.Up(icon, buffs)
    icon.tex:SetDesaturated(false)
    icon.label:Hide()
    icon.buffs:SetText(buffs)
    icon.buffs:Show()
end

function Look.Sitting(icon)
    icon.tex:SetDesaturated(false)
    icon.label:SetText("Resting")
    icon.label:Show()
    icon.buffs:Hide()
end

function Look.Missing(icon)
    icon.tex:SetDesaturated(true)
    icon.label:SetText("Refresh Camp")
    icon.label:Show()
    icon.buffs:Hide()
    Look.Timed(icon, false)
end

function Look.Alert(alert)
    alert.text = ns.Font(alert, 28, "OUTLINE", T.accent)
    alert.text:SetPoint("CENTER")
    alert.text:SetText("Camp Nearby")
    alert:SetSize(alert.text:GetStringWidth() + 16, 40)
end

local icon, unlocked
local hasCamp       -- nil until the first read
local shownExpiry   -- the expiry the swipe was last started from
local alert
local alertGen = 0   -- invalidates an older Alert Under timer
local alertArmed     -- the expiry that timer was set for
local alertDismissed -- Ctrl-clicked away; back once you leave the campfire's range
local ringGen = 0    -- invalidates an older ring colour change
local showGen = 0    -- invalidates an older "drops under the Show Only When Low time" timer
local showArmed      -- the expiry and minutes that timer was set for

local function On()
    return S.Get("enabled") and S.Get("campfire")
end

-- Camp Benefits is earned in the open world, so dungeons, raids and battlegrounds never
-- nag about it.
local function InOpenWorld()
    local inInstance = IsInInstance()
    return not inInstance
end

-- Show Active Camp Buffs: Off, Always or On Mouseover. A profile that never picked one
-- follows the old on/off switch, so nobody's setting changes.
function ns.CampBuffMode()
    local mode = S.Get("campBuffMode")
    if mode then return mode end
    return S.Get("campBuffs") and "always" or "off"
end

-- On Mouseover: the buff lines stay written but invisible until the icon is hovered.
local function PaintBuffs()
    local hidden = ns.CampBuffMode() == "hover" and not unlocked and not icon:IsMouseOver()
    icon.buffs:SetAlpha(hidden and 0 or 1)
end

local function Build()
    icon = CreateFrame("Frame", "NaowhForeverCampfire", UIParent)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)

    Look.New(icon)

    -- Hovering the icon shows the buff lines while Show Active Camp Buffs is On Mouseover. The
    -- icon only takes the mouse then (Apply), so clicks and camera drags otherwise go through.
    icon:SetScript("OnEnter", PaintBuffs)
    icon:SetScript("OnLeave", PaintBuffs)

    icon.mover = ns.UI.AttachMover(icon, "Campfire", function(pos) S.Set("campPos", pos) end,
        "AuraBuffs/Settings", "AuraBuffs/Settings:campfire")
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
    local step = Look.Step(left)
    icon.drain:SetSwipeColor(step[2], step[3], step[4], 1)
    if step[1] > 0 then
        local gen = ringGen
        C_Timer.After(left - step[1] + 0.1, function()
            if gen == ringGen then ColorRing(expiry) end
        end)
    end
end

local function ShowUp(duration, expiry, buffs)
    Look.Up(icon, ns.CampBuffMode() ~= "off" and buffs or "")
    PaintBuffs()
    if S.Get("campTimer") and duration and duration > 0 then
        if shownExpiry ~= expiry then
            icon.timer:SetCooldown(expiry - duration, duration)
            icon.drain:SetCooldown(expiry - duration, duration)
            ColorRing(expiry)
            shownExpiry = expiry
        end
        Look.Timed(icon, true)
    else
        Look.Timed(icon, false)
        ringGen = ringGen + 1
        shownExpiry = nil
    end
    icon:Show()
end

local function ShowSitting(duration, expiry)
    Look.Sitting(icon)
    ringGen = ringGen + 1
    local timed = S.Get("campTimer")
    if timed and shownExpiry ~= expiry then
        icon.timer:SetCooldown(expiry - duration, duration)
        icon.drain:SetCooldown(expiry - duration, duration)
        icon.drain:SetSwipeColor(T.accent.r, T.accent.g, T.accent.b, 1)
        shownExpiry = expiry
    elseif not timed then
        shownExpiry = nil
    end
    Look.Timed(icon, timed)
    icon:Show()
end

local function ShowMissing()
    Look.Missing(icon)
    ringGen = ringGen + 1
    shownExpiry = nil
    icon:SetShown(S.Get("campShowMissing") or unlocked == true)
end

-- "Camp Nearby" in the middle of the screen when a campfire is in range and the camp needs
-- refreshing: no Camp Benefits, or less than two minutes left on it.
local function BuildAlert()
    alert = CreateFrame("Frame", "NaowhForeverCampNearby", UIParent)
    alert:SetMovable(true)
    alert:SetClampedToScreen(true)
    Look.Alert(alert)
    -- Ctrl-click dismisses it. It takes the mouse only while Ctrl is down, so an ordinary click
    -- or camera drag in the middle of the screen still reaches the world.
    alert:EnableMouse(false)
    alert:SetScript("OnShow", function(self)
        self:EnableMouse(IsControlKeyDown())
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
    end)
    alert:SetScript("OnHide", function(self) self:UnregisterEvent("MODIFIER_STATE_CHANGED") end)
    alert:SetScript("OnEvent", function(self) self:EnableMouse(IsControlKeyDown()) end)
    alert:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and IsControlKeyDown() and not unlocked then
            alertDismissed = true
            self:Hide()
        end
    end)
    alert.mover = ns.UI.AttachMover(alert, "Camp Nearby", function(pos) S.Set("campAlertPos", pos) end,
        "AuraBuffs/Settings", "AuraBuffs/Settings:campNearby")
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

-- The same tags found in the effect text, for a camp feature not in FEATURE_TAGS. Armor comes
-- before stats, since the Enchanted Lute's effect names both.
local EFFECT_TAGS = {
    { "rested", "+Rested" }, { "rest experience", "+Rested" }, { "critical strike", "+Crit" },
    { "armor", "+ARM" }, { "attack power", "+ATK" }, { "strength", "+STR" }, { "stamina", "+STA" },
    { "intellect", "+INT" }, { "spirit", "+Spirit" }, { "mana", "+MP5" }, { "mp5", "+MP5" },
    { "stats", "+Stats" },
}
-- Each camp feature's benefit as a short stat tag. Upgraded features give the benefit of the
-- one they replace (Wowhead's Forever item data, 2026-09-30). Matched by name first, so a
-- benefit text that names other stats (all stats spelled out one by one) cannot mislabel it.
local FEATURE_TAGS = {
    ["Camp Tent"] = "+Rested", ["Tanning Rack"] = "+Rested", ["Sewing Machine"] = "+Rested",
    ["Camp Chair"] = "+Crit", ["Trapper's Workbench"] = "+Crit", ["Field Guide"] = "+Crit",
    ["Enchanted Lute"] = "+ARM", ["Arcane Salvager"] = "+ARM", ["Arcane Forge"] = "+ARM",
    ["Lodestone"] = "+ATK", ["Rock Garden"] = "+ATK", ["Molten Foundry"] = "+ATK",
    ["Sharpening Wheel"] = "+STR", ["Anvil"] = "+STR", ["Master Forge"] = "+STR",
    ["First Aid Kit"] = "+STA", ["Toxin Study"] = "+STA", ["Plague Doctor's Laboratory"] = "+STA",
    ["Incense Candle"] = "+INT", ["Greenhouse"] = "+INT", ["Seed Hybridizer"] = "+INT",
    ["Faction Banner"] = "+Spirit", ["Spinning Wheel"] = "+Spirit", ["Loom"] = "+Spirit",
    ["Mana Well"] = "+MP5", ["Fermenter"] = "+MP5", ["Alchemy Laboratory"] = "+MP5",
    ["Fish Bowl"] = "+Stats", ["Fishing Rack"] = "+Stats", ["Fishing Hut"] = "+Stats",
}

-- Anything neither list knows keeps a short effect text, or else the camp feature's name.
local function ShortCampBuff(label, effect)
    if FEATURE_TAGS[label] then return FEATURE_TAGS[label] end
    local lower = effect:lower()
    for _, tag in ipairs(EFFECT_TAGS) do
        if lower:find(tag[1], 1, true) then return tag[2] end
    end
    if #effect > 0 and #effect <= 28 then return effect end
    return label
end

-- Only readable benefit rows, excluding the tooltip header, timer and ID metadata.
local function ActiveBuffs(aura)
    local data = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", aura.auraInstanceID)
    local names, seen = {}, {}
    for i, line in ipairs(data and data.lines or {}) do
        local text = line.leftText
        if i > 1 and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            for row in text:gmatch("[^\n]+") do
                local label = row:match("^%s*([^:]+):%s*%S")
                if label and not label:find("[%d|]") and not label:find("ID$") then
                    label = label:match("^%s*(.-)%s*$")
                    local effect = row:match("^[^:]+:%s*(.-)%s*$") or ""
                    local short = ShortCampBuff(label, effect)
                    if not seen[short] then
                        names[#names + 1] = short
                        seen[short] = true
                    end
                end
            end
        end
    end
    return table.concat(names, "\n")
end

local Refresh

local function DisarmAlert()
    alertGen = alertGen + 1
    alertArmed = nil
end

-- UNIT_AURA fires often, so the timer is only set again for a new expiry.
local function UpdateAlert(aura)
    if not (S.Get("campNearbyAlert") and C_UnitAuras.GetPlayerAuraBySpellID(CAMPFIRE_NEARBY)) then
        alertDismissed = nil
        DisarmAlert()
        SetAlert(false)
        return
    end
    if alertDismissed then
        DisarmAlert()
        SetAlert(false)
        return
    end
    local expiry = aura and aura.expirationTime
    if expiry and issecretvalue and issecretvalue(expiry) then expiry = nil end
    local left = expiry and expiry > 0 and expiry - GetTime()
    if aura and not left then
        DisarmAlert()
        SetAlert(false)
        return
    end
    local low = S.Get("campNearbyMinutes") * 60
    SetAlert(not aura or left < low)
    if not (aura and left >= low) then
        DisarmAlert()
    elseif alertArmed ~= expiry then
        DisarmAlert()
        alertArmed = expiry
        local gen = alertGen
        C_Timer.After(left - low + 0.1, function()
            if gen == alertGen then
                alertArmed = nil
                Refresh()
            end
        end)
    end
end

-- The client hides the player's auras from addons during combat, where this read comes back
-- empty with the buff up, so the icon keeps whatever it last showed until the fight ends.
-- InCombatLockdown() is still false while PLAYER_REGEN_DISABLED is handled.
function Refresh(_, event)
    if not icon then return end
    if unlocked then
        ShowUp(3600, GetTime() + 2400, "+Rested\n+Crit")
        SetAlert(S.Get("campNearbyAlert"))
        return
    end
    if not (On() and InOpenWorld()) then
        icon:Hide()
        DisarmAlert()
        SetAlert(false)
        return
    end
    if InCombatLockdown() or event == "PLAYER_REGEN_DISABLED" or C_Secrets.ShouldAurasBeSecret() then
        DisarmAlert()
        SetAlert(false)
        return
    end

    local aura = C_UnitAuras.GetPlayerAuraBySpellID(CAMP_BENEFITS)
    local had = hasCamp
    hasCamp = aura ~= nil
    local sitting = C_UnitAuras.GetPlayerAuraBySpellID(WELCOMING_CAMPFIRE)
    local sitDuration, sitExpiry = sitting and sitting.duration, sitting and sitting.expirationTime
    if sitting and not (issecretvalue and (issecretvalue(sitDuration) or issecretvalue(sitExpiry)))
        and sitDuration > 0 then
        ShowSitting(sitDuration, sitExpiry)
        DisarmAlert()
        SetAlert(false)
        return
    end
    if aura then
        local duration, expiry = aura.duration, aura.expirationTime
        if issecretvalue and (issecretvalue(duration) or issecretvalue(expiry)) then
            duration, expiry = nil, nil
        end
        local left = expiry and expiry > 0 and expiry - GetTime()
        local under = S.Get("campShowUnderMinutes") * 60
        if S.Get("campShowUnder") and left and left > under then
            icon:Hide()
            local key = expiry .. ":" .. under
            if showArmed ~= key then
                showArmed = key
                showGen = showGen + 1
                local gen = showGen
                C_Timer.After(left - under + 0.1, function()
                    if gen == showGen then
                        showArmed = nil
                        Refresh()
                    end
                end)
            end
        else
            if showArmed then
                showArmed = nil
                showGen = showGen + 1
            end
            ShowUp(duration, expiry, ns.CampBuffMode() ~= "off" and ActiveBuffs(aura) or "")
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
        DisarmAlert()
        SetAlert(false)
        if icon and not unlocked then icon:Hide() end
        if not unlocked then return end
    end
    if not icon then Build() end
    icon:EnableMouse(ns.CampBuffMode() == "hover")
    Look.Layout(icon)
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
    -- A timer armed for the old threshold would fire at the wrong time.
    if key == "campNearbyMinutes" then DisarmAlert() end
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

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group

local OFF = "Turn on AuraBuffs"
local STAGE_H, ALERT_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN = 230, 90, 10, 11, 16
local CAMP_HOUR, SIT_TIME, BUFF_GAP = 3600, 60, 12
local SAMPLE_BUFFS = "+Rested\n+Crit"
local SAMPLES = { up = 2400, low = 240, sitting = 35 }
local BUFF_MODES = { { off = "Off", always = "Always", hover = "On Mouseover" }, { "off", "always", "hover" } }
local SIDES = { { below = "Below", above = "Above", left = "Left", right = "Right" },
    { "below", "above", "left", "right" } }
local STATES = {
    { key = "up", label = "Camp Up", tip = "Camp Benefits with most of its hour left." },
    { key = "low", label = "Running Low", tip = "Camp Benefits about to run out." },
    { key = "sitting", label = "Sitting", tip = "Sitting at a campfire, before Camp Benefits lands." },
    { key = "missing", label = "Refresh Camp", tip = "No Camp Benefits, out in the world.",
      needs = "campShowMissing" },
}
local ALERT_STATES = {
    { key = "nearby", label = "Camp Nearby", tip = "A campfire in range while your camp needs refreshing." },
}

local function Enabled() return S.Get("enabled") and true or false end
local function Needs(key) return function() return S.Get("enabled") and S.Get(key) and true or false end end
local function CampOn() return S.Get("enabled") and S.Get("campfire") and true or false end
local function PickBuffMode(v) S.Set("campBuffMode", v) end

local function Hidden(state)
    if state == "up" and S.Get("campShowUnder") and SAMPLES.up > S.Get("campShowUnderMinutes") * 60 then
        return ("Show Only When Low: hidden until under %d min."):format(S.Get("campShowUnderMinutes"))
    end
end

local function NewPreview(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.icon = CreateFrame("Frame", nil, shot)
    Look.New(shot.icon)
    shot.note = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    shot.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return shot
end

local function Fit(shot)
    local f = shot.icon
    local reach = f:GetHeight() + (S.Get("campBuffTextSize") + BUFF_GAP) * 2
    local room = shot:GetHeight() - STAGE_MARGIN * 2 - NOTE_Y * 2
    local scale = 1
    if room > 0 and reach > room then scale = room / reach end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", shot, "CENTER", 0, NOTE_Y / scale)
end

local function Run(f, left, duration)
    local start = GetTime() - (duration - left)
    f.timer:SetCooldown(start, duration)
    f.drain:SetCooldown(start, duration)
    Look.Timed(f, S.Get("campTimer"))
end

local function PaintPreview(shot, state)
    local f = shot.icon
    Look.Layout(f)
    Fit(shot)
    local mode = ns.CampBuffMode()
    local hidden = Hidden(state)
    local note = hidden
    if state == "missing" then
        Look.Missing(f)
    elseif state == "sitting" then
        Look.Sitting(f)
        f.drain:SetSwipeColor(T.accent.r, T.accent.g, T.accent.b, 1)
        Run(f, SAMPLES.sitting, SIT_TIME)
    else
        Look.Up(f, mode ~= "off" and SAMPLE_BUFFS or "")
        f.buffs:SetAlpha(1)
        local step = Look.Step(SAMPLES[state])
        f.drain:SetSwipeColor(step[2], step[3], step[4], 1)
        Run(f, SAMPLES[state], CAMP_HOUR)
        if not note and mode == "hover" then note = "The buffs show while you hover the icon." end
    end
    f:SetShown(not hidden)
    shot.note:SetText(note or "")
end

local function NewAlert(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.alert = CreateFrame("Frame", nil, shot)
    Look.Alert(shot.alert)
    shot.alert:SetPoint("CENTER")
    return shot
end

local function PaintAlert() end

local function CampSummary(store)
    local parts = { store.Get("campTimer") and "Timer" or "No timer" }
    local mode = ns.CampBuffMode()
    if mode == "always" then parts[#parts + 1] = "camp buffs"
    elseif mode == "hover" then parts[#parts + 1] = "camp buffs on mouseover" end
    if store.Get("campSound") then parts[#parts + 1] = "a sound to refresh" end
    return table.concat(parts, ", ")
end

local function AlertSummary(store)
    return ("Under %d min"):format(store.Get("campNearbyMinutes"))
end

local page = Settings.Page("AuraBuffs/Settings", S)

page:Card({
    id = "campfire", name = "Campfire", order = 20, switch = "campfire",
    help = "A round camp icon while Camp Benefits is up, a one minute countdown while you sit at a campfire, "
        .. "and a reminder when the camp is gone. Open world only. Move it in Unlock Mode.",
    summary = CampSummary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Icon"),
        { key = "campIconSize", label = "Icon Size", slider = { 24, 110, 1 }, needs = Enabled, why = OFF },
        { key = "campTimer", label = "Show Camp Timer", toggle = true, needs = Enabled, why = OFF,
          help = "A countdown in the icon, and a ring around it that drains as the camp runs down: green "
              .. "above 30 minutes, yellow above 5, red under 5." },
        { key = "campShowMissing", label = "Show Refresh Reminder", toggle = true, needs = Enabled, why = OFF,
          help = "The camp icon, greyed out and saying Refresh Camp, while you have no Camp Benefits." },
        { key = "campShowUnder", label = "Show Only When Low", toggle = true, needs = Enabled, why = OFF,
          help = "Keeps the icon hidden while Camp Benefits has more time left than Show Under, and shows "
              .. "it once the camp drops under that. The sitting countdown and the Refresh Camp reminder "
              .. "still show." },
        { key = "campShowUnderMinutes", label = "Show Under", slider = { 1, 59, 1 }, unit = " min",
          needs = Needs("campShowUnder"), why = "Needs Show Only When Low" },
        Group("Camp Buffs"),
        { key = "campBuffMode", label = "Show Active Camp Buffs", choice = BUFF_MODES, get = ns.CampBuffMode,
          set = PickBuffMode, needs = Enabled, why = OFF,
          help = "The active effects reported in your Camp Benefits tooltip. On Mouseover shows them while "
              .. "the mouse is over the camp icon." },
        { key = "campBuffTextSize", label = "Buff Text Size", slider = { 8, 28, 1 }, needs = Enabled, why = OFF },
        { key = "campBuffSide", label = "Buff Text Position", choice = SIDES, needs = Enabled, why = OFF },
        Group("Sound"),
        { key = "campSound", label = "Play a Sound to Refresh", toggle = true, needs = Enabled, why = OFF,
          help = "Plays when it is time to refresh the camp." },
        { key = "campSoundKey", label = "Sound", sound = true, needs = Needs("campSound"),
          why = "Needs Play a Sound to Refresh" },
    },
})

page:Card({
    id = "campNearby", name = "Camp Nearby", order = 30, switch = "campNearbyAlert",
    help = "\"Camp Nearby\" in the middle of the screen when a campfire is in range and your camp needs "
        .. "refreshing: no Camp Benefits, or less than Alert Under minutes left. Ctrl-click it to dismiss "
        .. "it until you leave that campfire. Part of the Campfire reminder, so it needs that on. Move it "
        .. "in Unlock Mode.",
    summary = AlertSummary,
    studio = { height = ALERT_H, states = ALERT_STATES, new = NewAlert, paint = PaintAlert },
    rows = {
        { key = "campNearbyMinutes", label = "Alert Under", slider = { 1, 59, 1 }, unit = " min",
          needs = CampOn, why = "Needs the Campfire reminder",
          help = "How little Camp Benefits time counts as needing a refresh." },
    },
})
