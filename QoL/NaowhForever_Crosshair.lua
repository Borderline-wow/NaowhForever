-------------------------------------------------------------------------------
--  NaowhForever_Crosshair.lua -- the QoL crosshair at the middle of the screen, optionally
--  recoloured while your target is out of melee range, and its card on QoL > Cursor with a
--  live preview drawn by the same code as the crosshair.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI
local T = ns.THEME

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

local frame, parts
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

local function Texture(f, layer, sub, path)
    local t = f:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(path, "CLAMP", "CLAMP", "TRILINEAR")
    if path == RING then
        t:SetTexCoord(TEXEL_HALF, 1 - TEXEL_HALF, TEXEL_HALF, 1 - TEXEL_HALF)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    return t
end

local Look = {}

function Look.New(f)
    local p = { arms = {}, shadows = {} }
    for i = 1, #ARMS do
        p.shadows[i] = Texture(f, "ARTWORK", 0, BAR)
        p.arms[i] = Texture(f, "ARTWORK", 1, BAR)
    end
    p.dotShadow, p.dot = Texture(f, "ARTWORK", 0, BAR), Texture(f, "ARTWORK", 1, BAR)
    p.ringShadow, p.ring = Texture(f, "ARTWORK", 0, RING), Texture(f, "ARTWORK", 1, RING)
    return p
end

-- Draws one piece and its outline, centred on (x, y) from the frame's corner.
local function Place(f, tex, shadow, w, h, x, y, angle, c, outline, ow, alpha)
    tex:SetSize(w, h)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", f, "BOTTOMLEFT", x, y)
    tex:SetRotation(angle)
    tex:SetVertexColor(c.r, c.g, c.b, alpha)
    tex:Show()
    if outline then
        shadow:SetSize(w + ow * 2, h + ow * 2)
        shadow:ClearAllPoints()
        shadow:SetPoint("CENTER", f, "BOTTOMLEFT", x, y)
        shadow:SetRotation(angle)
        shadow:SetVertexColor(outline.r, outline.g, outline.b, alpha)
        shadow:Show()
    else
        shadow:Hide()
    end
end

function Look.Paint(f, p, out)
    local size, thick, gap = S.Get("crossSize"), S.Get("crossThickness"), S.Get("crossGap")
    local alpha = S.Get("crossOpacity")
    local base = Color("crossColor", "crossClassColor")
    local outline = S.Get("crossOutline") and S.Get("crossOutlineColor") or nil
    local ow = S.Get("crossOutlineWeight")

    local melee = S.Get("crossMelee") and out
    local meleeColor = S.Get("crossMeleeColor")
    if melee and S.Get("crossMeleeBorder") then outline = meleeColor end

    local span = gap + size + (outline and ow or 0) + 2
    f:SetSize(span * 2, span * 2)

    local armColor = melee and S.Get("crossMeleeArms") and meleeColor or base
    for i, def in ipairs(ARMS) do
        if S.Get(def.key) then
            local dist = gap + size / 2
            Place(f, p.arms[i], p.shadows[i], thick, size, span + dist * sin(def.base),
                span + dist * cos(def.base), -def.base, armColor, outline, ow, alpha)
        else
            p.arms[i]:Hide()
            p.shadows[i]:Hide()
        end
    end

    if S.Get("crossDot") then
        local ds = S.Get("crossDotSize")
        Place(f, p.dot, p.dotShadow, ds, ds, span, span, 0,
            melee and S.Get("crossMeleeDot") and meleeColor or base, outline, ow, alpha)
    else
        p.dot:Hide()
        p.dotShadow:Hide()
    end

    if S.Get("crossCircle") then
        local cs = S.Get("crossCircleSize")
        Place(f, p.ring, p.ringShadow, cs, cs, span, span, 0,
            melee and S.Get("crossMeleeCircle") and meleeColor or S.Get("crossCircleColor"),
            outline, ow, alpha)
    else
        p.ring:Hide()
        p.ringShadow:Hide()
    end
    return span
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverCrosshair", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:EnableMouse(false)
    parts = Look.New(frame)
end

local function Layout()
    Look.Paint(frame, parts, outOfMelee)
    local scale = UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        math.floor(S.Get("crossX") * scale + 0.5) / scale, math.floor(S.Get("crossY") * scale + 0.5) / scale)
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

local Group = ns.Shared.Settings.Group
local PREVIEW_FIT = 120
local PREVIEW_Y = 10
local NOTE_Y, NOTE_SIZE = 10, 11
local STATES = {
    { key = "inRange", label = "In Range", tip = "No target, or your target in melee range: the crosshair in its own colours." },
    { key = "outOfRange", label = "Out of Range", tip = "Your target out of melee range.", needs = "crossMelee" },
}


local function OwnColour() return not S.Get("crossClassColor") end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.shape = CreateFrame("Frame", nil, preview)
    preview.shape:SetPoint("CENTER", 0, PREVIEW_Y)
    preview.parts = Look.New(preview.shape)
    preview.note = preview:CreateFontString(nil, "OVERLAY")
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    preview.note:SetFont(ns.UIFontPath(), NOTE_SIZE, "")
    preview.note:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1)
    return preview
