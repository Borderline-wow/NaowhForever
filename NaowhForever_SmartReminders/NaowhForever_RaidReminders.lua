-------------------------------------------------------------------------------
--  NaowhForever_RaidReminders.lua -- raid-wide external/CD reminders.
--
--  Countdown reminders assignable to a role/class/spec/name/subgroup, driven by the
--  BigWigs/DBM bar bridge (ns.ScheduleBWFire). Targeting is evaluated locally at fire
--  time, with no addon comms. Engine only; the editor lives in NaowhForever_Bosses.lua.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
if not ns then return end

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
-- profile.raidReminders[encounterID][uid] = { name, enabled,
--   trigger = { type = "bwtimer"|"bwmsg"|"pull"|"stage", spellID, leadTime, delay (s after pull/stage), stage },
--   target  = { all, roles/classes/specs/names/subgroups = sets keyed by TANK/PALADIN/specID/name/group },
--   display = { type = "text"|"icon"|"bar"|"circle"|"chat"|"wa"|"nameplateGlow"|"raidframeGlow",
--               text, spellID, color, dur, sound, tts } }
local function RaidRemindersTable(create, enc)
    return ns.PerBossSet("raidReminders", create, enc)
end
ns.RaidRemindersTable = RaidRemindersTable

-------------------------------------------------------------------------------
--  Targeting -- evaluated against the LOCAL player only, no roster sync needed
-------------------------------------------------------------------------------
-- No API answers "which subgroup am I in" directly, so walk the raid roster.
local function MySubgroup()
    for i = 1, 40 do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name and UnitIsUnit(name, "player") then return subgroup end
    end
    return 1   -- solo/party: no raid roster, only ever "group 1"
end

-- For the glow displays, which target another raider's frame.
local function UnitTokenForName(name)
    if not name or name == "" then return nil end
    if UnitName("player") == name then return "player" end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitName(unit) == name then return unit end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitName(unit) == name then return unit end
        end
    end
    return nil
end

-- Old single kind+value targets are normalized on read, not migrated; every reader of
-- a raid reminder's target goes through this.
function ns.NormalizeRaidReminderTarget(target)
    if not target then return { all = true } end
    if target.kind then
        local n = { all = target.kind == "all" }
        if target.kind == "role" then n.roles = { [target.value] = true }
        elseif target.kind == "class" then n.classes = { [target.value] = true }
        elseif target.kind == "spec" then n.specs = { [target.value] = true }
        elseif target.kind == "name" then n.names = { [target.value] = true }
        elseif target.kind == "subgroup" then n.subgroups = { [target.value] = true }
        end
        return n
    end
    return target
end

-- AND across categories, OR within one, as MRT does; an empty category matches anyone.
function ns.RaidReminderTargetsMe(target)
    target = ns.NormalizeRaidReminderTarget(target)
    if target.all then return true end

    if target.roles and next(target.roles) and not target.roles[UnitGroupRolesAssigned("player")] then
        return false
    end
    if target.classes and next(target.classes) then
        local _, classToken = UnitClass("player")
        if not target.classes[classToken] then return false end
    end
    if target.specs and next(target.specs) then
        local id = ns.CurrentSpec and ns.CurrentSpec()
        if not target.specs[id] then return false end
    end
    if target.names and next(target.names) and not target.names[UnitName("player")] then
        return false
    end
    if target.subgroups and next(target.subgroups) and not target.subgroups[MySubgroup()] then
        return false
    end
    return true
end

-------------------------------------------------------------------------------
--  Rendering -- one movable anchor per display type, each with a pool of regions.
-------------------------------------------------------------------------------
local ANCHOR_DEFAULT_POS = {
    text = { x = 0, y = 40 },
    timer = { x = -120, y = 40 },
    icon = { x = 120, y = 40 },
    bar = { x = 0, y = -60 },
    circle = { x = 120, y = -60 },
}

-- profile.raidReminderAnchorPos[displayType] = { point, relPoint, x, y }, written by Unlock Mode.
local function ApplyAnchorPosition(a, displayType)
    local p = ns.DB().raidReminderAnchorPos and ns.DB().raidReminderAnchorPos[displayType]
    a:ClearAllPoints()
    if p then
        a:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        local def = ANCHOR_DEFAULT_POS[displayType]
        a:SetPoint("CENTER", UIParent, "CENTER", def and def.x or 0, def and def.y or 0)
    end
end

local anchors = {}   -- [displayType] = frame, .pool = {}, .active = {}

local function GetAnchor(displayType)
    local a = anchors[displayType]
    if a then return a end
    a = CreateFrame("Frame", "NaowhForeverRaidReminder" .. displayType .. "Anchor", UIParent)
    a:SetSize(10, 10)
    a:SetClampedToScreen(true)
    -- ns.PreviewRaidReminder raises this to FULLSCREEN_DIALOG over the editor modal.
    a:SetFrameStrata("HIGH")
    a.pool, a.active = {}, {}
    anchors[displayType] = a
    ApplyAnchorPosition(a, displayType)
    return a
end

-- Unlock Mode's getFrame; creates the anchor even if this type has never fired.
ns.GetRaidReminderAnchor = GetAnchor

function ns.ApplyRaidReminderAnchorPosition(displayType)
    local a = anchors[displayType]
    if a then ApplyAnchorPosition(a, displayType) end
end

-- Includes config mode's off-pool sample (a._configSample), the region on screen while
-- dragging a size slider; resizing only pool + active made the sliders look dead.
local function ForEachRegion(a, fn)
    for _, r in ipairs(a.pool) do fn(r) end
    for _, r in ipairs(a.active) do fn(r) end
    if a._configSample then fn(a._configSample) end
end

local function RestackRegions(a)
    local y = 0
    for i = 1, #a.active do
        local r = a.active[i]
        r:ClearAllPoints()
        r:SetPoint("TOP", a, "TOP", 0, y)
        y = y - r:GetHeight() - 4
    end
end

