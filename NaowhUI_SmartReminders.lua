-------------------------------------------------------------------------------
--  NaowhUI_TankReminder.lua -- shows which defensive to press when Blizzard's encounter
--  timeline says a tank ability is about to land.
--
--  The core owns the DB and decides where this section renders: on NaowhUI_EUI's Gameplay
--  page when the companion is installed, on our own page under the NaowhUI group when it
--  is not. Nothing here needs to know which.
--
--  Both halves of this feature are secret on 12.1, and neither can be an `if`:
--
--    "is this a tank hit"  -- the TankRole bit of EncounterTimelineEventInfo.icons,
--                             secret for every Encounter-source event.
--    "is this spell ready" -- cooldown state, secret in instanced combat.
--
--  Comparing a secret, testing its truthiness, doing arithmetic on it or using it as a
--  table key all raise. So nothing in this file decides anything. Every decision is
--  handed to the engine and consumed as alpha:
--
--    * the tank gate rides C_EncounterTimeline.SetEventIconTextures, Blizzard's own
--      pixels-only substitute for the bit.band(icons, TankRole) that only untainted
--      code can do -- it sets alpha, never Shown, so geometry stays constant.
--    * the priority pick rides a chain of C_CurveUtil.EvaluateColorValueFromBoolean, which
--      is AllowedWhenTainted in ALL arguments and so composes: a secret may be both the
--      condition and a branch value, and the result goes straight into SetAlpha.
--
--  A slot frame's alpha (did this defensive win the priority pick) multiplies with its
--  icon texture's alpha (is this event a tank hit), so exactly one icon is visible and
--  only on a tank ability -- without either answer ever reaching Lua.
--
--  The tank gate only reaches TEXTURES. A FontString cannot carry it, which is why the
--  text channel is unavailable while the tank filter is on rather than silently firing
--  on every ability.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
-- enabled defaults off: until the user opts in, no events are registered and no frames
-- are built. Flat scalars only -- a nested default would hand out a live reference to
-- DEFAULTS itself. `disabled` and `lists` are created on demand for the same reason.
local DEFAULTS = {
    -- On by default FOR THE TEST BUILD, at the owner's request: the tester should
    -- install and see it work. Flip back to false before any public release; the house
    -- rule is that features ship opt-in.
    enabled   = true,
    showIcon  = true,
    showText  = false,
    showBar   = false,
    soundOn   = false,
    soundKey  = "none",
    inDungeons = true,
    inRaids    = true,
    fallbackOn = true,
    aggroOnly  = false,
    learnMode  = false,
    coveredSkip = true,  -- a defensive already active 5s+ suppresses the next callout  -- unknown bosses: quiet by default, call-everything when authoring
    leadTime   = 3,     -- seconds before impact that the alert fires
    voiceOn   = false,
    voiceNone = "Call for external",
    voiceVol  = 100,
    iconSize  = 64,
    -- 21 matches what the OLD derived formula (floor(iconSize * 0.34), floored at 12)
    -- produced at the default iconSize of 64, so a first read after this shipped changed
    -- nothing on screen for an existing install.
    textSize   = 21,
    -- pos = { point, relPoint, x, y } once moved in Unlock Mode; nil = default centre.
    -- textPos = same shape, for the text callout's own anchor.
}

