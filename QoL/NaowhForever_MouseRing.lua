-------------------------------------------------------------------------------
--  NaowhForever_MouseRing.lua -- the QoL mouse ring: a ring that follows the cursor, with
--  your global cooldown and casts swept around it, an optional trail, centre dot and border,
--  and a red recolour while your target is out of melee range.
--
--  The melee check uses the crosshair's spell, Melee Spell ID included.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\MouseRing\\"
local RING_TEXEL = 0.5 / 256
local TRAIL_TEXEL = 0.5 / 128
local TRAIL_MAX = 60
local TRAIL_SHAPES = {
    glow = "trail_glow.tga", circle = "nq_circle.tga", ring = "nq_ring_soft1.tga",
    star = "nq_star.tga", sparkle = "sparkle.tga",
}
local MELEE_TICK = 0.05
local IDLE_FADE = 0.5
local PI, TWO_PI = math.pi, math.pi * 2
local floor, max, min = math.floor, math.max, math.min

local sparkleColors = {}
for i = 1, 40 do
    sparkleColors[i] = { r = math.random(30, 90) / 100, g = math.random(30, 90) / 100,
        b = math.random(30, 90) / 100 }
end

local container, ring, borderRing, readyRing, dot
local sweep = {}
local trail, trailPoints = nil, {}

local state = {
    inCombat = false, inInstance = false, afk = false, rightDown = false,
    castStart = 0, castEnd = 0, casting = false,
    gcd = nil, castSwipeAllowed = false, gcdSwipeAllowed = true,
    outOfMelee = false, lastInRange = nil,
    lastMove = 0, idleAlpha = 1,
}
local sweepState = { active = false, mode = nil, start = 0, duration = 1, modRate = 1 }
local castDelay, gcdDelay, alarmTicker
local meleeSpell
local meleeTicker, mouseWatcher = CreateFrame("Frame"), CreateFrame("Frame")

local UpdateRender

local function On()
    return S.Get("enabled") and S.Get("mouseRing")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Color(key, classKey)
    if S.Get(classKey) then return RAID_CLASS_COLORS[select(2, UnitClass("player"))] end
    return S.Get(key)
end

local function SetupTexture(tex, shape)
    tex:SetTexture(MEDIA .. shape, "CLAMP", "CLAMP", "TRILINEAR")
    tex:SetTexCoord(RING_TEXEL, 1 - RING_TEXEL, RING_TEXEL, 1 - RING_TEXEL)
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
end

local function Visible()
    if not On() then return false end
    if S.Get("mouseHideOnClick") and state.rightDown then return false end
    if state.inCombat then return true end
    if S.Get("mouseHideAfk") and state.afk then return false end
    return S.Get("mouseShowOOC")
end

-- The idle fade is applied to the whole ring and trail, on top of this.
local function Opacity()
    return (state.inCombat or state.inInstance) and S.Get("mouseOpacityCombat")
        or S.Get("mouseOpacityOOC")
end

-------------------------------------------------------------------------------
--  Sweep: two half rings masked by rotating half discs
-------------------------------------------------------------------------------
local function HideSweep()
    sweep.right:Hide()
    sweep.left:Hide()
    sweep.frame:Hide()
end

-- Returns true once the sweep has finished.
local function UpdateSweep()
    local s = sweepState
    if not s.active then return end
    local frac = min((GetTime() - s.start) / (s.duration / s.modRate), 1)
    if frac >= 1 then
        if s.mode == "gcd" then
            state.gcd = nil
            state.gcdSwipeAllowed = true
        end
        s.active, s.mode = false, nil
        HideSweep()
        return true
    end
    local angle = frac * TWO_PI
    sweep.right:SetVertexColor(s.r, s.g, s.b, s.a)
    sweep.rightProg:SetRotation(PI - min(angle, PI))
    sweep.right:Show()
    if angle > PI then
        sweep.left:SetVertexColor(s.r, s.g, s.b, s.a)
        sweep.leftProg:SetRotation(-(angle - PI))
        sweep.left:Show()
    else
        sweep.left:Hide()
    end
end

local function SweepHalf(clipRotation, progRotation)
    local tex = sweep.frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local clip = sweep.frame:CreateMaskTexture()
    clip:SetTexture(MEDIA .. "half_disk_clip.tga", "CLAMP", "CLAMP", "TRILINEAR")
    clip:SetAllPoints()
    clip:SetRotation(clipRotation)
    tex:AddMaskTexture(clip)
    local prog = sweep.frame:CreateMaskTexture()
    prog:SetTexture(MEDIA .. "half_disk.tga", "CLAMP", "CLAMP", "TRILINEAR")
    prog:SetAllPoints()
    prog:SetRotation(progRotation)
    tex:AddMaskTexture(prog)
    tex:Hide()
    return tex, prog