local function ReleaseRegion(a, r)
    r.reminderEntry = nil
    for i = 1, #a.active do
        if a.active[i] == r then table.remove(a.active, i) break end
    end
    r:Hide()
    if r.hideTimer then r.hideTimer:Cancel(); r.hideTimer = nil end
    a.pool[#a.pool + 1] = r
    -- Undo Preview's elevation so a real fight never inherits it.
    a:SetFrameStrata("HIGH")
    a:SetFrameLevel(1)
    RestackRegions(a)
end

local function AlertFontPath()
    return ns.AlertFontPath()
end

local TEXT_WIDTH_DEFAULT, TEXT_FONTSIZE_DEFAULT = 320, 16
local function TextSize()
    local w = ns.DB().raidReminderTextWidth
    local fs = ns.DB().raidReminderTextFontSize
    w = (type(w) == "number" and w > 0) and w or TEXT_WIDTH_DEFAULT
    fs = (type(fs) == "number" and fs > 0) and fs or TEXT_FONTSIZE_DEFAULT
    return w, fs
end

-- Caption sizes, stored per display type.
local LABEL_SIZE_DEFAULTS = {
    raidReminderIconTextSize = 12,
    raidReminderCircleTextSize = 12,
    raidReminderBarTextSize = 12,
    raidReminderTimerTextSize = 11,
    raidReminderTimerNumberSize = 26,
}
local function LabelSize(key)
    local s = ns.DB()[key]
    return (type(s) == "number" and s > 0) and s or LABEL_SIZE_DEFAULTS[key]
end

local function CreateTextRegion(a)
    local w, fs = TextSize()
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(w, fs + 10)
    r.text = ns.Font(r, fs, "OUTLINE")
    r.text:SetFont(AlertFontPath(), fs, "OUTLINE")
    r.text:SetPoint("CENTER")
    r:Hide()
    return r
end

local function SizeText(r)
    local w, fs = TextSize()
    r:SetSize(w, fs + 10)
    r.text:SetFont(AlertFontPath(), fs, "OUTLINE")
end

function ns.ResizeRaidReminderText()
    local a = anchors.text
    if not a then return end
    ForEachRegion(a, SizeText)
    RestackRegions(a)
end

-- A big ticking number of whole seconds, with an optional caption above it.
local function TimerSize()
    local cap = LabelSize("raidReminderTimerTextSize")
    local num = LabelSize("raidReminderTimerNumberSize")
    return cap, num, math.max(120, num * 3), cap + num + 8
end

local function CreateTimerRegion(a)
    local cap, num, w, h = TimerSize()
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(w, h)
    r.label = ns.Font(r, cap, "OUTLINE")
    r.label:SetFont(AlertFontPath(), cap, "OUTLINE")
    r.label:SetPoint("TOP", r, "TOP", 0, 0)
    r.number = ns.Font(r, num, "OUTLINE")
    r.number:SetFont(AlertFontPath(), num, "OUTLINE")
    r.number:SetPoint("TOP", r.label, "BOTTOM", 0, -2)
    r:Hide()
    return r
end

local function SizeTimer(r)
    local cap, num, w, h = TimerSize()
    r:SetSize(w, h)
    r.label:SetFont(AlertFontPath(), cap, "OUTLINE")
    r.number:SetFont(AlertFontPath(), num, "OUTLINE")
end

function ns.ResizeRaidReminderTimer()
    local a = anchors.timer
    if not a then return end
    ForEachRegion(a, SizeTimer)
    RestackRegions(a)
end

local ICON_SIZE_DEFAULT = 48
local function IconSize()
    local s = ns.DB().raidReminderIconSize
    return (type(s) == "number" and s > 0) and s or ICON_SIZE_DEFAULT
end

local function CreateIconRegion(a)
    local size = IconSize()
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(size, size + LabelSize("raidReminderIconTextSize") + 6)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(size, size)
    r.icon:SetPoint("TOP", r, "TOP", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local fs = LabelSize("raidReminderIconTextSize")
    r.label = ns.Font(r, fs, "OUTLINE")
    r.label:SetFont(AlertFontPath(), fs, "OUTLINE")
    r.label:SetPoint("TOP", r.icon, "BOTTOM", 0, -2)
    r:Hide()
    return r
end

local function SizeIcon(r)
    local size = IconSize()
    local fs = LabelSize("raidReminderIconTextSize")
    r:SetSize(size, size + fs + 6)
    r.icon:SetSize(size, size)
    r.label:SetFont(AlertFontPath(), fs, "OUTLINE")
end

function ns.ResizeRaidReminderIcon()
    local a = anchors.icon
    if not a then return end
    ForEachRegion(a, SizeIcon)
    RestackRegions(a)
end

local function StatusBarTexture()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local ok, path = pcall(LSM.Fetch, LSM, "statusbar", "NaowhGradient", true)
    return ok and path or nil
end

-- expirationTime is set fresh by ns.DisplayRaidReminder on every acquire, so a pooled
-- region never counts down from the last reminder's value.
local BAR_WIDTH_DEFAULT, BAR_HEIGHT_DEFAULT = 240, 16
local function BarSize()
    local w, h = ns.DB().raidReminderBarWidth, ns.DB().raidReminderBarHeight
    w = (type(w) == "number" and w > 0) and w or BAR_WIDTH_DEFAULT
    h = (type(h) == "number" and h > 0) and h or BAR_HEIGHT_DEFAULT
    return w, h
end

local function CreateBarRegion(a)
    local w, h = BarSize()
    local fs = LabelSize("raidReminderBarTextSize")
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(w, h + fs + 4)

    r.label = ns.Font(r, fs, "OUTLINE")
    r.label:SetFont(AlertFontPath(), fs, "OUTLINE")
    r.label:SetPoint("TOP", r, "TOP", 0, 0)

    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetSize(w, h)
    r.bar:SetPoint("BOTTOM", r, "BOTTOM", 0, 0)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetStatusBarTexture(StatusBarTexture() or "Interface\\TargetingFrame\\UI-StatusBar")
    local T = ns.THEME
    local bg = r.bar:CreateTexture(nil, "BACKGROUND")
    ns.PixelInset(bg, -1, r.bar)
    bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 0.9)
    local fill = r.bar:GetStatusBarTexture()
    if fill then fill:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, 1) end
    ns.Border(r.bar)

    r:Hide()
    return r
end

local function SizeBar(r)
    local w, h = BarSize()
    local fs = LabelSize("raidReminderBarTextSize")
    r:SetSize(w, h + fs + 4)
    r.bar:SetSize(w, h)
    r.label:SetFont(AlertFontPath(), fs, "OUTLINE")
end

function ns.ResizeRaidReminderBar()
    local a = anchors.bar
    if not a then return end
    ForEachRegion(a, SizeBar)
    RestackRegions(a)
end

-- Mask and ring art come from Tools/make_media.py, shape in the alpha channel since masks read alpha.
local CIRCLE_SIZE_DEFAULT = 56
local CIRCLE_MASK_PATH = "Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga"

local function CircleSize()
    local s = ns.DB().raidReminderCircleSize
    return (type(s) == "number" and s > 0) and s or CIRCLE_SIZE_DEFAULT
