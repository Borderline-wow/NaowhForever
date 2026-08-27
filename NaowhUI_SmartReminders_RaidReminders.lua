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
--  authoring UI (ns.BuildRaidRemindersPage/ns.ShowRaidReminderEditor, the "Raid
--  Reminders" Setup tab) lives in NaowhUI_SmartReminders_Bosses.lua, which already had
--  the tab/mechanic-picker scaffolding this needed and loads after this file.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
-- profile.raidReminders[encounterID][uid] = {
--     name, enabled,
--     trigger = { type = "bwtimer"|"bwmsg", spellID, leadTime },
--     target  = { kind = "all"|"role"|"class"|"spec"|"name"|"subgroup", value },
--     display = { type = "text"|"icon"|"bar"|"circle", text, spellID, color, dur, sound },
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

function ns.RaidReminderTargetsMe(target)
    if not target or target.kind == "all" then return true end
    if target.kind == "role" then
        return UnitGroupRolesAssigned("player") == target.value
    elseif target.kind == "class" then
        local _, classToken = UnitClass("player")
        return classToken == target.value
    elseif target.kind == "spec" then
        local id = ns.CurrentSpec and ns.CurrentSpec()
        return id == target.value
    elseif target.kind == "name" then
        return UnitName("player") == target.value
    elseif target.kind == "subgroup" then
        return MySubgroup() == target.value
    end
    return false
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

local function CreateTextRegion(a)
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(320, 26)
    r.text = ns.Font(r, 16, "OUTLINE")
    r.text:SetFont(AlertFontPath(), 16, "OUTLINE")
    r.text:SetPoint("CENTER")
    r:Hide()
    return r
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
local ICON_SIZE = 48
local function CreateIconRegion(a)
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(ICON_SIZE, ICON_SIZE + 18)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("TOP", r, "TOP", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.label = ns.Font(r, 12, "OUTLINE")
    r.label:SetFont(AlertFontPath(), 12, "OUTLINE")
    r.label:SetPoint("TOP", r.icon, "BOTTOM", 0, -2)
    r:Hide()
    return r
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
local BAR_WIDTH, BAR_HEIGHT = 240, 16
local function CreateBarRegion(a)
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(BAR_WIDTH, BAR_HEIGHT + 16)

    r.label = ns.Font(r, 12, "OUTLINE")
    r.label:SetFont(AlertFontPath(), 12, "OUTLINE")
    r.label:SetPoint("TOP", r, "TOP", 0, 0)

    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
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

-- A real spell icon with the standard Blizzard cooldown-swipe widget on top -- the same
-- two primitives every action button combines, so this reads exactly like every other
-- cooldown on screen instead of a flat colour swatch (what this used to be: a plain
-- gold square with no icon at all, which is what did not "look good").
local CIRCLE_SIZE = 56
local function CreateCircleRegion(a)
    local r = CreateFrame("Frame", nil, a)
    r:SetSize(CIRCLE_SIZE, CIRCLE_SIZE + 18)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(CIRCLE_SIZE, CIRCLE_SIZE)
    r.icon:SetPoint("TOP", r, "TOP", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.swipe = CreateFrame("Cooldown", nil, r, "CooldownFrameTemplate")
    r.swipe:SetAllPoints(r.icon)
    r.swipe:SetHideCountdownNumbers(false)

    r.label = ns.Font(r, 12, "OUTLINE")
    r.label:SetFont(AlertFontPath(), 12, "OUTLINE")
    r.label:SetPoint("TOP", r.icon, "BOTTOM", 0, -2)

    r:Hide()
    return r
end

-- Anchor sizes for Unlock Mode's mover box (ns.GetRaidReminderAnchor's caller) -- the
-- anchor frame itself is a bare 10x10 point, so without this the mover would draw far
-- smaller than what actually appears there.
function ns.RaidReminderAnchorSize(displayType)
    if displayType == "text" then return 320, 26
    elseif displayType == "timer" then return 120, 46
    elseif displayType == "icon" then return ICON_SIZE, ICON_SIZE + 18
    elseif displayType == "bar" then return BAR_WIDTH, BAR_HEIGHT + 16
    elseif displayType == "circle" then return CIRCLE_SIZE, CIRCLE_SIZE + 18
    end
    return 10, 10
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

-- The one place every real fire (and, once the editor exists, every Preview click)
-- routes through -- same "one dispatcher" shape as the existing ns.DisplayReminder for
-- Custom Reminders.
function ns.DisplayRaidReminder(entry)
    local display = entry and entry.display
    if not display then return end
    local a, r = AcquireRegion(display.type)
    if not r then
        ns.Print(("|cffff6060raid reminder|r: display type %q not built yet."):format(
            tostring(display.type)))
        return
    end

    -- Computed here, not after the type dispatch below: Bar/Circle need it to drive
    -- their own live countdown, and the release timer at the bottom needs the SAME
    -- value so a bar's visual countdown and the moment it actually disappears agree.
    local dur = (type(display.dur) == "number" and display.dur > 0) and display.dur or 4

    if display.type == "text" then
        r.text:SetText(display.text or "")
        if display.color then
            r.text:SetTextColor(display.color.r or 1, display.color.g or 1,
                display.color.b or 1, display.color.a or 1)
        else
            r.text:SetTextColor(1, 1, 1, 1)
        end
    elseif display.type == "icon" then
        r.icon:SetTexture(ResolveDisplayIconID(display) or 134400)
        if display.text and display.text ~= "" then
            r.label:SetText(display.text)
            r.label:Show()
        else
            r.label:Hide()
        end
    elseif display.type == "timer" then
        r.label:SetText(display.text or "")
        r.expirationTime = GetTime() + dur
        r.number:SetText(tostring(math.ceil(dur)))
        r:SetScript("OnUpdate", function(self)
            local remain = self.expirationTime - GetTime()
            self.number:SetText(remain > 0 and tostring(math.ceil(remain)) or "0")
        end)
    elseif display.type == "bar" then
        r.label:SetText(display.text or "")
        r.bar.expirationTime = GetTime() + dur
        r.bar:SetMinMaxValues(0, dur)
        r.bar:SetValue(dur)
        r.bar:SetScript("OnUpdate", function(self)
            local remain = self.expirationTime - GetTime()
            self:SetValue(remain > 0 and remain or 0)
        end)
    elseif display.type == "circle" then
        r.icon:SetTexture(ResolveDisplayIconID(display) or 134400)
        r.label:SetText(display.text or "")
        r.swipe:SetCooldown(GetTime(), dur)
    end

    r:Show()
    RestackRegions(a)
    ns.PlayReminderSound(display)

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
    local a = GetAnchor(display.type)
    if a then
        a:SetFrameStrata("FULLSCREEN_DIALOG")
        a:SetFrameLevel(250)
    end
    ns.DisplayRaidReminder(entry)
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