end

-------------------------------------------------------------------------------
--  Frames
-------------------------------------------------------------------------------
local function BuildRing()
    container = CreateFrame("Frame", "NaowhForeverMouseRing", UIParent)
    container:SetFrameStrata("TOOLTIP")
    container:EnableMouse(false)

    borderRing = container:CreateTexture(nil, "BACKGROUND")
    borderRing:SetPoint("CENTER")
    ring = container:CreateTexture(nil, "BORDER")
    ring:SetAllPoints()
    readyRing = container:CreateTexture(nil, "ARTWORK")
    readyRing:SetAllPoints()

    sweep.frame = CreateFrame("Frame", nil, container)
    sweep.frame:SetAllPoints()
    sweep.frame:SetFrameLevel(container:GetFrameLevel() + 5)
    sweep.frame:Hide()
    sweep.right, sweep.rightProg = SweepHalf(0, PI)
    sweep.left, sweep.leftProg = SweepHalf(PI, 0)
    sweep.frame:SetScript("OnUpdate", function()
        if UpdateSweep() then UpdateRender() end
    end)

    dot = container:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    dot:SetPoint("CENTER")

    local lastX, lastY = 0, 0
    container:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x, y = floor(x / scale + 0.5), floor(y / scale + 0.5)
        if x ~= lastX or y ~= lastY then
            lastX, lastY = x, y
            state.lastMove = GetTime()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end
        if S.Get("mouseFadeIdle") then
            local idle = GetTime() - state.lastMove - S.Get("mouseFadeDelay")
            local target = S.Get("mouseFadeOpacity")
            state.idleAlpha = idle > 0 and max(target, 1 - idle / IDLE_FADE * (1 - target)) or 1
            self:SetAlpha(state.idleAlpha)
            if trail then trail:SetAlpha(state.idleAlpha) end
        elseif state.idleAlpha ~= 1 then
            state.idleAlpha = 1
            self:SetAlpha(1)
            if trail then trail:SetAlpha(1) end
        end
    end)
end

local function BuildTrail()
    trail = CreateFrame("Frame", nil, UIParent)
    trail:SetFrameStrata("TOOLTIP")
    trail:SetFrameLevel(1)
    trail:SetPoint("BOTTOMLEFT")
    trail:SetSize(1, 1)
    trail:Hide()
    for i = 1, TRAIL_MAX do
        local tex = trail:CreateTexture(nil, "BACKGROUND")
        tex:SetBlendMode("ADD")
        tex:Hide()
        trailPoints[i] = { tex = tex, x = 0, y = 0, time = 0, active = false }
    end

    local head, lastX, lastY, acc, activeCount = 0, 0, 0, 0, 0
    local function Step(self, elapsed)
        acc = acc + elapsed
        if acc < 0.025 then return end
        acc = 0
        local now = GetTime()
        local tracking = S.Get("mouseTrail") and Visible()
        if tracking then
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            x, y = floor(x / scale + 0.5), floor(y / scale + 0.5)
            local spacing = max(2, S.Get("mouseTrailSize") * 0.1)
            if (x - lastX) ^ 2 + (y - lastY) ^ 2 >= spacing * spacing then
                lastX, lastY = x, y
                head = head % S.Get("mouseTrailLength") + 1
                local pt = trailPoints[head]
                if not pt.active then activeCount = activeCount + 1 end
                pt.x, pt.y, pt.time, pt.active = x, y, now, true
            end
        end
        if activeCount > 0 then
            local duration = max(S.Get("mouseTrailDuration"), 0.1)
            local c = Color("mouseTrailColor", "mouseTrailClassColor")
            local alpha = Opacity() * S.Get("mouseTrailBrightness")
            local size = S.Get("mouseTrailSize")
            local sparkle = S.Get("mouseTrailSparkle")
            for i = 1, TRAIL_MAX do
                local pt = trailPoints[i]
                if pt.active then
                    local fade = 1 - (now - pt.time) / duration
                    if fade <= 0 then
                        pt.active = false
                        pt.tex:Hide()
                        activeCount = activeCount - 1
                    else
                        local pc = sparkle and sparkleColors[(i - 1) % #sparkleColors + 1] or c
                        pt.tex:ClearAllPoints()
                        pt.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pt.x, pt.y)
                        pt.tex:SetVertexColor(pc.r, pc.g, pc.b, fade * alpha)
                        pt.tex:SetSize(size * fade, size * fade)
                        pt.tex:Show()
                    end
                end
            end
        end
        if not tracking and activeCount == 0 then self:SetScript("OnUpdate", nil) end
    end
    trail:SetScript("OnShow", function(self) self:SetScript("OnUpdate", Step) end)