end

-- The ring is two half-disc textures, each clipped to one half and rotated to the sweep
-- angle. Masking the Cooldown widget's swipe draws an opaque black square on this client
-- (confirmed live twice with two mask shapes; do not retry it). Thickness is a centred
-- hole mask, so it stays a live setting.
local CIRCLE_HALF_PATH = "Interface\\AddOns\\NaowhForever\\Media\\circle_half.tga"
local CIRCLE_HOLE_PATH = "Interface\\AddOns\\NaowhForever\\Media\\circle_hole.tga"
local CIRCLE_THICKNESS_DEFAULT = 10

local function CircleThickness()
    local t = ns.DB().raidReminderCircleThickness
    t = (type(t) == "number" and t > 0) and t or CIRCLE_THICKNESS_DEFAULT
    -- A hole at least 2px across, or the mask stops reading as a ring at all.
    return math.min(t, CircleSize() / 2 - 1)
end

-- circle_half.tga carries the RIGHT half of a disc, which is the clockwise span 0-180
-- from twelve o'clock. Rotating it clockwise by A moves that span to A..180+A, and the
-- half it is clipped to shows only what still falls inside -- so the right piece draws
-- A..180 and the left piece, based one half-turn round, draws A..360. Positive rotation
-- is counter-clockwise (Blizzard's own arrow rotations), hence the negated angles.
local function SetCircleSweep(r, elapsedDeg)
    if elapsedDeg >= 360 then
        r.fillR:Hide(); r.fillL:Hide()
        return
    end
    r.fillR:SetShown(elapsedDeg < 180)
    r.fillR:SetRotation(-math.rad(math.min(elapsedDeg, 180)))
    r.fillL:Show()
    r.fillL:SetRotation(-math.pi - math.rad(math.max(elapsedDeg - 180, 0)))
end

local function LayoutCircle(r, size, thickness, fs)
    r:SetSize(size, size + fs + 6)
    r.ring:SetSize(size, size)
    r.bg:SetSize(size, size)
    r.clipL:SetSize(size / 2, size)
    r.clipR:SetSize(size / 2, size)
    r.fillL:SetSize(size, size)
    r.fillR:SetSize(size, size)
    r.hole:SetSize(size - 2 * thickness, size - 2 * thickness)
    r.label:SetFont(AlertFontPath(), fs, "OUTLINE")
end

local function CreateCircleRegion(a)
    local size, thickness = CircleSize(), CircleThickness()
    local fs = LabelSize("raidReminderCircleTextSize")
    local r = CreateFrame("Frame", nil, a)

    r.ring = CreateFrame("Frame", nil, r)
    r.ring:SetPoint("BOTTOM", r, "BOTTOM", 0, 0)

    r.hole = r.ring:CreateMaskTexture()
    r.hole:SetPoint("CENTER", r.ring, "CENTER")
    r.hole:SetTexture(CIRCLE_HOLE_PATH, "CLAMPTOWHITE", "CLAMPTOWHITE")

    r.bg = r.ring:CreateTexture(nil, "BACKGROUND")
    r.bg:SetPoint("CENTER", r.ring, "CENTER")
    r.bg:SetTexture(CIRCLE_MASK_PATH)
    r.bg:SetVertexColor(0, 0, 0, 0.5)
    r.bg:AddMaskTexture(r.hole)

    -- The clip frames are what turn a rotating half-disc into an arc; without
    -- SetClipsChildren each piece would spill into the other half.
    r.clipL = CreateFrame("Frame", nil, r.ring)
    r.clipL:SetPoint("TOPLEFT", r.ring, "TOPLEFT")
    r.clipL:SetClipsChildren(true)
    r.clipR = CreateFrame("Frame", nil, r.ring)
    r.clipR:SetPoint("TOPRIGHT", r.ring, "TOPRIGHT")
    r.clipR:SetClipsChildren(true)

    for _, side in ipairs({ "L", "R" }) do
        local clip = (side == "L") and r.clipL or r.clipR
        local t = clip:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE_HALF_PATH)
        t:SetPoint("CENTER", r.ring, "CENTER")
        t:AddMaskTexture(r.hole)
        r["fill" .. side] = t
    end

    r.label = ns.Font(r, fs, "OUTLINE")
    r.label:SetPoint("BOTTOM", r.ring, "TOP", 0, 4)

    LayoutCircle(r, size, thickness, fs)
    SetCircleSweep(r, 0)
    r:Hide()
    return r
end

local function SizeCircle(r)
    LayoutCircle(r, CircleSize(), CircleThickness(), LabelSize("raidReminderCircleTextSize"))
end

function ns.ResizeRaidReminderCircle()
    local a = anchors.circle
    if not a then return end
    ForEachRegion(a, SizeCircle)
    RestackRegions(a)
end

-- Unlock Mode's mover size; the anchor itself is a bare 10x10 point. Floored at
-- MOVER_MIN so thin Text/Bar anchors stay easy to grab.
local MOVER_MIN = 100
function ns.RaidReminderAnchorSize(displayType)
    local w, h
    if displayType == "text" then local tw, fs = TextSize(); w, h = tw, fs + 10
    elseif displayType == "timer" then local _, _, tw, th = TimerSize(); w, h = tw, th
    elseif displayType == "icon" then local s = IconSize()
        w, h = s, s + LabelSize("raidReminderIconTextSize") + 6
    elseif displayType == "bar" then local bw, bh = BarSize()
        w, h = bw, bh + LabelSize("raidReminderBarTextSize") + 4
    elseif displayType == "circle" then local s = CircleSize()
        w, h = s, s + LabelSize("raidReminderCircleTextSize") + 6
    else w, h = MOVER_MIN, MOVER_MIN end
    return math.max(w, MOVER_MIN), math.max(h, MOVER_MIN)
end

local REGION_CTORS = {
    text = CreateTextRegion, timer = CreateTimerRegion, icon = CreateIconRegion,
    bar = CreateBarRegion, circle = CreateCircleRegion,
}
local REGION_SIZERS = { text = SizeText, timer = SizeTimer, icon = SizeIcon, bar = SizeBar, circle = SizeCircle }

ns.RaidReminderSizeDefaults = {
    raidReminderTextWidth = TEXT_WIDTH_DEFAULT, raidReminderTextFontSize = TEXT_FONTSIZE_DEFAULT,
    raidReminderIconSize = ICON_SIZE_DEFAULT, raidReminderBarWidth = BAR_WIDTH_DEFAULT,
    raidReminderBarHeight = BAR_HEIGHT_DEFAULT, raidReminderCircleSize = CIRCLE_SIZE_DEFAULT,
    raidReminderCircleThickness = CIRCLE_THICKNESS_DEFAULT,
}
for key, size in pairs(LABEL_SIZE_DEFAULTS) do ns.RaidReminderSizeDefaults[key] = size end