local function TRDB()
    local root = ns.SettingsRoot()
    if type(root.tankReminder) ~= "table" then root.tankReminder = {} end
    local t = root.tankReminder
    -- One-way migration from the single flat list per spec this addon shipped with before
    -- presets existed: every existing list becomes that spec's "Default" preset, so nobody's
    -- configured priority order disappears the first time this loads.
    if type(t.lists) == "table" and next(t.lists) ~= nil and type(t.presets) ~= "table" then
        t.presets = {}
        t.activePreset = t.activePreset or {}
        for specKey, list in pairs(t.lists) do
            t.presets[specKey] = { p1 = { name = "Default", list = list } }
            t.activePreset[specKey] = "p1"
        end
        t.lists = nil
    end
    for k, v in pairs(DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

local function IsSpellDisabled(spellID)
    local d = TRDB().disabled
    return d ~= nil and d[spellID] == true
end

local function SetSpellDisabled(spellID, off)
    local t = TRDB()
    if off then
        if type(t.disabled) ~= "table" then t.disabled = {} end
        t.disabled[spellID] = true
    elseif type(t.disabled) == "table" then
        t.disabled[spellID] = nil
        if next(t.disabled) == nil then t.disabled = nil end
    end
end

-------------------------------------------------------------------------------
--  The priority list is the user's, per spec -- grouped into named presets
-------------------------------------------------------------------------------
-- This addon ships with NO ability data of its own -- no boss timers, no spell lists, no
-- encounter knowledge. It is an engine: the player builds the priority order themselves
-- (or imports one through an EllesmereUI profile string) and it drives whatever they put
-- in it. Everything it reacts to at runtime comes from Blizzard's own encounter timeline.
--
-- Per spec rather than global, because a priority order is only meaningful within one spec
-- and a tank who also heals should not rebuild it on every switch. Within a spec, a player
-- can keep more than one named list (an M+ set, a raid-CD set, ...) and switch which one is
-- active; only the active preset's list is "the" spec default anywhere else in this file.
-- profile.presets[specKey][presetKey] = { name = "...", list = { spellID, ... } }
-- profile.activePreset[specKey] = presetKey
local function PresetsTable(forSpec, create)
    local t = TRDB()
    if type(t.presets) ~= "table" then
        if not create then return nil end
        t.presets = {}
    end
    local key = tostring(forSpec or 0)
    if type(t.presets[key]) ~= "table" then
        if not create then return nil end
        t.presets[key] = {}
    end
    return t.presets[key]
end

-- Read-only: which preset is active for this spec, or nil if none exist yet.
local function ActivePresetKey(forSpec)
    local t = TRDB()
    local presets = PresetsTable(forSpec, false)
    if not presets then return nil end
    local key = tostring(forSpec or 0)
    local a = type(t.activePreset) == "table" and t.activePreset[key]
    if a and presets[a] then return a end
    -- The pointer is missing or points at a preset that got deleted: the first one that
    -- still exists becomes active, rather than the spec silently reading as unconfigured.
    a = next(presets)
    if a then
        if type(t.activePreset) ~= "table" then t.activePreset = {} end
        t.activePreset[key] = a
    end
    return a
end
ns.ActivePresetKey = ActivePresetKey

-- Same, but seeds an empty "Default" preset the first time this spec is touched at all, so
-- there is always something selected to add spells to.
local function EnsureActivePreset(forSpec)
    local a = ActivePresetKey(forSpec)
    if a then return a end
    local presets = PresetsTable(forSpec, true)
    presets.p1 = { name = "Default", list = {} }
    local t = TRDB()
    if type(t.activePreset) ~= "table" then t.activePreset = {} end
    t.activePreset[tostring(forSpec or 0)] = "p1"
    return "p1"
end

-- Every preset for this spec, name and key, in a stable creation-ish order (numerically by
-- key where the key is one of ours -- "p1", "p2", ... -- which sorts sensibly since they
-- are only ever appended, never renumbered).
function ns.ListPresets(forSpec)
    local presets = PresetsTable(forSpec, false)
    local out = {}
    if not presets then return out end
    for key, p in pairs(presets) do
        out[#out + 1] = { key = key, name = p.name or key }
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- Default name is "Preset N" for the lowest N not already in use, so deleting one and
-- adding another does not produce a duplicate label.
function ns.NextPresetName(forSpec)
    local presets = PresetsTable(forSpec, false)
    local used = {}
    if presets then
        for _, p in pairs(presets) do used[p.name] = true end
    end
    local n = 1
    while used["Preset " .. n] do n = n + 1 end
    return "Preset " .. n
end

function ns.AddPreset(forSpec, name)
    local presets = PresetsTable(forSpec, true)
    local n = 1
    while presets["p" .. n] do n = n + 1 end
    local key = "p" .. n
    presets[key] = { name = (name and name ~= "" and name) or ns.NextPresetName(forSpec),
                      list = {} }
    local t = TRDB()
    if type(t.activePreset) ~= "table" then t.activePreset = {} end
    t.activePreset[tostring(forSpec or 0)] = key
    return key
end

function ns.SelectPreset(forSpec, presetKey)
    local presets = PresetsTable(forSpec, false)
    if not (presets and presets[presetKey]) then return false end
    local t = TRDB()
    if type(t.activePreset) ~= "table" then t.activePreset = {} end
    t.activePreset[tostring(forSpec or 0)] = presetKey
    return true
end

function ns.RenamePreset(forSpec, presetKey, name)
    local presets = PresetsTable(forSpec, false)
    local p = presets and presets[presetKey]
    if not p then return false end
    p.name = (name and name ~= "") and name or p.name
    return true
end

-- Refuses to delete the last preset a spec has: EnsureActivePreset would just recreate an
-- empty "Default" preset a moment later, so the button would look like it did nothing.
function ns.DeletePreset(forSpec, presetKey)
    local presets = PresetsTable(forSpec, false)
    if not presets or not presets[presetKey] then return false end
    local count = 0
    for _ in pairs(presets) do count = count + 1 end
    if count <= 1 then return false end
    presets[presetKey] = nil
    local t = TRDB()
    local key = tostring(forSpec or 0)
    if type(t.activePreset) == "table" and t.activePreset[key] == presetKey then
        t.activePreset[key] = nil
    end
    ActivePresetKey(forSpec)   -- re-pick immediately so nothing reads as unconfigured
    return true
end

local function UserList(forSpec, create)
    local presetKey = create and EnsureActivePreset(forSpec) or ActivePresetKey(forSpec)
    if not presetKey then return nil end
    local presets = PresetsTable(forSpec, create)
    local p = presets and presets[presetKey]
    if not p then return nil end
    if type(p.list) ~= "table" then
        if not create then return nil end
        p.list = {}
    end
    return p.list
end

-- Per-boss overrides live beside the spec default, keyed spec:encounter. The key is the
-- dungeonEncounterID -- the same id ENCOUNTER_START reports and the same one the journal
-- hands back -- so what the tree sets up and what fires in the fight are the same record.
--
-- Fallback is deliberate and one level deep: an empty or absent boss list means "use my spec
-- default", so a tank sets their normal order once and only overrides the fights that need it.
local function BossKey(forSpec, encounterID)
    return tostring(forSpec or 0) .. ":" .. tostring(encounterID or 0)
end

local function BossList(forSpec, encounterID, create)
    local t = TRDB()
    if type(t.bossLists) ~= "table" then
        if not create then return nil end
        t.bossLists = {}
    end
    local key = BossKey(forSpec, encounterID)
    if type(t.bossLists[key]) ~= "table" then
        if not create then return nil end
        t.bossLists[key] = {}
    end
    return t.bossLists[key]
end

local function ClearBossList(forSpec, encounterID)
    local t = TRDB()
    if type(t.bossLists) ~= "table" then return end
    t.bossLists[BossKey(forSpec, encounterID)] = nil
    if next(t.bossLists) == nil then t.bossLists = nil end
end

-- Which preset a boss draws its defensives from -- a persistent, per-boss choice, not a
-- live mirror of the spec's active preset. nil means nothing was ever explicitly picked
-- for this boss, at which point the active preset applies by fallback (see EffectiveList).
local function BossPresetKey(forSpec, encounterID)
    local t = TRDB()
    local bp = type(t.bossPreset) == "table" and t.bossPreset[BossKey(forSpec, encounterID)]
    local presets = PresetsTable(forSpec, false)
    if bp and presets and presets[bp] then return bp end
    return nil
end
ns.BossPresetKey = BossPresetKey

local function SetBossPreset(forSpec, encounterID, presetKey)
    local t = TRDB()
    if type(t.bossPreset) ~= "table" then t.bossPreset = {} end
    t.bossPreset[BossKey(forSpec, encounterID)] = presetKey
end
ns.SetBossPreset = SetBossPreset

local function ListIndexOf(list, spellID)
    for i = 1, #list do
        if list[i] == spellID then return i end
    end
    return nil
end

-- Spoken line per spell. Defaults to "Use <name>"; the point of storing an override is that
-- "Use Incarnation: Guardian of Ursoc" is not what anyone says out loud.
local function CalloutFor(spellID, spellName)
    local c = TRDB().callouts
    local custom = c and c[spellID]
    if type(custom) == "string" and custom ~= "" then return custom end
    -- The name alone. The "Use " prefix was cut on tester feedback: in a fight the extra
    -- word is latency, and nobody hearing "Shield Wall" wonders what to do with it.
    return spellName or ""
end

local function SetCallout(spellID, text)
    local t = TRDB()
    if type(text) == "string" and text ~= "" then
        if type(t.callouts) ~= "table" then t.callouts = {} end
        t.callouts[spellID] = text
    elseif type(t.callouts) == "table" then
        t.callouts[spellID] = nil
        if next(t.callouts) == nil then t.callouts = nil end
    end
end

-- The encounter we are actually in, from ENCOUNTER_START. Plain: encounter ids are not
-- secret. nil outside a boss fight, which is what makes the spec default apply everywhere else.
local currentEncounter

-- The list that actually drives the alert: this boss's override when it has one, otherwise
-- the spec default.
-- Three layers, most specific first: this ability's own list (composite key
-- "encounter#fingerprint", from the older per-ability editor -- still honored for anyone
-- who has one saved, though nothing writes new ones since the boss modal moved to picking
-- a whole preset per boss instead), then the boss's chosen preset, then the spec default.
local function EffectiveList(forSpec, encounterID, fp)
    if encounterID and fp then
        local al = BossList(forSpec, tostring(encounterID) .. "#" .. fp, false)
        if al and #al > 0 then return al, true end
        -- The old UI keyed per-ability lists by NAME too, since one ability can own several
        -- fingerprints; that form stays honored for older saves.
        local nm = ns.EventNameFor and ns.EventNameFor(encounterID, fp)
        if nm and nm ~= fp then
            local anl = BossList(forSpec, tostring(encounterID) .. "#" .. nm, false)
            if anl and #anl > 0 then return anl, true end
        end
    end
    if encounterID then
        local explicit = BossPresetKey(forSpec, encounterID)
        local presetKey = explicit or ActivePresetKey(forSpec)
        if presetKey then
            local presets = PresetsTable(forSpec, false)
            local p = presets and presets[presetKey]
            if p and type(p.list) == "table" and #p.list > 0 then
                return p.list, explicit ~= nil
            end
        end
    end
    return UserList(forSpec, false), false
end

-- Cap on built slots, and on how long a list the options page will accept. Nothing reads a
-- secret to size this, and it must not: slot count, creation and layout are all driven by
-- the saved list and talent state, which stay plain.
local MAX_SLOTS = 8

-------------------------------------------------------------------------------
--  Capability gate
-------------------------------------------------------------------------------
-- Probed once rather than assumed. Every one of these is load-bearing, and on a client
-- missing any of them the feature stays inert instead of erroring per boss ability.
local canSelect, canGate, canSound, canBar

local function ProbeCapabilities()
    canSelect = (C_CurveUtil ~= nil and C_CurveUtil.EvaluateColorValueFromBoolean ~= nil
        and C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil)

    canGate = (C_EncounterTimeline ~= nil and C_EncounterTimeline.SetEventIconTextures ~= nil
        and Enum ~= nil and Enum.EncounterEventIconmask ~= nil
        and Enum.EncounterEventIconmask.TankRole ~= nil)

    canSound = (C_EncounterEvents ~= nil and C_EncounterEvents.SetEventSound ~= nil
        and C_EncounterEvents.GetEventList ~= nil and C_EncounterEvents.GetEventInfo ~= nil
        and Enum ~= nil and Enum.EncounterEventSoundTrigger ~= nil)

    canBar = (C_EncounterTimeline ~= nil and C_EncounterTimeline.GetEventTimer ~= nil)
end

-- The feature exists on this client at all. This is the ONLY availability check that may
-- gate event registration.
--
-- IsFeatureEnabled() must never be used for that: it folds in the player's CVars, and the
-- events keep firing when those are off. A popular boss-mod addon ships with
-- encounterTimelineEnabled forced to "0" and the timeline frame reparented away, and then
-- drives its own bars from these very events -- so gating on IsFeatureEnabled would break
-- this addon for that entire userbase while the data was flowing the whole time.
local function TimelineAvailable()
    return C_EncounterTimeline ~= nil
        and C_EncounterTimeline.IsFeatureAvailable ~= nil
        and C_EncounterTimeline.IsFeatureAvailable()
end

-- The master switch, which is a different thing from the timeline's own display toggle.
-- We never write either one: two boss-mod addons already fight over the display CVar every
-- pull, and a third writer would just make that worse. Detect, tell the user once, move on.
-- Reported by the diagnostic command, never acted on. The CVar gates Blizzard's own
-- timeline frame and nothing else: with it at 0 the events still arrive and a registered
-- sound still plays, both measured on a live boss. Worth SHOWING when reading a bug
-- report, worth never warning about.
local function TimelineDisplayOff()
    return C_CVar ~= nil and C_CVar.GetCVarBool ~= nil
        and C_CVar.GetCVarBool("encounterTimelineEnabled") == false
end

local function CombatWarningsOff()
    return C_CVar ~= nil and C_CVar.GetCVarBool ~= nil
        and C_CVar.GetCVarBool("combatWarningsEnabled") == false
end

-------------------------------------------------------------------------------
--  Can we legally NAME the defensive out loud?
-------------------------------------------------------------------------------
-- Every visual channel dodges the secret by handing the question to the engine and taking
-- back pixels. A spoken line cannot: choosing which line to speak IS a Lua branch on
-- readiness, and no sound or speech API accepts a secret in the argument that would select
-- it. (C_VoiceChat.SpeakText does accept a secret string, but nothing hands us a
-- pre-selected secret spell NAME, so that opening leads nowhere.)
--
-- So the callout is only lawful when the spell's cooldown is not classified. The predicate
-- below returns a PLAIN boolean and is safe to branch on -- Blizzard's own code does the
-- same shape in Blizzard_AuraContainerUtil.
--
-- Realistically that means out of combat, because SecretWhenCooldownsRestricted engages on
-- combat, encounter, challenge mode OR pvp match -- which is precisely when a defensive
-- callout is wanted. The one way it survives combat is a spell carrying the data-side
-- NeverSecret flag, which overrides restrictions. Whether any real defensive is flagged that
-- way is game data, not something the client source can answer: /nutank secrecy measures it.
--
-- Note HasSecretRestrictions() is NOT the check. It reports whether this client BUILD has
-- the system compiled in, not whether restrictions are live, so it is constant true on
-- retail and gates nothing.
local function CanNameSpellAloud(spellID)
    if not (C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret) then return false end
    local ok, secret = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
    return ok and secret == false
end

local function IsSpellAvailable(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        if C_SpellBook.IsSpellKnownOrInSpellBook(spellID) then return true end
    end
    return IsPlayerSpell ~= nil and IsPlayerSpell(spellID) == true
end

-------------------------------------------------------------------------------
--  Spec and role
-------------------------------------------------------------------------------
-- One call answers both, and `role` is why this beats reading the spec ID alone:
-- UnitGroupRolesAssigned returns "NONE" for an ungrouped player, so it cannot gate a
-- feature that has to work while soloing a dummy.
local specID, isTank = 0, false

local function RefreshSpec()
    specID, isTank = 0, false
    if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then return end
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then return end
    local id, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(index)
    specID = id or 0
    isTank = (role == "TANK")
end

-------------------------------------------------------------------------------
--  The display
-------------------------------------------------------------------------------
local Reminder = {}
local frame, slots = nil, {}
-- The text callout's own frame -- separate from the icon so the two can be dragged to
-- different parts of the screen. slot.label stays PARENTED to its slot (nothing here
-- touches ApplyPriorityAlpha's secret-driven alpha cascade, which slot.label still rides
-- unchanged); only the anchor TARGET moves to textFrame. Parent and anchor target are
-- independent in the frame API, which is what makes this safe to decouple at all.
local textFrame
local bar
local activeSlots = 0           -- how many slots the current spec actually uses
local hideTimer

local function ApplyPosition()
    if not frame then return end
    local p = TRDB().pos
    frame:ClearAllPoints()
    if p then
        frame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
end

-- Defaults to the SAME spot as the icon so an existing install looks identical until the
-- text is actually dragged elsewhere in Unlock Mode.
local function ApplyTextPosition()
    if not textFrame then return end
    local p = TRDB().textPos
    textFrame:ClearAllPoints()
    if p then
        textFrame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        textFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
end

-- The suite's own media, resolved through SharedMedia so the paths live in one place and
-- locale variants (the Asia font files) resolve themselves. Everything degrades: no media
-- addon means the companion font, then the client default.
local function NaowhMedia(kind, name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local ok, path = pcall(LSM.Fetch, LSM, kind, name, true)
    return ok and path or nil
end

local function AlertFont()
    local path = NaowhMedia("font", "Naowh")
    if path then return path end
    local EUI = _G.EllesmereUI
    path = EUI and EUI.GetFontPath and EUI.GetFontPath("extras")
    return path or STANDARD_TEXT_FONT
end

-- Display only, never clickable. Alpha 0 hides the art but NOT hit-testing, so a losing
-- slot left mouse-enabled would still be a live mouse target sitting over the screen.
local function CreateSlot(index)
    local slot = CreateFrame("Frame", nil, frame)
    slot:SetPoint("TOP")                -- every slot stacks on the same spot: one wins, the
    slot:EnableMouse(false)             -- rest sit at alpha 0 behind it
    slot:SetAlpha(0)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints()
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local T = ns.THEME

    -- The spoken callout, written instead of said: "Use Barkskin". It stays PARENTED to the
    -- slot, so the priority alpha that picks the winning icon still picks the winning line
    -- too -- one stacked font string per spell, engine-revealed, no branch. That is why the
    -- text can name the defensive in combat while the spoken version cannot. Only the ANCHOR
    -- target moves to textFrame, which the frame API allows independent of parentage, so the
    -- text can sit anywhere on screen without touching the secret-driven alpha at all.
    --
    -- A FontString still cannot carry the tank gate (that rides textures only), which is the
    -- separate reason this channel is offered only while the tank filter is off.
    slot.label = slot:CreateFontString(nil, "OVERLAY")
    slot.label:SetPoint("TOP", textFrame, "BOTTOM", 0, -4)
    slot.label:SetFont(AlertFont(), 16, "OUTLINE")
    slot.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    slot.label:Hide()

    slots[index] = slot
    return slot
end

-- One bar for the whole alert, not one per slot: it counts down the incoming ability, which
-- is the same fact whichever defensive wins. Built from textures throughout so the tank gate
-- can reach every part of it.
local function CreateBar()
    if bar then return bar end
    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOP", frame, "BOTTOM", 0, -26)
    bar:SetHeight(10)
    bar:EnableMouse(false)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture(NaowhMedia("statusbar", "NaowhGradient")
        or "Interface\\TargetingFrame\\UI-StatusBar")
    bar.fill = bar:GetStatusBarTexture()
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    local T = ns.THEME
    bar.bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 0.9)
    if bar.fill then bar.fill:SetVertexColor(T.gold.r, T.gold.g, T.gold.b, 1) end
    bar:Hide()
    return bar
end

function Reminder.Create()
    if frame then return frame end

    frame = CreateFrame("Frame", "NaowhUITankReminder", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()

    -- Independently positioned from the icon (Unlock Mode moves the two separately); a
    -- fixed nominal size is all it needs since nothing draws on textFrame itself, only on
    -- the font strings anchored to it.
    textFrame = CreateFrame("Frame", "NaowhUITankReminderText", UIParent)
    textFrame:SetSize(240, 10)
    textFrame:SetFrameStrata("HIGH")
    textFrame:SetClampedToScreen(true)
    textFrame:EnableMouse(false)
    textFrame:Hide()

    -- "Call for external". This one is not per-spell, so it sits on the container and takes
    -- the accumulator LEFT OVER after the priority walk: that value is 1 only when nobody
    -- won, which is exactly "nothing on your list is up". The engine works it out; we never
    -- learn it.
    -- The authored reminder line sits ABOVE textFrame; the defensive callout text (built in
    -- CreateSlot, anchored to textFrame too) lives below it, so the two never fight. Plain
    -- data only: fingerprints and authored text.
    frame.reminder = textFrame:CreateFontString(nil, "OVERLAY")
    frame.reminder:SetPoint("BOTTOM", textFrame, "TOP", 0, 6)
    frame.reminder:SetFont(AlertFont(), 15, "OUTLINE")
    frame.reminder:SetTextColor(1, 1, 1, 1)
    frame.reminder:Hide()

    frame.fallback = textFrame:CreateFontString(nil, "OVERLAY")
    frame.fallback:SetPoint("TOP", textFrame, "BOTTOM", 0, -4)
    frame.fallback:SetFont(AlertFont(), 16, "OUTLINE")
    local T = ns.THEME
    frame.fallback:SetTextColor(T.goldSoft.r, T.goldSoft.g, T.goldSoft.b, 1)
    frame.fallback:SetAlpha(0)
    frame.fallback:Hide()

    -- Call Out Unknown Bosses changes what every uncovered boss does -- quiet becomes
    -- call-everything -- and shipped with no on-screen sign it was active at all. Twice
    -- now, a callout that looked like wrong data was actually just this switch left on
    -- from an earlier authoring session. The tag rides the text callout; the border rides
    -- the icon -- between the two, whichever one someone's eyes are on says so.
    frame.learnTag = textFrame:CreateFontString(nil, "OVERLAY")
    frame.learnTag:SetPoint("BOTTOM", frame.reminder, "TOP", 0, 4)
    frame.learnTag:SetFont(AlertFont(), 12, "OUTLINE")
    frame.learnTag:SetTextColor(1, 0.65, 0.2, 1)
    frame.learnTag:SetText("AUTHORING MODE -- CALLING EVERY ABILITY")
    frame.learnTag:Hide()
    frame.learnBorder = ns.Border(frame, { r = 1, g = 0.65, b = 0.2 }, 1)
    if frame.learnBorder and frame.learnBorder._frame then frame.learnBorder._frame:Hide() end

    -- A spec with no list never reaches RebuildSlots, and a zero-sized frame is one Unlock
    -- Mode cannot pick up, so position it now regardless.
    ApplyPosition()
    ApplyTextPosition()
    return frame
end

local function ApplySize()
    if not frame then return end
    local t = TRDB()
    local size = t.iconSize or DEFAULTS.iconSize
    -- Independent of icon size: this used to be derived from it (floor(size * 0.34)), which
    -- was the whole reason moving the icon and text apart still left them stuck at the same
    -- size as each other.
    local fontSize = t.textSize or DEFAULTS.textSize
    local textOn = t.showText
    frame:SetSize(size, size)
    for i = 1, #slots do
        slots[i]:SetSize(size, size)
        slots[i].label:SetFont(AlertFont(), fontSize, "OUTLINE")
        slots[i].label:SetShown(textOn)
        slots[i].icon:SetShown(t.showIcon)
    end
    if frame.fallback then
        frame.fallback:SetFont(AlertFont(), fontSize, "OUTLINE")
        frame.fallback:SetText(t.voiceNone or "")
        frame.fallback:SetShown(textOn and t.fallbackOn ~= false)
    end
    if bar then bar:SetWidth(math.max(size * 2, 120)) end
end

-------------------------------------------------------------------------------
--  Rebuilding the slot list
-------------------------------------------------------------------------------
-- Talent state is plain, so everything here -- which spells qualify, how many slots exist,
-- what icon each carries -- is decided in the clear and never mid-fight. The secret half
-- only ever touches alpha.
local function RebuildSlots(fp)
    activeSlots = 0
    if not frame then return end

    local list = EffectiveList(specID, currentEncounter, fp)
    -- No list for this spec yet: seed one from the same detection the picker uses, so the
    -- addon works out of the box and what appears in the options is a REAL saved list the
    -- player can reorder or prune, not an invisible default they cannot see. Tester
    -- feedback: nobody should have to build a list before the addon does anything.
    if (not list or #list == 0) and ns.SeedDefaultList then
        local seeded = ns.SeedDefaultList(specID)
        if seeded and #seeded > 0 then list = seeded end
    end
    if not list then
        for i = 1, #slots do slots[i]:SetAlpha(0) end
        return
    end

    for i = 1, #list do
        local spellID = list[i]
        if activeSlots < MAX_SLOTS and IsSpellAvailable(spellID) and not IsSpellDisabled(spellID) then
            activeSlots = activeSlots + 1
            local slot = slots[activeSlots] or CreateSlot(activeSlots)
            slot.spellID = spellID
            -- GetSpellInfo returns nothing for a spell the client has not cached, which is
            -- the normal case right after someone types an ID in. GetSpellTexture answers from
            -- a different path and usually has it; the question mark is the last resort.
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            local iconID = info and info.iconID
            if not iconID and C_Spell and C_Spell.GetSpellTexture then
                local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
                if ok then iconID = tex end
            end
            slot.iconID = iconID or 134400
            slot.icon:SetTexture(slot.iconID)
            -- Same string the spoken callout uses, so editing it once changes both.
            slot.label:SetText(CalloutFor(spellID, info and info.name))
        end
    end

    -- Unused slots keep existing but never light up. Rebuilding on talent change rather
    -- than releasing them keeps frame creation off the combat path entirely.
    for i = 1, #slots do
        slots[i]:SetAlpha(0)
    end
    ApplySize()
end

-------------------------------------------------------------------------------
--  The priority pick
-------------------------------------------------------------------------------
-- N-way exclusive select with no branch on a secret anywhere.
--
--   ready     -- a possibly-secret boolean, never inspected
--   eligible  -- "nobody above me has won yet"; plain 1 on the first pass, secret after
--
-- SetAlpha(ev(ready, eligible, 0)) lights this slot only when it is ready AND still
-- eligible, and the accumulator then closes the door for everyone below. The evaluator is
-- AllowedWhenTainted in every argument, which is what makes the secret `eligible` legal as a
-- branch value. EllesmereUI already chains these two deep for the nameplate kick tick; this
-- is the same primitive generalised to N.
--
-- The loop runs for EVERY slot on every pass, with no break and no early return: Blizzard's
-- own comment in EncounterTimelineTemplates warns that skipping setters leaks the secret
-- through the call count.
-- Defined further down alongside chargeState; forward-declared so ApplyPriorityAlpha can
-- close over them.
local EnsureChargeState, ChargesAvailable

local function ApplyPriorityAlpha()
    local ev = C_CurveUtil.EvaluateColorValueFromBoolean
    local eligible = 1

    for i = 1, activeSlots do
        local slot = slots[i]

        -- Charges first, mirroring SpeakCallout below: holding 1 of 2 charges leaves a
        -- recharge timer ACTIVE, so GetSpellCooldownDuration reads it as running even
        -- though the spell is castable right now. Without this the icon lost the pick to
        -- the next slot down while the voice, which already special-cased charges,
        -- correctly called the held one -- a callout with the wrong icon lit.
        EnsureChargeState(slot.spellID)
        local charges = ChargesAvailable(slot.spellID)
        local dur = (not charges) and C_Spell.GetSpellCooldownDuration(slot.spellID, true) or nil
        -- ignoreGCD=true is load-bearing. It defaults to FALSE, and the returned duration
        -- then covers the global cooldown -- so mid-fight, with a GCD running almost
        -- constantly, every defensive reported as unavailable and no icon ever appeared.
        --
        -- A duration object is a PLAIN handle wrapping secret state (unlike GetSpellCooldown,
        -- which is flagged SecretWhenCooldownsRestricted), so testing the handle and its
        -- method is legal. Calling IsZero() is what produces the secret.

        if charges then
            -- Tracked from the player's own casts, so this is plain even in restricted
            -- content: no engine evaluator needed for this branch.
            local ready = charges > 0
            slot:SetAlpha(ready and eligible or 0)
            if ready then eligible = 0 end
        elseif dur and dur.IsZero then
            local ready = dur:IsZero()
            -- SetAlpha with an engine-evaluated value rather than SetAlphaFromBoolean: the
            -- latter documents its alpha default as 255, so its scale is ambiguous, and this
            -- is the form EllesmereUI already ships for secret-driven alpha.
            slot:SetAlpha(ev(ready, eligible, 0))
            eligible = ev(ready, 0, eligible)
        else
            -- The API is MayReturnNothing and returns the ACTIVE cooldown, so a spell that is
            -- READY hands back nothing at all. Treating that as unknown was why a defensive
            -- sitting off cooldown never won the pick and everything fell through to the
            -- fallback line. Nil-ness is plain, so branching on it is legal.
            slot:SetAlpha(eligible)
            eligible = 0
        end
    end

    -- Whatever eligibility survived the walk IS "nobody was ready", so the fallback line
    -- needs no extra check of its own. Set unconditionally, like every other slot: a
    -- conditional setter here would leak the answer through the call count.
    -- Switched off means never shown, so the alpha is forced rather than left to the
    -- accumulator.
    if frame and frame.fallback then
        if TRDB().fallbackOn == false then
            frame.fallback:SetAlpha(0)
        else
            frame.fallback:SetAlpha(eligible)
        end
    end
end

-------------------------------------------------------------------------------
--  The tank gate
-------------------------------------------------------------------------------
-- SetEventIconTextures assigns atlases and alpha to the textures it is handed, from the
-- event's secret icon mask. Passing a mask of only TankRole means a non-tank event leaves
-- the texture at alpha 0 -- the answer arrives as pixels and is never readable.
--
-- One call per texture, each with a single-texture array, rather than one call with all of
-- them: Blizzard passes fewer textures than its mask has bits and the fill order is not
-- documented, so a shared array would leave textures 2..N at the mercy of an unspecified
-- assignment rule. One bit, one texture, no ordering to get wrong.
--
-- SetTexture afterwards puts our own art back over whatever atlas the engine assigned. It
-- is AllowedWhenTainted and touches the Texture aspect, not Alpha, so the gate survives.
-- The tex coords have to go back too: an atlas carries its own and they outlive the swap.
local function GateTexture(eventID, tex, restore)
    if not tex then return end
    C_EncounterTimeline.SetEventIconTextures(eventID, Enum.EncounterEventIconmask.TankRole, { tex })
    if restore then restore(tex) end
end

-- Is this live event a boss ability, rather than a respawn timer or another addon's
-- bar? `source` is NeverSecret on EncounterTimelineEventInfo, so reading it alone is
-- legal even while the rest of the struct is sealed, and the comparison is plain.
--
-- Only ADDED carries the struct; HIGHLIGHT delivers a bare id. GetEventInfo is asked
-- again here rather than caching, because this fires a handful of times per pull and a
-- cache is another thing to invalidate.
-- Source and base duration, captured when the event is ADDED and keyed by its id.
--
-- This has to be a cache. ADDED carries the whole struct; HIGHLIGHT carries a bare id and
-- nothing else, and asking GetEventInfo again at highlight time is not reliable -- when it
-- comes back empty the check below FAILS OPEN and every script event is treated as a boss
-- ability. That is how a respawn timer, or another addon's bar, calls for a defensive while
-- the boss is doing nothing but meleeing.
--
-- Both fields are NeverSecret on the struct, so this stays plain even though the event
-- itself is flagged SecretWhenEncounterEvent. Duration is kept because it is the only plain
-- handle on WHICH ability an event is, and any future filtering by ability has to ride it.
local eventSource, eventDuration = {}, {}

-- Which event ids have already produced a full show/speak pass. Blizzard's own timeline
-- view re-triggers ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT more than once per event with no
-- dedup of its own (OnEventHighlight just replays the glow every time; harmless for a
-- glow, not for a spoken callout), so without this an ability with a long lead time could
-- get announced repeatedly while still the same single cast.
local announced = {}

local function NoteEventAdded(info)
    if type(info) ~= "table" then return end
    pcall(function()
        local id = info.id
        if id == nil then return end
        eventSource[id] = info.source
        eventDuration[id] = info.duration
    end)
end

-- Alerts waiting for their moment: the engine announces about five seconds out, and the
-- player-chosen lead is usually shorter, so the show is scheduled rather than immediate.
-- Every path that kills an event must kill its pending alert too, or a boss that dies in
-- the gap gets a callout over its corpse.
local pendingShow = {}

local function CancelPendingShow(eventID)
    local t = pendingShow[eventID]
    if t then
        t:Cancel()
        pendingShow[eventID] = nil
    end
end

local function ForgetEvent(eventID)
    if eventID == nil then return end
    CancelPendingShow(eventID)
    eventSource[eventID] = nil
    eventDuration[eventID] = nil
    announced[eventID] = nil
end

local function WipeEventCache()
    for id in pairs(pendingShow) do
        local t = pendingShow[id]
        if t then t:Cancel() end
    end
    wipe(pendingShow)
    wipe(eventSource)
    wipe(eventDuration)
    wipe(announced)
end

local function IsEncounterSourced(eventID)
    local encounter = Enum and Enum.EncounterTimelineEventSource
        and Enum.EncounterTimelineEventSource.Encounter or 0

    -- What ADDED told us, which is the only reading taken while the struct was actually in
    -- hand. Nothing else can contradict it.
    local cached = eventSource[eventID]
    if cached ~= nil then return cached == encounter end

    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventInfo) then return true end

    local ok, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
    if not ok or type(info) ~= "table" then return true end

    local got, source = pcall(function() return info.source end)
    if not got or source == nil then return true end

    return source == encounter
end

-- Per-ability muting, keyed by base duration.
--
-- Measured on a live boss: spellID and icons come back SECRET on every event, so neither
-- Blizzard's tank flag nor a curated spell list can name a live ability. `duration` is
-- NeverSecret and differs between abilities in the same fight (8.0 and 25.0 on the same
-- boss), which makes it the only thing a per-ability filter can key on.
--
-- It is a fingerprint, not an identity: it says "this is the same ability as that one", never
-- which ability it is. That is enough to mute the one that does not need a defensive, and it
-- keeps working in keys, where identity never will.
--
-- Scoped per encounter because durations collide freely across different bosses.
-- The encounter is remembered alongside the fingerprint: a player usually types the command
-- right after the kill or the wipe, and by then ENCOUNTER_END has already cleared
-- currentEncounter, which would file the entry under the wrong boss.
local lastFingerprint, lastFingerprintEncounter
local lastUnknownNotice

-- Every fingerprint this fight that was seen and skipped as unmarked, and whether anything
-- was announced at all. Read once at ENCOUNTER_END; see the report there. Latched per
-- encounter because plenty of bosses have no tank hit at all by design -- Hoardmonger and
-- Sentinel of Winter among them -- and those would otherwise report every single kill.
local silencedFingerprints = {}
local calloutsThisFight = 0
local noCalloutNotice = {}

-- For attributing a boss cast back to the timeline event that announced it, and for
-- detecting when that attribution would be ambiguous. Written by ShowForEvent, read by the
-- cast watcher below it.
local lastFingerprintAt, prevFingerprintAt = 0, 0
local lastCalloutAt = 0

-- What the cast probe has established about this content, for the trace: "unseen" until a
-- boss casts, then "plain" or "secret". This is the whole question of whether automation
-- is possible here, so it is worth a word in every report.
local castIdentity = "unseen"
local cleuIdentity = "unseen"

local function FingerprintFor(eventID)
    local d = eventDuration[eventID]
    if type(d) ~= "number" then return nil end
    return string.format("%.1f", d)
end

-- Both per-boss sets share one shape: profile.<field>[encounterID][fingerprint] = true.
local function PerBossSet(field, create, enc)
    local t = TRDB()
    if type(t[field]) ~= "table" then
        if not create then return nil end
        t[field] = {}
    end
    local key = tostring(enc or 0)
    if type(t[field][key]) ~= "table" then
        if not create then return nil end
        t[field][key] = {}
    end
    return t[field][key]
end

local function MutedTable(create, enc)
    return PerBossSet("muted", create, enc)
end

-- Boss-scoped custom reminders, independent of the timeline-fingerprint system: each one
-- carries its own trigger (pull, a spell cast/aura) rather than riding an existing marked
-- ability. profile.customReminders[encounterID][uid] = { name, preset, trigger = {...}, dur }.
-- `preset` names a spec preset to pick from at fire time; older entries carry a `msg` string
-- instead and still display it verbatim.
local function CustomRemindersTable(create, enc)
    return PerBossSet("customReminders", create, enc)
end

-- The tank-buster allowlist. A blocklist was tried first and pointed the wrong way: a pull
-- carries far more non-tank events than tank ones (8-20 measured), so the player was being
-- asked to mute the many to keep the few. Marking is the same fingerprint data used in the
-- right direction -- name the two that matter, silence the rest at once.
--
-- Empty means "not configured", not "block everything": a boss with no marks calls out every
-- ability, exactly as before, so the feature works out of the box and gets sharper per boss
-- as marks are added.
local function MarksTable(create, enc)
    return PerBossSet("tankMarks", create, enc)
end

-- Authored reminder text per boss ability: profile.reminders[encounterID][fingerprint].
-- This is the phase-two content layer -- what a curator writes on an ability ("swap after
-- this one", "stack for the barrage") -- shown and spoken alongside the defensive pick.
local function RemindersTable(create, enc)
    return PerBossSet("reminders", create, enc)
end

-- One ability can own several fingerprints (a late-cast variant is a second duration of
-- the same spell), and the UI configures by ABILITY. So reminder state is keyed by the
-- ability's name, with fingerprint keys still honored for anything saved before the
-- grouping existed. The raw entry can be true (custom mode, no text yet) or a string.
local function ReminderEntry(enc, fp)
    if not (enc and fp) then return nil end
    local r = RemindersTable(false, enc)
    if not r then return nil end
    local v = r[fp]
    if v == nil then
        local nm = EventNameFor(enc, fp)
        if nm and nm ~= fp then v = r[nm] end
    end
    return v
end
ns.ReminderEntry = ReminderEntry

local function ReminderFor(enc, fp)
    local v = ReminderEntry(enc, fp)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- The ability's display name, from authored data; the raw fingerprint as the fallback so
-- an uncovered event is still addressable in the editor.
local function EventNameFor(enc, fp)
    if not (enc and fp) then return nil end
    local names = ns.EVENT_NAMES and ns.EVENT_NAMES[enc]
    return (names and names[fp]) or fp
end
ns.EventNameFor = EventNameFor
ns.RemindersTable = RemindersTable
ns.MarksTable = MarksTable
ns.MutedTable = MutedTable
ns.CustomRemindersTable = CustomRemindersTable

local function IsMutedEvent(eventID)
    local fp = FingerprintFor(eventID)
    if not fp then return false end
    local m = MutedTable(false, currentEncounter)
    return m ~= nil and m[fp] == true
end

-- Does any live boss consider ME its problem? For two-tank raids: the buster lands on
-- whoever has the boss, and the other tank does not need to burn a cooldown for it.
--
-- Threat status first (>= 2 means tanking), the boss's literal target second -- threat
-- survives the momentary retargets a boss does mid-cast, the target check catches fixates
-- that never touch the threat table. The two reads are gated by DIFFERENT restrictions
-- (SecretWhenUnitThreatStateRestricted / SecretWhenUnitComparisonRestricted), so one being
-- secret says nothing about the other -- a Mythic+ co-tank report of getting alerted with
-- "Only Alert When Tanking" on is consistent with threat state reading secret there while
-- the target comparison stays plain, and bailing out on the first secret read (the old
-- code did) never even tried the second. Both are checked independently now; only "both
-- secret" counts as unknown. An unknown still fails OPEN: a spare callout costs a moment
-- of attention, a suppressed one on the actual tank costs a death. No boss units at all
-- also fails open, for the same reason.
local function TankingSomeBoss()
    local sawBoss, unknown = false, false
    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) then
            sawBoss = true
            local ok, verdict = pcall(function()
                local status = UnitThreatSituation("player", unit)
                local statusKnown = not (issecretvalue and issecretvalue(status))
                if statusKnown and type(status) == "number" and status >= 2 then return true end

                local same = UnitIsUnit(unit .. "target", "player")
                local sameKnown = not (issecretvalue and issecretvalue(same))
                if sameKnown and same == true then return true end

                if statusKnown and sameKnown then return false end
                return nil
            end)
            if ok and verdict == true then return true end
            if not ok or verdict == nil then unknown = true end
        end
    end
    if not sawBoss or unknown then return true end
    return false
end

-- Is one of the listed defensives ALREADY active with meaningful time left? A tank who
-- just pressed Shield Wall does not need "Demoralizing Shout" shouted over it -- the next
-- callout can wait for the next buster. Own buffs are the one aura set the client answers
-- most freely, but every read is still guarded and every unknown fails OPEN: a redundant
-- callout costs a shrug, a suppressed one on an uncovered tank costs a death.
local COVERED_MIN_REMAINING = 5

local function CoveredByActiveDefensive()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    local now = GetTime()
    for i = 1, activeSlots do
        local sid = slots[i].spellID
        local ok, remaining = pcall(function()
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
            if type(aura) ~= "table" then return nil end
            local exp = aura.expirationTime
            if issecretvalue and issecretvalue(exp) then return nil end
            if type(exp) ~= "number" then return nil end
            -- A zero expiration is an aura with no clock; a defensive that does not
            -- expire on its own counts as covering.
            if exp == 0 then return COVERED_MIN_REMAINING end
            return exp - now
        end)
        if ok and remaining and remaining >= COVERED_MIN_REMAINING then return true end
    end
    return false
end

-- Shipped fingerprints for this encounter, or nil. Read per event rather than captured:
-- the data file is optional and the feature must work identically without it.
local function ShippedMarks(enc)
    local d = ns.TANK_FINGERPRINTS
    if not d or enc == nil then return nil end
    -- Both key shapes: the file uses numbers, but nothing guarantees what type the event
    -- handed us, and a silent type mismatch here disables the whole filter.
    return d[enc] or d[tonumber(enc)] or d[tostring(enc)]
end
-- Exported HERE, below the definition: an export wrapper placed above it resolved
-- ShippedMarks as a nil global inside the closure, and the boss window died on it.
ns.ShippedMarksFor = function(enc) return ShippedMarks(enc) end

-- The filter players actually experience: shipped data covers the boss out of the box, and
-- a player's own marks UNION with it rather than replacing it, so marking stays available
-- as the authoring tool and as the escape hatch for a boss the data has not covered yet.
--
-- An event with NO fingerprint fails OPEN when marks exist. That happens when the ADDED was
-- missed (a reload mid-fight), and staying silent on what might be the tank buster is the
-- worse mistake -- an extra callout costs annoyance, a missing one costs a death. A wrong
-- SHIPPED mark is recoverable in game: the mute check runs after this one.
local function IsUnmarkedEvent(eventID)
    local player = MarksTable(false, currentEncounter)
    if player ~= nil and next(player) == nil then player = nil end
    local shipped = ShippedMarks(currentEncounter)
    if player == nil and shipped == nil then return false end

    local fp = FingerprintFor(eventID)
    if not fp then return false end
    -- Exact first, whole-second second. Some community modules author their durations
    -- rounded to integers, so a live 17.4 must still find a shipped "17.0". The tolerant
    -- form only ever WIDENS what counts as marked -- it can admit a near-miss ability,
    -- never silence a marked one -- which is the right direction to be wrong in.
    local rounded
    local n = tonumber(fp)
    if n then rounded = string.format("%.1f", math.floor(n + 0.5)) end
    local function marked(t)
        if t == nil then return false end
        if t[fp] == true then return true end
        return rounded ~= nil and t[rounded] == true
    end
    if marked(player) or marked(shipped) then return false end
    return true
end

local function ApplyTankGate(eventID)
    for i = 1, activeSlots do
        local slot = slots[i]

        -- Cleared FIRST. The engine paints the alpha of textures whose bit is set and
        -- leaves the others alone, so an icon lit by a tank buster stayed lit through the
        -- next cast that was not one. Starting from hidden means an event that does not
        -- match simply never turns it on.
        slot.icon:SetAlpha(0)

        GateTexture(eventID, slot.icon, function(tex)
            tex:SetTexture(slot.iconID)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end)
    end
    if bar and bar:IsShown() then
        local T = ns.THEME
        GateTexture(eventID, bar.fill, function(tex) tex:SetVertexColor(T.gold.r, T.gold.g, T.gold.b, 1) end)
        GateTexture(eventID, bar.bg, function(tex) tex:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 0.9) end)
    end
end

-- Fallback, and the shipped behaviour when the user turns the tank filter off: every
-- timeline event counts, so the art carries no gate and the priority pick alone decides.
local function ClearTankGate()
    for i = 1, activeSlots do
        slots[i].icon:SetAlpha(1)
    end
    if bar then
        if bar.fill then bar.fill:SetAlpha(1) end
        if bar.bg then bar.bg:SetAlpha(1) end
    end
end

-------------------------------------------------------------------------------
--  Sound
-------------------------------------------------------------------------------
-- Sound is an ACTION, not a visual channel: there is no way to play one at alpha 0 and let
-- the engine decide, and no sound API anywhere accepts a secret argument. So the alpha trick
-- cannot carry it.
--
-- What CAN: C_EncounterEvents.SetEventSound registers a file against a static
-- encounterEventID, and the client plays it when that event highlights. The static records
-- (unlike the live timeline ones) carry NO secrecy at all, so their TankRole bit reads in the
-- clear and we can register against exactly the tank-flagged abilities.
--
-- The limit this leaves, and it is worth being honest about in the UI: the sound knows the
-- ability is a tank hit, but nothing can make it know whether YOUR defensive is ready. That
-- half is secret and there is no operator that joins the two. Sound says when; the icon and
-- bar say whether.
local soundRegistered = false
local soundError               -- surfaced on the options page; silence is the worst outcome

local function ResolveSoundFile()
    local key = TRDB().soundKey
    if not key or key == "none" then return nil end
    local EUI = _G.EllesmereUI
    local paths = EUI and EUI._groupDeathSoundPaths
    local value = paths and paths[key]
    -- SetEventSound wants a file asset. A SoundKitID (LSM hands out either) is not one, so
    -- a numeric entry is skipped rather than passed through and silently ignored.
    if type(value) == "string" then return value end
    return nil
end

-- Chunked: GetEventList is the whole encounter-event database, not the current pull, and
-- registering it in one pass is a login hitch nobody asked for.
-- MEASURED on a live boss, and worth recording because it cost five rounds of chasing
-- to establish: the engine plays a registered sound AT MOST ONCE PER ENCOUNTER.
--
-- It is not a registration problem. After a fight where the same ability cast twice and
-- sounded once, GetEventSound still returned our file for every sampled event, both casts
-- had highlighted, and re-registering between them -- including clearing before setting --
-- changed nothing. The engine simply will not replay it.
--
-- So this channel is a once-per-fight cue, not a per-cast one, and the tooltip says so.
-- The ICON is unaffected: SetEventIconTextures paints every time, which is why the icon
-- is the reliable per-cast signal and the sound is not.
--
-- Anything wanting a repeating, filtered, NAMED callout cannot be built on this API at
-- all. That needs the ability identified in Lua, and the only route to that is recording
-- a fight and matching on the plain ordinal and base duration.
local function RegisterEventSounds()
    soundError = nil
    if not TRDB().soundOn then return end
    if not canSound then
        soundError = "This client does not support per-ability sounds."
        return
    end

    -- There used to be a warning here that a registered sound will not play while
    -- encounterTimelineEnabled is 0. It has been removed because it is MEASURED FALSE:
    -- on a live boss with that CVar at 0, a registered sound played and the timeline
    -- events kept arriving throughout. The CVar gates Blizzard's own frame and nothing
    -- else.
    --
    -- It was also stale by construction. soundError is only recomputed when registration
    -- re-runs, so once shown it stayed on the page after the player turned the CVar on,
    -- which is how it came to be reported as wrong twice over.
    --
    -- The real limit of this channel is that the engine plays a registered sound at most
    -- once per encounter, and that is on the option's own tooltip where it belongs.

    local file = ResolveSoundFile()
    if not file then
        soundError = soundError or "Pick a sound file. Built-in game sounds cannot be used here."
        return
    end

    local ids = C_EncounterEvents.GetEventList()
    if not ids then
        soundError = "No encounter ability data available yet."
        return
    end

    local trigger = Enum.EncounterEventSoundTrigger.OnTimelineEventHighlight
    local mask = Enum.EncounterEventIconmask.TankRole

    -- Read here rather than captured at load: the data file is optional, and the feature
    -- has to work identically when it is absent.
    local curatedTank = ns.TANK_ABILITIES
    local sound = { file = file, volume = 1 }
    local i, total = 1, #ids

    local function Step()
        local stop = math.min(i + 199, total)
        while i <= stop do
            local info = C_EncounterEvents.GetEventInfo(ids[i])

            -- Blizzard's bit OR our own list. Measured against a live 870-event
            -- catalogue, the bit alone carries 13 of the 23 tank busters this season's
            -- pool has in that catalogue, so on its own it is correctly silent on nearly
            -- half of them -- which from the player's chair is indistinguishable from
            -- the feature being broken.
            --
            -- Additive deliberately: an ability neither source knows about is still
            -- handled the moment Blizzard flags it, with no update to this addon.
            local flagged = info and info.icons and bit.band(info.icons, mask) ~= 0
            local curated = info and info.spellID and curatedTank
                and curatedTank[info.spellID] ~= nil

            if flagged or curated then
                pcall(C_EncounterEvents.SetEventSound, ids[i], trigger, sound)
            end
            i = i + 1
        end
        if i <= total then C_Timer.After(0, Step) end
    end

    soundRegistered = true
    Step()
end

-------------------------------------------------------------------------------
--  Self-tracked cooldowns (what lets the voice work in combat)
-------------------------------------------------------------------------------
-- The API's answer to "is this ready" is sealed in combat, but our OWN casts are not:
-- cast queries only go secret for units other than the player or their pet. So this watches
-- the player's UNIT_SPELLCAST_SUCCEEDED, writes down GetTime() + cooldown, and the voice
-- pick branches on numbers the addon wrote itself -- plain Lua, legal anywhere.
--
-- Three layers keep it honest, each covering what the previous cannot:
--   1. LEARNED totals. Base cooldowns do not include static talent reductions, so whenever a
--      cast happens while this spell's cooldown is readable, the real total is recorded (per
--      profile) and used instead of the base from then on -- including later, inside a key.
--   2. The PLAIN nil signal. Whether the API returns a duration object at all is not sealed,
--      only what is inside one -- and no object means no active cooldown. Every
--      SPELL_UPDATE_COOLDOWN re-checks it, so spender-driven reduction (the kind no table
--      can predict) corrects the model the moment a spell actually comes back.
--   3. Full resync whenever cooldowns are readable (out of combat; between raid pulls).
local readyAt = {}          -- [list spellID] = GetTime() at which it is back up

-------------------------------------------------------------------------------
--  Charges
-------------------------------------------------------------------------------
-- Real cooldowns for spells GetSpellBaseCooldown misreports, in seconds. Both models read
-- this: the plain-cooldown estimate treats it as the cooldown, and a charge spell treats it
-- as the per-charge recharge, which is what the tooltip figure means on a charge spell.
--
-- Only ever measured or authoritative numbers here, never a scaled guess -- the whole point
-- is to bypass an API that is not merely imprecise. It reports 0 for Divine Shield and 8
-- SECONDS for Guardian of Ancient Kings, whose real cooldown is three minutes; used as a
-- recharge rate that handed back a charge every 8 seconds and called the spell all fight.
--
-- Declared HERE, above the charge code rather than beside the cooldown model that used to
-- own it: a local declared later in the file is not an upvalue to a function defined
-- earlier, so referencing it from EnsureChargeState would have read a nil global and
-- silently done nothing.
local KNOWN_BASE_COOLDOWN = {
    [642] = 300,      -- Divine Shield
    [86659] = 180,    -- Guardian of Ancient Kings
}

-- GetSpellCooldownDuration describes the COOLDOWN. A charge spell is gated by its
-- RECHARGE, which is a separate clock, and the two disagree in both directions:
--
--   * Holding 1 of 2 charges, a recharge IS running, so the cooldown accessor hands
--     back an object and the spell reads as unavailable while it is perfectly castable.
--   * At ZERO charges the spell cooldown is not running at all, so the accessor can hand
--     back nothing and the spell reads as ready when it is empty.
--
-- SpellChargeInfo marks exactly two fields NeverSecret, and they are the whole solution:
--   maxCharges -- is this a charge spell, and how many
--   isActive   -- FALSE means not recharging, which means AT MAXIMUM
--
-- currentCharges is NOT among them, so the count is never readable in a key and is
-- tracked from the player's own casts, which are always plain. `isActive` going false is
-- then a free correction back to full.
local chargeState = {}

-- Third return is whether the read is trustworthy at all -- false means the API call or
-- the field read itself failed (missing API, a thrown pcall), as opposed to a valid read
-- that CONFIRMS max < 2. The distinction matters to the caller: a spell that genuinely
-- lost its second charge (a talent swap) should wipe the tracked count, but a spell that
-- simply could not be read THIS one time must not -- see EnsureChargeState.
local function ReadChargeShape(sid)
    if not (C_Spell and C_Spell.GetSpellCharges) then return nil, nil, false end

    local ok, info = pcall(C_Spell.GetSpellCharges, sid)
    if not ok or type(info) ~= "table" then return nil, nil, false end

    -- The two plain fields are read behind their own pcall. The rest of this struct is
    -- secret in restricted content and a wrong field raises rather than returning nil.
    local got, max, active = pcall(function() return info.maxCharges, info.isActive end)
    if not got then return nil, nil, false end
    if type(max) ~= "number" or max < 2 then return nil, nil, true end

    return max, active == true, true
end

function EnsureChargeState(sid)
    local max, active, ok = ReadChargeShape(sid)
    if not ok then
        -- The read itself failed -- keep whatever is already tracked rather than guessing.
        -- Wiping here on a single dropped read was the bug: the very next successful read
        -- re-establishes a FRESH state at full charges, so a spell that had just spent its
        -- last charge would read as ready again the moment one read hiccuped.
        return chargeState[sid]
    end
    if not max then
        -- A confirmed read says this is not (or is no longer) a charge spell.
        chargeState[sid] = nil
        return nil
    end

    local st = chargeState[sid]
    if not st or st.max ~= max then
        -- MEASURED: GetSpellBaseCooldown reports 8 seconds for Guardian of Ancient Kings,
        -- whose real cooldown is five minutes. Used as a recharge rate that regenerates a
        -- charge every 8 seconds, so spending both charges put the model back at full
        -- inside twenty seconds and it called the spell for the rest of the pull. The
        -- number is not merely imprecise here, it is wrong by a factor of forty, and it is
        -- the ONLY input that can invent a charge the player does not have. So it is not
        -- used for charge spells at all: either the recharge has been measured from a
        -- readable cooldown, or there is no climb.
        local t = TRDB()
        local learned = type(t.learned) == "table" and t.learned[tostring(sid)] or nil
        st = {
            -- currentCharges is secret, so a spell seen for the first time cannot be read
            -- directly -- but isActive (a charge recharging right now) is plain, and it was
            -- being discarded here. Assuming a full stack regardless was the bug: a spell
            -- already on cooldown before this pull, or before the addon got a chance to see
            -- it, kept reading as fully charged for the rest of the session.
            --
            -- isActive only says "at least one charge missing," never how many. Guessing
            -- max-1 was tried and is still wrong whenever more than one is actually missing
            -- -- still a false ready, just a smaller one. Zero is the only guess with no way
            -- to be an overcount: the recharge math below counts back up from there on its
            -- own, so an undercount here costs a few seconds of silence instead of a false
            -- callout for a defensive still on cooldown.
            max = max, count = active and 0 or max, tick = GetTime(),
            -- Whether that count is a GUESS from isActive rather than something we watched
            -- happen. It matters because with no measured recharge there is nothing to
            -- climb back on, so a pessimistic guess would otherwise stand for the rest of
            -- the run -- which is how a held Guardian of Ancient Kings lost the pick to
            -- "call for external" on Xathuux. Cleared the moment a real cast is witnessed
            -- or the stack reads full, after which the count is tracked, not assumed.
            guessed = active or nil,
            -- Zero means no climb at all, which is a complete answer rather than a
            -- degraded one: the count still falls on every witnessed cast, and
            -- ChargesAvailable still snaps it back to full the moment isActive reports
            -- nothing recharging. What is lost is only the middle of the stack -- holding
            -- 1 of 2 reads as 0 until the last charge lands -- and that is silence about a
            -- spell that is up, never a call for one that is down.
            recharge = learned or KNOWN_BASE_COOLDOWN[sid] or 0,
        }
        chargeState[sid] = st
    end
    return st
end

function ChargesAvailable(sid)
    local st = chargeState[sid]
    if not st then return nil end

    local max, active = ReadChargeShape(sid)
    if max and not active then
        -- Back to full, and if exactly one charge was out this is a free MEASUREMENT of
        -- the recharge: the gap between the cast that broke the stack and the moment the
        -- engine stopped reporting a recharge IS the per-charge time. Plain signals only,
        -- so unlike reading the cooldown it works in restricted content, which is the only
        -- place this matters. Restricted to the one-charge case on purpose -- with two out
        -- the elapsed time covers two recharges and our own count is the thing in doubt.
        if st.recharge <= 0 and st.missingSince and st.count == st.max - 1 then
            local measured = GetTime() - st.missingSince
            if measured > 1.5 then
                st.recharge = measured
                local t = TRDB()
                if type(t.learned) ~= "table" then t.learned = {} end
                t.learned[tostring(sid)] = measured
            end
        end
        st.count, st.tick, st.missingSince, st.guessed = st.max, GetTime(), nil, nil
        return st.count
    end

    if st.recharge > 0 and st.count < st.max then
        local gained = math.floor((GetTime() - st.tick) / st.recharge)
        if gained > 0 then
            st.count = math.min(st.max, st.count + gained)
            st.tick  = st.tick + gained * st.recharge
        end
    end

    -- A guessed count with no recharge to climb on cannot recover, so it must not be the
    -- pessimistic end of what isActive actually proved. isActive says at least one charge
    -- is out -- on the two-charge defensives this list carries, the other one is up. Report
    -- that instead of zero until a cast is actually witnessed, at which point the count is
    -- tracked and this stops applying. Zero remains correct for a stack we WATCHED empty.
    if st.guessed and st.recharge <= 0 and st.count < st.max - 1 then
        st.count = st.max - 1
    end

    -- isActive is plain and exact, and it was only ever read in the one direction above.
    -- Read the other way it is a hard ceiling: something is recharging, so the stack CANNOT
    -- be full, whatever the model believes. Catches an over-count from any source -- a
    -- missed cast, a stale learned recharge, a talent swap mid-fight -- not just the base
    -- cooldown that produced this one.
    if active and st.count >= st.max then
        st.count = st.max - 1
    end
    return st.count
end
local castToBase = {}       -- cast-time override id -> the id the list stores

local function RebuildCastMap()
    wipe(castToBase)
    for i = 1, activeSlots do
        local sid = slots[i].spellID
        castToBase[sid] = sid
        if C_Spell and C_Spell.GetOverrideSpell then
            local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
            if ok and ov and ov ~= sid then castToBase[ov] = sid end
        end
    end
end

local function NoteOwnCast(castSpellID)
    local sid = castSpellID and castToBase[castSpellID]
    if not sid then return end

    -- A charge spell never touches readyAt: a cast spends a charge, and holding one is
    -- what makes it available, not the absence of a timer. Established here too, not only
    -- from ResyncModel/ApplyPriorityAlpha: a charge spell's very first cast of a session,
    -- before either of those has run for it yet, would otherwise fall through to the
    -- readyAt/base-cooldown model below and get tracked by the wrong clock entirely.
    EnsureChargeState(sid)
    local st = chargeState[sid]
    if st then
        ChargesAvailable(sid)
        -- The recharge clock starts on the drop FROM maximum. Restarting it on every
        -- cast would push the next charge further away each time one was spent.
        -- missingSince marks the same moment for the measurement in ChargesAvailable:
        -- this cast is what put the stack below full, so the run back up starts here.
        if st.count >= st.max then
            st.tick = GetTime()
            st.missingSince = GetTime()
        end
        st.count = math.max(0, st.count - 1)
        -- Watched, not assumed, from here on.
        st.guessed = nil
        return
    end

    -- Learned beats base: a previously observed real total already includes every static
    -- talent reduction, which the base number never does.
    local t = TRDB()
    local learned = type(t.learned) == "table" and t.learned[tostring(sid)] or nil
    local baseMs = GetSpellBaseCooldown and GetSpellBaseCooldown(sid)
    -- A cast whose length we cannot determine STILL put the spell on cooldown. Leaving
    -- readyAt untouched left it reading as available forever, so a defensive that had
    -- just been pressed kept being called for: GetSpellBaseCooldown reports 0 for plenty
    -- of spells whose cooldown comes from a talent or an aura, and Divine Shield is one.
    --
    -- The placeholder only has to be wrong in the safe direction. ResyncModel clears it
    -- the moment the cooldown object disappears, so an over-long guess costs nothing and
    -- an absent one costs a wrong callout.
    local UNKNOWN_COOLDOWN = 30

    local secs
    if learned then
        secs = learned
    elseif KNOWN_BASE_COOLDOWN[sid] then
        secs = KNOWN_BASE_COOLDOWN[sid]
    elseif type(baseMs) == "number" and baseMs > 0 then
        -- An UPPER bound, not a measurement. GetSpellBaseCooldown ignores talent cooldown
        -- reduction -- Unbreakable Spirit alone takes 30% off Ardent Defender and Divine
        -- Shield -- and it appears nowhere in Blizzard's current UI source or generated
        -- docs, so nothing keeps it honest. Held at full length while cooldowns are sealed
        -- it cannot self-correct (see ResyncSpell: the free correction needs a nil the API
        -- almost never returns), so it keeps a defensive marked down long after it is back
        -- and the callout falls through to "call for external" with two defensives up.
        -- Trimmed by the largest common tank reduction so the residual error lands on the
        -- side this file already documents as the cheaper one -- naming a defensive that
        -- turns out to be down beats staying silent when one was available. A learned
        -- total, once measured, replaces this outright.
        secs = (baseMs / 1000) * 0.7
    else
        secs = UNKNOWN_COOLDOWN
    end
    readyAt[sid] = GetTime() + secs

    -- And when the cooldown this cast just started is readable, record its real total for
    -- every future cast -- the learning half of layer 1 above. The 1.5s floor keeps a
    -- GCD-length reading from ever overwriting a real cooldown.
    if CanNameSpellAloud(sid) then
        local ok, total = pcall(function()
            local dur = C_Spell.GetSpellCooldownDuration(sid, true)
            return (dur and dur.GetTotalDuration and dur:GetTotalDuration()) or nil
        end)
        if ok and type(total) == "number" and total > 1.5 then
            if type(t.learned) ~= "table" then t.learned = {} end
            t.learned[tostring(sid)] = total
            readyAt[sid] = GetTime() + total
        end
    end
end

local function ResyncSpell(sid)
    -- Re-read the shape every pass. A talent swap can add or remove charges, and a
    -- stale shape is what makes the model confidently wrong rather than absent.
    EnsureChargeState(sid)

    -- Everything below is the plain-cooldown model, which says nothing useful about
    -- a charge spell: it holds a running recharge while still being castable.
    local cs = chargeState[sid]
    if cs then
        -- One thing here IS worth reading for a charge spell. Its running cooldown, when
        -- it reads plainly, is the real recharge time, and the count climbs back up off
        -- that figure -- so a base-derived guess that is too short resurrects charges the
        -- player never got back. Learned into the same store the cooldown model uses, so
        -- it survives the reload that wipes chargeState.
        if CanNameSpellAloud(sid) then
            local ok, total = pcall(function()
                local dur = C_Spell.GetSpellCooldownDuration(sid, true)
                return (dur and dur.GetTotalDuration and dur:GetTotalDuration()) or nil
            end)
            if ok and type(total) == "number" and total > 1.5 then
                cs.recharge = total
                local t = TRDB()
                if type(t.learned) ~= "table" then t.learned = {} end
                t.learned[tostring(sid)] = total
            end
        end
        return
    end

    -- Free correction, available even in restricted content: no duration object means no
    -- active cooldown, so whatever the estimate believed is wrong and the spell is up.
    -- This is what keeps the model from drifting through a fight as talent and resource
    -- cooldown reductions shorten things it thinks are still running.
    local live = C_Spell.GetSpellCooldownDuration(sid, true)
    if not live then readyAt[sid] = 0 end

    -- Only while the predicate says this spell's cooldown reads plainly; the pcall is
    -- belt and braces against the classification changing under us mid-read.
    if CanNameSpellAloud(sid) then
        local ok, rem, total = pcall(function()
            local dur = C_Spell.GetSpellCooldownDuration(sid, true)
            -- Nothing back means nothing running, so zero remaining.
            if not dur or not dur.GetRemainingDuration then return 0 end
            return dur:GetRemainingDuration() or 0,
                (dur.GetTotalDuration and dur:GetTotalDuration()) or nil
        end)
        if ok and type(rem) == "number" then
            readyAt[sid] = GetTime() + math.max(0, rem)
        end

        -- A cooldown still running while this reads plainly IS the real total, talent
        -- reductions and all. Captured here and not only at cast time: the cast almost
        -- always happens inside an instance where this is sealed, while the tail of that
        -- same cooldown is usually still running once the player is back outside, which
        -- makes this a free measurement of a number the estimate can only guess at.
        -- The 1.5s floor keeps a GCD-length reading from overwriting a real cooldown.
        if ok and type(total) == "number" and total > 1.5 then
            local t = TRDB()
            if type(t.learned) ~= "table" then t.learned = {} end
            t.learned[tostring(sid)] = total
        end
    end
end

local function ResyncModel()
    for i = 1, activeSlots do
        ResyncSpell(slots[i].spellID)
    end
end

-- Is this spell castable right now? Shared by the voice pick and by preset-bound custom
-- reminders, deliberately in one place: a second copy of this ladder drifting out of step
-- with the first is precisely the class of bug this file keeps producing.
--
-- MEASURED, after getting this wrong three times. Write down what is actually true so the
-- next attempt does not relitigate it:
--
--   * GetSpellCooldownDuration returns an OBJECT for a READY spell too. It is IsZero() that
--     separates ready from running. Testing `== nil` instead was tried on a live boss and
--     every defensive lost the pick, every pull, so the player heard "call for external"
--     while Ardent Defender sat off cooldown. Nil comes back rarely, so nil-ness is a
--     usable READY signal but never a usable NOT-READY one.
--   * IsZero() returns a secret ONLY while cooldowns are restricted. CanNameSpellAloud is
--     exactly that question, so branching on IsZero behind that predicate is legal. An
--     earlier pass here removed it as an illegal secret branch; that was wrong, and removing
--     it is what broke the pick.
--   * Sealed and unwitnessed is genuinely unknowable. Defaulting to READY is the right
--     direction: at a pull start every defensive is up, and naming one that turns out to be
--     down costs less than staying silent when one was available.
--
-- May raise on the IsZero branch if the classification changes mid-read, so every caller
-- runs it inside a pcall.
-- Is this spell's cooldown actually running? Blizzard's own definition, lifted from
-- CooldownViewer: isOnActualCooldown = not isOnGCD and cooldownIsActive. Both fields are
-- flagged NeverSecret on SpellCooldownInfo, so unlike IsZero() this ANSWERS in restricted
-- content -- which removes the reason the voice was dead reckoning off readyAt for a whole
-- dungeon, and with it every way that estimate could drift out of step with the icon.
--
-- Operand order is Blizzard's, not incidental: the GCD test is the clean one and
-- short-circuits, which is how their code stays legal. Written the other way round the
-- same expression can raise.
--
-- Returns nil, not a guess, when the client cannot answer -- callers fall back to the
-- older ladder rather than treating "no answer" as ready.
local function CooldownRunning(sid)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, running = pcall(function()
        local info = C_Spell.GetSpellCooldown(sid)
        if type(info) ~= "table" then return nil end
        return (not info.isOnGCD) and info.isActive
    end)
    if not ok or type(running) ~= "boolean" then return nil end
    return running
end

local function SpellReady(sid, now)
    local charges = ChargesAvailable(sid)
    if charges then return charges > 0 end

    -- The real answer first, whenever the client gives one. Everything below is what this
    -- addon had to do before it turned out one was available.
    local running = CooldownRunning(sid)
    if running ~= nil then return not running end

    local dur = C_Spell.GetSpellCooldownDuration(sid, true)
    if not dur then return true end
    if CanNameSpellAloud(sid) then
        return dur.IsZero and dur:IsZero() and true or false
    end
    return (readyAt[sid] or 0) <= now
end

-------------------------------------------------------------------------------
--  Spoken callouts
-------------------------------------------------------------------------------
-- The one channel that has to branch in Lua, and therefore the one that only works while
-- the cooldowns it reads are unclassified. See CanNameSpellAloud for why.
--
-- The whole list is checked first and the walk is abandoned unless EVERY entry is readable.
-- A partial read would silently skip the sealed entries and name a lower-priority defensive
-- as though the better one were down, which is worse than saying nothing.
local function Speak(text)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) or not text or text == "" then return end
    -- The generated docs give (voiceID, text, rate, volume, overlap), but EllesmereUI carries
    -- a field note that the live client treats the third argument as a destination that must
    -- be 1. Passing 1 satisfies both readings -- it is a valid rate and the required
    -- destination -- so this matches their proven call rather than the docs alone.
    -- Only `text` may carry a secret; every other argument is NeverSecret, and ours are plain.
    pcall(C_VoiceChat.SpeakText, 0, text, 1, TRDB().voiceVol or 100, true)
