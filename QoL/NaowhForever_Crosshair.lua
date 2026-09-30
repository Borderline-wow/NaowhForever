-------------------------------------------------------------------------------
--  NaowhForever_Crosshair.lua -- the QoL crosshair: four arms, a dot and a circle at the
--  middle of the screen, optionally recoloured with a sound while your target is out of
--  melee range.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

local BAR = "Interface\\Buttons\\WHITE8x8"
local RING = "Interface\\AddOns\\NaowhForever\\Media\\crosshair_ring.tga"
local TEXEL_HALF = 0.5 / 512
local PI, sin, cos = math.pi, math.sin, math.cos
local TICK = 0.05

-- A melee-range ability per class, lowest rank (Forever keeps every rank known). Druids
-- depend on form. Shamans without Stormstrike and casters have none; a spell ID of your own
-- can be set on the options page.
local MELEE = { WARRIOR = 1715, ROGUE = 1752, HUNTER = 2973, SHAMAN = 17364, PALADIN = 679 }
local DRUID_MELEE = { [1] = 1082, [5] = 6807, [8] = 6807 }   -- Claw in Cat, Maul in Bear

local ARMS = {
    { key = "crossTop", base = 0 },
    { key = "crossRight", base = PI / 2 },
    { key = "crossBottom", base = PI },
    { key = "crossLeft", base = 3 * PI / 2 },
}

local frame, arms, shadows, dot, dotShadow, ring, ringShadow
local inCombat, outOfMelee, lastInRange = false, false, nil
local alarmTicker, tickAcc = nil, 0
local ticker = CreateFrame("Frame")

local function On()
    return S.Get("enabled") and S.Get("crosshair")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Color(key, classKey)
    if classKey and S.Get(classKey) then return RAID_CLASS_COLORS[select(2, UnitClass("player"))] end
    return S.Get(key)
end

local function MeleeSpell()
    local own = S.Get("crossMeleeSpell")
    if own > 0 then return own end
    local _, class = UnitClass("player")
    if class == "DRUID" then return DRUID_MELEE[GetShapeshiftFormID()] end
    local id = MELEE[class]
    return id and C_SpellBook.IsSpellKnown(id) and id or nil
end
ns.MeleeRangeSpell = MeleeSpell

local function Texture(layer, sub, path)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(path, "CLAMP", "CLAMP", "TRILINEAR")
    if path == RING then
        t:SetTexCoord(TEXEL_HALF, 1 - TEXEL_HALF, TEXEL_HALF, 1 - TEXEL_HALF)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    return t
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverCrosshair", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:EnableMouse(false)
    arms, shadows = {}, {}
    for i = 1, #ARMS do
        shadows[i] = Texture("ARTWORK", 0, BAR)
        arms[i] = Texture("ARTWORK", 1, BAR)
    end
    dotShadow, dot = Texture("ARTWORK", 0, BAR), Texture("ARTWORK", 1, BAR)
    ringShadow, ring = Texture("ARTWORK", 0, RING), Texture("ARTWORK", 1, RING)
end

-- Draws one piece and its outline, centred on (x, y) from the frame's corner.
local function Place(tex, shadow, w, h, x, y, angle, c, outline, ow, alpha)
    tex:SetSize(w, h)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", frame, "BOTTOMLEFT", x, y)
    tex:SetRotation(angle)
    tex:SetVertexColor(c.r, c.g, c.b, alpha)
    tex:Show()
    if outline then
        shadow:SetSize(w + ow * 2, h + ow * 2)
        shadow:ClearAllPoints()
        shadow:SetPoint("CENTER", frame, "BOTTOMLEFT", x, y)
        shadow:SetRotation(angle)
        shadow:SetVertexColor(outline.r, outline.g, outline.b, alpha)
        shadow:Show()
    else
        shadow:Hide()
    end
end