local function AcquireRegion(displayType)
    local a = GetAnchor(displayType)
    local ctor = REGION_CTORS[displayType]
    if not ctor then return nil end
    local r = table.remove(a.pool)
    if not r then r = ctor(a) end
    -- A pooled region may predate the anchor's last strata change, e.g. a preview elevation.
    r:SetFrameStrata(a:GetFrameStrata())
    r:SetFrameLevel(a:GetFrameLevel() + 1)
    a.active[#a.active + 1] = r
    return a, r
end

-------------------------------------------------------------------------------
--  Glow display types -- nameplate/raid-frame highlights on an existing unit frame.
--  The glow engine parks textures on the frame it is handed, so it gets a dedicated
--  overlay wrapper, never the unit frame itself, or leftovers outlive the reminder.
-------------------------------------------------------------------------------
local glowPool, activeGlows = {}, {}

local function AcquireGlowWrapper()
    local w = table.remove(glowPool)
    if not w then
        w = CreateFrame("Frame", nil, UIParent)
        w:SetFrameStrata("HIGH")
    end
    activeGlows[#activeGlows + 1] = w
    return w
end

local function ReleaseGlowWrapper(w)
    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG then LCG.PixelGlow_Stop(w) end
    if w.hideTimer then w.hideTimer:Cancel(); w.hideTimer = nil end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(UIParent)
    w.hideAfterCastID = nil
    w.reminderEntry = nil
    for i = 1, #activeGlows do
        if activeGlows[i] == w then table.remove(activeGlows, i) break end
    end
    glowPool[#glowPool + 1] = w
end

-- LibGetFrame scans via coroutine.resume and discards errors, so one frame raising under
-- UIParent silently truncates its cache. EllesmereUI raid buttons never reached it
-- (measured live on two accounts, 2026-09-04). This backs the library up by reading the
-- secure "unit" attribute, as LibGetFrame does.
local EUI_UNIT_BUTTONS
local function ResolveEUIUnitFrame(unit)
    if not EUI_UNIT_BUTTONS then
        EUI_UNIT_BUTTONS = {}
        local function add(n) EUI_UNIT_BUTTONS[#EUI_UNIT_BUTTONS + 1] = n end
        -- Extra frames are capped at 20 (XF.CAP), not 8.
        for i = 1, 40 do add("ERFFlatHeaderUnitButton" .. i) end
        for g = 1, 8 do for i = 1, 5 do add("ERFGroupHeader" .. g .. "UnitButton" .. i) end end
        for i = 1, 20 do add("ERFExtraFrame" .. i) end
        for i = 1, 5 do add("ERFPartyHeaderUnitButton" .. i) end
        add("ERFPartySelfButton")
    end
    local issec = _G.issecretvalue
    for i = 1, #EUI_UNIT_BUTTONS do
        local b = _G[EUI_UNIT_BUTTONS[i]]
        if b then
            -- IsVisible, not IsShown: a button reports shown while an ancestor
            -- is hidden, and the raid header's buttons sit hidden in a party.
            local okV, vis = pcall(b.IsVisible, b)
            if okV and vis then
                local okA, u = pcall(b.GetAttribute, b, "unit")
                -- Type check first: a secret attribute is not a string.
                if okA and type(u) == "string" and not (issec and issec(u)) then
                    if u == unit then return b end
                    -- In a raid the player's button carries a raidN token. UnitIsUnit
                    -- is refused on an addon-restricted map, so accept only a plain true.
                    if unit == "player" then
                        local okU, same = pcall(UnitIsUnit, u, "player")
                        if okU and not (issec and issec(same)) and same == true then
                            return b
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function ResolveGlowFrame(displayType, unit)
    if displayType == "nameplateGlow" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        return plate and (plate.UnitFrame or plate)
    elseif displayType == "raidframeGlow" then
        local LGF = LibStub and LibStub("LibGetFrame-1.0", true)
        local f = LGF and LGF.GetUnitFrame and LGF.GetUnitFrame(unit)
        if f then return f end
        return ResolveEUIUnitFrame(unit)
    end
    return nil
end

local function FireGlowReminder(display, dur, entry)
    local unit = UnitTokenForName(display.glowTarget)
    local frame = unit and ResolveGlowFrame(display.type, unit)
    if not frame then return end

    local w = AcquireGlowWrapper()
    w:SetParent(frame)
    w:ClearAllPoints()
    w:SetAllPoints(frame)
    w:Show()
    w.hideAfterCastID = display.hideAfterCastID
    w.reminderEntry = entry

    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG then
        local c = display.color
        LCG.PixelGlow_Start(w, { (c and c.r) or 1, (c and c.g) or 0.82, (c and c.b) or 0, 1 })
    end

    if w.hideTimer then w.hideTimer:Cancel() end
    w.hideTimer = C_Timer.NewTimer(dur, function() ReleaseGlowWrapper(w) end)
end

-- GetSpellInfo returns nothing for a spell the client has not cached; GetSpellTexture still answers.
local function ResolveDisplayIconID(display)
    if not display.spellID then return nil end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(display.spellID)
    local iconID = info and info.iconID
    if not iconID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, display.spellID)
        if ok then iconID = tex end
    end
    return iconID
end

-- A small subset of MRT's placeholders. %name is always the viewer's own name and class
-- color, since a reminder can target several people.
local function FormatReminderMsg(text, display)
    if type(text) ~= "string" or text == "" then return text end

    if text:find("%%name") then
        local name = UnitName("player") or ""
        local _, classToken = UnitClass("player")
        local colors = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
        local c = classToken and colors and colors[classToken]
        if c and c.colorStr then name = "|c" .. c.colorStr .. name .. "|r" end
        text = text:gsub("%%name", name)
    end

    if text:find("%%specicon") then
        local icon = ""
        if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
            local index = C_SpecializationInfo.GetSpecialization()
            if index then
                local _, _, _, iconTex = C_SpecializationInfo.GetSpecializationInfo(index)
                if iconTex then icon = "|T" .. iconTex .. ":16|t" end
            end
        end
        text = text:gsub("%%specicon", icon)
    end

    if text:find("%%time") then
        local dur = (type(display.dur) == "number" and display.dur > 0) and display.dur or 4
        text = text:gsub("%%time", tostring(math.floor(dur + 0.5)))
    end

    if text:find("{spell:") then
        text = text:gsub("{spell:(%-?%d+)}", function(idStr)
            local sid = tonumber(idStr)
            if not sid then return "" end
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            local name = (info and info.name) or ("Spell " .. sid)
            local iconID = info and info.iconID
            if not iconID and C_Spell and C_Spell.GetSpellTexture then
                local ok, tex = pcall(C_Spell.GetSpellTexture, sid)
                if ok then iconID = tex end
            end
            return (iconID and ("|T" .. iconID .. ":16|t") or "") .. name
        end)
    end

    return text
end
ns.FormatReminderMsg = FormatReminderMsg

function ns.DisplayRaidReminder(entry, preview)
    if not ns.IsReminderEnabled(entry, preview) then return end
    local display = entry and entry.display
    if not display then return end

    -- display.text stays the raw template; it is re-resolved on every fire.
    local formattedText = FormatReminderMsg(display.text, display)

    if display.type == "chat" then
        if formattedText and formattedText ~= "" then ns.Print(formattedText) end
        ns.PlayReminderSound(display)
        ns.SpeakReminderTTS(display, formattedText, preview)
        return
    end

    if display.type == "nameplateGlow" or display.type == "raidframeGlow" then
        local dur = (type(display.dur) == "number" and display.dur > 0) and display.dur or 4
        FireGlowReminder(display, dur, entry)
        ns.PlayReminderSound(display)
        ns.SpeakReminderTTS(display, formattedText, preview)
        return
    end

    local a, r = AcquireRegion(display.type)
    if not r then
        ns.Print(("|cffff6060raid reminder|r: display type %q not built yet."):format(
            tostring(display.type)))
        return
    end
    r.hideAfterCastID = display.hideAfterCastID
    r.reminderEntry = entry

    -- Shared by the Bar/Circle countdown and the release timer so the two agree.
    local dur = (type(display.dur) == "number" and display.dur > 0) and display.dur or 4

    if display.type == "text" then
        r.text:SetText(formattedText or "")
        if display.color then
            r.text:SetTextColor(display.color.r or 1, display.color.g or 1,
                display.color.b or 1, display.color.a or 1)
        else
            r.text:SetTextColor(1, 1, 1, 1)
        end
    elseif display.type == "icon" then
        r.icon:SetTexture(ResolveDisplayIconID(display) or 134400)
        if formattedText and formattedText ~= "" then
            r.label:SetText(formattedText)
            r.label:Show()
        else
            r.label:Hide()
        end
    elseif display.type == "timer" then
        r.label:SetText(formattedText or "")
        r.expirationTime = GetTime() + dur
        r.number:SetText(tostring(math.ceil(dur)))
        r.shownSecond = math.ceil(dur)
        -- Only on a new second: SetText + tostring every frame allocated a string per frame.
        r:SetScript("OnUpdate", function(self)
            local remain = self.expirationTime - GetTime()
            local sec = remain > 0 and math.ceil(remain) or 0
            if sec ~= self.shownSecond then
                self.shownSecond = sec
                self.number:SetText(tostring(sec))
            end
        end)
    elseif display.type == "bar" then
        r.label:SetText(formattedText or "")
        r.bar.expirationTime = GetTime() + dur
        r.bar:SetMinMaxValues(0, dur)
        r.bar:SetValue(dur)
        r.bar:SetScript("OnUpdate", function(self)
            local remain = self.expirationTime - GetTime()
            self:SetValue(remain > 0 and remain or 0)
        end)
    elseif display.type == "circle" then
        local iconID = ResolveDisplayIconID(display)
        local caption = formattedText or ""
        if iconID then caption = ("|T%s:0|t %s"):format(tostring(iconID), caption) end
        local color = display.color
        if color then
            r.fillL:SetVertexColor(color.r, color.g, color.b)
            r.fillR:SetVertexColor(color.r, color.g, color.b)
            r.label:SetTextColor(color.r, color.g, color.b)
        else
            local T = ns.THEME
            r.fillL:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
            r.fillR:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
            r.label:SetTextColor(1, 1, 1)
        end
        r.caption = caption
        r.expirationTime = GetTime() + dur
        SetCircleSweep(r, 0)
        r.label:SetText(caption)
        r.shownTenth = nil
        -- One decimal, since a whole-second number beside a moving arc looks stuck. The
        -- sweep runs per frame; the caption only on a new tenth.
        r:SetScript("OnUpdate", function(self)
            local remain = self.expirationTime - GetTime()
            if remain < 0 then remain = 0 end
            SetCircleSweep(self, (1 - remain / dur) * 360)
            -- Printed from the tenth it keys on, not from remain: %.1f rounds half to even,
            -- so an exact .x5 frame showed a tenth the key had already moved past.
            local tenth = math.floor(remain * 10)
            if tenth ~= self.shownTenth then
                self.shownTenth = tenth
                self.label:SetFormattedText("%s (%.1f)", self.caption, tenth / 10)
            end
        end)
    end

    r:Show()
    RestackRegions(a)
    ns.PlayReminderSound(display)
    ns.SpeakReminderTTS(display, formattedText, preview)

    if r.hideTimer then r.hideTimer:Cancel() end
    r.hideTimer = C_Timer.NewTimer(dur, function() ReleaseRegion(a, r) end)
end

-- Raised above the editor's FULLSCREEN_DIALOG modal; ReleaseRegion drops it back to HIGH.
function ns.PreviewRaidReminder(entry)
    if not ns.IsReminderEnabled(entry, true) then return end
    local display = entry and entry.display
    if not display then return end
    local NO_ANCHOR_TYPES = { chat = true, nameplateGlow = true, raidframeGlow = true }
    local a = (not NO_ANCHOR_TYPES[display.type]) and GetAnchor(display.type) or nil
    if a then
        a:SetFrameStrata("FULLSCREEN_DIALOG")
        a:SetFrameLevel(250)
        -- A preview replaces the last one instead of piling up. Real fires still stack.
        while #a.active > 0 do ReleaseRegion(a, a.active[#a.active]) end
    end
    ns.DisplayRaidReminder(entry, true)
end

-- Clear only displays owned by opted-out reminders; preserve unrelated alerts.
function ns.HideFilteredRaidReminders()
    for _, a in pairs(anchors) do
        for i = #a.active, 1, -1 do
            local r = a.active[i]
            if r.reminderEntry and not ns.IsReminderEnabled(r.reminderEntry) then ReleaseRegion(a, r) end
        end
    end
    for i = #activeGlows, 1, -1 do
        local w = activeGlows[i]
        if w.reminderEntry and not ns.IsReminderEnabled(w.reminderEntry) then ReleaseGlowWrapper(w) end
    end
end

-- display.hideAfterCastID: the reminder disappears once you cast that spell.
local castGateWatcher = CreateFrame("Frame")
castGateWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castGateWatcher:SetScript("OnEvent", function(_, _, _, _, spellID)
    if not spellID then return end
    for _, a in pairs(anchors) do
        for i = #a.active, 1, -1 do
            local r = a.active[i]
            if r.hideAfterCastID == spellID then ReleaseRegion(a, r) end
        end
    end
    for i = #activeGlows, 1, -1 do
        local w = activeGlows[i]
        if w.hideAfterCastID == spellID then ReleaseGlowWrapper(w) end
    end
end)

-------------------------------------------------------------------------------
--  Anchor config -- move and resize every anchor with a live sample, opened from
--  Unlock Mode.
-------------------------------------------------------------------------------
local DISPLAY_TYPE_LABEL = { defensive = "Defensive", text = "Message", timer = "Timer", icon = "Icon", bar = "Bar", circle = "Circle" }
local CONFIG_ORDER = { "defensive", "text", "timer", "icon", "bar", "circle" }

-- Session-local.
local configShown = {}
for _, dt in ipairs(CONFIG_ORDER) do configShown[dt] = true end

local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- Static placeholder content: no countdown, no hide timer.
local function PopulateSample(displayType, r)
    if displayType == "text" then
        r.text:SetText("Sample Reminder")
        r.text:SetTextColor(1, 1, 1, 1)
    elseif displayType == "icon" then
        r.icon:SetTexture(SAMPLE_ICON)
        r.label:SetText("Sample")
        r.label:Show()
    elseif displayType == "timer" then
        r.label:SetText("Sample Timer")
        r.number:SetText("5")
    elseif displayType == "bar" then
        r.label:SetText("Sample Bar")
        r.bar:SetScript("OnUpdate", nil)
        r.bar:SetMinMaxValues(0, 1)
        r.bar:SetValue(0.6)
    elseif displayType == "circle" then
        r:SetScript("OnUpdate", nil)
        r.label:SetText("|T" .. SAMPLE_ICON .. ":0|t Sample (3.4)")
        r.label:SetTextColor(1, 1, 1)
        local T = ns.THEME
        r.fillL:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
        r.fillR:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
        -- Parked 40% through so the sweep's direction is visible while placing it.
        SetCircleSweep(r, 0.4 * 360)
    end
end

function ns.NewRaidReminderSample(displayType, parent)
    return REGION_CTORS[displayType](parent)
end

function ns.PaintRaidReminderSample(displayType, r)
    REGION_SIZERS[displayType](r)
    PopulateSample(displayType, r)
    r:Show()
end

-- The defensive alert keeps its own position field, which the main file's preview drag
-- also writes.
local function SaveAnchorPos(displayType, point, relPoint, x, y)
    if not point then return end
    local db = ns.DB()
    if displayType == "defensive" then
        db.pos = { point = point, relPoint = relPoint, x = x, y = y }
        if ns.ApplyDefensiveAlertPosition then ns.ApplyDefensiveAlertPosition() end
    else
        db.raidReminderAnchorPos = db.raidReminderAnchorPos or {}
        db.raidReminderAnchorPos[displayType] = { point = point, relPoint = relPoint, x = x, y = y }
    end
end

local function EnsureConfigHandle(displayType, a)
    if a._configHandle then return a._configHandle end
    a:SetMovable(true)
    local h = ns.UI.AttachMover(a, "Reminder " .. DISPLAY_TYPE_LABEL[displayType], function(pos)
        SaveAnchorPos(displayType, pos.point, pos.relPoint, pos.x, pos.y)
    end, "Smart Reminders/Settings")
    h.text:ClearAllPoints()
    h.text:SetPoint("TOP", h, "BOTTOM", 0, -4)

    local gear = CreateFrame("Button", nil, h)
    gear:SetSize(16, 16)
    gear:SetPoint("TOPLEFT", h, "TOPLEFT", 2, -2)
    local gearTex = gear:CreateTexture(nil, "ARTWORK")
    gearTex:SetAllPoints()
    gearTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetScript("OnClick", function() ns.ShowRaidReminderAnchorSizePopup(displayType) end)
    ns.Tooltip(gear, "Size", "Set this display's size and text.")

    a._configHandle = h
    return h
end

local function RefreshConfigVisual(displayType)
    -- The defensive alert is not pooled: the main file shows its own preview, and only
    -- the handle comes from here.
    if displayType == "defensive" then
        if not (ns.SetDefensiveAnchorConfigShown and ns.GetDefensiveAlertFrame) then return end
        ns.SetDefensiveAnchorConfigShown(true)
        local f, alertBar = ns.GetDefensiveAlertFrame()
        if not f then return end
        local h = EnsureConfigHandle("defensive", f)
        h:ClearAllPoints()
        local below = (alertBar and alertBar:IsShown()) and alertBar or f
        h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        h:SetPoint("BOTTOMRIGHT", below, "BOTTOMRIGHT", 0, 0)
        h:Show()
        return
    end
    local a = GetAnchor(displayType)
    local h = EnsureConfigHandle(displayType, a)

    -- Kept out of a.active/a.pool so a real fire or Preview cannot restack the sample.
    if not a._configSample then
        a._configSample = REGION_CTORS[displayType](a)
    end
    a._configSample:SetFrameStrata(a:GetFrameStrata())
    a._configSample:SetFrameLevel(a:GetFrameLevel() + 1)
    PopulateSample(displayType, a._configSample)
    a._configSample:ClearAllPoints()
    a._configSample:SetPoint("TOP", a, "TOP", 0, 0)
    a._configSample:Show()

    h:ClearAllPoints()
    h:SetAllPoints(a._configSample)
    h:Show()
end

local function HideConfigVisual(displayType)
    if displayType == "defensive" then
        local f = ns.GetDefensiveAlertFrame and ns.GetDefensiveAlertFrame()
        if f and f._configHandle then f._configHandle:Hide() end
        if ns.SetDefensiveAnchorConfigShown then ns.SetDefensiveAnchorConfigShown(false) end
        return
    end
    local a = anchors[displayType]
    if not a then return end
    if a._configHandle then a._configHandle:Hide() end
    if a._configSample then a._configSample:Hide() end
end

local function RefreshAllConfigVisuals()
    if not ns.IsRaidReminderAnchorConfigActive() or ns.DB().enabled ~= true then return end
    for _, displayType in ipairs(CONFIG_ORDER) do
        if configShown[displayType] then RefreshConfigVisual(displayType) end
    end
end
ns.RefreshRaidReminderAnchorConfig = RefreshAllConfigVisuals

function ns.SetRaidReminderAnchorConfigShown(displayType, shown)
    configShown[displayType] = shown or nil
    if not ns.IsRaidReminderAnchorConfigActive() then return end
    if shown then RefreshConfigVisual(displayType) else HideConfigVisual(displayType) end
end

function ns.IsRaidReminderAnchorConfigShown(displayType)
    return configShown[displayType] == true
end

local function AnchorsOn() return ns.DB().enabled == true end

-- With Smart Reminders off its anchors stay hidden; the toolbar still carries Exit Config.
local toolbarChecks = {}
for _, displayType in ipairs(CONFIG_ORDER) do
    toolbarChecks[#toolbarChecks + 1] = { label = DISPLAY_TYPE_LABEL[displayType],
        get = function() return configShown[displayType] == true end,
        set = function(v) ns.SetRaidReminderAnchorConfigShown(displayType, v) end,
        enabled = AnchorsOn }
end
ns.AddUnlockModeChecks(function() return AnchorsOn() and "Smart Reminders" or "Smart Reminders is off" end,
    toolbarChecks)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", RefreshAllConfigVisuals)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    for _, displayType in ipairs(CONFIG_ORDER) do HideConfigVisual(displayType) end
end)

-- Rows for each anchor's gear popup. Timer has no box, so its two font sizes are its rows.
local TEXT_SIZE_MIN, TEXT_SIZE_MAX = 8, 48
local function TextSizeRow(label, key, resize)
    return { label = label, min = TEXT_SIZE_MIN, max = TEXT_SIZE_MAX,
        get = function() return LabelSize(key) end,
        set = function(v) ns.DB()[key] = math.floor(v); resize() end }
end
local RESIZE_ROWS = {
    defensive = {
        { label = "Icon Size", min = 16, max = 200,
            get = function() return ns.DB().iconSize or 64 end,
            set = function(v)
                ns.DB().iconSize = math.max(16, math.floor(v))
                if ns.RefreshDefensivePreview then ns.RefreshDefensivePreview() end
            end },
        { label = "Text Size", min = TEXT_SIZE_MIN, max = TEXT_SIZE_MAX,
            get = function() return ns.DB().textSize or 21 end,
            set = function(v)
                ns.DB().textSize = math.floor(v)
                if ns.RefreshDefensivePreview then ns.RefreshDefensivePreview() end
            end },
    },
    circle = {
        { label = "Size", min = 20, max = 200, get = function() return CircleSize() end,
            set = function(v) ns.DB().raidReminderCircleSize = math.max(20, math.floor(v)); ns.ResizeRaidReminderCircle() end },
        { label = "Thickness", min = 2, max = 40, get = function() return CircleThickness() end,
            set = function(v) ns.DB().raidReminderCircleThickness = math.max(2, math.floor(v)); ns.ResizeRaidReminderCircle() end },
        TextSizeRow("Text Size", "raidReminderCircleTextSize", function() ns.ResizeRaidReminderCircle() end),
    },
    icon = {
        { label = "Size", min = 16, max = 200, get = function() return IconSize() end,
            set = function(v) ns.DB().raidReminderIconSize = math.max(16, math.floor(v)); ns.ResizeRaidReminderIcon() end },
        TextSizeRow("Text Size", "raidReminderIconTextSize", function() ns.ResizeRaidReminderIcon() end),
    },
    bar = {
        { label = "Width", min = 60, max = 600, get = function() return (BarSize()) end,
            set = function(v) ns.DB().raidReminderBarWidth = math.max(60, math.floor(v)); ns.ResizeRaidReminderBar() end },
        { label = "Height", min = 6, max = 60, get = function() local _, h = BarSize(); return h end,
            set = function(v) ns.DB().raidReminderBarHeight = math.max(6, math.floor(v)); ns.ResizeRaidReminderBar() end },
        TextSizeRow("Text Size", "raidReminderBarTextSize", function() ns.ResizeRaidReminderBar() end),
    },
    text = {
        { label = "Width", min = 60, max = 800, get = function() return (TextSize()) end,
            set = function(v) ns.DB().raidReminderTextWidth = math.max(60, math.floor(v)); ns.ResizeRaidReminderText() end },
        { label = "Text Size", min = TEXT_SIZE_MIN, max = TEXT_SIZE_MAX,
            get = function() local _, fs = TextSize(); return fs end,
            set = function(v) ns.DB().raidReminderTextFontSize = math.max(8, math.floor(v)); ns.ResizeRaidReminderText() end },
    },
    timer = {
        TextSizeRow("Caption Size", "raidReminderTimerTextSize", function() ns.ResizeRaidReminderTimer() end),
        { label = "Number Size", min = 12, max = 96,
            get = function() return LabelSize("raidReminderTimerNumberSize") end,
            set = function(v) ns.DB().raidReminderTimerNumberSize = math.floor(v); ns.ResizeRaidReminderTimer() end },
    },
}

local sizePopups = {}

function ns.ShowRaidReminderAnchorSizePopup(displayType)
    local rows = RESIZE_ROWS[displayType]
    if not rows then return end
    for other, popup in pairs(sizePopups) do
        if other ~= displayType then popup.dimmer:Hide() end
    end

    local popup = sizePopups[displayType]
    if not popup then
        local dimmer, panel = ns.MakeModal(340, 60 + #rows * 34,
            "raidReminderAnchorSize:" .. displayType)
        local head = ns.Font(panel, 13, "OUTLINE")
        head:SetPoint("TOP", panel, "TOP", 0, -14)
        head:SetText((DISPLAY_TYPE_LABEL[displayType] or displayType) .. " Size")

        popup = { dimmer = dimmer, paints = {} }
        local PAD, y = 16, -42
        for i = 1, #rows do
            local row = rows[i]
            local l = ns.Font(panel, 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
            l:SetText(row.label)

            local track, valBox, paint = ns.UI.BuildSliderCore(panel, 120, 4, 12, 44, 22, 12, 1,
                row.min or 8, row.max or 200, 1, row.get,
                function(v) row.set(v); RefreshAllConfigVisuals() end)
            valBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y + 4)
            track:SetPoint("RIGHT", valBox, "LEFT", -8, 0)
            popup.paints[i] = paint
            y = y - 34
        end

        ns.Button(panel, "Done", 90, 26, function() dimmer:Hide() end)
            :SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
        sizePopups[displayType] = popup
    end
    for i = 1, #popup.paints do popup.paints[i]() end
    popup.dimmer:Show()
end

-------------------------------------------------------------------------------
--  Firing
-------------------------------------------------------------------------------
local function FireRaidReminder(entry)
    if ns.DB().enabled ~= true or not ns.BossAllowed() then return end
    if not ns.IsReminderEnabled(entry) then return end
    if not ns.RaidReminderTargetsMe(entry.target) then return end
    ns.DisplayRaidReminder(entry)
end

local function RaidRemindersAllowed()
    return ns.DB().enabled == true and ns.BossAllowed()
end

-- Capture ownership, not just the entry: an editor replaces/deletes the table value,
-- and a profile switch can leave an otherwise enabled entry belonging to old settings.
local function ReminderStillCurrent(reminders, uid, entry)
    local profile = ns.DB()
    local encounter = ns.CurrentEncounter()
    local startedAt = ns.PullContext()
    return function()
        return RaidRemindersAllowed() and ns.DB() == profile
            and ns.InEncounter() and ns.CurrentEncounter() == encounter
            and ns.PullContext() == startedAt
            and RaidRemindersTable(false, encounter) == reminders
            and reminders[uid] == entry and ns.IsReminderEnabled(entry)
    end
end

-- BigWigs only: OnBigWigsEvent is the sole caller, and has already secret-checked
-- sid/duration/barIdentity.
function ns.HandleRaidReminderAbility(sid, duration, barIdentity, retried)
    if type(sid) ~= "number" or sid <= 0 then return end
    if not RaidRemindersAllowed() then return end
    local enc = ns.CurrentEncounter and ns.CurrentEncounter()
    -- An engage broadcast can arrive before the main file's ENCOUNTER_START handler has set
    -- the encounter: retried next frame, with the time already elapsed taken off a bar.
    if not enc then
        if not retried then
            local at = GetTime()
            C_Timer.After(0, function()
                ns.HandleRaidReminderAbility(sid, duration and duration - (GetTime() - at),
                    barIdentity, true)
            end)
        end
        return
    end
    if not (ns.InEncounter and ns.InEncounter()) then return end
    local reminders = RaidRemindersTable(false, enc)
    if not reminders then return end

    for uid, entry in pairs(reminders) do
        local trig = entry.trigger
        if ns.IsReminderEnabled(entry) and trig and trig.spellID == sid then
            local wantsBar = trig.type == "bwtimer"
            local haveBar = type(duration) == "number" and duration > 0.5
            if wantsBar and haveBar then
                -- 0 is a real answer ("at the end of the bar"), so only a missing or
                -- negative lead falls back to the 3s default.
                local lead = (type(trig.leadTime) == "number" and trig.leadTime >= 0)
                    and trig.leadTime or 3
                -- A channel per reminder: on a shared one, a second reminder on the same bar
                -- reads as a duplicate of the first and supersedes it.
                ns.ScheduleBWFire("raid:" .. tostring(uid), sid, duration, barIdentity, lead, function()
                    FireRaidReminder(entry)
                end, nil, ReminderStillCurrent(reminders, uid, entry))
            elseif trig.type == "bwmsg" and not haveBar then
                FireRaidReminder(entry)
            end
        end
    end
end

-- Called once from ENCOUNTER_START (NaowhForever_SmartReminders.lua).
function ns.CheckRaidReminderPullTriggers()
    if not (ns.InEncounter and ns.InEncounter()) then return end
    if not RaidRemindersAllowed() then return end
    local enc = ns.CurrentEncounter and ns.CurrentEncounter()
    if not enc then return end
    local reminders = RaidRemindersTable(false, enc)
    if not reminders then return end

    for uid, entry in pairs(reminders) do
        local trig = entry.trigger
        if ns.IsReminderEnabled(entry) and trig and trig.type == "pull" then
            local delay = (type(trig.delay) == "number" and trig.delay >= 0) and trig.delay or 0.01
            -- leadTime pulls the fire earlier so the display counts down TO the noted
            -- moment rather than starting at it.
            local lead = type(trig.leadTime) == "number" and trig.leadTime or 0
            ns.TrackReminderTimer("pull", math.max(delay - lead, 0.01),
                function() FireRaidReminder(entry) end, nil, ReminderStillCurrent(reminders, uid, entry))
        end
    end
end

-- Run on each new stage; the main file's SetStage owns change detection and cancelling
-- the previous stage's timers.
function ns.CheckRaidReminderStageTriggers(stage)
    if not (ns.InEncounter and ns.InEncounter()) then return end
    if not RaidRemindersAllowed() then return end
    local enc = ns.CurrentEncounter and ns.CurrentEncounter()
    if not enc then return end
    local reminders = RaidRemindersTable(false, enc)
    if not reminders then return end

    for uid, entry in pairs(reminders) do
        local trig = entry.trigger
        if ns.IsReminderEnabled(entry) and trig and trig.type == "stage" and trig.stage == stage then
            local delay = (type(trig.delay) == "number" and trig.delay >= 0) and trig.delay or 0.01
            local lead = type(trig.leadTime) == "number" and trig.leadTime or 0
            ns.TrackReminderTimer("stage", math.max(delay - lead, 0.01),
                function() FireRaidReminder(entry) end, nil, ReminderStillCurrent(reminders, uid, entry))
        end
    end
end

-- Called from OnCombatLog on SPELL_AURA_APPLIED/REMOVED, which has already secret-checked
-- destGUID/spellID. The combat log still sees auras that C_UnitAuras'
-- RequiresNonSecretAura gate hides in restricted content.
function ns.CheckRaidReminderAuraTriggers(kind, destGUID, spellID)
    if not (ns.InEncounter and ns.InEncounter()) then return end
    if not RaidRemindersAllowed() then return end
    local enc = ns.CurrentEncounter and ns.CurrentEncounter()
    if not enc then return end
    local reminders = RaidRemindersTable(false, enc)
    if not reminders then return end

    local isPlayer = destGUID == ns.PlayerGUID()
    local isBoss = not isPlayer and ns.bossGUIDs[destGUID] == true
    if not (isPlayer or isBoss) then return end

    for _, entry in pairs(reminders) do
        local trig = entry.trigger
        if trig and trig.type == "aura" and trig.spellID == spellID
           and (trig.auraEvent or "applied") == kind
           and (trig.target == "player") == isPlayer then
            FireRaidReminder(entry)
        end
    end
end