end

-- The single place a callout becomes audible, so the sound-or-speech choice is made once
-- rather than at each of the call sites below.
local function Announce(spellID, text)
    local key = ns.SoundFor(spellID)
    if key then
        local EUI = _G.EllesmereUI
        local paths = EUI and EUI._groupDeathSoundPaths
        local value = paths and paths[key]
        if value and EUI._PlayLSMSound then
            EUI._PlayLSMSound(value)
            return
        end
        -- The chosen file is gone (a SharedMedia pack removed, say). Speaking is better than
        -- silence, since the callout still has its words.
    end
    Speak(text)
end

-- A second timeline event landing while the first is still fresh and picking the SAME
-- defensive says nothing new -- the player was already told to press it. Multi-unit fights
-- (several adds each telegraphing the same tank buster within a handful of seconds of each
-- other) hit this constantly. A DIFFERENT pick still announces normally: that genuinely is
-- new information (the first choice went on cooldown, say).
--
-- 5 seconds (the alert's own display window) measured too short on a live pull -- repeats
-- of the same ability landed up to ~10s apart and still announced twice. 12s covers that
-- with a little room, while staying well short of any real defensive's own cooldown, so a
-- genuinely later need for the same one is never the thing being suppressed.
local SUPPRESS_REPEAT_WINDOW = 12
local lastAnnouncedSpellID, lastAnnouncedAt = nil, 0

local function SpeakCallout()
    local t = TRDB()
    if not t.voiceOn or activeSlots == 0 then return end

    -- NOTE: the tank filter cannot reach audio -- the engine applies it to artwork only. So
    -- with that filter on, the voice speaks for every timeline ability while the icon shows
    -- only tank ones. That is stated in the option's tooltip. Suppressing the voice instead
    -- was tried and was worse: the feature simply went silent with no indication why.

    -- The model is the last rung of the ladder below, for spells whose cooldown is sealed
    -- and whose cast we have not witnessed. Resync first so it is current.
    ResyncModel()
    local now = GetTime()

    -- The winner is chosen inside a pcall so that a throw cannot swallow the fallback.
    -- That failure mode has already been seen once here: an error mid-loop skipped the
    -- fallback line at the end, and the symptom was not an error message but SILENCE
    -- exactly when the player most needed to be told nobody was up. A pick that errors
    -- must degrade to "call for external", never to nothing.
    local ok, picked = pcall(function()
        for i = 1, activeSlots do
            local sid = slots[i].spellID
            if SpellReady(sid, now) then return sid end
        end
    end)

    -- On failure pcall's second return is the error STRING, which is truthy and would be
    -- announced as though it were the winning spell.
    -- A thrown pick degrades to the fallback, which is right, but it must not do so
    -- SILENTLY: "call for external" then looks identical to a genuine no-defensive-up and
    -- hides the throw completely. Reported through the same guarded stringify used
    -- elsewhere, because a secret-carrying error raises again on tostring.
    if not ok then
        local why = picked
        if issecretvalue and issecretvalue(why) then
            why = "the error itself carries a secret"
        end
        ns.Print("|cffff6060pick failed|r, using the fallback: " .. tostring(why))
        picked = nil
    end

    if picked then
        -- A muted winner means silence, not the next one down: the player deliberately
        -- turned this entry's audio off and still wants it to win the pick.
        if not ns.IsAudioOff(picked) then
            if picked == lastAnnouncedSpellID and (now - lastAnnouncedAt) < SUPPRESS_REPEAT_WINDOW then
                return
            end
            lastAnnouncedSpellID, lastAnnouncedAt = picked, now
            local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(picked)
            Announce(picked, CalloutFor(picked, info and info.name))
        end
        return
    end

    if t.fallbackOn ~= false and not ns.IsAudioOff(0) then Announce(0, t.voiceNone) end
end

-------------------------------------------------------------------------------
--  Showing and hiding
-------------------------------------------------------------------------------
-- Visibility is driven by plain data only -- the event ID and a timer. It must never ride
-- a secret: SetShown is AllowedWhenUntainted and would error, and hiding on a secret would
-- leak the answer through frame state. A non-tank event still SHOWS this frame; everything
-- inside it just sits at alpha 0.
-- /nutank trace arms a one-shot report on the next timeline event. Printed rather than
-- guessed at: this path runs mid-fight where nothing can be inspected by hand.
-- A COUNT, not a one-shot. Arming for a single event meant every report described the
-- first ability of the pull, which is almost never the tank buster being investigated.
-- Narrowing it to tank events instead is not possible: that classification arrives as a
-- secret icon mask, so Lua cannot ask "was this one a tank hit" at all. Covering the next
-- several events is the only way to be sure the interesting one is in the report.
local TRACE_EVENTS = 5
local traceLeft = 0

-- Bumped whenever this readout changes. Printed in the header so a report answers "is the
-- current code even loaded" outright, instead of us inferring it from which lines are
-- missing, which cost a pull to get wrong.
local TRACE_BUILD = "0820k"

-- Never tostring an error straight into a message. When a secret value is what raised, the
-- error object carries one, and tostring() on it raises in turn -- OUTSIDE the guard that
-- caught the original. That is how a report can vanish completely and silently: the row
-- throws, printing the row's failure throws, printing THAT failure throws, and the whole
-- thing unwinds out of the event handler with nothing on screen and nothing in the log.
-- Reduces a possibly-secret value to a string that is always safe to display.
--
-- The guard that matters is issecretvalue(), not pcall. tostring() on a secret does NOT
-- raise: it hands back a SECRET STRING, and secretness then rides through string.format
-- and .. all the way to the display call, which silently drops the line. No error, nothing
-- in the log, just a missing line. Four builds of this diagnostic went missing that way
-- before the cause was found, each time looking like the code had not loaded.
--
-- issecretvalue() answers a PLAIN boolean about a value without reading it, which is why
-- branching on it is legal where branching on the value is not. Blizzard's own Dump and
-- EventTrace pick their formatting the same way.
--
-- The callback returns a RAW value. Formatting happens here, after the check, so no caller
-- can reintroduce the bug by coercing early.
local function Safe(fn, fmt)
    local ok, v = pcall(fn)
    if not ok then return "|cffff6060refused|r" end
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "|cffF0A830secret|r" end
    return fmt and string.format(fmt, v) or tostring(v)
end

local function ErrText(err)
    if issecretvalue and issecretvalue(err) then
        return "unreadable (the error itself carries a secret)"
    end
    local ok, text = pcall(function() return tostring(err) end)
    return ok and text or "unreadable"
end

local function TraceEvent(eventID)
    traceLeft = math.max(0, traceLeft - 1)
    local t = TRDB()
    ns.Print(("|cffF0A830trace %d/%d|r build=%s event=%s slots=%d voice=%s icon=%s text=%s")
        :format(TRACE_EVENTS - traceLeft, TRACE_EVENTS,
                TRACE_BUILD, tostring(eventID), activeSlots, tostring(t.voiceOn),
                tostring(t.showIcon), tostring(t.showText)))

    -- SpeakCallout already ran for this event by the time this prints (see ShowForEvent's
    -- call order), so this is the actual pick, not a guess -- and whether the repeat
    -- suppressor (SUPPRESS_REPEAT_WINDOW) is why nothing was heard.
    if lastAnnouncedSpellID then
        local sinceInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(lastAnnouncedSpellID)
        ns.Print(("  last announced: %s (%s), %.1fs ago%s"):format(
            (sinceInfo and sinceInfo.name) or "?", tostring(lastAnnouncedSpellID),
            GetTime() - lastAnnouncedAt,
            (GetTime() - lastAnnouncedAt < SUPPRESS_REPEAT_WINDOW)
                and "  |cff8a99b5(a repeat of this one would be suppressed)|r" or ""))
    end

    -- WHICH list built these slots. A per-boss override silently replaces the spec order,
    -- so "it called them in the wrong order" and "it is using a different list than the one
    -- I edited" look identical from the outside. Naming the source separates them.
    local _, fromBoss = EffectiveList(specID, currentEncounter)
    ns.Print(("  list=%s encounter=%s"):format(
        fromBoss and "|cffF0A830per-boss override|r" or "spec default",
        tostring(currentEncounter or "none")))

    -- Is this event's IDENTITY readable? Everything about filtering text and voice to tank
    -- abilities turns on this one answer. spellID and icons carry no NeverSecret annotation,
    -- so they are plain OUTSIDE restricted content and sealed inside it. If they read here,
    -- fingerprints can be learned automatically wherever identity is available and applied
    -- by duration where it is not, and nobody has to record anything by hand.
    -- castID is the cast-probe verdict: whether THE BOSS'S CAST BAR names its spell
    -- plainly here. "plain" means learning and callouts are fully automatic in this
    -- content; "secret" means shipped fingerprints are the only route; "unseen" means no
    -- boss has cast since login.
    ns.Print(("  identity: spellID=%s icons=%s duration=%s source=%s cachedDur=%s castID=%s"):format(
        Safe(function() return C_EncounterTimeline.GetEventInfo(eventID).spellID end),
        Safe(function() return C_EncounterTimeline.GetEventInfo(eventID).icons end),
        Safe(function() return C_EncounterTimeline.GetEventInfo(eventID).duration end, "%.1f"),
        Safe(function() return C_EncounterTimeline.GetEventInfo(eventID).source end),
        Safe(function() return eventDuration[eventID] end, "%.1f"),
        castIdentity))
    ns.Print(("  identity channels: castbar=%s combatlog=%s restricted=%s"):format(
        castIdentity, cleuIdentity,
        Safe(function()
            if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
                return tostring(C_CombatLog.IsCombatLogRestricted())
            end
            return "no probe"
        end)))

    -- Whether the authored data is loaded AT ALL. The fingerprints file is the newest in
    -- the TOC, and a /reload does not pick up new files -- only a full client launch reads
    -- the list. An unloaded file and an unmatched fingerprint produce identical symptoms,
    -- and only this line can tell them apart.
    if not ns.TANK_FINGERPRINTS then
        ns.Print("  shipped data: |cffff6060table absent|r")
    else
        local m = ShippedMarks(currentEncounter)
        local n = 0
        if m then for _ in pairs(m) do n = n + 1 end end
        ns.Print(("  shipped data: loaded, %d fingerprint(s) for this boss"):format(n))
    end

    if activeSlots == 0 then
        ns.Print("  |cffff6060no slots built|r -- nothing on your list is talented, or the list is empty.")
        return
    end

    -- The display side, so "picked correctly but nothing on screen" is answerable without
    -- another round trip.
    --
    -- Every read of a value the engine may have made secret formats INSIDE its own pcall.
    -- The guard used to wrap only the read, on the theory that reading a driven alpha would
    -- refuse. It does not refuse: it hands back a secret VALUE quite happily, and it is
    -- tostring/string.format that throw. Guarding the read and coercing outside the guard
    -- therefore caught nothing, and this whole report died at its first slot -- which, since
    -- the trace runs ahead of the callout, took the callout down with it.
    if frame then
        ns.Print(("  frame shown=%s alpha=%s size=%dx%d"):format(
            tostring(frame:IsShown()),
            Safe(function() return frame:GetAlpha() end, "%.2f"),
            math.floor(frame:GetWidth() or 0), math.floor(frame:GetHeight() or 0)))
    end

    local now = GetTime()
    for i = 1, activeSlots do
      -- Identity first, on its own line, before anything that can refuse. Slot index, spell
      -- id and name are all plain, so this prints even when every field after it raises --
      -- and a report that at least names the spell in each slot beats one that dies before
      -- saying anything, which is what the last three pulls produced.
      local slotID = slots[i] and slots[i].spellID
      local slotInfo = slotID and C_Spell and C_Spell.GetSpellInfo
          and C_Spell.GetSpellInfo(slotID)
      -- Every field is fetched and FORMATTED behind its own guard. One refusing call then
      -- costs that one field, not the row and not the report. This is the whole point: the
      -- report exists to say which call refuses, so it must survive a refusal to say it.
      local readable = Safe(function() return CanNameSpellAloud(slotID) end)

      local durState = Safe(function()
          local dur = C_Spell.GetSpellCooldownDuration(slotID, true)
          if not dur then return "nil (READY)" end
          if not CanNameSpellAloud(slotID) then return "object (sealed)" end
          return dur:IsZero()
      end)

      -- HasSecretValues is flagged ReturnsNeverSecret, so unlike IsZero it answers even
      -- while cooldowns are sealed. It was worth testing as a readiness signal that would
      -- let the voice stop dead reckoning. REFUTED on a live pull (Ra'vi, 2026-08-20): it
      -- read true for all three slots at once, including one the model had as ready and
      -- one mid-cooldown, so it reports only that the object CAN carry secret state, not
      -- whether a cooldown is running. Kept in the readout because it is free and confirms
      -- the sealing, but nothing may branch on it.
      -- The plain truth, if the client answers: Blizzard's own not-isOnGCD-and-isActive.
      -- "running" or "ready" here is the REAL cooldown state even while sealed; "nil" means
      -- the client would not answer and the model below is what the pick actually used.
      local realCD = Safe(function()
          if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
          local info = C_Spell.GetSpellCooldown(slotID)
          if type(info) ~= "table" then return nil end
          return ((not info.isOnGCD) and info.isActive) and "running" or "ready"
      end)

      local secretVals = Safe(function()
          local dur = C_Spell.GetSpellCooldownDuration(slotID, true)
          if not dur or not dur.HasSecretValues then return "n/a" end
          return dur:HasSecretValues()
      end)

      -- A charge spell never touches readyAt (see NoteOwnCast), so the plain-cooldown
      -- model line would always read 0.0s for one regardless of its real charge count.
      -- That is what hid the Guardian of Ancient Kings state from the last two reports.
      local model = Safe(function()
          local charges = ChargesAvailable(slotID)
          if charges then
              local st = chargeState[slotID]
              -- recharge=0.0s means GetSpellBaseCooldown reported nothing usable for this
              -- spell, same as Divine Shield originally did -- the count cannot climb back
              -- up on its own until a real cast is witnessed, only KNOWN_BASE_COOLDOWN or a
              -- confirmed full recharge fixes that.
              return string.format("%d/%s charges (recharge=%.1fs)",
                  charges, tostring(st and st.max or "?"), st and st.recharge or 0)
          end
          return string.format("%.1fs", math.max(0, (readyAt[slotID] or 0) - now))
      end)

      local learned = Safe(function()
          local t2 = TRDB()
          local v = type(t2.learned) == "table" and t2.learned[tostring(slotID)] or nil
          return v or "no"
      end)

      -- Static data, always readable regardless of sealing. A non-charge spell whose base
      -- cooldown reads 0 or nil here falls through NoteOwnCast to KNOWN_BASE_COOLDOWN, or
      -- failing that the 30s UNKNOWN_COOLDOWN placeholder -- which is nowhere close to a
      -- multi-minute defensive's real cooldown and is the leading suspect for a defensive
      -- reading ready long before it actually is.
      local baseCD = Safe(function()
          local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(slotID)
          return (type(ms) == "number") and (ms / 1000) or 0
      end, "%.1fs")

      local alpha = Safe(function() return slots[i]:GetAlpha() end, "%.2f")
      local iconShown = Safe(function()
          return slots[i].icon and slots[i].icon:IsShown()
      end)
      local audio = ns.IsAudioOff(slotID) and "audioOFF" or "audioOn"

      ns.Print(("  %d. %s (%s) readable=%s cd=%s realcd=%s secretvals=%s model=%s learned=%s basecd=%s alpha=%s icon=%s %s")
          :format(i, (slotInfo and slotInfo.name) or "?", tostring(slotID),
                  readable, durState, realCD, secretVals, model, learned, baseCD, alpha, iconShown, audio))
    end
end

local shownForEvent

local function HideReminder()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    shownForEvent = nil
    if frame then
        if frame.reminder then frame.reminder:Hide() end
        frame:Hide()
    end
    if textFrame then textFrame:Hide() end
    if bar then bar:Hide() end
end

local function ShowForEvent(eventID)
    if not frame then return end

    -- HIGHLIGHT is not one-shot: the engine replays it for the same event more than once
    -- (Blizzard's own timeline view just re-triggers its glow animation every time, with
    -- no dedup of its own), which without this repeated a callout for a single cast that
    -- had a long lead time. Latched below, only once the event actually gets announced.
    if announced[eventID] then
        if traceLeft > 0 then
            traceLeft = traceLeft - 1
            ns.Print(("|cffF0A830trace|r event=%s |cff80ff80repeat|r (already announced "
                .. "this event)"):format(tostring(eventID)))
        end
        return
    end

    local t = TRDB()

    -- Remembered even when muted, so "that one was wrong" can still be acted on afterwards
    -- without having to catch it live.
    prevFingerprintAt = lastFingerprintAt
    lastFingerprintAt = GetTime()
    lastFingerprint = FingerprintFor(eventID)
    lastFingerprintEncounter = currentEncounter

    -- A boss with NO data at all used to call out on every timeline event, on the theory
    -- that missing a buster is worse than noise. A live lair boss settled it: five abilities
    -- on ten-second cycles is nonstop alerts, which players turn off, and off catches
    -- nothing. Unknown bosses are now QUIET -- the engine beep still covers flagged and
    -- curated busters -- and say so once, and learning mode brings the old behavior back
    -- for exactly the person it was built for: whoever is authoring the boss.
    do
        local player = MarksTable(false, currentEncounter)
        local covered = (player ~= nil and next(player) ~= nil)
            or (ShippedMarks(currentEncounter) ~= nil)
        if not covered and not t.learnMode then
            if lastUnknownNotice ~= currentEncounter then
                lastUnknownNotice = currentEncounter
                -- The encounter id belongs in BOTH lines. This branch returns long before
                -- the trace prints its "encounter=" header, so a report of a silent boss
                -- said "unknown boss" and nothing else -- no way to tell WHICH boss was
                -- missing without going and looking it up by hand.
                --
                -- "No data yet" and "checked, and this boss has no tank buster" look
                -- identical from the player's seat, and only the first is worth acting on.
                -- Sending a tank to author an ability that does not exist wastes a pull.
                if ns.TANK_NONE and ns.TANK_NONE[currentEncounter] then
                    ns.Print(("this boss (encounter %s) has no tank buster to call -- "
                        .. "checked against the boss mods, it does not have one. Silence "
                        .. "here is correct."):format(tostring(currentEncounter)))
                else
                    ns.Print(("this boss (encounter %s) has no tank buster data yet, so "
                        .. "callouts stay quiet here. The alert sound still covers known "
                        .. "busters. Authoring it: /nutank learn, then /nutank tank on the "
                        .. "real busters."):format(tostring(currentEncounter)))
                end
            end
            if traceLeft > 0 then
                traceLeft = traceLeft - 1
                ns.Print(("|cffF0A830trace|r event=%s |cff80ff80quiet|r (encounter %s is "
                    .. "unknown, learning mode off, fingerprint %s)"):format(
                        tostring(eventID), tostring(currentEncounter),
                        tostring(lastFingerprint)))
            end
            return
        end
    end

    if IsUnmarkedEvent(eventID) then
        -- Kept for the end-of-fight report below. "I got no callouts on this boss" has cost
        -- several pulls each time to answer, because the trace has to be armed BEFORE the
        -- ability lands and the tank buster is rarely the first event. A fight that called
        -- nothing can say what it saw instead, after the fact.
        if lastFingerprint then silencedFingerprints[lastFingerprint] = true end
        if traceLeft > 0 then
            traceLeft = traceLeft - 1
            ns.Print(("|cffF0A830trace|r event=%s |cff80ff80silenced|r (fingerprint %s is not "
                .. "a marked tank buster)"):format(tostring(eventID), tostring(lastFingerprint)))
        end
        return
    end

    if IsMutedEvent(eventID) then
        if traceLeft > 0 then
            traceLeft = traceLeft - 1
            ns.Print(("|cffF0A830trace|r event=%s |cff80ff80muted|r (fingerprint %s)")
                :format(tostring(eventID), tostring(lastFingerprint)))
        end
        return
    end

    if t.aggroOnly and not TankingSomeBoss() then
        if traceLeft > 0 then
            traceLeft = traceLeft - 1
            ns.Print(("|cffF0A830trace|r event=%s |cff80ff80off-tank|r (the boss is on the "
                .. "other tank)"):format(tostring(eventID)))
        end
        return
    end

    if t.coveredSkip ~= false and CoveredByActiveDefensive() then
        if traceLeft > 0 then
            traceLeft = traceLeft - 1
            ns.Print(("|cffF0A830trace|r event=%s |cff80ff80covered|r (a defensive is "
                .. "already active with %ds+ left)"):format(tostring(eventID),
                COVERED_MIN_REMAINING))
        end
        return
    end

    -- The two alert types are EXCLUSIVE, per the tester's design: an ability set to a
    -- custom alert says that line and nothing else -- no defensive pick, no icons -- and
    -- a defensive ability never carries custom text. The mode is simply whether reminder
    -- state exists for this fingerprint.
    local customText = ReminderFor(currentEncounter, lastFingerprint)
    local customMode = ReminderEntry(currentEncounter, lastFingerprint) ~= nil

    if customMode then
        -- Plain constant alpha is legal; only engine-driven values are not. The slots go
        -- dark rather than unbuilt so the frame keeps its size for placement.
        for i = 1, activeSlots do slots[i]:SetAlpha(0) end
    else
        -- The defensive pick honors this ABILITY's own list when one exists: slots are
        -- rebuilt against the fingerprint before anything reads them. Cheap, and the next
        -- event or encounter start rebuilds again, so nothing needs restoring.
        RebuildSlots(lastFingerprint)
        RebuildCastMap()
        ApplyPriorityAlpha()
    end

    -- The bar counts down the incoming ability. GetEventTimer hands back a duration object
    -- that is PLAIN (only the descriptive event fields are secret), and the engine ticks it
    -- against a clock that already accounts for encounter pauses -- so this is set once per
    -- event and never polled.
    if t.showBar and canBar then
        CreateBar()
        local durObj = C_EncounterTimeline.GetEventTimer(eventID)
        if durObj and bar.SetTimerDuration then
            bar:SetMinMaxValues(0, 1)
            bar:SetTimerDuration(durObj, Enum.StatusBarInterpolation.Immediate,
                Enum.StatusBarTimerDirection.RemainingTime)
            bar:Show()
        end
    elseif bar then
        bar:Hide()
    end

    -- Every event that reaches this point already passed the fingerprint filter, which is
    -- the tank filter now -- and unlike the engine gate it covers text and voice too. The
    -- gate machinery itself stays for the /nutank gate diagnostic.
    ClearTankGate()

    announced[eventID] = true
    calloutsThisFight = calloutsThisFight + 1
    shownForEvent = eventID
    if frame.learnTag then
        frame.learnTag:SetShown(t.learnMode == true)
        if frame.learnBorder and frame.learnBorder._frame then
            frame.learnBorder._frame:SetShown(t.learnMode == true)
        end
    end
    frame:Show()
    if textFrame then textFrame:Show() end
    -- The callout happens BEFORE the report, and the report is guarded. Either alone would
    -- do; both together mean no future change to the readout can cost the player an alert.
    -- It already did once: an unguarded throw in here ran ahead of the callout and took the
    -- audio with it on the exact pull being diagnosed.
    if not customMode then SpeakCallout() end
    lastCalloutAt = GetTime()

    -- The authored layer: what the curator wrote on THIS ability, named when the data
    -- knows it. Shown over the icon and spoken after the defensive, so the actionable
    -- word still comes first.
    if frame.reminder then
        local reminder = customText
        if reminder then
            if t.showText then
                frame.reminder:SetText(reminder)
                frame.reminder:Show()
            end
            if t.voiceOn then Speak(reminder) end
        else
            -- Authored text only. Showing the incoming ability's name here was tried and
            -- cut on tester feedback: mid-pull, a second line of text above the icon is
            -- noise unless a person chose the words.
            frame.reminder:Hide()
        end
    end

    if traceLeft > 0 then
        local okT, err = pcall(TraceEvent, eventID)
        if not okT then ns.Print("|cffff6060trace failed|r: " .. ErrText(err)) end
    end

    if hideTimer then hideTimer:Cancel() end
    -- Up for exactly the window being shown: the player's lead when the alert was delayed
    -- to it, the engine's when the engine announced later than the player asked for.
    local lead = 5
    if C_EncounterTimeline and C_EncounterTimeline.GetEventHighlightTime then
        local v = C_EncounterTimeline.GetEventHighlightTime()
        if type(v) == "number" and v > 0 then lead = v end
    end
    local want = TRDB().leadTime or 3
    if want > 0 and want < lead then lead = want end
    hideTimer = C_Timer.NewTimer(lead, HideReminder)
end

-- Previews one custom line exactly as a fight would deliver it: the text over the alert
-- frame for a few seconds, and the voice saying it. Used by the Says row's Preview button.
function ns.PreviewReminderLine(text)
    if type(text) ~= "string" or text == "" then return end
    if not frame then Reminder.Create() end
    if frame and frame.reminder then
        frame.reminder:SetText(text)
        frame.reminder:Show()
        frame:Show()
        if textFrame then textFrame:Show() end
        C_Timer.After(3, function()
            if frame and frame.reminder and not shownForEvent then
                frame.reminder:Hide()
                if not previewing then
                    frame:Hide()
                    if textFrame then textFrame:Hide() end
                end
            end
        end)
    end
    Speak(text)
end

-- Used by /nutank test. Deliberately bypasses the tank gate so the two failure modes can
-- be told apart.
function ns.ForceShowTest()
    if not frame then Reminder.Create() end
    ApplyPriorityAlpha()
    ClearTankGate()
    if TRDB().showBar then
        CreateBar()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        if bar.fill then bar.fill:SetAlpha(1) end
        if bar.bg then bar.bg:SetAlpha(1) end
        bar:Show()
    end
    shownForEvent = nil
    frame:Show()
    if textFrame then textFrame:Show() end
    -- The voice too: a test that skips a channel reports that channel broken when it is
    -- merely untested. At the desk cooldowns read plainly, so this speaks whichever
    -- defensive is genuinely up, exactly as a fight would.
    SpeakCallout()

    -- A test that can show nothing must SAY so. With every channel off this otherwise
    -- reports success by displaying nothing, which reads as broken -- and the engine sound
    -- cannot prove itself here at all, since it only fires on a real boss event.
    local t2 = TRDB()
    if not (t2.showIcon or t2.showText or t2.voiceOn) then
        ns.Print("|cffff6060icon, text and voice are all switched off|r -- there is nothing "
            .. "for this test to show. Play a Sound is engine-driven and only fires on a "
            .. "real boss.")
    end
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(5, HideReminder)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local watcher

-- The All Dungeons / All Raids switches. Anywhere else (open world, delves, scenarios) is
-- unaffected by them.
local function AllowedHere()
    local t = TRDB()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then return t.inDungeons ~= false end
    if instanceType == "raid" then return t.inRaids ~= false end
    return true
end

-- A boss switched off in the tree. Enforceable because the game tells us which encounter we
-- are in, unlike which ability is incoming.
local function BossAllowed()
    local t = TRDB()
    if not (currentEncounter and type(t.bossOff) == "table") then return true end
    return t.bossOff[tostring(currentEncounter)] ~= true
end

-- The timeline carries more than boss abilities -- respawn timers and other non-encounter
-- events ride it too, which is how a callout fired while standing at the instance entrance
-- after a wipe. Gate on an encounter actually being underway.
local function InEncounter()
    if C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress then
        return C_InstanceEncounter.IsEncounterInProgress()
    end
    return currentEncounter ~= nil
end

-- Every specialization. The role is still resolved because the optional tank filter needs
-- it, but it no longer gates whether the feature runs at all.
local function ShouldRun()
    return TRDB().enabled == true and canSelect
        and activeSlots > 0 and TimelineAvailable() and AllowedHere() and BossAllowed()
end

-- The other door into the fight: the boss's own cast bar. Timeline events keep their spell
-- identity secret (measured -- every event, every pull), but UnitCastingInfo is only
-- SecretWhenUnitSpellCastRestricted, i.e. CONDITIONALLY. Where it reads plainly, the moment
-- Triple Shot's cast starts we know it is Triple Shot by spell id, the curated list answers
-- "tank buster" outright, and no shipped fingerprint or marking is needed at all.
--
-- Two jobs, both automatic:
--
--   1. LEARN. Pair the cast's spell id with the most recent timeline fingerprint, and mark
--      that fingerprint as a tank buster for this boss. That is the same mark /nutank tank
--      records by hand -- authored here by the game instead of a person. The pairing is
--      skipped when TWO events announced within the window, because attributing the cast to
--      the wrong one would poison the mark; an unambiguous pairing arrives within a cast or
--      two and marks persist, so the filter converges and then holds.
--   2. BACKSTOP. If no callout happened recently -- the event was silenced by a wrong or
--      missing mark, or never made the timeline -- fire the callout now. Later than the
--      timeline's five seconds, but on time beats silent.
--
-- Where cast identity turns out secret, issecretvalue answers plainly, the probe records it
-- for the trace, and this whole path steps aside -- shipped fingerprints remain the answer
-- in that content.
-- Both identity channels funnel here with a PLAIN spell id in hand. Everything after
-- identification is channel-agnostic: check the curated list, learn the fingerprint,
-- backstop the callout.
local lastIdentifiedSid, lastIdentifiedAt = nil, 0

local function HandleIdentifiedCast(sid)
    if not frame or activeSlots == 0 then return end
    if not (ShouldRun() and InEncounter()) then return end

    -- Both channels usually see the same cast; the second sighting adds nothing.
    local now = GetTime()
    if sid == lastIdentifiedSid and (now - lastIdentifiedAt) < 3 then return end
    lastIdentifiedSid, lastIdentifiedAt = sid, now

    local buster = ns.TANK_ABILITIES and ns.TANK_ABILITIES[sid]

    -- The learn path narrates itself while a trace is armed. Learning that silently
    -- declines is indistinguishable from learning that is broken, and that ambiguity has
    -- already cost full dungeon runs elsewhere in this file.
    local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    local castName = (si and si.name) or tostring(sid)
    if traceLeft > 0 then
        ns.Print(("|cffF0A830cast|r %s (%s) curated=%s"):format(
            castName, tostring(sid), buster and "TANK BUSTER" or "no"))
    end
    if not buster then return end

    -- Learn: one recent announcement, and only one, else the attribution is a guess.
    local skip
    if not (lastFingerprint and currentEncounter) then
        skip = "no timeline event announced this"
    elseif lastFingerprintEncounter ~= currentEncounter then
        skip = "last announcement was another encounter's"
    elseif (now - lastFingerprintAt) >= 10 then
        skip = ("last announcement was %.0fs ago, too old to attribute"):format(
            now - lastFingerprintAt)
    elseif (now - prevFingerprintAt) < 10 then
        skip = "two events announced back to back, attribution would be a guess"
    end

    if not skip then
        local m = MarksTable(true, currentEncounter)
        if m[lastFingerprint] ~= true then
            m[lastFingerprint] = true
            ns.Print(("Learned: fingerprint %s on encounter %s is a tank buster (%s). "
                .. "Other abilities on this boss will stop calling out."):format(
                lastFingerprint, tostring(currentEncounter), castName))
        end
    elseif traceLeft > 0 then
        ns.Print("  |cffF0A830not learned|r: " .. skip)
    end

    -- Backstop: the timeline path already spoke for this cast if anything did.
    if (now - lastCalloutAt) < 6 then return end
    if TRDB().aggroOnly and not TankingSomeBoss() then return end
    if TRDB().coveredSkip ~= false and CoveredByActiveDefensive() then return end

    ApplyPriorityAlpha()
    -- The previous event may have left the engine gate's alpha 0 on these icons; this
    -- callout is for a KNOWN tank buster, so they must be visible.
    ClearTankGate()
    frame:Show()
    if textFrame then textFrame:Show() end
    SpeakCallout()
    lastCalloutAt = now
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(5, HideReminder)
end

-------------------------------------------------------------------------------
--  Custom reminders: pull, BigWigs/DBM message and BigWigs/DBM timer triggers
-------------------------------------------------------------------------------
-- Independent of the defensive-priority system entirely: a player with nothing on their
-- priority list should still get these, so gating never touches ShouldRun()/activeSlots.
local function CustomRemindersAllowed()
    return TRDB().enabled == true and AllowedHere() and BossAllowed()
end

-- "Show in" syntax: blank fires immediately. A plain number or MM:SS(.ms) (e.g. "1:30.5")
-- is seconds; comma-separate several to fire more than once. Non-positive values are
-- nudged up rather than treated as "now", so a scheduled fire never lands in the past.
local function ParseDelayList(text)
    if type(text) ~= "string" or text == "" then return nil end
    local out = {}
    for tok in text:gmatch("[^, ]+") do
        local n = tonumber(tok)
        if not n then
            local m, s, frac = tok:match("^(%d+):(%d+)%.?(%d*)$")
            if m then
                local ms = (frac ~= "") and tonumber("0." .. frac) or 0
                n = tonumber(m) * 60 + tonumber(s) + ms
            end
        end
        if n then out[#out + 1] = math.max(n, 0.01) end
    end
    return #out > 0 and out or nil
end

-- Counter condition syntax: a bare number, >=N, >N, <=N, <N, !N or =N. Comma-separated
-- terms are OR'd; a leading + on a term ANDs it with the one before it in the same group
-- (comma still required) -- e.g. ">3,+<7" means "more than 3 and less than 7".
local function ParseOnePred(tok)
    local op, num = tok:match("^(>=)(%-?%d+%.?%d*)$")
    if not num then op, num = tok:match("^(<=)(%-?%d+%.?%d*)$") end
    if not num then op, num = tok:match("^(>)(%-?%d+%.?%d*)$") end
    if not num then op, num = tok:match("^(<)(%-?%d+%.?%d*)$") end
    if not num then op, num = tok:match("^(!)(%-?%d+%.?%d*)$") end
    if not num then op, num = tok:match("^(=)(%-?%d+%.?%d*)$") end
    if not num then op, num = "=", tok:match("^(%-?%d+%.?%d*)$") end
    num = tonumber(num)
    if not num then return nil end
    return { op = op, num = num }
end

local function ParseCounterCondition(text)
    if type(text) ~= "string" or text == "" then return nil end
    local groups = {}
    for tok in text:gmatch("[^,]+") do
        tok = tok:gsub("^%s+", ""):gsub("%s+$", "")
        local andWithPrev = tok:sub(1, 1) == "+"
        local pred = ParseOnePred(andWithPrev and tok:sub(2) or tok)
        if pred then
            if andWithPrev and #groups > 0 then
                local g = groups[#groups]
                g[#g + 1] = pred
            else
                groups[#groups + 1] = { pred }
            end
        end
    end
    return #groups > 0 and groups or nil
end

local function CheckCounterCondition(groups, n)
    if not groups then return true end
    for i = 1, #groups do
        local g = groups[i]
        local allMatch = true
        for k = 1, #g do
            local p = g[k]
            local ok
            if p.op == ">=" then ok = n >= p.num
            elseif p.op == "<=" then ok = n <= p.num
            elseif p.op == ">" then ok = n > p.num
            elseif p.op == "<" then ok = n < p.num
            elseif p.op == "!" then ok = n ~= p.num
            else ok = n == p.num end
            if not ok then allMatch = false; break end
        end
        if allMatch then return true end
    end
    return false
end

local customFrame
local customHideTimer
-- Per-uid occurrence count for the "Nth cast" counter, reset every pull.
local customCounters = {}
-- Cached at ENCOUNTER_START so OnCombatLog's hot path stays a single boolean read on a
-- boss with nothing configured, the same reasoning runActive already uses below.
local hasCustomReminders = false

local function RefreshCustomRemindersFlag()
    local set = currentEncounter and CustomRemindersTable(false, currentEncounter)
    hasCustomReminders = set ~= nil and next(set) ~= nil
end
ns.RefreshCustomRemindersFlag = RefreshCustomRemindersFlag

-- Same shape as ApplyPosition/ApplyTextPosition: nil = default centre, otherwise wherever
-- Unlock Mode last saved it.
local function ApplyCustomReminderPosition()
    if not customFrame then return end
    local p = TRDB().customPos
    customFrame:ClearAllPoints()
    if p then
        customFrame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        customFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
end

local function CreateCustomFrame()
    if customFrame then return customFrame end
    customFrame = CreateFrame("Frame", "NaowhUITankReminderCustom", UIParent)
    customFrame:SetSize(360, 40)
    -- HIGH, matching the icon and text callout (frame/textFrame) -- part of Smart
    -- Reminders' own display, not something that should out-rank EllesmereUI's windows or
    -- the rest of Smart Reminders' own alert. The editor's Preview button temporarily
    -- raises this (see PreviewCustomReminder below) since it fires from inside a modal
    -- that sits above HIGH; everything else leaves it here.
    customFrame:SetFrameStrata("HIGH")
    customFrame:SetClampedToScreen(true)
    customFrame:EnableMouse(false)
    customFrame:Hide()

    customFrame.text = customFrame:CreateFontString(nil, "OVERLAY")
    customFrame.text:SetPoint("CENTER")
    customFrame.text:SetFont(AlertFont(), 18, "OUTLINE")
    customFrame.text:SetTextColor(1, 1, 1, 1)
    ApplyCustomReminderPosition()
    return customFrame
end

local function HideCustomReminder()
    if customHideTimer then customHideTimer:Cancel(); customHideTimer = nil end
    if customFrame then
        customFrame:Hide()
        -- Undo any Preview-specific elevation so a real fight never inherits it.
        customFrame:SetFrameStrata("HIGH")
    end
end

-- What a preset-bound reminder actually says: the best defensive still available in the
-- chosen preset, decided at fire time by the same ladder the main callout uses. A line the
-- player typed before the pull cannot know what is up, which is the whole reason these
-- moved from free text to a preset.
--
-- Resolved against the CURRENT spec, like every other preset lookup here -- presets are
-- per-spec and the stored key indexes into whichever spec is live.
local function PickFromPreset(presetKey)
    local presets = PresetsTable(specID, false)
    local p = presets and presets[presetKey]
    local list = p and p.list
    if type(list) ~= "table" then return nil end

    local now = GetTime()
    -- SpellReady can raise if a cooldown's classification changes mid-read; the whole walk
    -- is guarded so that degrades to the no-defensive line rather than to a Lua error.
    local ok, picked = pcall(function()
        for i = 1, #list do
            local sid = list[i]
            -- Untalented entries are skipped rather than called for, matching RebuildSlots.
            if IsSpellAvailable(sid) then
                ResyncSpell(sid)
                if SpellReady(sid, now) then return sid end
            end
        end
    end)
    return ok and picked or nil
end

-- Bypasses trigger matching entirely -- used both by the real firing path below and by
-- the editor's Preview button, so a preview shows exactly what a fight would.
local function FireCustomReminder(r)
    if not r then return end

    local msg
    if r.preset then
        local picked = PickFromPreset(r.preset)
        if picked then
            local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(picked)
            msg = CalloutFor(picked, info and info.name)
        else
            -- Nothing in the preset is up. Same line the main callout falls back to, so a
            -- custom reminder never goes blank at the moment it matters most.
            msg = TRDB().voiceNone
        end
    else
        -- Reminders saved before preset binding existed still show their authored text.
        msg = (type(r.msg) == "string" and r.msg ~= "" and r.msg) or r.name
    end

    if not msg or msg == "" then return end
    CreateCustomFrame()
    customFrame.text:SetText(msg)
    customFrame:Show()
    if customHideTimer then customHideTimer:Cancel() end
    local dur = (type(r.dur) == "number" and r.dur > 0) and r.dur or 3
    customHideTimer = C_Timer.NewTimer(dur, HideCustomReminder)
end

-- The editor's Preview button fires this from inside its own modal (FULLSCREEN_DIALOG),
-- which HIGH sits well below, so it needs a taller strata just for this one showing --
-- HideCustomReminder (above) drops it back to HIGH once the preview ends, so the elevation
-- never leaks into how a real fight displays this frame.
function ns.PreviewCustomReminder(r)
    CreateCustomFrame()
    customFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    customFrame:SetFrameLevel(250)
    FireCustomReminder(r)
end

-- The match decided a reminder should go off; this is where "Show in" (a raw string on
-- the trigger, parsed fresh here rather than pre-compiled -- these fire rarely enough that
-- the cost never matters) turns into either an immediate call or one timer per listed
-- delay, so a comma list fires more than once from the same match.
local function ActivateCustomReminder(r)
    local delays = ParseDelayList(r.trigger and r.trigger.delay)
    if not delays then
        FireCustomReminder(r)
        return
    end
    for i = 1, #delays do
        C_Timer.NewTimer(delays[i], function() FireCustomReminder(r) end)
    end
end

-- kind: "pull" | "cast" | "aura". spellID is nil for a pull check. "cast"/"aura" are the
-- older combat-log triggers -- the editor no longer creates them, but anything already
-- saved that way keeps working.
local function CheckCustomReminders(kind, spellID)
    if not (hasCustomReminders and CustomRemindersAllowed()) then return end
    local set = CustomRemindersTable(false, currentEncounter)
    if not set then return end
    for uid, r in pairs(set) do
        local trig = r.trigger
        if r.enabled ~= false and trig then
            local hit = (kind == "pull" and trig.type == "pull")
                or (trig.type == "spell" and trig.spellID == spellID
                    and (trig.kind or "cast") == kind)
            if hit and type(trig.counter) == "number" and trig.counter > 1 then
                customCounters[uid] = (customCounters[uid] or 0) + 1
                hit = customCounters[uid] >= trig.counter
            end
            if hit then ActivateCustomReminder(r) end
        end
    end
end

-------------------------------------------------------------------------------
--  Custom reminders: BigWigs/DBM message and timer triggers
-------------------------------------------------------------------------------
-- Which boss mod owns this pull, latched on its first message so a player running both
-- BigWigs and DBM does not get every message/timer trigger firing twice. Reset every pull.
local bwActiveMod

-- Pending "timeleft" activations for bwtimer triggers, so a bar that stops or pauses
-- early can cancel the reminder before it fires. Keyed by uid .. "|" .. mod .. ":" .. bar
-- text, since a stop/pause event only ever carries the bar's text back, not its key.
local bwPendingTimers = {}

local function CancelBossModTimers(mod, text)
    local prefix = mod .. ":" .. tostring(text)
    for k, handle in pairs(bwPendingTimers) do
        if k:find(prefix, 1, true) then
            if handle.Cancel then handle:Cancel() end
            bwPendingTimers[k] = nil
        end
    end
end

local function CheckBossModMessage(mod, key)
    if bwActiveMod and bwActiveMod ~= mod then return end
    if type(key) ~= "number" then return end
    if not (hasCustomReminders and CustomRemindersAllowed()) then return end
    local set = CustomRemindersTable(false, currentEncounter)
    if not set then return end
    local matched = false
    for uid, r in pairs(set) do
        local trig = r.trigger
        if r.enabled ~= false and trig and trig.type == "bwmsg" and trig.spellID == key then
            matched = true
            local hit = true
            if trig.counter and trig.counter ~= "" then
                customCounters[uid] = (customCounters[uid] or 0) + 1
                hit = CheckCounterCondition(ParseCounterCondition(trig.counter), customCounters[uid])
            end
            if hit then ActivateCustomReminder(r) end
        end
    end
    if matched and not bwActiveMod then bwActiveMod = mod end
end

-- barIdentity is whatever the stop/pause event for this mod hands back later -- BigWigs
-- only ever gives the bar TEXT back, DBM only ever gives the timer ID back, so the two
-- mods key their pending timers differently even though everything else is shared. text
-- carries the bar's own occurrence count when the boss mod prints one in parens (BigWigs'
-- "(3)" ability-count suffix) -- that overrides our own tally for the counter check when
-- present, matching what the number on screen actually says.
local function CheckBossModTimerStart(mod, key, barIdentity, duration, text)
    if bwActiveMod and bwActiveMod ~= mod then return end
    if type(key) ~= "number" or type(duration) ~= "number" then return end
    if not (hasCustomReminders and CustomRemindersAllowed()) then return end
    local set = CustomRemindersTable(false, currentEncounter)
    if not set then return end
    local barCount = type(text) == "string" and tonumber(text:match("%((%d%d?)%)"))
    local matched = false
    for uid, r in pairs(set) do
        local trig = r.trigger
        if r.enabled ~= false and trig and trig.type == "bwtimer" and trig.spellID == key
           and type(trig.timeleft) == "number" and duration >= trig.timeleft then
            matched = true
            customCounters[uid] = (customCounters[uid] or 0) + 1
            local n = barCount or customCounters[uid]
            local hit = true
            if trig.counter and trig.counter ~= "" then
                hit = CheckCounterCondition(ParseCounterCondition(trig.counter), n)
            end
            if hit then
                local barKey = uid .. "|" .. mod .. ":" .. tostring(barIdentity)
                -- A re-announced bar (some modules resync a running bar rather than only
                -- ever starting a fresh one) must not stack a second pending fire on top
                -- of the first.
                local old = bwPendingTimers[barKey]
                if old and old.Cancel then old:Cancel() end
                local fireDelay = math.max(duration - trig.timeleft, 0.01)
                bwPendingTimers[barKey] = C_Timer.NewTimer(fireDelay, function()
                    bwPendingTimers[barKey] = nil
                    ActivateCustomReminder(r)
                end)
            end
        end
    end
    if matched and not bwActiveMod then bwActiveMod = mod end
end

-- kind: "applied" | "removed". destGUID identifies whether the affected unit is a boss --
-- cross-referenced against boss1-boss5, the same way OnBossCast already identifies a boss
-- unit, rather than a destFlags hostile-NPC check that would also catch trash adds -- or
-- the player. Reads directly off the combat log rather than through BigWigs/DBM, since
-- SPELL_AURA_APPLIED/REMOVED fire for every aura on every unit regardless of whether any
-- boss module's author chose to announce it, giving this broader coverage than a message
-- trigger ever could for something as generic as "an aura landed."
local function CheckAuraReminder(kind, destGUID, spellID)
    if not (hasCustomReminders and CustomRemindersAllowed()) then return end
    if type(spellID) ~= "number" or type(destGUID) ~= "string" then return end
    local isPlayer = destGUID == UnitGUID("player")
    local isBoss = false
    if not isPlayer then
        for i = 1, 5 do
            if destGUID == UnitGUID("boss" .. i) then isBoss = true; break end
        end
    end
    if not (isPlayer or isBoss) then return end
    local set = CustomRemindersTable(false, currentEncounter)
    if not set then return end
    for uid, r in pairs(set) do
        local trig = r.trigger
        if r.enabled ~= false and trig and trig.type == "aura" and trig.spellID == spellID
           and (trig.auraEvent or "applied") == kind
           and (trig.target == "player") == isPlayer then
            local hit = true
            if trig.counter and trig.counter ~= "" then
                customCounters[uid] = (customCounters[uid] or 0) + 1
                hit = CheckCounterCondition(ParseCounterCondition(trig.counter), customCounters[uid])
            end
            if hit then ActivateCustomReminder(r) end
        end
    end
end

-- Both dispatchers below register with a plain function, so the message name arrives as
-- the FIRST argument -- confirmed against BigWigs' and DBM's own dispatch code, not
-- assumed. issecretvalue guards the payload before anything touches it, the same rule
-- every other identity channel in this file follows.
local function OnBigWigsEvent(event, ...)
    if not hasCustomReminders then return end
    if event == "BigWigs_Message" then
        local _, key, text = ...
        if issecretvalue and (issecretvalue(key) or issecretvalue(text)) then return end
        CheckBossModMessage("BW", key)
    elseif event == "BigWigs_StartBar" then
        local _, key, text, duration = ...
        if issecretvalue and (issecretvalue(key) or issecretvalue(text) or issecretvalue(duration)) then return end
        -- BigWigs only ever hands the bar TEXT back on stop/pause, so text doubles as
        -- both the cancellation identity and the count-extraction source.
        CheckBossModTimerStart("BW", key, text, duration, text)
    elseif event == "BigWigs_Timer" then
        -- The newer non-bar timer API; some modules fire this INSTEAD of StartBar. When
        -- isBarEnabled (the last argument) is true, StartBar already fired for the same
        -- bar and handling both would double the reminder.
        local _, key, duration, _, text, _, _, _, isBarEnabled = ...
        if isBarEnabled then return end
        if issecretvalue and (issecretvalue(key) or issecretvalue(text) or issecretvalue(duration)) then return end
        CheckBossModTimerStart("BW", key, text, duration, text)
    elseif event == "BigWigs_StopBar" or event == "BigWigs_PauseBar" then
        local _, text = ...
        if issecretvalue and issecretvalue(text) then return end
        CancelBossModTimers("BW", text)
    elseif event == "BigWigs_StopBars" or event == "BigWigs_OnBossDisable" then
        CancelBossModTimers("BW", "")
    end
end

local function OnDBMEvent(event, ...)
    if not hasCustomReminders then return end
    if event == "DBM_Announce" then
        local _, _, _, spellId = ...
        if issecretvalue and issecretvalue(spellId) then return end
        CheckBossModMessage("DBM", spellId)
    elseif event == "DBM_TimerBegin" or event == "DBM_TimerStart" then
        local id, msg, duration, _, _, spellId = ...
        if issecretvalue and (issecretvalue(spellId) or issecretvalue(id) or issecretvalue(duration)) then return end
        -- DBM hands the timer ID back on stop/pause, not the message text, so ID is the
        -- cancellation identity here; msg is only used for count extraction.
        CheckBossModTimerStart("DBM", spellId, id, duration, msg)
    elseif event == "DBM_TimerStop" or event == "DBM_TimerPause" then
        local id = ...
        if issecretvalue and issecretvalue(id) then return end
        CancelBossModTimers("DBM", id)
    end
end

local bwHooked, dbmHooked = false, false
local function RegisterBossModHooks()
    if _G.BigWigsLoader and not bwHooked then
        local ok = pcall(function()
            local BWL = _G.BigWigsLoader
            BWL.RegisterMessage(ns, "BigWigs_Message", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_StartBar", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_Timer", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_StopBar", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_PauseBar", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_StopBars", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_OnBossDisable", OnBigWigsEvent)
        end)
        bwHooked = ok and true or false
    end
    if _G.DBM and not dbmHooked then
        local ok = pcall(function()
            local D = _G.DBM
            -- Both event names registered defensively: the installed DBM fires
            -- DBM_TimerBegin (verified against its own source), but registering the
            -- older DBM_TimerStart name too costs nothing if some fork still sends it.
            D:RegisterCallback("DBM_Announce", OnDBMEvent)
            D:RegisterCallback("DBM_TimerBegin", OnDBMEvent)
            D:RegisterCallback("DBM_TimerStart", OnDBMEvent)
            D:RegisterCallback("DBM_TimerStop", OnDBMEvent)
            D:RegisterCallback("DBM_TimerPause", OnDBMEvent)
        end)
        dbmHooked = ok and true or false
    end
end
ns.RegisterBossModHooks = RegisterBossModHooks

-- Channel 1: the boss's cast bar. Sealed in the content measured so far, but the
-- annotation is conditional, so the probe stays.
local function OnBossCast(unit)
    -- issecretvalue BEFORE anything else touches sid -- even `== nil` is a branch on the
    -- value and raises when it is secret. The probe verdict must be recorded from the read
    -- alone, not from a comparison that would never be reached.
    local sid = select(9, UnitCastingInfo(unit))
    if issecretvalue and issecretvalue(sid) then
        castIdentity = "secret"
        return
    end
    if sid == nil then return end
    castIdentity = "plain"
    HandleIdentifiedCast(sid)
end

-- Channel 2: the combat log. A different door than the cast bar, with its own probe
-- (C_CombatLog.IsCombatLogRestricted) and its own secrecy rules, so one being sealed says
-- nothing about the other. No source check is needed: the curated list holds boss tank
-- busters only, so a matching spell id IS the answer regardless of who cast it.
--
-- Registered for the whole session, not per encounter: its registration cannot be toggled
-- from insecure code in restricted content at all. This event fires for every combat action
-- on screen, so the handler must cost nothing outside the one window where it can learn
-- something, which is what the two plain reads at the top of OnCombatLog are for.
-- Mirrors the last ShouldRun() result so OnCombatLog can gate on a plain read. The event
-- is now registered for the whole session (see UpdateEventRegistration), so "feature off
-- during an encounter" is a state the handler must refuse cheaply; calling ShouldRun()
-- itself per combat log line would mean several function calls a line instead of one read.
local runActive = false

local function OnCombatLog()
    -- The price of static registration: this fires for every combat log line, so outside
    -- an encounter it must cost one plain variable read and nothing else. Custom reminders
    -- ride the same registration under their own gate (hasCustomReminders), independent of
    -- runActive: a defensive priority list is not a prerequisite for a boss-pull reminder.
    if currentEncounter == nil or not (runActive or hasCustomReminders) then return end
    local _, sub, _, _, _, _, _, destGUID, _, _, _, spellId = CombatLogGetCurrentEventInfo()
    if issecretvalue and (issecretvalue(sub) or issecretvalue(spellId) or issecretvalue(destGUID)) then
        cleuIdentity = "secret"
        return
    end

    if hasCustomReminders and type(spellId) == "number" then
        if sub == "SPELL_CAST_SUCCESS" then
            CheckCustomReminders("cast", spellId)
        elseif sub == "SPELL_AURA_APPLIED" then
            CheckCustomReminders("aura", spellId)
            CheckAuraReminder("applied", destGUID, spellId)
        elseif sub == "SPELL_AURA_REMOVED" then
            CheckAuraReminder("removed", destGUID, spellId)
        end
    end

    if not runActive then return end
    if sub ~= "SPELL_CAST_START" and sub ~= "SPELL_CAST_SUCCESS" then return end
    if type(spellId) ~= "number" then return end
    cleuIdentity = "plain"
    HandleIdentifiedCast(spellId)
end


-- The combat log registration latch: set the first time the event is successfully
-- registered, never cleared, because the registration itself is never undone.
local cleuRegistered = false

local function UpdateEventRegistration()
    if not watcher then return end

    if not ShouldRun() then
        runActive = false
        -- The three HasRestrictions events (COMBAT_LOG_EVENT_UNFILTERED and both
        -- ENCOUNTER_TIMELINE_* ones) are NEVER unregistered, matching how the register
        -- side already treats them. InCombatLockdown() was the wrong gate and produced a
        -- live ADDON_ACTION_FORBIDDEN on UnregisterEvent from inside its own guard:
        -- toggling a restricted event's registration is forbidden for insecure code in
        -- restricted content generally, not only inside the secure-frame lockdown window,
        -- and ENCOUNTER_START (which calls this) is exactly that context. pcall cannot
        -- catch a forbidden call, so there is no window to find. Every one of these
        -- handlers already self-gates -- OnCombatLog returns on `currentEncounter == nil`,
        -- HIGHLIGHT tests ShouldRun(), REMOVED no-ops with nothing shown -- so leaving
        -- them registered costs one plain read per event and changes no behaviour.
        watcher:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
        watcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        watcher:UnregisterEvent("PLAYER_ALIVE")
        watcher:UnregisterEvent("PLAYER_UNGHOST")
        -- ENCOUNTER_START and ENCOUNTER_END stay registered, always. Dropping them was a
        -- LATCH: ShouldRun() tests activeSlots > 0 and BossAllowed(), and both of those
        -- are answers about the boss we are on, which is what these two events establish.
        -- Turning them off is the gate discarding the only thing that could tell it to
        -- come back on.
        --
        -- It fires on a completely ordinary setup. A tank who keeps per-boss lists and an
        -- empty spec default drops to activeSlots == 0 the moment a boss ENDS, because
        -- RebuildSlots falls back to that empty default -- so ENCOUNTER_START is
        -- unregistered on the first kill of the run, and every boss after it never sets
        -- currentEncounter at all. The marks lookup then reads nil, and a boss we ship
        -- data for reports "no tank buster data yet": Murder Row's Zaen, which carries a
        -- mark, came back as an unknown boss for exactly this reason.
        --
        -- Leaving them on costs two plain assignments per pull and gates nothing: alerts
        -- run off the timeline handlers, which test ShouldRun() themselves.
        HideReminder()
        return
    end

    -- Probed, not assumed: registering an event the client does not know throws.
    if C_EventUtils and C_EventUtils.IsEventValid then
        if C_EventUtils.IsEventValid("ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT") then
            watcher:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
            -- The boss's own cast, for identity where the timeline has none.
            -- RegisterUnitEvent takes two units at most, so this is the broad
            -- registration filtered in the handler; the match is one string test.
            watcher:RegisterEvent("UNIT_SPELLCAST_START")
            watcher:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT")
        end
        if C_EventUtils.IsEventValid("ENCOUNTER_TIMELINE_EVENT_REMOVED") then
            watcher:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
        end
    end

    -- The cooldown model's inputs. Unit-filtered, so the cast event fires only for the
    -- player's own presses; regen feeds the resync. SPELL_UPDATE_COOLDOWN drives the plain
    -- nil-signal correction -- event-driven, a handful of C calls per fire, no polling.
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")

    -- ONCE, ever. Two live forbidden-action errors taught the full rule: toggling this
    -- HasRestrictions event's registration from insecure code is forbidden in restricted
    -- content, in either direction, and InCombatLockdown() is not the gate -- content is.
    -- So the call happens exactly one time, only when Blizzard's own probe says the
    -- combat log is unrestricted here, and after that the latch keeps every later Apply
    -- from ever calling RegisterEvent again. Logging in inside restricted content just
    -- means the latch waits for the first Apply that runs outside it.
    if not cleuRegistered then
        local restricted = C_CombatLog and C_CombatLog.IsCombatLogRestricted
            and C_CombatLog.IsCombatLogRestricted()
        if restricted == false or restricted == nil then
            watcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            cleuRegistered = true
        end
    end

    -- Which boss we are on, so a per-boss override can take over from the spec default.
    watcher:RegisterEvent("ENCOUNTER_START")
    watcher:RegisterEvent("ENCOUNTER_END")
    watcher:RegisterEvent("PLAYER_ALIVE")
    watcher:RegisterEvent("PLAYER_UNGHOST")

    runActive = true
end

-- Said once per session, not per pull. The master switch genuinely stops the data; the
-- timeline's own display toggle does not, and warning about that one would nag every
-- boss-mod user for no reason.
local warnedCombatWarnings = false
local saidAudioOnly = false

local function WarnIfMuted()
    if warnedCombatWarnings or not TRDB().enabled or not isTank then return end
    if not CombatWarningsOff() then return end
    warnedCombatWarnings = true
    ns.Print("|cffff6060Boss Warnings are turned off|r, so the game sends no timeline data and "
        .. "the tank reminder cannot fire. Turn it back on in Options, Advanced, Combat Warnings, "
        .. "Enable Boss Warnings. Hiding the timeline itself is fine and changes nothing here.")
end

function ns.Apply()
    -- Resolved even while switched off: the list is built BEFORE the feature is enabled, and
    -- an unknown spec silently refuses every add. Two API calls, which is not a cost worth a
    -- bug. Everything expensive still sits behind the gate below.
    RefreshSpec()

    if not TRDB().enabled then
        activeSlots = 0
        HideReminder()
        UpdateEventRegistration()
        return
    end

    ProbeCapabilities()
    RefreshSpec()
    Reminder.Create()
    ApplyPosition()
    RebuildSlots()
    RebuildCastMap()
    ResyncModel()
    UpdateEventRegistration()
    WarnIfMuted()

    if TRDB().soundOn and not soundRegistered then RegisterEventSounds() end
end

-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
local function RegisterUnlock()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end

    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key   = "NaowhUI_TankReminder",   -- storage key; renaming it would orphan saved positions
            label = "Smart",
            group = "NaowhUI",
            order = 3,
            -- Sized from the icon slider, so a resize handle would be overwritten by the
            -- next update.
            noResize = true,
            isHidden = function() return not TRDB().enabled end,
            -- A getter and nothing more: Unlock Mode calls this while building its element
            -- list, so anything shown from here would appear unasked.
            getFrame = function() return frame or Reminder.Create() end,
            getSize  = function()
                local size = TRDB().iconSize or DEFAULTS.iconSize
                return size, size
            end,
            savePos = function(_, point, relPoint, x, y)
                TRDB().pos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            loadPos = function()
                local p = TRDB().pos
                if not p then return nil end
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function() TRDB().pos = nil end,
            applyPos = ApplyPosition,
        }),
        EUI.MakeUnlockElement({
            key   = "NaowhUI_TankReminderText",   -- storage key; renaming it would orphan saved positions
            label = "Smart Text",
            group = "NaowhUI",
            order = 4,
            noResize = true,
            isHidden = function() return not TRDB().enabled end,
            getFrame = function()
                if not textFrame then Reminder.Create() end
                return textFrame
            end,
            getSize  = function() return 240, 10 end,
            savePos = function(_, point, relPoint, x, y)
                TRDB().textPos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            loadPos = function()
                local p = TRDB().textPos
                if not p then return nil end
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function() TRDB().textPos = nil end,
            applyPos = ApplyTextPosition,
        }),
        EUI.MakeUnlockElement({
            key   = "NaowhUI_TankReminderCustom",   -- storage key; renaming it would orphan saved positions
            label = "Smart Custom Reminder",
            group = "NaowhUI",
            order = 5,
            noResize = true,
            isHidden = function() return not TRDB().enabled end,
            getFrame = function()
                if not customFrame then CreateCustomFrame() end
                return customFrame
            end,
            getSize  = function() return 240, 10 end,
            savePos = function(_, point, relPoint, x, y)
                TRDB().customPos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            loadPos = function()
                local p = TRDB().customPos
                if not p then return nil end
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function() TRDB().customPos = nil end,
            applyPos = ApplyCustomReminderPosition,
        }),
    }, "NaowhUI_EUI")
end

-------------------------------------------------------------------------------
--  Preview
-------------------------------------------------------------------------------
-- The settings panel is the only window in which anyone needs something to drag, so the
-- stand-in lives exactly as long as it does. Alpha is set directly here rather than through
-- the gate: out of an encounter there is no event to gate against.
local previewing = false
-- The visible half of the preview switch: previewing says the options window is open,
-- previewPin says the player wants the stand-in on screen. Both must hold. Pinned on by
-- default so the preview appears the moment the page opens -- tester feedback was not
-- "the preview is intrusive" but "I cannot find it".
local previewPin = true

local function UpdatePreview()
    if not (previewing and previewPin) then
        -- Strip the preview's drag affordances the moment it stops being a preview: a
        -- mouse-enabled alert frame in a fight would sit invisibly over the screen
        -- eating clicks.
        if frame then
            frame:EnableMouse(false)
            frame:SetScript("OnDragStart", nil)
            frame:SetScript("OnDragStop", nil)
        end
        if textFrame then
            textFrame:EnableMouse(false)
            textFrame:SetScript("OnDragStart", nil)
            textFrame:SetScript("OnDragStop", nil)
        end
        if customFrame then
            customFrame:EnableMouse(false)
            customFrame:SetScript("OnDragStart", nil)
            customFrame:SetScript("OnDragStop", nil)
        end
        -- Never yank a live call-out off the screen because the settings panel closed.
        if frame and not shownForEvent then frame:Hide() end
        if textFrame and not shownForEvent then textFrame:Hide() end
        if bar and not shownForEvent then bar:Hide() end
        -- Same rule for the custom reminder frame: customHideTimer is only running while
        -- a real (or Preview-button) fire is actually on screen.
        if customFrame and not customHideTimer then customFrame:Hide() end
        return
    end
    if not TRDB().enabled then return end

    Reminder.Create()
    RebuildSlots()

    -- The preview doubles as the placement tool: drag it and the position saves to the
    -- same slot Unlock Mode writes. Mouse and movability exist ONLY while the preview is
    -- up -- the early-return branch above strips them -- so the fight-time alert stays a
    -- pure display that can never eat a click. Icon and text drag independently, saving
    -- to separate positions, since that is the whole point of splitting them.
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point then
            TRDB().pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
        ApplyPosition()
    end)

    textFrame:SetMovable(true)
    textFrame:SetClampedToScreen(true)
    textFrame:EnableMouse(true)
    textFrame:RegisterForDrag("LeftButton")
    textFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    textFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point then
            TRDB().textPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
        ApplyTextPosition()
    end)

    -- The custom reminder frame previews too, with a placeholder line rather than a real
    -- fight message -- there is no "current" custom reminder the way there is a current
    -- defensive slot. Skipped while a real (or Preview-button) fire is already showing its
    -- own text, so dragging into place never stomps on an actual preview mid-display.
    CreateCustomFrame()
    if not customHideTimer then
        customFrame.text:SetText("Custom Reminder")
    end
    customFrame:SetMovable(true)
    customFrame:SetClampedToScreen(true)
    customFrame:EnableMouse(true)
    customFrame:RegisterForDrag("LeftButton")
    customFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    customFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point then
            TRDB().customPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
        ApplyCustomReminderPosition()
    end)
    customFrame:Show()

    if activeSlots > 0 then
        slots[1]:SetAlpha(1)
        slots[1].icon:SetAlpha(1)
        slots[1].icon:SetShown(TRDB().showIcon)
        -- The text channel previews too: the label carries exactly what a fight would show
        -- for this slot, so moving and sizing is done against the real thing.
        if slots[1].label then
            local sid = slots[1].spellID
            local si = sid and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            slots[1].label:SetText(CalloutFor(sid, si and si.name))
            slots[1].label:SetShown(TRDB().showText and true or false)
        end
    end
    -- The stand-in shows the winning line, not the fallback: a preview of "nothing is ready"
    -- is not what anyone is trying to position.
    if frame.fallback then frame.fallback:SetAlpha(0) end
    if TRDB().showBar then
        CreateBar()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        if bar.fill then bar.fill:SetAlpha(1) end
        if bar.bg then bar.bg:SetAlpha(1) end
        bar:Show()
    elseif bar then
        bar:Hide()
    end
    frame:Show()
    textFrame:Show()