end

local function StyleTrail()
    local path = MEDIA .. (TRAIL_SHAPES[S.Get("mouseTrailShape")] or TRAIL_SHAPES.glow)
    for _, pt in ipairs(trailPoints) do
        pt.tex:SetTexture(path, "CLAMP", "CLAMP", "TRILINEAR")
        pt.tex:SetTexCoord(TRAIL_TEXEL, 1 - TRAIL_TEXEL, TRAIL_TEXEL, 1 - TRAIL_TEXEL)
    end
end

-------------------------------------------------------------------------------
--  Render
-------------------------------------------------------------------------------
local function StartSweep(mode, start, duration, modRate, c, alpha)
    sweepState.active, sweepState.mode = true, mode
    sweepState.start, sweepState.duration, sweepState.modRate = start, duration, modRate
    sweepState.r, sweepState.g, sweepState.b, sweepState.a = c.r, c.g, c.b, alpha
    sweep.frame:Show()
    UpdateSweep()
end

function UpdateRender()
    if not container then return end
    if not Visible() then
        container:Hide()
        if trail then trail:Hide() end
        return
    end
    container:Show()
    local alpha = Opacity()
    local melee = S.Get("mouseMelee") and state.outOfMelee
    local gcdOn = S.Get("mouseGCD")

    local size = S.Get("mouseSize")
    local showBorder = S.Get("mouseBorder") or (melee and S.Get("mouseMeleeBorder"))
    if showBorder then
        local bw = S.Get("mouseBorderWeight")
        local c = (melee and S.Get("mouseMeleeBorder")) and { r = 1, g = 0, b = 0 }
            or Color("mouseBorderColor", "mouseBorderClassColor")
        borderRing:SetSize(size + bw * 2, size + bw * 2)
        borderRing:SetVertexColor(c.r, c.g, c.b, alpha)
        borderRing:Show()
    else
        borderRing:Hide()
    end

    if gcdOn and S.Get("mouseHideBackground") then
        ring:Hide()
    else
        local c = melee and { r = 1, g = 0, b = 0 } or Color("mouseColor", "mouseClassColor")
        ring:SetVertexColor(c.r, c.g, c.b, alpha)
        ring:Show()
    end

    local sweepAlpha = alpha * S.Get("mouseGCDAlpha")
    if gcdOn and S.Get("mouseCastSwipe") and state.casting and state.castSwipeAllowed then
        StartSweep("cast", state.castStart, state.castEnd - state.castStart, 1,
            Color("mouseCastColor", "mouseCastClassColor"), sweepAlpha)
    elseif gcdOn and state.gcd and state.gcdSwipeAllowed then
        StartSweep("gcd", state.gcd.startTime, state.gcd.duration, state.gcd.modRate or 1,
            Color("mouseGCDColor", "mouseGCDClassColor"), sweepAlpha)
    else
        sweepState.active, sweepState.mode = false, nil
        HideSweep()
    end

    if gcdOn and not state.gcd and not state.casting then
        local c = S.Get("mouseReadyMatch") and Color("mouseGCDColor", "mouseGCDClassColor")
            or S.Get("mouseReadyColor")
        if melee and S.Get("mouseMeleeRing") then c = { r = 1, g = 0, b = 0 } end
        readyRing:SetVertexColor(c.r, c.g, c.b, alpha)
        readyRing:Show()
    else
        readyRing:Hide()
    end

    if S.Get("mouseDot") then
        local ds = S.Get("mouseDotSize")
        local c = Color("mouseDotColor", "mouseDotClassColor")
        dot:SetSize(ds, ds)
        dot:SetVertexColor(c.r, c.g, c.b, alpha)
        dot:Show()
    else
        dot:Hide()
    end

    if trail then trail:SetShown(S.Get("mouseTrail")) end
end

-------------------------------------------------------------------------------
--  Melee range
-------------------------------------------------------------------------------
local function StopAlarm()
    if alarmTicker then
        alarmTicker:Cancel()
        alarmTicker = nil
    end
end

local function PlayAlarm()
    UI._PlayLSMSound(UI.SoundPathFor(S.Get("mouseMeleeSoundKey")))
end

local function StartAlarm()
    StopAlarm()
    PlayAlarm()
    local every = S.Get("mouseMeleeSoundInterval")
    if every > 0 then alarmTicker = C_Timer.NewTicker(every, PlayAlarm) end
end

local function SetOutOfMelee(out)
    if out == state.outOfMelee then return end
    state.outOfMelee = out
    UpdateRender()