end

local function PaintPreview(preview, state)
    local out = state == "outOfRange"
    local span = Look.Paint(preview.shape, preview.parts, out)
    preview.shape:SetScale(math.min(1, PREVIEW_FIT / math.max(1, span * 2)))
    preview.note:SetText("")
end

local function Summary(store)
    local arms = 0
    for _, def in ipairs(ARMS) do
        if store.Get(def.key) then arms = arms + 1 end
    end
    return ("%d %s%s%s%s"):format(arms, arms == 1 and "arm" or "arms", store.Get("crossDot") and ", dot" or "",
        store.Get("crossCircle") and ", circle" or "", store.Get("crossCombatOnly") and ", in combat only" or "")
end

ns.Shared.Settings.Page("QoL/Cursor", S):Card({
    id = "crosshair", name = "Crosshair", order = 10, switch = "crosshair",
    help = "A crosshair at the middle of your screen.",
    summary = Summary,
    studio = { height = 170, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("When"),
        { key = "crossCombatOnly", label = "Only In Combat", toggle = true },
        { key = "crossHideMounted", label = "Hide While Mounted", toggle = true },
        Group("Shape"),
        { key = "crossTop", label = "Top Arm", toggle = true },
        { key = "crossRight", label = "Right Arm", toggle = true },
        { key = "crossBottom", label = "Bottom Arm", toggle = true },
        { key = "crossLeft", label = "Left Arm", toggle = true },
        { key = "crossSize", label = "Arm Length", slider = { 4, 100, 1 } },
        { key = "crossThickness", label = "Thickness", slider = { 1, 20, 1 } },
        { key = "crossGap", label = "Gap", slider = { 0, 50, 1 }, wide = true,
          help = "Space between the middle and each arm." },
        { key = "crossDot", label = "Centre Dot", toggle = true },
        { key = "crossDotSize", label = "Dot Size", slider = { 1, 20, 1 }, needs = "crossDot" },
        { key = "crossCircle", label = "Circle", toggle = true },
        { key = "crossCircleSize", label = "Circle Size", slider = { 10, 200, 1 }, needs = "crossCircle" },
        Group("Colour"),
        { key = "crossClassColor", label = "Class Colour", toggle = true },
        { key = "crossColor", label = "Colour", colour = true, needs = OwnColour, why = "Class colour is on" },
        { key = "crossCircleColor", label = "Circle Colour", colour = true, needs = "crossCircle" },
        { key = "crossOpacity", label = "Opacity", slider = { 10, 100, 5 }, unit = "%", scale = 0.01 },
        Group("Outline"),
        { key = "crossOutline", label = "Outline", toggle = true },
        { key = "crossOutlineWeight", label = "Outline Width", slider = { 1, 5, 1 }, needs = "crossOutline" },
        { key = "crossOutlineColor", label = "Outline Colour", colour = true, needs = "crossOutline" },
        Group("Position"),
        { key = "crossX", label = "X Offset", slider = { -500, 500, 1 } },
        { key = "crossY", label = "Y Offset", slider = { -500, 500, 1 } },
        Group("Out of Melee Range"),
        { key = "crossMelee", label = "Recolour Out of Melee Range", toggle = true,
          help = "Changes colour while your target is out of melee range. Warriors, rogues, hunters "
              .. "(Raptor Strike), shamans with Stormstrike, and druids in Cat or Bear Form have "
              .. "an ability it can check; anyone else can set a spell ID below." },
        { key = "crossMeleeColor", label = "Out of Range Colour", colour = true, needs = "crossMelee" },
        { key = "crossMeleeBorder", label = "Recolour Outline", toggle = true, needs = "crossMelee" },
        { key = "crossMeleeArms", label = "Recolour Arms", toggle = true, needs = "crossMelee" },
        { key = "crossMeleeDot", label = "Recolour Dot", toggle = true, needs = "crossMelee" },
        { key = "crossMeleeCircle", label = "Recolour Circle", toggle = true, needs = "crossMelee" },
        { key = "crossMeleeSound", label = "Play a Sound", toggle = true, needs = "crossMelee",
          help = "Plays as your target leaves melee range." },
        { key = "crossMeleeSoundKey", label = "Sound", sound = true, needs = { "crossMelee", "crossMeleeSound" } },
        { key = "crossMeleeSoundInterval", label = "Repeat Every (s)", slider = { 0, 10, 1 },
          needs = { "crossMelee", "crossMeleeSound" },
          help = "Plays the sound again this often while out of range. 0 plays it once." },
        { key = "crossMeleeSpell", label = "Melee Spell ID", text = true, wide = true, always = true,
          help = "Spell ID to check melee range with. 0 uses your class's own. The mouse ring's "
              .. "melee check uses it too.",
          get = function() return tostring(S.Get("crossMeleeSpell")) end,
          set = function(v) S.Set("crossMeleeSpell", tonumber(v) or 0) end },
    },
})