end

-------------------------------------------------------------------------------
--  Diagnostics
-------------------------------------------------------------------------------
-- /nutank -- the two things that cannot be settled from Blizzard's source.
--
--   catalogue : C_EncounterEvents carries no secret annotations at all, so the full list of
--               authored boss abilities and their TankRole bits should read in the clear.
--               This is what tells a silent test apart from a broken one.
--   gate      : what the engine actually does to a texture whose icon bit is absent is
--               documented only as "atlases and alpha values" -- the absent case is not
--               specified, and Blizzard never reads these textures back. Run this on a live
--               boss with an ability on the timeline.
SLASH_NAOWHUITANK1 = "/nutank"
SlashCmdList["NAOWHUITANK"] = function(msg)
    local arg = (msg or ""):lower():match("^%s*(%S*)")
    ProbeCapabilities()
    RefreshSpec()

    if arg == "catalogue" or arg == "catalog" then
        if not (C_EncounterEvents and C_EncounterEvents.GetEventList) then
            ns.Print("C_EncounterEvents is not available on this client.")
            return
        end
        local ids = C_EncounterEvents.GetEventList()
        local total, tank, unreadable = 0, 0, 0
        for i = 1, #ids do
            local info = C_EncounterEvents.GetEventInfo(ids[i])
            if info then
                total = total + 1
                -- bit.band on a secret raises, so the read is pcall'd rather than trusted:
                -- the whole point of this probe is that the docs say these are plain and
                -- only the client can confirm it.
                -- Reduced to a plain number INSIDE the guard. Returning the comparison
                -- itself hands back a secret boolean that the branch below then throws on,
                -- outside the pcall, which is the guard catching nothing.
                local ok, isTankFlag = pcall(function()
                    return bit.band(info.icons, Enum.EncounterEventIconmask.TankRole) ~= 0
                        and 1 or 0
                end)
                if not ok then
                    unreadable = unreadable + 1
                elseif isTankFlag == 1 then
                    tank = tank + 1
                end
            end
        end
        ns.Print(("catalogue: %d events, %d tank-flagged, %d unreadable"):format(total, tank, unreadable))
        return
    end

    -- The decisive test for spoken callouts. A spell whose cooldown secrecy is NeverSecret
    -- keeps reading plainly THROUGH combat restrictions, because per-spell flags override
    -- them -- so if your defensives come back NeverSecret, voice works everywhere. If they
    -- are ContextuallySecret, voice is out-of-combat only and there is no way around it.
    -- Run this once at rest and once mid-pull; the restriction lines should differ.
    if arg == "secrecy" or arg == "voice" then
        local list = UserList(specID, false)
        if not (list and #list > 0) then
            ns.Print("no priority list for this spec yet -- add a defensive first.")
            return
        end
        if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType then
            local parts = {}
            for _, key in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch" }) do
                local rt = Enum.AddOnRestrictionType[key]
                if rt then
                    local on = C_RestrictedActions.IsAddOnRestrictionActive(rt)
                    parts[#parts + 1] = ("%s=%s"):format(key, on and "ON" or "off")
                end
            end
            ns.Print("restrictions: " .. table.concat(parts, "  "))
        end
        for i = 1, #list do
            local sid = list[i]
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            local level = "?"
            if C_Secrets and C_Secrets.GetSpellCooldownSecrecy and Enum.SecrecyLevel then
                local ok, lv = pcall(C_Secrets.GetSpellCooldownSecrecy, sid)
                if ok then
                    for name, value in pairs(Enum.SecrecyLevel) do
                        if value == lv then level = name break end
                    end
                end
            end
            ns.Print(("%d. %s -- secrecy=%s speakable_now=%s"):format(
                i, (info and info.name) or sid, level, tostring(CanNameSpellAloud(sid))))
        end
        return
    end

    -- Ahead of the status block, like every other subcommand: it sits in a separate file, so
    -- saying plainly that the file is missing beats printing nothing and looking dead.
    -- Does Blizzard actually flag YOUR defensives? The predicate is real, but which spell
    -- ids carry the flag is client data no source can answer. This dumps it for the spells
    -- the picker is offering, plus anything already on your list.
    if arg == "defensives" then
        local shown = 0
        local CV = C_CooldownViewer
        if CV and CV.GetCooldownViewerCategorySet and Enum and Enum.CooldownViewerCategory then
            for _, cat in ipairs({ Enum.CooldownViewerCategory.Essential,
                                  Enum.CooldownViewerCategory.Utility }) do
                local ids = CV.GetCooldownViewerCategorySet(cat, false)
                for i = 1, (ids and #ids or 0) do
                    local info = CV.GetCooldownViewerCooldownInfo(ids[i])
                    if info and info.isKnown then
                        local sid = info.spellID
                        local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                        local flag = false
                        if C_UnitAuras and C_UnitAuras.AuraIsBigDefensive then
                            local ok, v = pcall(C_UnitAuras.AuraIsBigDefensive, sid)
                            flag = ok and v and true or false
                        end
                        local ext = false
                        if C_Spell and C_Spell.IsExternalDefensive then
                            local ok2, v2 = pcall(C_Spell.IsExternalDefensive, sid)
                            ext = ok2 and v2 and true or false
                        end
                        shown = shown + 1
                        -- Everything the filter looks at, so a missing spell can be traced to
                        -- the signal that failed rather than guessed at.
                        ns.Print(("%s (%d) bigDef=%s ext=%s selfAura=%s hasAura=%s -> %s"):format(
                            (si and si.name) or "?", sid, tostring(flag), tostring(ext),
                            tostring(info.selfAura), tostring(info.hasAura),
                            ns.InfoIsDefensive(info) and "|cff6DD09AINCLUDED|r" or "|cffff6060skipped|r"))
                    end
                end
            end
        end
        if shown == 0 then
            ns.Print("the Cooldown Manager returned nothing -- open it once, then retry.")
        end
        return
    end

    -- Shows the alert exactly as a fight would, minus the tank gate. If the icon appears
    -- here but not on a boss, the display is fine and the gate is the variable. If it does
    -- not appear here either, the problem is the display itself.
    -- Mute and unmute act on the LAST callout rather than asking for a number, because the
    -- player has no way to know an ability's fingerprint and should not have to. "That one
    -- was wrong" is the whole interaction.
    if arg == "mute" or arg == "unmute" then
        if not lastFingerprint or not lastFingerprintEncounter then
            ns.Print("nothing to " .. arg .. " yet -- pull a boss and let a callout happen first.")
            return
        end
        local m = MutedTable(true, lastFingerprintEncounter)
        m[lastFingerprint] = (arg == "mute") or nil
        ns.Print(("%s the ability with fingerprint %s on encounter %s."):format(
            arg == "mute" and "Muted" or "Unmuted", lastFingerprint,
            tostring(lastFingerprintEncounter or "none")))
        ns.Print("Its callouts " .. (arg == "mute" and "will stop." or "are back on.")
            .. " Only this ability on this boss is affected.")
        return
    end

    -- The pair the player actually wants: name the tank busters once, per boss, and every
    -- other ability goes quiet at the same moment. The cue for WHEN to type it is already
    -- built: the game's own registered sound plays exactly once per pull, on the first tank
    -- buster -- so "I just heard the sound" means "the ability that just called out is one".
    if arg == "tank" or arg == "untank" then
        -- Both halves checked: a fingerprint without its encounter would file the mark
        -- under key 0, a boss that does not exist, where it silences nothing forever.
        if not lastFingerprint or not lastFingerprintEncounter then
            ns.Print("nothing to mark yet -- pull a boss and let a callout happen first.")
            return
        end
        local m = MarksTable(true, lastFingerprintEncounter)
        local had = next(m) ~= nil
        m[lastFingerprint] = (arg == "tank") or nil
        if arg == "tank" then
            ns.Print(("Marked fingerprint %s as a tank buster on encounter %s."):format(
                lastFingerprint, tostring(lastFingerprintEncounter or "none")))
            if not had then
                ns.Print("From now on ONLY marked abilities call out on this boss. Mark each "
                    .. "tank buster the same way; the game's own alert sound is your cue, it "
                    .. "plays once per pull on the first tank buster.")
            end
        else
            ns.Print(("Unmarked fingerprint %s on encounter %s."):format(
                lastFingerprint, tostring(lastFingerprintEncounter or "none")))
            if next(m) == nil then
                ns.Print("No marks left -- every ability calls out again on this boss.")
            end
        end
        return
    end

    if arg == "learn" then
        local t2 = TRDB()
        t2.learnMode = not t2.learnMode
        if t2.learnMode then
            ns.Print("learning mode ON: unknown bosses call out every timeline ability so "
                .. "you can mark the real busters with /nutank tank. Turn it off when done.")
        else
            ns.Print("learning mode off: unknown bosses stay quiet again.")
        end
        return
    end

    if arg == "marked" then
        local enc = lastFingerprintEncounter or currentEncounter
        local n = 0
        local m = MarksTable(false, enc)
        if m then
            for fp in pairs(m) do
                ns.Print(("  tank buster fingerprint %s (yours)"):format(fp))
                n = n + 1
            end
        end
        local shipped = ShippedMarks(enc)
        if shipped then
            for fp in pairs(shipped) do
                ns.Print(("  tank buster fingerprint %s (shipped)"):format(fp))
                n = n + 1
            end
        end
        if n == 0 then
            ns.Print("no marks on this boss -- every ability calls out. Type /nutank tank "
                .. "right after a tank buster callout to start narrowing it.")
        end
        return
    end

    -- Prints every player mark in the data file's own format, so authoring a dungeon pool
    -- is: run it, /nutank tank on each buster, /nutank export, paste.
    if arg == "export" then
        local t = TRDB()
        local any = false
        if type(t.tankMarks) == "table" then
            for encKey, fps in pairs(t.tankMarks) do
                if type(fps) == "table" and next(fps) ~= nil then
                    local parts = {}
                    for fp in pairs(fps) do
                        parts[#parts + 1] = ('["%s"] = true'):format(fp)
                    end
                    table.sort(parts)
                    ns.Print(("    [%s] = { %s },"):format(encKey, table.concat(parts, ", ")))
                    any = true
                end
            end
        end
        if not any then
            ns.Print("no marks to export yet -- /nutank tank on a tank buster callout first.")
        end
        return
    end

    if arg == "muted" then
        local m = MutedTable(false, lastFingerprintEncounter or currentEncounter)
        local n = 0
        if m then
            for fp in pairs(m) do
                ns.Print(("  muted fingerprint %s"):format(fp))
                n = n + 1
            end
        end
        ns.Print(("%d muted on encounter %s. Fingerprints are base durations in seconds; "):format(
            n, tostring(currentEncounter or "none"))
            .. "they identify an ability WITHIN a fight, never across fights.")
        return
    end

    if arg == "trace" then
        traceLeft = TRACE_EVENTS
        ns.Print(("armed for the next %d timeline events (build %s). The tank buster is "
            .. "rarely the first one, so pull and let a few land."):format(
            TRACE_EVENTS, TRACE_BUILD))
        return
    end

    if arg == "test" then
        if not TRDB().enabled then
            ns.Print("switch the reminder on first.")
            return
        end
        RefreshSpec()
        ns.Apply()
        if activeSlots == 0 then
            ns.Print("nothing on your priority list is talented, so there is nothing to show.")
            return
        end
        ns.ForceShowTest()
        ns.Print(("showing %d slot(s) for 5s with the tank filter bypassed. If you see nothing, "
            .. "the icon is hidden or off-screen -- try Reset Icon Position."):format(activeSlots))
        return
    end

    if arg == "bosses" then
        if ns.PrintBossSummary then
            ns.PrintBossSummary()
        else
            ns.Print("|cffff6060the boss browser did not load|r -- "
                .. "NaowhUI_TankReminder_Bosses.lua is missing from the addon folder.")
        end
        return
    end

    if arg == "gate" then
        if not canGate then
            ns.Print("SetEventIconTextures is not available on this client.")
            return
        end
        local list = C_EncounterTimeline.GetEventList and C_EncounterTimeline.GetEventList()
        if not (list and #list > 0) then
            ns.Print("no timeline events right now -- run this during a boss encounter.")
            return
        end
        local probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:SetSize(1, 1)
        probe:SetPoint("CENTER")
        probe:SetAlpha(1)
        for i = 1, math.min(#list, 3) do
            local id = list[i]
            local set = pcall(C_EncounterTimeline.SetEventIconTextures, id,
                Enum.EncounterEventIconmask.TankRole, { probe })
            -- Reading back is expected to fail: GetAlpha is SecretReturnsForAspect once the
            -- Alpha aspect is applied, and even issecretvalue/tostring may refuse a secret
            -- from tainted code. A refusal here is the gate WORKING -- it means the engine
            -- really did write the secret bit into our texture's alpha.
            local read, alpha = pcall(function() return tostring(probe:GetAlpha()) end)
            ns.Print(("gate: event %s -> set=%s read=%s"):format(
                tostring(id),
                set and "ok" or "REFUSED",
                read and alpha or "SECRET/refused (gate is live)"))
        end
        probe:SetTexture(nil)
        probe:Hide()
        return
    end

    ns.Print(("tank reminder: enabled=%s spec=%d tank=%s slots=%d"):format(
        tostring(TRDB().enabled), specID, tostring(isTank), activeSlots))
    if TRDB().learnMode then
        ns.Print("|cffF0A830Call Out Unknown Bosses is ON|r (Smart Reminders options page, "
            .. "under How It Tells You) -- every uncovered boss calls out on EVERY timeline "
            .. "ability, tank buster or not. /nutank learn turns it off.")
    end
    ns.Print(("timeline: available=%s bossWarnings=%s timelineDisplay=%s"):format(
        tostring(TimelineAvailable()),
        CombatWarningsOff() and "|cffff6060OFF|r" or "on",
        TimelineDisplayOff() and "off (fine -- data still flows)" or "on"))
    ns.Print(("engine: select=%s gate=%s bar=%s sound=%s"):format(
        tostring(canSelect and true or false), tostring(canGate and true or false),
        tostring(canBar and true or false), tostring(canSound and true or false)))
    ns.Print("usage: /nutank trace | learn | tank | untank | marked | export | mute | unmute | muted | test | catalogue | gate | secrecy | bosses | defensives")
end

-------------------------------------------------------------------------------
--  "Add a Defensive" picker
-------------------------------------------------------------------------------
-- Built from the player's OWN spellbook, not from any list we ship. Reading someone's
-- spellbook is reading their character, not shipping ability data, so this stays inside the
-- rule that the addon carries no encounter or class knowledge -- while sparing them from
-- hunting spell IDs on a website.
--
-- The filter is a heuristic, not a database: non-passive, on the active spec, with a real
-- base cooldown. GetSpellBaseCooldown is static data and stays readable when live cooldown
-- state is secret.
-- Blizzard classifies these for us, so the addon still ships no spell list of its own.
-- Two client sources, each supplying half the answer:
--
--   * the Cooldown Manager's category sets give a spec-correct, Blizzard-authored,
--     server-hotfixed list of the player's real cooldowns -- already free of passives,
--     off-spec entries and trinket noise. But its taxonomy is essential/utility, not
--     offensive/defensive: Barkskin and Berserk both sit in Essential.
--   * C_UnitAuras.AuraIsBigDefensive supplies the missing axis. It is the same predicate
--     Blizzard's own aura frames use to decide what counts as a big defensive, and its
--     ordering code shows the set includes self-cast defensives, not just externals.
--
-- Note it is an AURA flag, so the id carrying it can differ from the id you press. Every
-- candidate is tested on its cast id, its override, and its linked ids.
local MIN_BASE_CD_MS = 30000          -- only used by the no-Cooldown-Manager fallback

local bigDefCache = {}

-- Externals are flagged big-defensive too (Pain Suppression comes back true), but they are
-- cast on somebody else -- pressing one does not save you. C_Spell.IsExternalDefensive is
-- Blizzard's own split between the two, so the list stays "what I press for myself".
local function IsExternalDefensive(spellID)
    if not (C_Spell and C_Spell.IsExternalDefensive) then return false end
    local ok, v = pcall(C_Spell.IsExternalDefensive, spellID)
    return ok and v == true
end

local function IsBigDefensive(spellID)
    if not (spellID and spellID > 0) then return false end
    if bigDefCache[spellID] == nil then
        local ok, v = false, nil
        if C_UnitAuras and C_UnitAuras.AuraIsBigDefensive then
            ok, v = pcall(C_UnitAuras.AuraIsBigDefensive, spellID)
        end
        bigDefCache[spellID] = (ok and v and not IsExternalDefensive(spellID)) and true or false
    end
    return bigDefCache[spellID]
end

-- An external is cast on somebody else, so it never belongs in a "what do I press to save
-- myself" list. Checked across every id the cooldown carries, because the flag sits on the
-- aura and that is often not the id you press.
local function InfoIsExternal(info)
    if IsExternalDefensive(info.spellID) then return true end
    if info.overrideSpellID and IsExternalDefensive(info.overrideSpellID) then return true end
    local linked = info.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do
            if IsExternalDefensive(linked[i]) then return true end
        end
    end
    -- selfAura is false for anything whose aura lands on another player, which catches the
    -- externals Blizzard's own flag misses.
    if info.hasAura and info.selfAura == false then return true end
    return false
end

local function InfoIsDefensive(info)
    if InfoIsExternal(info) then return false end

    if IsBigDefensive(info.spellID) or IsBigDefensive(info.overrideSpellID) then return true end
    local linked = info.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do
            if IsBigDefensive(linked[i]) then return true end
        end
    end

    -- A selfAura+hasAura fallback was tried here and removed. Measured against a live
    -- Protection Paladin it contributed nothing: the real defensives (Divine Shield, Ardent
    -- Defender) both report hasAura=false, so the pair never fired, while loosening it to
    -- selfAura alone would have pulled in Consecration and Divine Steed. Blizzard's flag plus
    -- the external exclusion is what actually works; anything it misses (Lay on Hands, say)
    -- is one spell ID away in the editor.
    return false
end

-- Fallback for a client without the Cooldown Manager: the old spellbook sweep, still
-- narrowed by the defensive predicate where it is available.
-- Builds and SAVES a first priority list for a spec that has none: the Cooldown
-- Manager's big defensives, longest cooldown first, same classification the picker shows.
-- Saved rather than computed-per-fight so the options page shows exactly what runs and
-- the player's edits stick. Returns nil when the Cooldown Manager has nothing yet (early
-- login), so the next rebuild simply tries again.
function ns.SeedDefaultList(forSpec)
    local CV = C_CooldownViewer
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo
        and Enum and Enum.CooldownViewerCategory) then return nil end

    local found = {}
    for _, cat in ipairs({ Enum.CooldownViewerCategory.Essential,
                          Enum.CooldownViewerCategory.Utility }) do
        local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, false)
        if ok and ids then
            for i = 1, #ids do
                local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, ids[i])
                if okI and info and info.isKnown and InfoIsDefensive(info) then
                    local castID = info.overrideSpellID
                    if not castID or castID == 0 then castID = info.spellID end
                    if castID and not found[castID] then
                        local base = GetSpellBaseCooldown and GetSpellBaseCooldown(castID)
                        found[castID] = (type(base) == "number" and base) or 0
                        found[#found + 1] = castID
                    end
                end
            end
        end
    end
    if #found == 0 then return nil end

    table.sort(found, function(a, b) return (found[a] or 0) > (found[b] or 0) end)
    local out = {}
    for i = 1, #found do out[i] = found[i] end

    -- Saved into the active preset (creating one if this spec has never been touched),
    -- not a bare table, so the seed shows up as a real, editable list on the options page.
    local list = UserList(forSpec, true)
    wipe(list)
    for i = 1, #out do list[i] = out[i] end
    return list
end

local function CollectFromSpellbook(seen, list, out)
    if not (C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo
        and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank) then
        return
    end
    local havePredicate = C_UnitAuras and C_UnitAuras.AuraIsBigDefensive
    for line = 1, 12 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if not info then break end
        local offset, count = info.itemIndexOffset or 0, info.numSpellBookItems or 0
        for i = 1, count do
            local item = C_SpellBook.GetSpellBookItemInfo(offset + i, Enum.SpellBookSpellBank.Player)
            local sid = item and item.spellID
            if sid and not seen[sid] and not item.isPassive and not item.isOffSpec then
                seen[sid] = true
                local base = GetSpellBaseCooldown and GetSpellBaseCooldown(sid)
                local keep
                if pickerShowAll or not havePredicate then
                    keep = type(base) == "number" and base >= MIN_BASE_CD_MS
                else
                    keep = IsBigDefensive(sid)
                end
                if keep and not (list and ns.ListIndexOf(list, sid)) then
                    out[#out + 1] = {
                        id = sid, name = item.name or ("Spell " .. sid),
                        icon = item.iconID, cd = (type(base) == "number" and base) or 0,
                    }
                end
            end
        end
    end
end

-- nil = the spec default; set = a per-boss override. The picker is otherwise identical, so
-- one popup serves both rather than two that could drift apart.
local pickerEncounter

local function TargetList(create)
    if pickerEncounter then return BossList(specID, pickerEncounter, create) end
    return UserList(specID, create)
end

-- Set from the picker's own toggle. The defensive flag is Blizzard's data, and if it turns
-- out thin for a spec the player must still be able to find their spell -- so the filter is
-- the default, not a cage.
local pickerShowAll = false

-- When true the caller wants EVERY defensive, listed or not: the inline editor renders the
-- full set and lets a toggle decide membership.
local collectAll = false

ns.InfoIsDefensive = InfoIsDefensive

local function CollectCandidates()
    local out, seen = {}, {}
    local list = (not collectAll) and TargetList(false) or nil

    local CV = C_CooldownViewer
    if CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo
        and Enum and Enum.CooldownViewerCategory then
        for _, cat in ipairs({ Enum.CooldownViewerCategory.Essential,
                              Enum.CooldownViewerCategory.Utility }) do
            local ids = CV.GetCooldownViewerCategorySet(cat, false)
            for i = 1, (ids and #ids or 0) do
                local info = CV.GetCooldownViewerCooldownInfo(ids[i])
                if info and info.isKnown and (pickerShowAll or InfoIsDefensive(info)) then
                    -- The pressable id, which is the override when one is active.
                    local castID = info.overrideSpellID
                    if not castID or castID == 0 then castID = info.spellID end
                    if castID and not seen[castID] then
                        seen[castID] = true
                        local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(castID)
                        local base = GetSpellBaseCooldown and GetSpellBaseCooldown(castID)
                        if not (list and ns.ListIndexOf(list, castID)) then
                            out[#out + 1] = {
                                id   = castID,
                                name = (si and si.name) or ("Spell " .. castID),
                                icon = si and si.iconID,
                                cd   = (type(base) == "number" and base) or 0,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Nothing from the Cooldown Manager (older client, or data not loaded yet): sweep the
    -- spellbook instead rather than showing an empty picker.
    if #out == 0 then
        CollectFromSpellbook(seen, list, out)
    end

    table.sort(out, function(a, b)
        if a.cd ~= b.cd then return a.cd > b.cd end   -- longest cooldown first: the big buttons
        return a.name < b.name
    end)
    return out
end

local pickPopup
local ShowPicker

local function AddSpell(spellID)
    -- Every refusal is reported. A silent false here reads as a broken button.
    if specID == 0 then
        RefreshSpec()
        if specID == 0 then
            ns.Print("cannot tell which specialization you are in yet -- try again in a moment.")
            return false
        end
    end
    local cur = TargetList(true)
    if not cur then return false end
    if ListIndexOf(cur, spellID) then return false end
    if #cur >= MAX_SLOTS then
        ns.Print(("your list is full (%d maximum) -- remove one first."):format(MAX_SLOTS))
        return false
    end
    cur[#cur + 1] = spellID
    RebuildSlots()
    UpdateEventRegistration()
    UpdatePreview()
    return true
end

local function BuildPicker()
    if pickPopup then return pickPopup end

    local dimmer, panel = ns.MakeModal(380, 460)

    local title = ns.Font(panel, 14, "OUTLINE")
    title:SetPoint("TOP", panel, "TOP", 0, -16)
    title:SetText("Add a Defensive")

    local hint = ns.Font(panel, 11, nil, ns.THEME.muted)
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetPoint("LEFT", panel, "LEFT", 14, 0)
    hint:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    hint:SetJustifyH("CENTER")

    local toggle

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -68)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 52)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(300, 10)
    scroll:SetScrollChild(content)

    local rows = {}

    local function Refresh()
        local cands = CollectCandidates()
        for i = 1, #rows do rows[i]:Hide() end
        local y = 0
        for i = 1, #cands do
            local c = cands[i]
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(30)
                row:SetPoint("LEFT", content, "LEFT", 0, 0)
                row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                row.hl = ns.Solid(row, "BACKGROUND", ns.THEME.goldSoft, 0.10)
                row.hl:SetAllPoints(); row.hl:Hide()
                row.tex = row:CreateTexture(nil, "ARTWORK")
                row.tex:SetSize(24, 24)
                row.tex:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.name = ns.Font(row, 13, nil)
                row.name:SetPoint("LEFT", row.tex, "RIGHT", 8, 0)
                row.name:SetJustifyH("LEFT")
                row.cd = ns.Font(row, 12, nil, ns.THEME.muted)
                row.cd:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                rows[i] = row
            end
            row:SetPoint("TOP", content, "TOP", 0, -y)
            row.tex:SetTexture(c.icon)
            row.name:SetText(c.name)
            row.cd:SetText(("%ds"):format(math.floor(c.cd / 1000)))
            row:SetScript("OnEnter", function(self) self.hl:Show() end)
            row:SetScript("OnLeave", function(self) self.hl:Hide() end)
            row:SetScript("OnClick", function()
                if AddSpell(c.id) then
                    Refresh()
                    if pickPopup._onDone then pickPopup._onDone() end
                end
            end)
            row:Show()
            y = y + 30
        end
        content:SetHeight(math.max(y, 10))
        if #cands == 0 then
            hint:SetText(pickerShowAll
                and "Nothing left to add."
                or "No major defensives found. Try Show All Cooldowns.")
        else
            hint:SetText(pickerShowAll
                and "Every cooldown you have. Click one to add it."
                or "Your major defensives. Click one to add it to the bottom of the list.")
        end
    end

    pickPopup = { dimmer = dimmer, refresh = Refresh }

    toggle = ns.Button(panel, "Show All Cooldowns", 150, 22, function()
        pickerShowAll = not pickerShowAll
        Refresh()
    end)
    toggle:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 14)
    ns.Tooltip(toggle, "Show All Cooldowns",
        "The list is filtered to what the game marks as a major defensive. Turn this on to "
        .. "see every cooldown you have, in case something you want is not flagged.")

    ns.Button(panel, "Done", 110, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 14)

    return pickPopup
end

function ShowPicker(onDone)   -- forward-declared above; a global here would leak
    RefreshSpec()
    local p = BuildPicker()
    p._onDone = onDone
    p.refresh()
    p.dimmer:Show()
end

-------------------------------------------------------------------------------
--  Callout text editor
-------------------------------------------------------------------------------
-- A free-text box rather than a dropdown: the whole point is that the spoken line is
-- shorter than the spell name.
local textPopup

-- Two ways to be heard: pick a sound from EllesmereUI's alert catalogue, or type what should
-- be spoken. The dropdown carries a "Speak the text instead" entry, which is the no-sound
-- state -- so the two live on one control rather than needing a mode switch.
local function ShowCalloutEditor(title, current, onAccept, spellID)
    if not textPopup then
        local dimmer, panel = ns.MakeModal(400, 240)

        local head = ns.Font(panel, 14, "OUTLINE")
        head:SetPoint("TOP", panel, "TOP", 0, -16)

        local modeHolder = CreateFrame("Frame", nil, panel)
        modeHolder:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -46)
        modeHolder:SetSize(356, 22)

        -- The sound and text controls occupy the SAME slot: only one is ever shown, so
        -- stacking them keeps the dialog the same height either way.
        local soundLbl = ns.Font(panel, 11, nil, ns.THEME.muted)
        soundLbl:SetPoint("TOPLEFT", modeHolder, "BOTTOMLEFT", 0, -16)
        soundLbl:SetText("Sound")

        local ddHolder = CreateFrame("Frame", nil, panel)
        ddHolder:SetPoint("TOPLEFT", soundLbl, "BOTTOMLEFT", 0, -4)
        ddHolder:SetSize(356, 30)

        local textLbl = ns.Font(panel, 11, nil, ns.THEME.muted)
        textLbl:SetPoint("TOPLEFT", modeHolder, "BOTTOMLEFT", 0, -16)
        textLbl:SetText("Spoken text")

        -- The one hand-built widget: EllesmereUI's factory has no text input.
        local box = CreateFrame("EditBox", nil, panel)
        box:SetPoint("TOPLEFT", textLbl, "BOTTOMLEFT", 0, -4)
        box:SetSize(356, 28)
        box:SetAutoFocus(false)
        box:SetMaxLetters(60)
        box:SetFontObject("GameFontHighlight")
        box:SetTextInsets(6, 6, 0, 0)
        local well = ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1)
        well:SetAllPoints()
        ns.Border(box)

        textPopup = { dimmer = dimmer, panel = panel, box = box, head = head,
                      ddHolder = ddHolder, textLbl = textLbl,
                      modeHolder = modeHolder, soundLbl = soundLbl }

        local function Accept()
            -- Both halves land together on Save; picking a sound and then cancelling leaves
            -- nothing behind. Text mode clears the sound, which is what makes the radio the
            -- single source of truth for how this callout is heard.
            ns.SetSoundFor(textPopup._spellID,
                (textPopup._mode == "sound") and textPopup._soundKey or nil)
            dimmer:Hide()
            if textPopup._onAccept then textPopup._onAccept(box:GetText()) end
        end

        local hear = ns.Button(panel, "Hear it", 96, 26, function()
            local key = (textPopup._mode == "sound") and textPopup._soundKey or nil
            local EUI = _G.EllesmereUI
            if key and textPopup._paths and EUI and EUI._PlayLSMSound then
                EUI._PlayLSMSound(textPopup._paths[key])
            else
                Speak(box:GetText())
            end
        end)
        hear:SetPoint("BOTTOM", panel, "BOTTOM", -114, 16)
        ns.Tooltip(hear, "Hear it", "Plays it exactly as it will sound in a fight.")

        ns.Button(panel, "Save", 96, 26, Accept):SetPoint("BOTTOM", panel, "BOTTOM", -6, 16)
        ns.Button(panel, "Cancel", 96, 26, function() dimmer:Hide() end)
            :SetPoint("BOTTOM", panel, "BOTTOM", 102, 16)

        box:SetScript("OnEnterPressed", Accept)
        box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    end

    local tp = textPopup
    tp._onAccept = onAccept
    tp._spellID = spellID or 0
    tp.head:SetText(title or "Callout")
    tp.box:SetText(current or "")

    -- The dropdown is rebuilt per open: its choices depend on what SharedMedia has registered
    -- by now, and its callbacks close over this particular spell.
    if tp._dd then tp._dd:Hide(); tp._dd = nil end
    local paths, names, order = ns.SoundChoices()
    tp._paths = paths
    -- nil, not "none": the mode below is derived from this being set, and a placeholder
    -- string is truthy, which would open every callout in sound mode.
    tp._soundKey = ns.SoundFor(tp._spellID)

    -- Mode is explicit, so "I want a sound" and "I have not picked one yet" are different
    -- states rather than both reading as empty.
    tp._mode = tp._soundKey and "sound" or "text"
    tp._firstSound = order and order[1] or nil

    local EUI = _G.EllesmereUI
    local segRefresh

    local function Sync()
        local speaking = (tp._mode == "text")
        tp.box:SetShown(speaking)
        tp.textLbl:SetShown(speaking)
        if tp._dd then tp._dd:SetShown(not speaking) end
        tp.soundLbl:SetShown(not speaking)
        if segRefresh then segRefresh() end
    end
    tp._sync = Sync

    -- One switch, built once. On means spoken text, off means a sound file -- and only the
    -- control that actually applies is on screen, so there is never a dimmed widget inviting
    -- a click that does nothing.
    if not tp._modeToggle and EUI and EUI.BuildToggleControl then
        local tg, _, tgSnap = EUI.BuildToggleControl(tp.modeHolder,
            tp.modeHolder:GetFrameLevel() + 5,
            function() return tp._mode == "text" end,
            function(v)
                tp._mode = v and "text" or "sound"
                -- Switching to sound with nothing chosen takes the first one, so the mode is
                -- never left meaning nothing.
                if tp._mode == "sound" and not tp._soundKey then
                    tp._soundKey = tp._firstSound
                end
                if tp._sync then tp._sync() end
            end)
        tg:SetPoint("LEFT", tp.modeHolder, "LEFT", 0, 0)
        tp._modeToggle, tp._modeSnap = tg, tgSnap

        tp.modeLbl = ns.Font(tp.modeHolder, 12, nil)
        tp.modeLbl:SetPoint("LEFT", tg, "RIGHT", 10, 0)
        tp.modeLbl:SetText("Speak Text")
    end

    segRefresh = function()
        if tp._modeSnap then tp._modeSnap() end
    end

    if paths and EUI and EUI.BuildDropdownControl then
        tp._dd = EUI.BuildDropdownControl(tp.ddHolder, 356, tp.panel:GetFrameLevel() + 8,
            names, order,
            function() return tp._soundKey or tp._firstSound end,
            function(v)
                tp._soundKey = v   -- held until Save
                tp._mode = "sound"
                Sync()
            end)
        tp._dd:SetPoint("TOPLEFT", tp.ddHolder, "TOPLEFT", 0, 0)
    end
    Sync()

    tp.dimmer:Show()
    tp.box:SetFocus()
end

-------------------------------------------------------------------------------
--  Options (chained onto the companion's Gameplay page, or our own page standalone)
-------------------------------------------------------------------------------
-- Returns the raw running y, section-builder style, so the companion can chain us. Our own
-- standalone page wrapper is what takes math.abs of it.
function ns.BuildSection(parent, y)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "SMART REMINDERS", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Smart Reminders",
          tooltip = "Shows what to press when the boss timeline says an ability is about to land. "
          .. "It picks the highest entry on your own list that you have talented and off "
          .. "cooldown. Build that list below -- nothing is set up for you. Works on every "
          .. "specialization.",
          getValue = function() return TRDB().enabled end,
          setValue = function(v)
              TRDB().enabled = v
              ns.Apply()
              UpdatePreview()
              EUI:RefreshPage(true)
          end },
        -- "Only for Tank Abilities" lived here until the fingerprint data shipped. It was
        -- the engine's icon-only filter: it could not reach text or audio, so the channels
        -- disagreed with each other, and on covered bosses the fingerprint filter now does
        -- the same job for every channel at once. The stored tankOnly flag is ignored, not
        -- migrated, so downgrading does not lose it.
        { type = "toggle", text = "Only While I Have the Boss",
          tooltip = "For raids with two tanks: stay quiet when the boss is on the other tank. "
          .. "Checked at the moment the warning fires -- threat first, then the boss's actual "
          .. "target -- and whenever the game keeps the answer sealed the alert plays anyway, "
          .. "because a spare callout costs less than a silent tank buster. Solo content is "
          .. "unaffected: the boss is always on you.",
          getValue = function() return TRDB().aggroOnly end,
          setValue = function(v) TRDB().aggroOnly = v end }
    ); y = y - h

    -- Only worth saying when it is actually wrong. The timeline's own display toggle is
    -- deliberately not mentioned: boss-mod addons turn it off as a matter of course and the
    -- data keeps flowing, so flagging it would be a false alarm for a lot of people.
    if TRDB().enabled and CombatWarningsOff() then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "|cffff6060Boss Warnings are off in the game options.|r" },
            { type = "label", text = "Options, Advanced, Enable Boss Warnings." }
        ); y = y - h
    end

    _, h = W:SectionHeader(parent, "HOW IT TELLS YOU", y); y = y - h

    -- The countdown bar toggle lived here and was removed on tester feedback; the bar
    -- machinery stays for stored profiles that still have showBar set, it just cannot be
    -- switched on from the UI anymore.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show the Icon",
          tooltip = "The icon of the defensive to press.",
          getValue = function() return TRDB().showIcon end,
          setValue = function(v) TRDB().showIcon = v; ApplySize(); UpdatePreview() end },
        { type = "toggle", text = "Skip When Already Covered",
          tooltip = "Stays quiet when one of your defensives is already active with five or "
          .. "more seconds left as the warning fires -- you are covered, no need to stack "
          .. "another. When the game hides a buff's timing, the callout plays anyway.",
          getValue = function() return TRDB().coveredSkip ~= false end,
          setValue = function(v) TRDB().coveredSkip = v end }
    ); y = y - h

    -- This toggle used to lock itself while the engine tank filter was on, because a
    -- FontString cannot carry that filter and the text would have contradicted the icon.
    -- The fingerprint filter made the lock obsolete: it silences whole events upstream, so
    -- text is tank-only on covered bosses regardless -- and voice was never locked despite
    -- having the identical limitation, so the lock bought inconsistency, not honesty.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show a Text Callout",
          tooltip = "Writes the callout on screen -- \"Use Barkskin\" -- for whichever defensive "
          .. "it picked, and your fallback line when nothing is up. On bosses with tank buster "
          .. "data this appears only for tank busters. On bosses without data it appears for "
          .. "every timeline ability until the boss is learned or marked. Set each line in "
          .. "the list below.",
          getValue = function() return TRDB().showText end,
          setValue = function(v)
              TRDB().showText = v; ApplySize(); UpdatePreview()
          end },
        { type = "toggle", text = "Play a Sound",
          tooltip = "Plays a sound when a tank ability is coming. The game plays this one itself, "
          .. "which is the only way it can be limited to tank abilities -- but it also means the "
          .. "sound cannot know whether your defensive is ready. Watch the icon for that.|n|n"
          .. "|cffff6b5eIt plays at most ONCE per boss fight.|r The game will not repeat a "
          .. "registered sound, so a second cast of the same ability is silent. The icon is "
          .. "not affected and marks every cast.",
          getValue = function() return TRDB().soundOn end,
          setValue = function(v)
              TRDB().soundOn = v
              soundRegistered = false
              if v then RegisterEventSounds() end
              EUI:RefreshPage(true)
          end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Speak Which Defensive to Use",
          tooltip = "Says the callout for the defensive it picked, and your fallback line when "
          .. "nothing is up. On bosses with tank buster data this speaks only for tank "
          .. "busters; on bosses without it yet, it speaks for every timeline ability. In "
          .. "combat the pick comes from the addon's own tracking of your casts.",
          getValue = function() return TRDB().voiceOn end,
          setValue = function(v) TRDB().voiceOn = v; EUI:RefreshPage(true) end },
        { type = "slider", text = "Voice Volume", min = 0, max = 100, step = 5,
          tooltip = "Volume of the spoken callouts.",
          getValue = function() return TRDB().voiceVol or 100 end,
          setValue = function(v) TRDB().voiceVol = v end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Warn This Many Seconds Early", min = 1, max = 5, step = 1,
          tooltip = "How close to the hit the alert fires. The game announces abilities about "
          .. "five seconds out; the alert waits and fires this many seconds before impact, so "
          .. "lower is closer to the hit. When the game announces later than this, the alert "
          .. "fires immediately.",
          getValue = function() return TRDB().leadTime or 3 end,
          setValue = function(v) TRDB().leadTime = v end },
        { type = "toggle", text = "Call Out Unknown Bosses",
          tooltip = "Bosses with no tank buster data stay quiet by default (the alert sound "
          .. "still covers known busters). Turn this on while authoring a boss: every "
          .. "timeline ability calls out so you can mark the real busters, then turn it "
          .. "back off.",
          getValue = function() return TRDB().learnMode end,
          setValue = function(v) TRDB().learnMode = v end }
    ); y = y - h

    if TRDB().soundOn then
        local paths, names, order = EUI.BuildAlertSoundTables()
        if EUI.AppendSharedMediaSounds then EUI.AppendSharedMediaSounds(paths, names, order) end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Alert Sound",
              values = names, order = order,
              tooltip = "Sound files only. A few entries are built-in game sounds rather than "
              .. "files, and the game will not accept those for this.",
              getValue = function() return TRDB().soundKey or "none" end,
              setValue = function(v)
                  TRDB().soundKey = v
                  soundRegistered = false
                  if EUI._PlayLSMSound and paths[v] then EUI._PlayLSMSound(paths[v]) end
                  RegisterEventSounds()
              end },
            { type = "label", text = "Re-registers when you change it." }
        ); y = y - h

        if soundError then
            _, h = W:DualRow(parent, y,
                { type = "label", text = "|cffff6060" .. soundError .. "|r" },
                { type = "label", text = "" }
            ); y = y - h
        end
    end

    _, h = W:SectionHeader(parent, "SIZE AND PLACE", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Icon Size", min = 32, max = 128, step = 1,
          tooltip = "Size of the defensive icon. Independent of the text callout's size.",
          getValue = function() return TRDB().iconSize or DEFAULTS.iconSize end,
          setValue = function(v)
              TRDB().iconSize = v
              ApplySize()
              UpdatePreview()
          end },
        { type = "slider", text = "Text Size", min = 10, max = 40, step = 1,
          tooltip = "Size of the text callout -- the defensive name and fallback line. "
          .. "Independent of the icon's size.",
          getValue = function() return TRDB().textSize or DEFAULTS.textSize end,
          setValue = function(v)
              TRDB().textSize = v
              ApplySize()
              UpdatePreview()
          end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show a Preview",
          tooltip = "Puts a stand-in of the alert on screen while these options are open -- "
          .. "the icon and the text callout exactly as a fight would draw them. DRAG EITHER "
          .. "ONE to move it independently; each position saves instantly and Unlock Mode "
          .. "edits the same two spots, under the names Smart (icon) and Smart Text. It "
          .. "hides itself when the options close.",
          getValue = function() return previewPin end,
          setValue = function(v) previewPin = v; UpdatePreview() end },
        { type = "label", text = "" }
    ); y = y - h

    -- Escape hatch: a UI-scale change can strand a moved icon or text block off-screen
    -- where Unlock Mode cannot reach it.
    _, h = W:Button(parent, "Reset Icon Position", y, function()
        TRDB().pos = nil
        ApplyPosition()
    end)
    y = y - h

    _, h = W:Button(parent, "Reset Text Position", y, function()
        TRDB().textPos = nil
        ApplyTextPosition()
    end)
    y = y - h

    _, h = W:Button(parent, "Reset Custom Reminder Position", y, function()
        TRDB().customPos = nil
        ApplyCustomReminderPosition()
    end)
    y = y - h

    -- The player's own list for the current spec, in priority order. This addon ships no
    -- ability data, so an empty list here is the correct starting state -- the section says
    -- so rather than looking broken.
    _, h = W:SectionHeader(parent, "PRESET LIST (THIS SPEC)", y); y = y - h

    -- Left: the presets you have for this spec, and a way to add more. Right: the active
    -- one's list, every row condensed to a name, a switch, and a settings cog.
    if ns.RenderPresetListEditor then
        y = ns.RenderPresetListEditor(parent, y, W, EUI, specID)
    end

    return y