end

local meleeAcc = 0
local function MeleeTick(_, elapsed)
    meleeAcc = meleeAcc + elapsed
    if meleeAcc < MELEE_TICK then return end
    meleeAcc = 0
    local inRange = C_Spell.IsSpellInRange(meleeSpell, "target")
    if inRange == nil or Secret(inRange) then return end
    if not inRange and state.lastInRange == true and S.Get("mouseMeleeSound") then StartAlarm() end
    if inRange then StopAlarm() end
    state.lastInRange = inRange
    SetOutOfMelee(not inRange)
end

local function EvaluateMelee()
    meleeSpell = ns.MeleeRangeSpell()
    if On() and S.Get("mouseMelee") and meleeSpell and UnitExists("target")
        and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target") then
        meleeTicker:SetScript("OnUpdate", MeleeTick)
        if not S.Get("mouseMeleeSound") then StopAlarm() end
    else
        meleeTicker:SetScript("OnUpdate", nil)
        StopAlarm()
        state.lastInRange = nil
        SetOutOfMelee(false)
    end
end

-------------------------------------------------------------------------------
--  Casts and the global cooldown. The player's own casts are never secret; the global
--  cooldown is read only while the client hands it over readable.
-------------------------------------------------------------------------------
local function DelaySwipe(field, timerVar)
    state[field] = false
    if timerVar then timerVar:Cancel() end
    return C_Timer.NewTimer(S.Get("mouseSwipeDelay"), function()
        state[field] = true
        UpdateRender()
    end)
end

local function ReadCast()
    local _, _, _, startMs, endMs = UnitCastingInfo("player")
    if not startMs then _, _, _, startMs, endMs = UnitChannelInfo("player") end
    if startMs and not Secret(startMs) and not Secret(endMs) then
        -- A pushback moves the end of a cast already showing; only a new cast waits again.
        local already = state.casting
        state.casting, state.castStart, state.castEnd = true, startMs / 1000, endMs / 1000
        if not already then castDelay = DelaySwipe("castSwipeAllowed", castDelay) end
    else
        state.casting = false
        if castDelay then castDelay:Cancel(); castDelay = nil end
        state.castSwipeAllowed = false
    end
end

local function ReadGCD()
    local info = C_Spell.GetSpellCooldown(ns.GCDSpell())
    if info and info.isOnGCD and not Secret(info.duration) and not Secret(info.startTime)
        and not Secret(info.modRate) then
        local wasReady = state.gcd == nil
        state.gcd = info
        if wasReady then gcdDelay = DelaySwipe("gcdSwipeAllowed", gcdDelay) end
    else
        state.gcd = nil
        if gcdDelay then gcdDelay:Cancel(); gcdDelay = nil end
        state.gcdSwipeAllowed = true
    end
end

local function RefreshZone()
    state.inCombat = UnitAffectingCombat("player")
    local inInstance, kind = IsInInstance()
    state.inInstance = inInstance and (kind == "party" or kind == "raid" or kind == "pvp")
    state.afk = not state.inInstance and UnitIsAFK("player") or false
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" or event == "SPELLS_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
        state.lastInRange = nil
        StopAlarm()
        SetOutOfMelee(false)
        EvaluateMelee()
        return
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if S.Get("mouseGCD") then ReadGCD() end
    elseif event:find("^UNIT_SPELLCAST") then
        ReadCast()
    else
        RefreshZone()
    end
    UpdateRender()
end)

mouseWatcher:SetScript("OnUpdate", function()
    local down = IsMouseButtonDown("RightButton")
    if down ~= state.rightDown then
        state.rightDown = down
        UpdateRender()
    end
end)
mouseWatcher:Hide()

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if container then container:Hide() end
        if trail then trail:Hide() end
        mouseWatcher:Hide()
        EvaluateMelee()
        return
    end
    if not container then
        BuildRing()
        BuildTrail()
    end
    local shape = S.Get("mouseShape")
    local size = S.Get("mouseSize")
    size = size + size % 2
    container:SetSize(size, size)
    for _, tex in ipairs({ borderRing, ring, readyRing, sweep.right, sweep.left }) do
        SetupTexture(tex, shape)
    end
    StyleTrail()
    state.rightDown = false
    mouseWatcher:SetShown(S.Get("mouseHideOnClick"))
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "PLAYER_FLAGS_CHANGED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
        events:RegisterUnitEvent(event, "player")
    end
    RefreshZone()
    ReadCast()
    ReadGCD()
    state.lastMove = GetTime()
    EvaluateMelee()
    UpdateRender()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "crossMeleeSpell" or key:find("^mouse") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
