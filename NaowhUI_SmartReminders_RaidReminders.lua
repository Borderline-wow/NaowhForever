-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_RaidReminders.lua -- raid-wide external/CD reminders.
--
--  Same idea as NorthernSkyRaidTools/TimelineReminders (countdown Bar/Icon/Text/
--  Circle reminders assignable to a role/class/spec/name/subgroup, not just the local
--  player), built on the BigWigs/DBM bar bridge the main file already runs for tank
--  busters (ns.ScheduleBWFire) instead of a hand-authored pull-timer table. Neither
--  reference addon actually listens to BigWigs/DBM at all -- this is additive to
--  proven code, not a port of their approach.
--
--  Targeting is evaluated LOCALLY, per client, at fire time -- no addon comms. Every
--  raider's own BigWigs instance already broadcasts the same bar independently, so
--  each client deciding for itself whether a reminder is "for me" is the same model
--  the tank-buster engine already uses, just with an extra yes/no check before
--  showing anything.
--
--  Engine only -- data model, scheduling, targeting, and all four displays. The
--  authoring UI (ns.ShowRaidReminderEditor, reached through the boss-detail cog's
--  ns.ShowBossReminderPicker rather than its own top-level tab) lives in
--  NaowhUI_SmartReminders_Bosses.lua, which already had the tab/mechanic-picker
--  scaffolding this needed and loads after this file.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
-- profile.raidReminders[encounterID][uid] = {
--     name, enabled,
--     trigger = { type = "bwtimer"|"bwmsg"|"pull", spellID, leadTime },
--     target  = { all = bool, roles = {TANK=true,...}, classes = {PALADIN=true,...},
--                 specs = {[specID]=true,...}, names = {["Name"]=true,...},
--                 subgroups = {[1]=true,...} },
--     display = { type = "text"|"icon"|"bar"|"circle"|"chat"|"wa"|"nameplateGlow"|
--                 "raidframeGlow", text, spellID, color, dur, sound, tts },
-- }
-- Same PerBossSet shape customReminders already uses (NaowhUI_SmartReminders.lua),
-- reused rather than reimplemented -- one helper, every per-boss table goes through it.
local function RaidRemindersTable(create, enc)
    return ns.PerBossSet("raidReminders", create, enc)
end
ns.RaidRemindersTable = RaidRemindersTable

-------------------------------------------------------------------------------
--  Targeting -- evaluated against the LOCAL player only, no roster sync needed
-------------------------------------------------------------------------------
-- Subgroup needs a roster walk since UnitGroupRolesAssigned/UnitClass/spec all answer
-- for "player" directly, but there is no single-call "which subgroup am I in" outside
-- raid group info -- confirmed against NorthernSkyRaidTools' own GetSubGroup, which
-- walks the same GetRaidRosterInfo/UnitIsUnit loop (architecture only, not copied).
local function MySubgroup()
    for i = 1, 40 do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name and UnitIsUnit(name, "player") then return subgroup end
    end
    return 1   -- solo/party: no raid roster, only ever "group 1"
end

-- Which unit token a player name currently answers to -- needed for the glow display
-- types (nameplate/raid-frame), which target a SPECIFIC other raider's frame rather
-- than deciding whether the local client should show anything at all. nil when the
-- name isn't found (out of group, typo, or just not visible in the roster this frame).
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

-- Old single kind+value shape, normalized to the new multi-flag one on read rather
-- than migrated in place -- this feature only shipped this session, so there is no
-- real saved data to preserve, and a read-time fallback is simpler than a migration
-- file for something this new. Every reader of a raid reminder's target (targeting
-- itself, the editor, the summary description) goes through this.
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

-- Confirmed against MRT's own CheckPlayerCondition: AND across categories, OR within
-- one. Multiple role flags OR together, multiple class flags OR together, but setting
-- both Role=Healer AND Class=Priest narrows to their intersection, not their union --
-- an empty/unset category is vacuously true rather than false, same as MRT's own
-- pflitercount/cflitercount/rflitercount == 0 short-circuit, so picking only a role
-- does not also require a class match by accident.
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
--  Rendering -- one Anchor (movable container) per display type, each holding a pool
--  of Region instances (one per currently-shown reminder of that type). Regions are
--  created once and hidden/reused, never destroyed -- same idiom RebuildSlots already
--  uses for the tank-buster slots[] pool.
-------------------------------------------------------------------------------
local ANCHOR_DEFAULT_POS = {
    text = { x = 0, y = 40 },
    timer = { x = -120, y = 40 },
    icon = { x = 120, y = 40 },
    bar = { x = 0, y = -60 },
    circle = { x = 120, y = -60 },
}