end

-- The whole page: the alert settings above, then the dungeon and raid tree from the other
-- file. Registered as its own sidebar entry rather than a section of Gameplay, so the tree
-- has room to breathe.
function ns.BuildPage(parent, yOffset)
    local EUI = _G.EllesmereUI
    if EUI.ClearContentHeader then EUI:ClearContentHeader() end
    RefreshSpec()   -- the list editors below are all keyed on it

    local y = ns.BuildSection(parent, yOffset)
    if ns.BuildTreeSection then
        y = ns.BuildTreeSection(parent, y)
    end
    return math.abs(y)
end

-- Shared with the boss tree page, which renders the same list editor for a per-boss
-- override as this page does for the spec default.
-- Every major defensive the player has, regardless of what is already on a list.
function ns.AllDefensives(forSpec, encounterID)
    RefreshSpec()
    local prevEnc, prevAll = pickerEncounter, collectAll
    pickerEncounter, collectAll = encounterID, true
    local ok, out = pcall(CollectCandidates)
    pickerEncounter, collectAll = prevEnc, prevAll
    return ok and out or {}
end

-- Adds or removes a spell from whichever list the editor is pointed at.
function ns.SetSpellOnList(forSpec, encounterID, spellID, on)
    RefreshSpec()
    local cur
    if encounterID then cur = BossList(forSpec, encounterID, true)
    else cur = UserList(forSpec, true) end
    if not cur then return false end

    local at = ListIndexOf(cur, spellID)
    if on then
        if at then return true end
        if #cur >= MAX_SLOTS then
            ns.Print(("that list is full (%d maximum) -- switch one off first."):format(MAX_SLOTS))
            return false
        end
        cur[#cur + 1] = spellID
    elseif at then
        table.remove(cur, at)
    end
    RebuildSlots()
    UpdateEventRegistration()
    UpdatePreview()
    return true
end

-- Moves an entry to a new position in its list.
function ns.MoveOnList(forSpec, encounterID, spellID, dest)
    local cur = encounterID and BossList(forSpec, encounterID, true) or UserList(forSpec, true)
    if not cur then return end
    local at = ListIndexOf(cur, spellID)
    if not at then return end
    table.remove(cur, at)
    if dest < 1 then dest = 1 end
    if dest > #cur + 1 then dest = #cur + 1 end
    table.insert(cur, dest, spellID)
    RebuildSlots()
    UpdateEventRegistration()
    UpdatePreview()
end

function ns.EffectiveListFor(forSpec, encounterID)
    if encounterID then return BossList(forSpec, encounterID, false) end
    return UserList(forSpec, false)
end

-- User-added spell IDs, per spec. The automatic list comes from Blizzard's classification;
-- this is the escape hatch for anything it misses.
function ns.CustomSpells(forSpec)
    local t = TRDB()
    if type(t.custom) ~= "table" then return nil end
    return t.custom[tostring(forSpec or 0)]
end

function ns.AddCustomSpell(forSpec, spellID)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if not info then
        ns.Print(("no spell with ID %s."):format(tostring(spellID)))
        return false
    end
    local t = TRDB()
    if type(t.custom) ~= "table" then t.custom = {} end
    local key = tostring(forSpec or 0)
    if type(t.custom[key]) ~= "table" then t.custom[key] = {} end
    t.custom[key][tostring(spellID)] = true
    ns.Print(("added %s (%d). Switch it on to put it in your priority."):format(
        info.name or "?", spellID))
    return true
end

function ns.RemoveCustomSpell(forSpec, spellID)
    local t = TRDB()
    local key = tostring(forSpec or 0)
    if type(t.custom) ~= "table" or type(t.custom[key]) ~= "table" then return end
    t.custom[key][tostring(spellID)] = nil
    if next(t.custom[key]) == nil then t.custom[key] = nil end
    if next(t.custom) == nil then t.custom = nil end
end

-- Removing an auto-populated ability cannot delete it -- Blizzard's classification will hand
-- it straight back on the next rebuild -- so removal is recorded as a hide instead. User-added
-- spells are deleted outright, since nothing regenerates those.
function ns.HiddenSpells(forSpec)
    local t = TRDB()
    if type(t.hidden) ~= "table" then return nil end
    return t.hidden[tostring(forSpec or 0)]
end

function ns.HideSpell(forSpec, spellID)
    local t = TRDB()
    if type(t.hidden) ~= "table" then t.hidden = {} end
    local key = tostring(forSpec or 0)
    if type(t.hidden[key]) ~= "table" then t.hidden[key] = {} end
    t.hidden[key][tostring(spellID)] = true
end

function ns.UnhideAll(forSpec)
    local t = TRDB()
    if type(t.hidden) ~= "table" then return end
    t.hidden[tostring(forSpec or 0)] = nil
    if next(t.hidden) == nil then t.hidden = nil end
end

-- A spell ID resolves to a real spell. Used to gate the Add button as the user types.
function ns.ResolveSpell(text)
    local sid = tonumber(text and tostring(text):match("^%s*(%d+)%s*$"))
    if not sid or sid <= 0 then return nil end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    if not info then return nil end
    return sid, info
end

-- Per-spell audio. On unless switched off, so nothing has to be migrated and a fresh list
-- speaks by default. Spell ID 0 is the "nothing is up" fallback line.
function ns.IsAudioOff(spellID)
    local a = TRDB().audioOff
    return a ~= nil and a[tostring(spellID or 0)] == true
end

function ns.SetAudioOff(spellID, off)
    local t = TRDB()
    local key = tostring(spellID or 0)
    if off then
        if type(t.audioOff) ~= "table" then t.audioOff = {} end
        t.audioOff[key] = true
    elseif type(t.audioOff) == "table" then
        t.audioOff[key] = nil
        if next(t.audioOff) == nil then t.audioOff = nil end
    end
end

-- A callout is either a sound file or spoken text. Storing only the sound key keeps the
-- text intact underneath, so switching back to speech does not lose what was typed.
function ns.SoundFor(spellID)
    local t = TRDB().sounds
    local key = t and t[tostring(spellID or 0)]
    if key == nil or key == "none" then return nil end
    return key
end

function ns.SetSoundFor(spellID, key)
    local t = TRDB()
    local id = tostring(spellID or 0)
    if key and key ~= "none" then
        if type(t.sounds) ~= "table" then t.sounds = {} end
        t.sounds[id] = key
    elseif type(t.sounds) == "table" then
        t.sounds[id] = nil
        if next(t.sounds) == nil then t.sounds = nil end
    end
end

-- Fresh tables per call: EllesmereUI's SharedMedia appender mutates in place and caches by
-- table identity, so handing the same tables to two dropdowns collapses them into one.
function ns.SoundChoices()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.BuildAlertSoundTables) then return nil end
    local paths, names, order = EUI.BuildAlertSoundTables()
    if EUI.AppendSharedMediaSounds then EUI.AppendSharedMediaSounds(paths, names, order) end
    -- The speech option used to live in here as a pseudo-sound. It is a radio now, so the
    -- dropdown lists sounds and nothing else.
    names["none"] = nil
    for i = #order, 1, -1 do
        if order[i] == "none" then table.remove(order, i) end
    end
    return paths, names, order