local function Layout()
    local size, thick, gap = S.Get("crossSize"), S.Get("crossThickness"), S.Get("crossGap")
    local alpha = S.Get("crossOpacity")
    local base = Color("crossColor", "crossClassColor")
    local outline = S.Get("crossOutline") and S.Get("crossOutlineColor") or nil
    local ow = S.Get("crossOutlineWeight")

    local melee = S.Get("crossMelee") and outOfMelee
    local meleeColor = S.Get("crossMeleeColor")
    if melee and S.Get("crossMeleeBorder") then outline = meleeColor end

    local span = gap + size + (outline and ow or 0) + 2
    frame:SetSize(span * 2, span * 2)
    local scale = UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        math.floor(S.Get("crossX") * scale + 0.5) / scale, math.floor(S.Get("crossY") * scale + 0.5) / scale)

    local armColor = melee and S.Get("crossMeleeArms") and meleeColor or base
    for i, def in ipairs(ARMS) do
        if S.Get(def.key) then
            local dist = gap + size / 2
            Place(arms[i], shadows[i], thick, size, span + dist * sin(def.base),
                span + dist * cos(def.base), -def.base, armColor, outline, ow, alpha)
        else
            arms[i]:Hide()
            shadows[i]:Hide()
        end
    end

    if S.Get("crossDot") then
        local ds = S.Get("crossDotSize")
        Place(dot, dotShadow, ds, ds, span, span, 0,
            melee and S.Get("crossMeleeDot") and meleeColor or base, outline, ow, alpha)
    else
        dot:Hide()
        dotShadow:Hide()
    end

    if S.Get("crossCircle") then
        local cs = S.Get("crossCircleSize")
        Place(ring, ringShadow, cs, cs, span, span, 0,
            melee and S.Get("crossMeleeCircle") and meleeColor or S.Get("crossCircleColor"),
            outline, ow, alpha)
    else
        ring:Hide()
        ringShadow:Hide()
    end
end

local function Visible()
    if S.Get("crossCombatOnly") and not inCombat then return false end
    return not (S.Get("crossHideMounted") and IsMounted())
end

-------------------------------------------------------------------------------
--  Melee range
-------------------------------------------------------------------------------
local function PlayAlarm()
    UI._PlayLSMSound(UI.SoundPathFor(S.Get("crossMeleeSoundKey")))
end

local function StopAlarm()
    if alarmTicker then
        alarmTicker:Cancel()
        alarmTicker = nil
    end
end

local function StartAlarm()
    StopAlarm()
    PlayAlarm()
    local every = S.Get("crossMeleeSoundInterval")
    if every > 0 then alarmTicker = C_Timer.NewTicker(every, PlayAlarm) end
end

local function SetOutOfMelee(out)
    if out == outOfMelee then return end
    outOfMelee = out
    Layout()
end

local function HasTarget()
    return UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")
end

local spell

local function Tick(_, elapsed)
    tickAcc = tickAcc + elapsed
    if tickAcc < TICK then return end
    tickAcc = 0
    local inRange = C_Spell.IsSpellInRange(spell, "target")
    if inRange == nil or Secret(inRange) then return end
    -- The sound plays on leaving range, not on picking a target that is already out of it.
    if not inRange and lastInRange == true and S.Get("crossMeleeSound") then StartAlarm() end
    if inRange then StopAlarm() end
    lastInRange = inRange
    SetOutOfMelee(not inRange)
end

local function EvaluateMelee()
    spell = MeleeSpell()
    if On() and S.Get("crossMelee") and spell and HasTarget() then
        ticker:SetScript("OnUpdate", Tick)
        if not S.Get("crossMeleeSound") then StopAlarm() end
    else
        ticker:SetScript("OnUpdate", nil)
        StopAlarm()
        lastInRange = nil
        if frame then SetOutOfMelee(false) end
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_TARGET_CHANGED" then
        lastInRange = nil
        StopAlarm()
        SetOutOfMelee(false)
        EvaluateMelee()
        return
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "SPELLS_CHANGED" then
        EvaluateMelee()
        return
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        Layout()
    end
    frame:SetShown(Visible())
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if frame then frame:Hide() end
        EvaluateMelee()
        return
    end
    if not frame then Build() end
    inCombat = UnitAffectingCombat("player")
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM",
        "SPELLS_CHANGED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
        events:RegisterEvent(event)
    end
    Layout()
    frame:SetShown(Visible())
    EvaluateMelee()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^cross") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