-- profile.raidReminderAnchorPos[displayType] = { point, relPoint, x, y }, written by
-- Unlock Mode (ns.GetRaidReminderAnchor/ns.ApplyRaidReminderAnchorPosition, wired up in
-- NaowhUI_SmartReminders.lua's RegisterUnlock) the same way the tank-buster frame's own
-- TRDB().pos already works. Falls back to ANCHOR_DEFAULT_POS when nothing is saved.
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
    a = CreateFrame("Frame", "NaowhUIRaidReminder" .. displayType .. "Anchor", UIParent)
    a:SetSize(10, 10)
    a:SetClampedToScreen(true)
    -- Matches the tank-buster callout's own baseline (NaowhUI_SmartReminders.lua) --
    -- HIGH normally, bumped to FULLSCREEN_DIALOG only while ns.PreviewRaidReminder has
    -- the editor modal open (see below).
    a:SetFrameStrata("HIGH")
    a.pool, a.active = {}, {}
    anchors[displayType] = a
    ApplyAnchorPosition(a, displayType)
    return a
end

-- Unlock Mode's getFrame: lazily creates the anchor the first time Unlock Mode itself
-- is opened, same as a real/preview fire would, so there is always something to drag
-- even if this display type has never fired this session.
ns.GetRaidReminderAnchor = GetAnchor

function ns.ApplyRaidReminderAnchorPosition(displayType)
    local a = anchors[displayType]
    if a then ApplyAnchorPosition(a, displayType) end
end

-- Stacks active regions top-to-bottom under the anchor, most-recently-added first --
-- same function for all four display types, since each has its own Anchor and never
-- stacks against a different type. Fixed top-down for now; a real grow-direction
-- setting (the authoring UI's per-anchor gear window) is a later phase, not this loop.
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
    for i = 1, #a.active do
        if a.active[i] == r then table.remove(a.active, i) break end
    end
    r:Hide()
    if r.hideTimer then r.hideTimer:Cancel(); r.hideTimer = nil end
    a.pool[#a.pool + 1] = r
    -- Undo any Preview-specific elevation (ns.PreviewRaidReminder) so a real fight never
    -- inherits it -- same reset-on-hide shape HideCustomReminder already uses for the
    -- tank-buster editor's own Preview button.
    a:SetFrameStrata("HIGH")
    a:SetFrameLevel(1)
    RestackRegions(a)
end

-- LibSharedMedia lookup, same source NaowhMedia/AlertFont (NaowhUI_SmartReminders.lua)
-- read -- duplicated rather than exported, same reasoning StatusBarTexture below
-- already gives: a few lines, no state, not worth a cross-file call for.
local function AlertFontPath()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ok, path = pcall(LSM.Fetch, LSM, "font", "Naowh", true)
        if ok and path then return path end
    end
    local EUI = _G.EllesmereUI
    local path = EUI and EUI.GetFontPath and EUI.GetFontPath("extras")
    return path or STANDARD_TEXT_FONT
end

-- User-resizable via Unlock Mode (see MakeRaidReminderUnlockElement in
-- NaowhUI_SmartReminders.lua): width is the text box's own width, font size drives how
-- big the text itself reads -- independent axes, unlike Circle/Icon which stay square.
local TEXT_WIDTH_DEFAULT, TEXT_FONTSIZE_DEFAULT = 320, 16
local function TextSize()
    local w = ns.DB().raidReminderTextWidth
    local fs = ns.DB().raidReminderTextFontSize
    w = (type(w) == "number" and w > 0) and w or TEXT_WIDTH_DEFAULT
    fs = (type(fs) == "number" and fs > 0) and fs or TEXT_FONTSIZE_DEFAULT
    return w, fs
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

function ns.ResizeRaidReminderText()
    local a = anchors.text
    if not a then return end
    local w, fs = TextSize()
    for _, r in ipairs(a.pool) do r:SetSize(w, fs + 10); r.text:SetFont(AlertFontPath(), fs, "OUTLINE") end
    for _, r in ipairs(a.active) do r:SetSize(w, fs + 10); r.text:SetFont(AlertFontPath(), fs, "OUTLINE") end
    RestackRegions(a)
end

-- A big ticking number, distinct from the static Message display -- what NSRT and
-- TimelineReminders call a Timer. label is the optional caption above it (what the
-- countdown is FOR); the number itself is driven by the same expirationTime/OnUpdate
-- idiom CreateBarRegion already uses, just formatted as whole seconds instead of a fill.
local function CreateTimerRegion(a)
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(120, 46)
    r.label = ns.Font(r, 11, "OUTLINE")
    r.label:SetFont(AlertFontPath(), 11, "OUTLINE")
    r.label:SetPoint("TOP", r, "TOP", 0, 0)
    r.number = ns.Font(r, 26, "OUTLINE")
    r.number:SetFont(AlertFontPath(), 26, "OUTLINE")
    r.number:SetPoint("TOP", r.label, "BOTTOM", 0, -2)
    r:Hide()
    return r
end

-- Icon inset matches CreateSlot's (NaowhUI_SmartReminders.lua) own texture coords --
-- same reason: crops the icon's own border art rather than showing it doubled up
-- against this region's border.
-- User-resizable via Unlock Mode, stored at TRDB().raidReminderIconSize (see
-- CircleSize's own comment for the shape).
local ICON_SIZE_DEFAULT = 48
local function IconSize()
    local s = ns.DB().raidReminderIconSize
    return (type(s) == "number" and s > 0) and s or ICON_SIZE_DEFAULT
end

local function CreateIconRegion(a)
    local size = IconSize()
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(size, size + 18)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(size, size)
    r.icon:SetPoint("TOP", r, "TOP", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.label = ns.Font(r, 12, "OUTLINE")
    r.label:SetFont(AlertFontPath(), 12, "OUTLINE")
    r.label:SetPoint("TOP", r.icon, "BOTTOM", 0, -2)
    r:Hide()
    return r
end

function ns.ResizeRaidReminderIcon()
    local a = anchors.icon
    if not a then return end
    local size = IconSize()
    for _, r in ipairs(a.pool) do r:SetSize(size, size + 18); r.icon:SetSize(size, size) end
    for _, r in ipairs(a.active) do r:SetSize(size, size + 18); r.icon:SetSize(size, size) end
    RestackRegions(a)
end

-- LibSharedMedia lookup, same source NaowhMedia (NaowhUI_SmartReminders.lua) reads --
-- duplicated rather than exported: six lines, no state, not worth a cross-file call for.
local function StatusBarTexture()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local ok, path = pcall(LSM.Fetch, LSM, "statusbar", "NaowhGradient", true)
    return ok and path or nil
end

-- Styled like the tank-buster CreateBar (NaowhUI_SmartReminders.lua) -- same texture,
-- same bg/fill colors -- but genuinely counts down here (that bar is a static 1-slot
-- display with nothing driving its value live). expirationTime/OnUpdate are this
-- region's own; set fresh by ns.DisplayRaidReminder on every acquire, so a pooled
-- region picked back up for a new reminder starts counting down from the new value the
-- moment OnUpdate's next tick runs, never from whatever the last reminder left behind.
-- User-resizable via Unlock Mode, stored at TRDB().raidReminderBarWidth/Height --
-- independent axes (unlike Circle/Icon), since a bar naturally has separate width and
-- thickness.
local BAR_WIDTH_DEFAULT, BAR_HEIGHT_DEFAULT = 240, 16
local function BarSize()
    local w, h = ns.DB().raidReminderBarWidth, ns.DB().raidReminderBarHeight
    w = (type(w) == "number" and w > 0) and w or BAR_WIDTH_DEFAULT
    h = (type(h) == "number" and h > 0) and h or BAR_HEIGHT_DEFAULT
    return w, h
end

local function CreateBarRegion(a)
    local w, h = BarSize()
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(w, h + 16)

    r.label = ns.Font(r, 12, "OUTLINE")
    r.label:SetFont(AlertFontPath(), 12, "OUTLINE")
    r.label:SetPoint("TOP", r, "TOP", 0, 0)

    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetSize(w, h)
    r.bar:SetPoint("BOTTOM", r, "BOTTOM", 0, 0)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetStatusBarTexture(StatusBarTexture() or "Interface\\TargetingFrame\\UI-StatusBar")
    local T = ns.THEME
    local bg = r.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", r.bar, "TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", r.bar, "BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 0.9)
    local fill = r.bar:GetStatusBarTexture()
    if fill then fill:SetVertexColor(T.gold.r, T.gold.g, T.gold.b, 1) end
    ns.Border(r.bar)

    r:Hide()
    return r
end

function ns.ResizeRaidReminderBar()
    local a = anchors.bar
    if not a then return end
    local w, h = BarSize()
    for _, r in ipairs(a.pool) do r:SetSize(w, h + 16); r.bar:SetSize(w, h) end
    for _, r in ipairs(a.active) do r:SetSize(w, h + 16); r.bar:SetSize(w, h) end
    RestackRegions(a)
end

-- A real spell icon, circularly cropped, with the standard Blizzard cooldown-swipe
-- widget on top -- a square icon plus a swipe is what every action button does, but
-- reads as a square with a pie-wipe, not "an actual circle". The mask/border pair is
-- EllesmereUI's own "Circle" action-button shape asset (EllesmereUIActionBars.lua's
-- SHAPE_MASKS/SHAPE_BORDERS.circle) -- same file this addon already hard-depends on,
-- so a Circle reminder reads as the same circle shape the rest of the suite uses
-- rather than a second lookalike asset.
local CIRCLE_SIZE_DEFAULT = 56
local CIRCLE_MASK_PATH = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga"
local CIRCLE_BORDER_PATH = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_border.tga"

-- User-resizable via Unlock Mode's own resize handle (see MakeRaidReminderUnlockElement
-- in NaowhUI_SmartReminders.lua), stored at TRDB().raidReminderCircleSize.
local function CircleSize()
    local s = ns.DB().raidReminderCircleSize
    return (type(s) == "number" and s > 0) and s or CIRCLE_SIZE_DEFAULT
end

-- Masking the swipe with the ring shape (CIRCLE_BORDER_PATH) came back an opaque black
-- square, same as the full disc mask did before it -- confirmed live twice now with two
-- different mask shapes, so the Cooldown widget's own masking just does not work on
-- this client, full stop. The ring sweep below is built from scratch instead: RING_TICKS
-- small dark segments arranged clockwise from 12 o'clock, each individually masked with
-- the SAME ring mask already proven reliable on a plain Texture (it clips r.icon
-- correctly) -- shown/hidden progressively as time passes rather than relying on
-- anything the Cooldown widget draws itself. Cooldown is kept only for the countdown
-- number (SetDrawSwipe/SetDrawEdge false, so it contributes no visual fill).
local RING_TICKS = 24

-- Measured directly from circle_border.tga (128x128): its ring sits at radius 0.395 of
-- the half-size, not a guess -- alpha-extracted the texture and sampled a horizontal
-- line through the center to find the actual opaque band (x=10-17 and x=111-118 out of
-- 128px, i.e. radius ~50.5px of a 64px half-width). Tick size is derived from that same
-- radius's own circumference divided by RING_TICKS, so the overlap between neighbouring
-- segments (a small, deliberate one -- see tickSize below) scales correctly with icon
-- size instead of the old fixed 0.22*size guess, which overlapped by 30%+ regardless of
-- spacing and swallowed most of the icon.
local RING_RADIUS_FRAC = 0.395
local function PositionCircleTicks(r, size)
    local radius = size * RING_RADIUS_FRAC
    local arcLen = (2 * math.pi * radius) / RING_TICKS
    -- >1x on purpose: a wanted solid arc, not a dashed ring, so neighbouring segments
    -- overlap slightly rather than leaving a gap between them.
    local tickSize = arcLen * 1.15
    for i = 1, RING_TICKS do
        local t = r.ticks[i]
        t:SetSize(tickSize, tickSize)
        local theta = (i - 1) / RING_TICKS * (2 * math.pi)
        t:ClearAllPoints()
        t:SetPoint("CENTER", r.icon, "CENTER", radius * math.sin(theta), radius * math.cos(theta))
        t:SetRotation(-theta)
    end
end

local function CreateCircleRegion(a)
    local size = CircleSize()
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(size, size + 18)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(size, size)
    r.icon:SetPoint("TOP", r, "TOP", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local mask = r:CreateMaskTexture()
    mask:SetAllPoints(r.icon)
    mask:SetTexture(CIRCLE_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    r.icon:AddMaskTexture(mask)

    local ringMask = r:CreateMaskTexture()
    ringMask:SetAllPoints(r.icon)
    ringMask:SetTexture(CIRCLE_BORDER_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    r.swipe = CreateFrame("Cooldown", nil, r, "CooldownFrameTemplate")
    r.swipe:SetAllPoints(r.icon)
    r.swipe:SetHideCountdownNumbers(false)
    r.swipe:SetDrawEdge(false)
    r.swipe:SetDrawSwipe(false)

    -- Border MUST be created before the ticks: same OVERLAY layer, and a later-created
    -- texture draws on top of an earlier one at the same layer -- with border created
    -- after (as it was before), its own always-opaque ring sat on top of every tick and
    -- completely hid them regardless of color or show/hide state, which is why nothing
    -- ever appeared to change. Confirmed live: what looked like "the ring, unchanging"
    -- across the whole cooldown was just this static decoration the whole time.
    r.border = r:CreateTexture(nil, "OVERLAY")
    r.border:SetAllPoints(r.icon)
    r.border:SetTexture(CIRCLE_BORDER_PATH)

    r.ticks = {}
    for i = 1, RING_TICKS do
        local t = r:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        t:AddMaskTexture(ringMask)
        t:Hide()
        r.ticks[i] = t
    end
    PositionCircleTicks(r, size)

    r.label = ns.Font(r, 12, "OUTLINE")
    r.label:SetFont(AlertFontPath(), 12, "OUTLINE")
    r.label:SetPoint("TOP", r.icon, "BOTTOM", 0, -2)

    r:Hide()
    return r
end

-- Re-sizes every pooled/active Circle region to the current CircleSize() -- border/label
-- anchor off r.icon rather than carrying their own fixed size, so resizing r/r.icon
-- covers them; the ring ticks need their own positions/sizes recomputed since they are
-- placed by absolute offset, not anchored proportionally. Called from Unlock Mode's
-- setWidth/setHeight (NaowhUI_SmartReminders.lua) after a drag-resize.
function ns.ResizeRaidReminderCircle()
    local a = anchors.circle
    if not a then return end
    local size = CircleSize()
    for _, r in ipairs(a.pool) do
        r:SetSize(size, size + 18); r.icon:SetSize(size, size); PositionCircleTicks(r, size)
    end
    for _, r in ipairs(a.active) do
        r:SetSize(size, size + 18); r.icon:SetSize(size, size); PositionCircleTicks(r, size)
    end
    RestackRegions(a)
end

-- Anchor sizes for Unlock Mode's mover box (ns.GetRaidReminderAnchor's caller) -- the
-- anchor frame itself is a bare 10x10 point, so without this the mover would draw far
-- smaller than what actually appears there. Floored at MOVER_MIN in both dimensions
-- (well past the tank-buster "Smart" element's own default iconSize of 64) so every
-- anchor is comfortably easier to click and drag than that one, even where the real
-- content is thinner (Text/Bar are only ~16-32px tall by default).
local MOVER_MIN = 100
function ns.RaidReminderAnchorSize(displayType)
    local w, h
    if displayType == "text" then local tw, fs = TextSize(); w, h = tw, fs + 10
    elseif displayType == "timer" then w, h = 120, 46
    elseif displayType == "icon" then local s = IconSize(); w, h = s, s + 18
    elseif displayType == "bar" then local bw, bh = BarSize(); w, h = bw, bh + 16
    elseif displayType == "circle" then local s = CircleSize(); w, h = s, s + 18
    else w, h = MOVER_MIN, MOVER_MIN end
    return math.max(w, MOVER_MIN), math.max(h, MOVER_MIN)
end

local REGION_CTORS = {
    text = CreateTextRegion, timer = CreateTimerRegion, icon = CreateIconRegion,
    bar = CreateBarRegion, circle = CreateCircleRegion,
}

local function AcquireRegion(displayType)
    local a = GetAnchor(displayType)
    local ctor = REGION_CTORS[displayType]
    if not ctor then return nil end
    local r = table.remove(a.pool)
    if not r then r = ctor(a) end
    -- Set explicitly rather than left to inherit from the parent at creation time --
    -- a pooled region can be reused long after the anchor's own strata/level last
    -- changed (e.g. a preview elevation from an earlier open of the editor).
    r:SetFrameStrata(a:GetFrameStrata())
    r:SetFrameLevel(a:GetFrameLevel() + 1)
    a.active[#a.active + 1] = r
    return a, r
end

-------------------------------------------------------------------------------
--  Glow display types -- nameplate/raid-frame, a highlight on an EXISTING unit frame
--  rather than a floating on-screen widget, so they don't fit the Anchor/Region pool
--  above (that pool always renders at one fixed screen spot; a glow's location is
--  wherever the target's frame happens to be this instant, resolved fresh on every
--  fire). Own small pool of dedicated overlay wrapper frames instead: EllesmereUI's
--  glow engine (EllesmereUI.Glows) hides its glow via SetAlpha(0) on the frame it was
--  given (StopGlow), so that frame has to be a dedicated overlay parented over the
--  target, never the nameplate/raid-frame's own display frame -- gluing a glow
--  directly onto that would blank the whole frame the instant the glow ends.
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
    local Glows = _G.EllesmereUI and _G.EllesmereUI.Glows
    if Glows and Glows.StopGlow then Glows.StopGlow(w) end
    if w.hideTimer then w.hideTimer:Cancel(); w.hideTimer = nil end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(UIParent)
    w.hideAfterCastID = nil
    for i = 1, #activeGlows do
        if activeGlows[i] == w then table.remove(activeGlows, i) break end
    end
    glowPool[#glowPool + 1] = w
end

-- nameplate reads the live Blizzard nameplate directly (C_NamePlate); raidframe reads
-- EllesmereUI's own raid frame accessor (a small addition to EllesmereUIRaidFrames.lua
-- -- that frame keeps its unit->button map private otherwise). Either can come back
-- nil (unit not currently visible on any frame of that kind), in which case the glow
-- is silently skipped for this fire -- same behavior confirmed from MRT's own
-- raid-frame glow, which no-ops the same way when LibGetFrame finds nothing.
local function ResolveGlowFrame(displayType, unit)
    if displayType == "nameplateGlow" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        return plate and (plate.UnitFrame or plate)
    elseif displayType == "raidframeGlow" then
        local EUIg = _G.EllesmereUI
        return EUIg and EUIg.RaidFrames_GetFrameForUnit and EUIg.RaidFrames_GetFrameForUnit(unit)
    end
    return nil
end

local function FireGlowReminder(display, dur)
    local unit = UnitTokenForName(display.glowTarget)
    local frame = unit and ResolveGlowFrame(display.type, unit)
    if not frame then return end

    local w = AcquireGlowWrapper()
    w:SetParent(frame)
    w:ClearAllPoints()
    w:SetAllPoints(frame)
    w:Show()
    w.hideAfterCastID = display.hideAfterCastID

    local Glows = _G.EllesmereUI and _G.EllesmereUI.Glows
    if Glows and Glows.StartButtonGlow then
        local c = display.color
        Glows.StartButtonGlow(w, frame:GetWidth() or 40,
            (c and c.r) or 1, (c and c.g) or 0.82, (c and c.b) or 0, nil, frame:GetHeight() or 40)
    end

    if w.hideTimer then w.hideTimer:Cancel() end
    w.hideTimer = C_Timer.NewTimer(dur, function() ReleaseGlowWrapper(w) end)
end

-- Same two-step icon resolution CreateSlot (NaowhUI_SmartReminders.lua) already uses:
-- GetSpellInfo first (nothing for a spell the client has not cached yet), GetSpellTexture
-- as a second try, the question mark as the last resort -- never a blank icon. Shared by
-- Icon and Circle, the two display types that show a real spell icon.
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

-- Curated subset of MRT's own placeholder language (MRT's version runs to roughly 40
-- distinct constructs -- a math evaluator, regex find/replace, a class/role/subgroup
-- filter-query language; deliberately not reproduced here, see this session's own MRT
-- research). %name is always the VIEWER's own name and class color, never anyone
-- else's -- a reminder can target more than one person, and each client only ever
-- needs to say its own. {spell:ID} skips the hover tooltip MRT's version has: nothing
-- in this addon's display widgets are hoverable, so a tooltip would never be reachable.
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

-- The one place every real fire (and, once the editor exists, every Preview click)
-- routes through -- same "one dispatcher" shape as the existing ns.DisplayReminder for
-- Custom Reminders.
function ns.DisplayRaidReminder(entry)
    local display = entry and entry.display
    if not display then return end

    -- Resolved once, used everywhere below (every display widget, chat, and TTS) --
    -- display.text itself stays the raw saved template, since Preview/every future
    -- fire has to re-resolve it fresh (the viewer's own name can change between
    -- fires even within one pull, e.g. a raid reminder that fires more than once).
    local formattedText = FormatReminderMsg(display.text, display)

    -- Chat has no on-screen Region at all -- a local chat line, same sound/TTS as
    -- every other type, no pooled frame or hide timer to manage.
    if display.type == "chat" then
        if formattedText and formattedText ~= "" then ns.Print(formattedText) end
        ns.PlayReminderSound(display)
        ns.SpeakReminderTTS(display, formattedText)
        return
    end

    -- Glow types highlight an existing unit frame instead of the Anchor/Region pool
    -- below -- FireGlowReminder owns their whole lifecycle (frame resolution, the
    -- dedicated overlay wrapper, the hide timer), same sound/TTS tacked on same as
    -- every other type.
    if display.type == "nameplateGlow" or display.type == "raidframeGlow" then
        local dur = (type(display.dur) == "number" and display.dur > 0) and display.dur or 4
        FireGlowReminder(display, dur)
        ns.PlayReminderSound(display)
        ns.SpeakReminderTTS(display, formattedText)
        return
    end

    local a, r = AcquireRegion(display.type)
    if not r then
        ns.Print(("|cffff6060raid reminder|r: display type %q not built yet."):format(
            tostring(display.type)))
        return
    end
    -- Read by the UNIT_SPELLCAST_SUCCEEDED watcher below -- nil for the vast majority
    -- of reminders, which never carry this optional field.
    r.hideAfterCastID = display.hideAfterCastID

    -- Computed here, not after the type dispatch below: Bar/Circle need it to drive
    -- their own live countdown, and the release timer at the bottom needs the SAME
    -- value so a bar's visual countdown and the moment it actually disappears agree.
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
        r:SetScript("OnUpdate", function(self)
            local remain = self.expirationTime - GetTime()
            self.number:SetText(remain > 0 and tostring(math.ceil(remain)) or "0")
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
        -- No question-mark fallback here (unlike Icon): an empty ring is the wanted
        -- look for a Circle reminder with no spell ID set, not a placeholder icon.
        r.icon:SetTexture(ResolveDisplayIconID(display))
        r.label:SetText(formattedText or "")
        r.swipe:SetCooldown(GetTime(), dur)   -- countdown number only, no visual fill (see CreateCircleRegion)
        r.expirationTime = GetTime() + dur
        for i = 1, RING_TICKS do r.ticks[i]:Show() end
        -- Confirmed against TimelineReminders' own CircleRegion.lua: the cleared
        -- (elapsed) wedge starts AT 12 o'clock and grows CLOCKWISE as time passes, so
        -- the ticks nearest 12 (low index, small theta) are what should hide FIRST --
        -- the previous version hid high-index ticks first instead, sweeping backwards.
        r:SetScript("OnUpdate", function(self)
            local remain = self.expirationTime - GetTime()
            local elapsedFrac = remain > 0 and (1 - remain / dur) or 1
            local hideCount = math.floor(elapsedFrac * RING_TICKS)
            for i = 1, RING_TICKS do
                if i <= hideCount then self.ticks[i]:Hide() else self.ticks[i]:Show() end
            end
        end)
    end

    r:Show()
    RestackRegions(a)
    ns.PlayReminderSound(display)
    ns.SpeakReminderTTS(display, formattedText)

    if r.hideTimer then r.hideTimer:Cancel() end
    r.hideTimer = C_Timer.NewTimer(dur, function() ReleaseRegion(a, r) end)
end

-- The editor's Preview button fires this from inside its own modal (FULLSCREEN_DIALOG),
-- which the anchor's normal HIGH strata sits well below -- same problem and same fix
-- ns.PreviewCustomReminder (NaowhUI_SmartReminders.lua) already solved for the
-- tank-buster editor's own Preview button. ReleaseRegion drops the anchor back to HIGH
-- once the preview ends, so the elevation never leaks into a real fight's display.
function ns.PreviewRaidReminder(entry)
    local display = entry and entry.display
    if not display then return end
    -- Chat and the glow types have no anchor to elevate -- ns.DisplayRaidReminder's
    -- own branches for them handle everything needed below with nothing extra here.
    local NO_ANCHOR_TYPES = { chat = true, nameplateGlow = true, raidframeGlow = true }
    local a = (not NO_ANCHOR_TYPES[display.type]) and GetAnchor(display.type) or nil
    if a then
        a:SetFrameStrata("FULLSCREEN_DIALOG")
        a:SetFrameLevel(250)
        -- Clicking Preview again before the last one finished lingering was stacking a
        -- brand new region on top of it each time (AcquireRegion has no reason to know
        -- a previous preview of this exact type is still up) -- release whatever is
        -- still active on this anchor first so a preview replaces the last one instead
        -- of piling up. Only Preview does this; a real fire never should, since two
        -- genuinely different reminders of the same display type stacking together is
        -- correct there.
        while #a.active > 0 do ReleaseRegion(a, a.active[#a.active]) end
    end
    ns.DisplayRaidReminder(entry)
end

-- MRT's event-13 "hide after use" gate: a reminder with display.hideAfterCastID set
-- disappears the instant you successfully cast that spell, instead of waiting out its
-- own Linger. RegisterUnitEvent("player") rather than parsing the combat log --
-- lighter, and there is no need to know about anyone else's casts here.
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
--  Anchor config -- move and resize every anchor with a live sample shown for each,
--  opened from the Raid/Dungeon Reminders page ("Customize Anchors" button). Same idea
--  NSRT/TimelineReminders both offer, built on this addon's own existing pieces (the
--  Anchor/pool system above, ns.MakeModal, ns.THEME) rather than copying either one's
--  look: a plain in-house drag handle + gear popup instead of their green banner rows.
-------------------------------------------------------------------------------
local DISPLAY_TYPE_LABEL = { text = "Message", timer = "Timer", icon = "Icon", bar = "Bar", circle = "Circle" }
local CONFIG_ORDER = { "text", "timer", "icon", "bar", "circle" }

local configShown = {}     -- [displayType] = true while its checkbox is on
local configActive = false

-- Fills a region with static placeholder content -- no live countdown, no hide timer --
-- so it sits still on screen for as long as config mode has that type checked. Separate
-- from ns.DisplayRaidReminder's dispatch, which is built around a live, expiring fire.
local function PopulateSample(displayType, r)
    if displayType == "text" then
        r.text:SetText("Sample Reminder")
        r.text:SetTextColor(1, 1, 1, 1)
    elseif displayType == "icon" then
        r.icon:SetTexture(134400)
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
        r.icon:SetTexture(134400)
        r.label:SetText("Sample")
        r.swipe:SetCooldown(0, 0)
        r:SetScript("OnUpdate", nil)
        -- 40% elapsed for reference -- ticks near 12 o'clock (low index) hide first,
        -- matching the real fire's own direction (see ns.DisplayRaidReminder).
        local hideCount = math.floor(RING_TICKS * 0.4)
        for i = 1, RING_TICKS do
            if i <= hideCount then r.ticks[i]:Hide() else r.ticks[i]:Show() end
        end
    end
end

-- The draggable handle: a small labeled bar below the anchor's sample, carrying the
-- gear button. Created once per anchor and reused; StartMoving/StopMovingOrSizing are
-- called on the ANCHOR (the handle is just the visible grip), same idiom
-- NaowhUI_SmartReminders.lua's own UpdatePreview already uses for the tank-buster frame.
local function EnsureConfigHandle(displayType, a)
    if a._configHandle then return a._configHandle end
    local T = ns.THEME
    local h = CreateFrame("Button", nil, a)
    h:SetSize(150, 24)
    ns.Solid(h, "BACKGROUND", T.panel, 0.95)
    ns.Border(h)

    local label = ns.Font(h, 12, "OUTLINE", T.gold)
    label:SetPoint("LEFT", h, "LEFT", 8, 0)
    label:SetText(DISPLAY_TYPE_LABEL[displayType])

    local gear = CreateFrame("Button", nil, h)
    gear:SetSize(18, 18)
    gear:SetPoint("RIGHT", h, "RIGHT", -4, 0)
    local gearTex = gear:CreateTexture(nil, "ARTWORK")
    gearTex:SetAllPoints()
    gearTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetScript("OnClick", function() ns.ShowRaidReminderAnchorSizePopup(displayType) end)

    h:SetMovable(true)
    a:SetMovable(true)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function() a:StartMoving() end)
    h:SetScript("OnDragStop", function()
        a:StopMovingOrSizing()
        local point, _, relPoint, x, y = a:GetPoint(1)
        if point then
            local db = ns.DB()
            db.raidReminderAnchorPos = db.raidReminderAnchorPos or {}
            db.raidReminderAnchorPos[displayType] = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    a._configHandle = h
    return h
end

local function RefreshConfigVisual(displayType)
    local a = GetAnchor(displayType)
    local h = EnsureConfigHandle(displayType, a)

    -- Built directly from REGION_CTORS rather than AcquireRegion, deliberately NOT
    -- tracked in a.active/a.pool: a real fire or Preview click while config mode is
    -- open would otherwise pull this sample into RestackRegions' normal stacking and
    -- reshuffle both it and the handle anchored off it. This way the sample always
    -- sits still at the anchor's own TOP regardless of what else happens to fire.
    if not a._configSample then
        a._configSample = REGION_CTORS[displayType](a)
    end
    a._configSample:SetFrameStrata(a:GetFrameStrata())
    a._configSample:SetFrameLevel(a:GetFrameLevel() + 1)
    PopulateSample(displayType, a._configSample)
    a._configSample:ClearAllPoints()
    a._configSample:SetPoint("TOP", a, "TOP", 0, 0)
    a._configSample:Show()

    -- Right under the sample's ACTUAL current height, not a fixed guess -- otherwise a
    -- small type (Message, Timer) leaves a large gap to the handle below it, and a
    -- large one could have the handle overlapping it.
    h:ClearAllPoints()
    h:SetPoint("TOP", a._configSample, "BOTTOM", 0, -4)
    h:Show()
end

local function HideConfigVisual(displayType)
    local a = anchors[displayType]
    if not a then return end
    if a._configHandle then a._configHandle:Hide() end
    -- Not pool-tracked (see RefreshConfigVisual), so just hidden and kept cached on the
    -- anchor for next time rather than released back to a.pool.
    if a._configSample then a._configSample:Hide() end
end

-- Rebuilds every checked type's visual -- called on entering config mode and after any
-- resize, since the handle is anchored off the sample's own height and needs re-placing
-- when that height changes.
local function RefreshAllConfigVisuals()
    if not configActive then return end
    for _, displayType in ipairs(CONFIG_ORDER) do
        if configShown[displayType] then RefreshConfigVisual(displayType) end
    end
end
ns.RefreshRaidReminderAnchorConfig = RefreshAllConfigVisuals

function ns.SetRaidReminderAnchorConfigShown(displayType, shown)
    configShown[displayType] = shown or nil
    if not configActive then return end
    if shown then RefreshConfigVisual(displayType) else HideConfigVisual(displayType) end
end

function ns.IsRaidReminderAnchorConfigShown(displayType)
    return configShown[displayType] == true
end

-- The toolbar itself: a small draggable panel on UIParent (not inside the EllesmereUI
-- options panel, so it stays put and usable while the panel is scrolled or another
-- tab is open) with one checkbox per display type and an Exit button. Built once,
-- shown/hidden rather than recreated.
local configToolbar

-- 2-column grid: 5 checkboxes fill the first 2.5 rows, Exit Config takes the otherwise
-- empty slot next to Circle (last checkbox, alone in the left column) instead of a
-- separate bottom row that overlapped it.
local CONFIG_COL_W, CONFIG_ROW_H = 148, 24

local function BuildConfigToolbar()
    if configToolbar then return configToolbar end
    local T = ns.THEME
    local f = CreateFrame("Frame", "NaowhUIRaidReminderAnchorConfig", UIParent)
    f:SetSize(300, 116)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    ns.Solid(f, "BACKGROUND", { r = 0, g = 0, b = 0 }, 1):SetAllPoints()
    ns.Border(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local head = ns.Font(f, 12, "OUTLINE", T.gold)
    head:SetPoint("TOP", f, "TOP", 0, -10)
    head:SetText("Reminder Anchors")

    local checks = {}
    local lastRow = 0
    for i, displayType in ipairs(CONFIG_ORDER) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        lastRow = row
        local chk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        chk:SetSize(20, 20)
        chk:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + col * CONFIG_COL_W, -32 - row * CONFIG_ROW_H)
        local lbl = ns.Font(f, 11, nil, T.fg)
        lbl:SetPoint("LEFT", chk, "RIGHT", 2, 1)
        lbl:SetText("Show " .. DISPLAY_TYPE_LABEL[displayType] .. " Anchor")
        chk:SetScript("OnClick", function(self)
            ns.SetRaidReminderAnchorConfigShown(displayType, self:GetChecked() and true or false)
        end)
        checks[displayType] = chk
    end

    -- 5 items leaves the right column of the last row open; an odd count would instead
    -- fall after the last row entirely.
    local exitCol = (#CONFIG_ORDER % 2 == 1) and 1 or 0
    local exitRow = (#CONFIG_ORDER % 2 == 1) and lastRow or (lastRow + 1)
    ns.Button(f, "Exit Config", CONFIG_COL_W - 14, 22, function() ns.HideRaidReminderAnchorConfig() end)
        :SetPoint("TOPLEFT", f, "TOPLEFT", 14 + exitCol * CONFIG_COL_W, -31 - exitRow * CONFIG_ROW_H)

    f._checks = checks
    configToolbar = f
    return f
end

function ns.ShowRaidReminderAnchorConfig()
    configActive = true
    local f = BuildConfigToolbar()
    for _, displayType in ipairs(CONFIG_ORDER) do
        if f._checks[displayType] then f._checks[displayType]:SetChecked(configShown[displayType] == true) end
    end
    f:Show()
    RefreshAllConfigVisuals()
end

function ns.HideRaidReminderAnchorConfig()
    configActive = false
    if configToolbar then configToolbar:Hide() end
    for _, displayType in ipairs(CONFIG_ORDER) do HideConfigVisual(displayType) end
end

function ns.IsRaidReminderAnchorConfigActive()
    return configActive
end

-- Compact size popup for one anchor's gear button -- Width/Height for Bar and Message
-- (independent axes), a single Size for Icon/Circle (kept square), nothing for Timer
-- (not resizable, matching the Trigger/Target editor's own scope).
local RESIZE_ROWS = {
    circle = { { label = "Size", get = function() return CircleSize() end,
        set = function(v) ns.DB().raidReminderCircleSize = math.max(20, math.floor(v)); ns.ResizeRaidReminderCircle() end } },
    icon = { { label = "Size", get = function() return IconSize() end,
        set = function(v) ns.DB().raidReminderIconSize = math.max(16, math.floor(v)); ns.ResizeRaidReminderIcon() end } },
    bar = {
        { label = "Width", get = function() return (BarSize()) end,
            set = function(v) ns.DB().raidReminderBarWidth = math.max(60, math.floor(v)); ns.ResizeRaidReminderBar() end },
        { label = "Height", get = function() local _, h = BarSize(); return h end,
            set = function(v) ns.DB().raidReminderBarHeight = math.max(6, math.floor(v)); ns.ResizeRaidReminderBar() end },
    },
    text = {
        { label = "Width", get = function() return (TextSize()) end,
            set = function(v) ns.DB().raidReminderTextWidth = math.max(60, math.floor(v)); ns.ResizeRaidReminderText() end },
        { label = "Font Size", get = function() local _, fs = TextSize(); return fs end,
            set = function(v) ns.DB().raidReminderTextFontSize = math.max(8, math.floor(v)); ns.ResizeRaidReminderText() end },
    },
}

function ns.ShowRaidReminderAnchorSizePopup(displayType)
    local rows = RESIZE_ROWS[displayType]
    if not rows then return end

    local dimmer, panel = ns.MakeModal(240, 60 + #rows * 34)
    local head = ns.Font(panel, 13, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -14)
    head:SetText((DISPLAY_TYPE_LABEL[displayType] or displayType) .. " Size")

    local PAD, y = 16, -42
    for i = 1, #rows do
        local row = rows[i]
        local l = ns.Font(panel, 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        l:SetText(row.label)

        local box = CreateFrame("EditBox", nil, panel)
        box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y + 5)
        box:SetSize(70, 24)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(4)
        box:SetFontObject("GameFontHighlight")
        box:SetTextInsets(6, 6, 0, 0)
        ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
        ns.Border(box)
        box:SetText(tostring(math.floor(row.get() or 0)))
        local function Commit(self)
            local v = tonumber(self:GetText())
            if v then row.set(v); RefreshAllConfigVisuals() end
            self:ClearFocus()
        end
        box:SetScript("OnEnterPressed", Commit)
        box:SetScript("OnEditFocusLost", Commit)
        y = y - 34
    end

    ns.Button(panel, "Done", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
    dimmer:Show()
end

-------------------------------------------------------------------------------
--  Firing
-------------------------------------------------------------------------------
local function FireRaidReminder(entry)
    if entry.enabled == false then return end
    if not ns.RaidReminderTargetsMe(entry.target) then return end
    ns.DisplayRaidReminder(entry)
end

-- Same master switch as everything else in this addon (Custom Reminders already share
-- TRDB().enabled rather than having their own separate on/off) -- one switch, not a
-- second concept of "is the addon on" to keep in sync.
local function RaidRemindersAllowed()
    return ns.DB().enabled == true and ns.AllowedHere() and ns.BossAllowed()
end

-- BigWigs only, deliberately -- OnBigWigsEvent is the only caller (OnDBMEvent never
-- calls this). sid/duration/barIdentity are exactly what it already extracted and
-- issecretvalue-checked for ns.HandleBigWigsAbility -- reused as-is, no new secret
-- handling needed. Every raidReminders entry for the current encounter whose trigger
-- matches this exact broadcast gets scheduled independently (a pull can reasonably want
-- more than one reminder off the same bar, e.g. one for the tank and one for the healer).
function ns.HandleRaidReminderAbility(sid, duration, barIdentity)
    if type(sid) ~= "number" or sid <= 0 then return end
    if not (ns.InEncounter and ns.InEncounter()) then return end
    if not RaidRemindersAllowed() then return end
    local enc = ns.CurrentEncounter and ns.CurrentEncounter()
    if not enc then return end
    local reminders = RaidRemindersTable(false, enc)
    if not reminders then return end

    for _, entry in pairs(reminders) do
        local trig = entry.trigger
        if trig and trig.spellID == sid then
            local wantsBar = trig.type == "bwtimer"
            local haveBar = type(duration) == "number" and duration > 0.5
            if wantsBar and haveBar then
                local lead = (type(trig.leadTime) == "number" and trig.leadTime > 0)
                    and trig.leadTime or 3
                ns.ScheduleBWFire("raid", sid, duration, barIdentity, lead, function()
                    FireRaidReminder(entry)
                end)
            elseif trig.type == "bwmsg" and not haveBar then
                FireRaidReminder(entry)
            end
        end
    end
end

-- "pull" triggers aren't anchored to any BigWigs broadcast, so they never reach
-- ns.HandleRaidReminderAbility above -- called once from ENCOUNTER_START instead
-- (NaowhUI_SmartReminders.lua), the exact same moment CheckCustomReminders' own
-- "pull" trigger already answers to, rather than a second concept of "when did we
-- pull."
function ns.CheckRaidReminderPullTriggers()
    if not (ns.InEncounter and ns.InEncounter()) then return end
    if not RaidRemindersAllowed() then return end
    local enc = ns.CurrentEncounter and ns.CurrentEncounter()
    if not enc then return end
    local reminders = RaidRemindersTable(false, enc)
    if not reminders then return end

    for _, entry in pairs(reminders) do
        local trig = entry.trigger
        if trig and trig.type == "pull" then
            local delay = (type(trig.delay) == "number" and trig.delay >= 0) and trig.delay or 0.01
            C_Timer.NewTimer(math.max(delay, 0.01), function() FireRaidReminder(entry) end)
        end
    end
end