end

ns.DB            = TRDB
ns.UserList      = UserList
ns.BossList      = BossList
ns.ClearBossList = ClearBossList
ns.ListIndexOf   = ListIndexOf
ns.CalloutFor    = CalloutFor
ns.SetCallout    = SetCallout
ns.IsSpellDisabled  = IsSpellDisabled
ns.SetSpellDisabled = SetSpellDisabled
ns.IsSpellAvailable = IsSpellAvailable
ns.ShowPicker    = function(onDone) pickerEncounter = nil; ShowPicker(onDone) end
ns.ShowPickerFor = function(_, encounterID, onDone)
    pickerEncounter = encounterID
    ShowPicker(function()
        pickerEncounter = nil
        if onDone then onDone() end
    end)
end
ns.ShowCalloutEditor = function(...) return ShowCalloutEditor(...) end
ns.MAX_SLOTS     = MAX_SLOTS
function ns.CurrentSpec() return specID, isTank end
function ns.RefreshRuntime()
    RebuildSlots()
    RebuildCastMap()
    UpdateEventRegistration()
    UpdatePreview()
    RefreshCustomRemindersFlag()
end

-------------------------------------------------------------------------------
--  Reset / re-apply
-------------------------------------------------------------------------------
-- Re-apply is owned by the core's QueueReapply, which hooks EllesmereUI's own profile and
-- spec-switch entry points. The companion's RegisterReapply chain is deliberately NOT used:
-- it reapplies the companion's DB, and ours is a separate one it knows nothing about.

function ns.Reset()
    HideReminder()
    activeSlots = 0
    soundRegistered = false
    ns.SettingsRoot().tankReminder = nil
    ApplySize()        -- the saved size and position went with the table
    ApplyPosition()
    ApplyTextPosition()
    UpdateEventRegistration()
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")

watcher:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        -- Dying and running back resets much of a kit, and the model cannot see that. Drop
        -- the estimates and re-read whatever is readable now.
        wipe(readyAt)
        ResyncModel()
        return
    end

    if event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        currentEncounter = (event == "ENCOUNTER_START") and arg1 or nil
        -- A silent dungeon must cost one chat line to diagnose, not a run. If the feature
        -- is on but any gate is closed when a boss starts, say WHICH, once. Every earlier
        -- "nothing came up" report burned a full run because this line did not exist.
        -- Event ids are per-instance and get reused, so a stale entry would answer for a
        -- different ability entirely on the next pull.
        WipeEventCache()
        -- A fight that had data for this boss, saw abilities, and called nothing is the
        -- report that has been costing whole pulls to diagnose: the trace has to be armed
        -- before the ability lands, and the tank buster is rarely the first event. Say it
        -- after the fact instead, with the fingerprints it actually saw -- those are what
        -- /nutank tank marks, so the message doubles as the fix.
        if event == "ENCOUNTER_END" and TRDB().enabled == true
            and calloutsThisFight == 0 and next(silencedFingerprints) ~= nil
            -- arg1, not currentEncounter: the line above already cleared that to nil for
            -- ENCOUNTER_END, so keying the latch off it would file every boss under 0 and
            -- report exactly once per session for the whole game.
            and activeSlots > 0 and not noCalloutNotice[arg1 or 0] then
            noCalloutNotice[arg1 or 0] = true
            local list = {}
            for fp in pairs(silencedFingerprints) do list[#list + 1] = fp end
            table.sort(list, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
            ns.Print(("|cffff6060no callouts this fight|r. Abilities seen, none marked as "
                .. "tank busters: %s. If one of those WAS the tank hit, /nutank tank marks "
                .. "it."):format(table.concat(list, ", ")))
        end
        if event == "ENCOUNTER_END" then wipe(readyAt) end
        wipe(silencedFingerprints)
        calloutsThisFight = 0
        lastAnnouncedSpellID = nil
        RebuildSlots()          -- swap to this boss's list before the first ability lands
        RebuildCastMap()
        UpdateEventRegistration()   -- this boss may be switched off entirely

        -- Custom reminders: a fresh pull means a fresh count for the "Nth cast" counter,
        -- and the coverage flag has to catch up before the pull trigger itself can fire.
        -- Boss-mod arbitration and any bar-timeleft activations scheduled on the last
        -- pull reset the same way -- a stale pending timer must never survive into the
        -- next attempt.
        wipe(customCounters)
        bwActiveMod = nil
        for k, handle in pairs(bwPendingTimers) do
            if handle.Cancel then handle:Cancel() end
            bwPendingTimers[k] = nil
        end
        RefreshCustomRemindersFlag()
        if event == "ENCOUNTER_START" then
            RegisterBossModHooks()   -- in case BigWigs/DBM loaded after this addon did
            CheckCustomReminders("pull", nil)
        end

        -- The gate report BELOW the rebuild, never above it: it reads activeSlots, and
        -- until RebuildSlots runs those are the previous list's. A spec whose default list
        -- is empty but whose per-boss list is not was warned "no priority list" on every
        -- pull, about a state that stopped being true one line later.
        if event == "ENCOUNTER_START" and TRDB().enabled == true then
            local why
            if not canSelect then why = "this client lacks the cooldown API"
            elseif activeSlots == 0 then why = "no priority list for this spec (or nothing on it is talented)"
            elseif not TimelineAvailable() then why = "the boss timeline feature is unavailable here"
            elseif not AllowedHere() then why = "dungeons/raids toggle excludes this instance"
            elseif not BossAllowed() then why = "this boss is switched off in Smart Reminders"
            end
            if not why then
                local t2 = TRDB()
                if not (t2.showIcon or t2.showText or t2.voiceOn or t2.soundOn) then
                    why = "icon, text, voice and sound are ALL switched off"
                elseif not (t2.showIcon or t2.showText or t2.voiceOn)
                    and not saidAudioOnly then
                    -- A reminder for a legitimate configuration, so once per session; the
                    -- true all-off state above stays per boss because it is always wrong.
                    saidAudioOnly = true
                    why = "only Play a Sound is on: expect one beep per ability per pull, "
                        .. "nothing else"
                end
            end
            if why then
                ns.Print("|cffff6060not running this fight|r: " .. why)
            end
        end

        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        NoteOwnCast(arg3)   -- (unit, castGUID, spellID); unit is always "player" here
        return
    end

    if event == "PLAYER_REGEN_ENABLED" or event == "SPELL_UPDATE_COOLDOWN" then
        ResyncModel()
        -- A combat log toggle skipped because of combat lockdown lands here.
        if event == "PLAYER_REGEN_ENABLED" then UpdateEventRegistration() end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local okL, errL = pcall(OnCombatLog)
        if not okL and traceLeft > 0 then
            ns.Print("|cffff6060combat log watch failed|r: " .. ErrText(errL))
        end
        return
    end

    if event == "UNIT_SPELLCAST_START" then
        if type(arg1) == "string" and arg1:match("^boss%d+$") then
            local okC, err = pcall(OnBossCast, arg1)
            if not okC and traceLeft > 0 then
                ns.Print("|cffff6060cast watch failed|r: " .. ErrText(err))
            end
        end
        return
    end

    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        -- The one moment the struct is in hand. Recorded now so the highlight, which
        -- arrives with nothing but an id, does not have to guess.
        NoteEventAdded(arg1)
        return
    end

    if event == "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT" then
        -- Boss abilities ONLY. The timeline also carries Script events, which is what a
        -- respawn timer is and what other addons add through the scripting API, plus
        -- EditMode layout previews. Reacting to those calls a defensive with no boss in
        -- the room, which is exactly how it was reported.
        --
        -- `source` is one of the four NeverSecret fields on the event struct, so this is
        -- a plain comparison. An unknown source is treated as an encounter event: the
        -- only way to get one is a reload mid-pull, and being late to a real boss ability
        -- is worse than being early to somebody else's timer.
        if ShouldRun() and InEncounter() and IsEncounterSourced(arg1) then
            -- The engine announces at its own lead (about five seconds); the player picks
            -- how close to the hit the alert fires. The wait is a timer rather than a
            -- reread of the event clock, which accepts a small drift if the timeline
            -- pauses inside the window -- rare, and a paused timeline usually means the
            -- ability is not landing on schedule anyway.
            local eventID = arg1
            local engineLead = 5
            if C_EncounterTimeline.GetEventHighlightTime then
                local v = C_EncounterTimeline.GetEventHighlightTime()
                if type(v) == "number" and v > 0 then engineLead = v end
            end
            local want = TRDB().leadTime or 3
            local delay = (want > 0 and want < engineLead) and (engineLead - want) or 0
            if delay > 0.1 then
                CancelPendingShow(eventID)
                pendingShow[eventID] = C_Timer.NewTimer(delay, function()
                    pendingShow[eventID] = nil
                    ShowForEvent(eventID)
                end)
            else
                ShowForEvent(eventID)
            end
        end
        return
    end

    if event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        -- Plain comparison: event IDs are NeverSecret.
        if shownForEvent ~= nil and arg1 == shownForEvent then HideReminder() end
        ForgetEvent(arg1)
        return
    end

    if event == "PLAYER_LOGIN" then
        RegisterUnlock()
        RegisterBossModHooks()
        local EUI = _G.EllesmereUI
        if EUI and EUI.RegisterOnShow then
            EUI:RegisterOnShow(function() previewing = true; UpdatePreview() end)
        end
        if EUI and EUI.RegisterOnHide then
            EUI:RegisterOnHide(function() previewing = false; UpdatePreview() end)
        end
        -- The two CVars that decide whether data flows. Blizzard already marks them cachable,
        -- so this piggybacks rather than polling. We only ever READ them.
        if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
            for _, cvar in ipairs({ "combatWarningsEnabled", "encounterTimelineEnabled" }) do
                pcall(function()
                    CVarCallbackRegistry:RegisterCallback(cvar, function() ns.Apply() end, watcher)
                end)
            end
        end
        C_Timer.After(1, function() ns.Apply() end)
        return
    end

    ns.Apply()
end)
