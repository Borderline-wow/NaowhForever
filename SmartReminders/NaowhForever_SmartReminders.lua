-------------------------------------------------------------------------------
--  NaowhForever_SmartReminders.lua -- the Smart Reminders module: shows which defensive to
--  press when Blizzard's encounter timeline says a tank ability is about to land.
--
--  "Is this a tank hit" (the TankRole icon bit) and "is this spell ready" (cooldown state)
--  are both secret in instanced combat, so the pick is handed to the engine: a chain of
--  C_CurveUtil.EvaluateColorValueFromBoolean (AllowedWhenTainted in all arguments) feeds
--  SetAlpha and the answer never reaches Lua.
--  The engine's tank gate (SetEventIconTextures) reaches textures only, never a FontString,
--  hence the fingerprint filter -- see ClearTankGate.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
if not ns then return end

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
-- Flat scalars only: a nested default would hand out a live reference to DEFAULTS itself.
-- Everything ships off by the owner's direction; until enabled, no events or frames exist.
local DEFAULTS = {
    enabled   = false,
    showIcon  = false,
    showText  = false,
    showBar   = false,
    soundOn   = false,
    soundKey  = "none",
    fallbackOn = false,
    coveredSkip = false,
    coveredCastWindow = 6,   -- how long your own cast counts as cover
    leadTime   = 3,     -- seconds before impact that the alert fires
    lingerSec  = 3,     -- display duration; early dismissal on cast is opt-in
    cdmGlow    = false, -- glow the called defensive on the Cooldown Manager bar
    voiceOn   = false,
    voiceNone = "Call for external",
    externalChat = false,
    voiceVol  = 100,
    iconSize  = 64,
    -- 21 matches the old derived floor(iconSize * 0.34) at the default iconSize of 64.
    textSize   = 21,
    textSide   = "BOTTOM",   -- TOP, BOTTOM, LEFT or RIGHT
    -- bossSource ("timeline", "bigwigs" or "dbm") has no default: unset follows the
    -- installed boss mod, see ns.BossSource().
    -- pos = { point, relPoint, x, y } once moved in Unlock Mode; nil = default centre.
}

-- Profile tables already migrated and default-filled. Keyed by table so nothing lands in
-- SavedVariables; per table, not once at init, because SettingsRoot() follows profile switches.
local prepared = setmetatable({}, { __mode = "k" })

local function TRDB()
    local root = ns.SettingsRoot()
    if type(root.tankReminder) ~= "table" then root.tankReminder = {} end
    local t = root.tankReminder
    if prepared[t] then return t end
    prepared[t] = true
    -- Migration: the pre-presets flat list per spec becomes that spec's "Default" preset.
    if type(t.lists) == "table" and next(t.lists) ~= nil and type(t.presets) ~= "table" then
        t.presets = {}
        t.activePreset = t.activePreset or {}
        for specKey, list in pairs(t.lists) do
            t.presets[specKey] = { p1 = { name = "Default", list = list } }
            t.activePreset[specKey] = "p1"
        end
        t.lists = nil
    end
    -- The text used to be positioned on its own; it rides the icon now.
    t.textPos = nil
    -- Broadcasts outside any encounter used to be catalogued under "0", which nothing reads.
    if type(t.bwCatalogue) == "table" then t.bwCatalogue["0"] = nil end
    -- Older builds pre-filled the callout editor with "Use <name>", so saved callouts still
    -- carry the prefix the spoken default dropped.
    if type(t.callouts) == "table" then
        for id, text in pairs(t.callouts) do
            local bare = type(text) == "string" and text:match("^[Uu]se%s+(.+)$")
            if bare then t.callouts[id] = bare end
        end
    end
    -- Call Together was briefly stored as a chain to the entry below; nothing reads it now.
    if type(t.presets) == "table" then
        for _, specPresets in pairs(t.presets) do
            if type(specPresets) == "table" then
                for _, p in pairs(specPresets) do
                    if type(p) == "table" then p.chain = nil end
                end
            end
        end
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
-- The addon ships no ability data; the player builds (or imports) the priority order and
-- everything at runtime comes from Blizzard's encounter timeline. Only the active preset's
-- list is "the" spec default anywhere else in this file.
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

local function ActivePresetKey(forSpec)
    local t = TRDB()
    local presets = PresetsTable(forSpec, false)
    if not presets then return nil end
    local key = tostring(forSpec or 0)
    local a = type(t.activePreset) == "table" and t.activePreset[key]
    if a and presets[a] then return a end
    a = next(presets)
    if a then
        if type(t.activePreset) ~= "table" then t.activePreset = {} end
        t.activePreset[key] = a
    end
    return a
end
ns.ActivePresetKey = ActivePresetKey

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

-- A nameless preset is malformed, so it shows as a visible placeholder, never the bare key.
function ns.ListPresets(forSpec)
    local presets = PresetsTable(forSpec, false)
    local out = {}
    if not presets then return out end
    for key, p in pairs(presets) do
        local name = p.name
        if type(name) ~= "string" or name == "" then name = "(unnamed " .. key .. ")" end
        out[#out + 1] = { key = key, name = name }
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function ns.PresetList(forSpec, presetKey)
    local presets = PresetsTable(forSpec, false)
    local p = presets and presetKey and presets[presetKey]
    return p and type(p.list) == "table" and p.list or nil
end

function ns.NextPresetName(forSpec)
    local presets = PresetsTable(forSpec, false)
    local used = {}
    if presets then
        for _, p in pairs(presets) do
            if p.name then used[p.name] = true end
        end
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

-- Refuses the last preset: EnsureActivePreset would just recreate an empty one.
function ns.DeletePreset(forSpec, presetKey)
    local presets = PresetsTable(forSpec, false)
    if not presets or not presets[presetKey] then return false end
    local count = 0
    for _ in pairs(presets) do count = count + 1 end
    if count <= 1 then return false end
    local t = TRDB()
    for _, set in pairs(t.customReminders or {}) do
        for _, r in pairs(set) do
            if r.preset == presetKey and (not r.specID or r.specID == forSpec) then
                ns.Print("Reassign or delete reminder '" .. (r.name or "Reminder")
                    .. "' before deleting this preset.")
                return false
            end
        end
    end
    presets[presetKey] = nil
    local key = tostring(forSpec or 0)
    if type(t.activePreset) == "table" and t.activePreset[key] == presetKey then
        t.activePreset[key] = nil
    end
    ActivePresetKey(forSpec)
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

-- One Call Together group per preset: when the pick lands on a member, every other ready
-- member is named alongside it. Keyed by spell id so drag-reorder needs no repair.
-- ns functions rather than chunk locals: this file is at the 200-local ceiling.
function ns.CalledTogetherInPreset(forSpec, presetKey, spellID)
    if not presetKey then return false end
    local presets = PresetsTable(forSpec, false)
    local p = presets and presets[presetKey]
    return (p and type(p.together) == "table" and p.together[tostring(spellID)]) == true
end

function ns.CalledTogether(forSpec, spellID)
    return ns.CalledTogetherInPreset(forSpec, ActivePresetKey(forSpec), spellID)
end

function ns.SetCalledTogether(forSpec, spellID, on)
    local presetKey = EnsureActivePreset(forSpec)
    if not presetKey then return end
    local presets = PresetsTable(forSpec, true)
    local p = presets and presets[presetKey]
    if not p then return end
    if type(p.together) ~= "table" then p.together = {} end
    p.together[tostring(spellID)] = on and true or nil
end

-- Per-boss overrides keyed spec:dungeonEncounterID, the id both ENCOUNTER_START and the
-- journal report. An empty or absent boss list falls back to the spec default.
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

-- nil means nothing was picked for this boss; the active preset applies (see EffectiveList).
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

-- Spoken line per spell. Defaults to the spell name; the point of storing an override is
-- that "Incarnation: Guardian of Ursoc" is not what anyone says out loud.
local function CalloutFor(spellID, spellName)
    local c = TRDB().callouts
    local custom = c and c[spellID]
    if type(custom) == "string" and custom ~= "" then return custom end
    -- No "Use " prefix: cut on tester feedback as latency.
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

-- From ENCOUNTER_START (encounter ids are not secret); nil outside a boss fight.
local currentEncounter

-- BigWigs' stage number from its BigWigs_SetStage broadcast, reset every pull. Declared
-- here because RecordBossModKey, which reads it, is defined before bwActiveMod.
local currentStage
-- GetTime() stamps. Later phases are health-gated, so only phase-relative times are reliable.
local currentStageAt
local currentEncounterStartedAt
local currentDifficultyID

-- The ability's own preset (fp is its spellID as a string), else the boss's preset, else
-- the spec default.
local function EffectiveList(forSpec, encounterID, fp, presetOverride)
    if presetOverride then
        local presets = PresetsTable(forSpec, false)
        local preset = presets and presets[presetOverride]
        return preset and preset.list, true, presetOverride
    end
    if encounterID and fp then
        local sid = tonumber(fp)
        local binding = sid and ns.BindingForBossModKey and ns.BindingForBossModKey(encounterID, sid)
        if binding and binding.preset then
            local presets = PresetsTable(forSpec, false)
            local p = presets and presets[binding.preset]
            if p and type(p.list) == "table" and #p.list > 0 then
                return p.list, true, binding.preset
            end
        end
        -- Legacy per-ability raw list ("encounter#fingerprint"): still read, never written.
        local al = BossList(forSpec, tostring(encounterID) .. "#" .. fp, false)
        if al and #al > 0 then return al, true, nil end
    end
    if encounterID then
        local explicit = BossPresetKey(forSpec, encounterID)
        local presetKey = explicit or ActivePresetKey(forSpec)
        if presetKey then
            local presets = PresetsTable(forSpec, false)
            local p = presets and presets[presetKey]
            if p and type(p.list) == "table" and #p.list > 0 then
                return p.list, explicit ~= nil, presetKey
            end
        end
    end
    return UserList(forSpec, false), false, ActivePresetKey(forSpec)
end
ns.EffectiveList = EffectiveList

-- Cap on built slots and list length. Sizing must never read a secret.
local MAX_SLOTS = 8

-------------------------------------------------------------------------------
--  Capability gate
-------------------------------------------------------------------------------
-- A client missing any of these leaves the feature inert instead of erroring per ability.
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

-- The only check that may gate event registration. Never IsFeatureEnabled(): it folds in
-- CVars, the events fire regardless, and a popular boss mod forces encounterTimelineEnabled 0.
local function TimelineAvailable()
    return C_EncounterTimeline ~= nil
        and C_EncounterTimeline.IsFeatureAvailable ~= nil
        and C_EncounterTimeline.IsFeatureAvailable()
end

-- Diagnostic only, never written (boss mods already fight over it). The CVar gates only
-- Blizzard's timeline frame: at 0 events still arrive and sounds still play, measured live.
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
-- Choosing a spoken line is a Lua branch on readiness, and no speech API takes a secret
-- selector, so naming is only lawful when the cooldown is not secret: in practice out of
-- combat, unless the spell carries NeverSecret (/nutank secrecy measures it). The predicate
-- returns a plain boolean, as in Blizzard_AuraContainerUtil. HasSecretRestrictions() is not
-- the check: it reports the build, not live restrictions.
local function CanNameSpellAloud(spellID)
    if not (C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret) then return false end
    local ok, secret = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
    return ok and secret == false
end

local function SecrecyLevelName(spellID)
    if not (C_Secrets and C_Secrets.GetSpellCooldownSecrecy and Enum.SecrecyLevel) then
        return "?"
    end
    local ok, lv = pcall(C_Secrets.GetSpellCooldownSecrecy, spellID)
    if not ok then return "?" end
    for name, value in pairs(Enum.SecrecyLevel) do
        if value == lv then return name end
    end
    return "?"
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
-- Role from the spec: UnitGroupRolesAssigned returns "NONE" while ungrouped.
local specID, isTank = 0, false

-- playerRole/playerClass live on ns: this chunk is at Lua's 200-local ceiling.
local function RefreshSpec()
    specID, isTank = 0, false
    ns.playerRole = nil
    ns.playerClass = select(2, UnitClass("player"))
    if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then return end
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then return end
    local id, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(index)
    specID = id or 0
    isTank = (role == "TANK")
    ns.playerRole = role
    -- Through ns: the migration is defined further down the file.
    if ns.MigrateBindingScopes then ns.MigrateBindingScopes() end
end

function ns.CurrentRole() return ns.playerRole end
function ns.CurrentClass() return ns.playerClass end

-------------------------------------------------------------------------------
--  The display
-------------------------------------------------------------------------------
local Reminder = {}
local frame, slots = nil, {}
-- Anchor for the text callout. slot.label stays parented to its slot (riding the secret
-- alpha); only its anchor target is textFrame.
local textFrame
local bar
local activeSlots = 0           -- how many slots the current spec actually uses
local hideTimer
local shownForEvent

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

-- Not in DEFAULTS: the shallow fill would share one color table across every profile.
local function DefensiveTextColor()
    local c = TRDB().defensiveTextColor
    return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1
end


local BAR_DROP, BAR_HEIGHT = 26, 10

local TEXT_GAP = 6
local REMINDER_SIZE = 15

local Look = { TEXT_GAP = TEXT_GAP }
ns.DefensiveLook = Look

function Look.TextColour()
    if TRDB().defensiveTextColorOn then return DefensiveTextColor() end
    return 1, 1, 1, 1
end

function Look.PlaceText(block, icon, side, drop)
    if side == "TOP" then
        block:SetPoint("BOTTOM", icon, "TOP", 0, TEXT_GAP)
        return "BOTTOM", 1
    elseif side == "LEFT" then
        block:SetPoint("RIGHT", icon, "LEFT", -TEXT_GAP, 0)
        return "RIGHT", 1
    elseif side == "RIGHT" then
        block:SetPoint("LEFT", icon, "RIGHT", TEXT_GAP, 0)
        return "LEFT", 1
    end
    block:SetPoint("TOP", icon, "BOTTOM", 0, -(TEXT_GAP + drop))
    return "TOP", -1
end

function Look.Icon(parent)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(parent, { r = 0, g = 0, b = 0 }, 1)
    return icon
end

-- Must color the slot labels as well as frame.reminder: coloring only the latter shipped
-- first and the toggle looked like it did nothing, since the labels are what shows in combat.
local function ApplyDefensiveTextColor()
    if not frame then return end
    local r, g, b, a = Look.TextColour()

    if frame.reminder then frame.reminder:SetTextColor(r, g, b, a) end
    for i = 1, #slots do
        if slots[i].label then slots[i].label:SetTextColor(r, g, b, a) end
    end
end

-- Every line hangs off the same anchor so a hidden line collapses to nothing. The near edge
-- is anchored, never the centre, which grew both ways and crept into the icon.
local function ApplyTextLayout()
    if not (frame and textFrame) then return end
    local t = TRDB()
    local side = t.textSide or DEFAULTS.textSide
    local line = (t.textSize or DEFAULTS.textSize) + 4

    textFrame:ClearAllPoints()
    -- The bar's toggle is gone from the UI but a stored showBar outlives it.
    local point, dir = Look.PlaceText(textFrame, frame, side, t.showBar and (BAR_DROP + BAR_HEIGHT) or 0)

    local function place(fs, offset)
        if not fs then return end
        fs:ClearAllPoints()
        fs:SetPoint(point, textFrame, point, 0, dir * offset)
    end
    for i = 1, #slots do place(slots[i].label, 0) end
    place(frame.fallback, 0)
    place(frame.reminder, line)
    place(frame.learnTag, line * 2 + REMINDER_SIZE + 4)

    -- The target name takes the authored line's row when that is unused; re-run per callout.
    -- Pitch is floored at REMINDER_SIZE, since `line` follows Text Size and at small sizes the
    -- name would overlap the callout.
    ns.PlaceCastTargetLine = function()
        local pitch = math.max(line, REMINDER_SIZE + 4)
        local occupied = frame.reminder and frame.reminder:IsShown()
        place(frame.castTarget, occupied and pitch * 2 or pitch)
    end
    ns.PlaceCastTargetLine()
end

-- Through SharedMedia so locale font variants resolve themselves; nil without it.
local function NaowhMedia(kind, name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local ok, path = pcall(LSM.Fetch, LSM, kind, name, true)
    return ok and path or nil
end

local function AlertFont()
    local selected = TRDB().fontName
    local path = type(selected) == "string" and NaowhMedia("font", selected)
    return path or ns.UIFontPath()
end
ns.AlertFontPath = AlertFont

-- Display only, never clickable. Alpha 0 hides the art but NOT hit-testing, so a losing
-- slot left mouse-enabled would still be a live mouse target sitting over the screen.
local function CreateSlot(index)
    local slot = CreateFrame("Frame", nil, frame)
    slot:SetPoint("TOP")                -- every slot stacks on the same spot: one wins, the
    slot:EnableMouse(false)             -- rest sit at alpha 0 behind it
    slot:SetAlpha(0)

    slot.icon = Look.Icon(slot)

    local T = ns.THEME

    -- Parented to the slot so the secret priority alpha reveals the winning line with no
    -- branch, which is why text can name the defensive in combat when speech cannot.
    -- A FontString cannot carry the tank gate (textures only).
    slot.label = slot:CreateFontString(nil, "OVERLAY")
    slot.label:SetFont(AlertFont(), 16, "OUTLINE")
    slot.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    slot.label:Hide()

    slots[index] = slot
    ApplyDefensiveTextColor()
    ApplyTextLayout()
    return slot
end

-- Built from textures throughout so the tank gate can reach every part of it.
local function CreateBar()
    if bar then return bar end
    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOP", frame, "BOTTOM", 0, -BAR_DROP)
    bar:SetHeight(BAR_HEIGHT)
    bar:EnableMouse(false)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture(NaowhMedia("statusbar", "NaowhGradient")
        or "Interface\\TargetingFrame\\UI-StatusBar")
    bar.fill = bar:GetStatusBarTexture()
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    ns.PixelInset(bar.bg, -1, bar)
    local T = ns.THEME
    bar.bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 0.9)
    if bar.fill then bar.fill:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, 1) end
    bar:Hide()
    return bar
end

function Reminder.Create()
    if frame then return frame end

    -- Not "NaowhForever": a named frame replaces the global of that name, and that
    -- global is the addon table other addons look up.
    frame = CreateFrame("Frame", "NaowhForeverAlert", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()

    textFrame = CreateFrame("Frame", "NaowhForeverAlertText", UIParent)
    textFrame:SetSize(1, 1)
    textFrame:SetFrameStrata("HIGH")
    textFrame:EnableMouse(false)
    textFrame:Hide()

    frame.reminder = textFrame:CreateFontString(nil, "OVERLAY")
    frame.reminder:SetFont(AlertFont(), REMINDER_SIZE, "OUTLINE")
    ApplyDefensiveTextColor()
    frame.reminder:Hide()

    -- "Call for external": its alpha is the accumulator left over after the priority walk,
    -- 1 only when nothing on the list is up.
    frame.fallback = textFrame:CreateFontString(nil, "OVERLAY")
    frame.fallback:SetFont(AlertFont(), 16, "OUTLINE")
    local T = ns.THEME
    frame.fallback:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1)
    frame.fallback:SetAlpha(0)
    frame.fallback:Hide()

    -- Its own font string: the target name arrives secret and concatenating a secret raises.
    frame.castTarget = textFrame:CreateFontString(nil, "OVERLAY")
    frame.castTarget:SetFont(AlertFont(), REMINDER_SIZE, "OUTLINE")
    frame.castTarget:Hide()

    -- No "you are targeted" marker: PlayerIsSpellTarget is secret and SetShown is
    -- AllowedWhenUntainted, so it failed silently (pcall-wrapped) for three versions.

    -- Authoring mode changes every uncovered boss to call-everything; twice a callout that
    -- looked like wrong data was this switch left on, hence the tag and border.
    frame.learnTag = textFrame:CreateFontString(nil, "OVERLAY")
    frame.learnTag:SetFont(AlertFont(), 12, "OUTLINE")
    frame.learnTag:SetTextColor(1, 0.65, 0.2, 1)
    frame.learnTag:SetText("AUTHORING MODE -- CALLING EVERY ABILITY")
    frame.learnTag:Hide()
    frame.learnBorder = ns.Border(frame, { r = 1, g = 0.65, b = 0.2 }, 1)
    if frame.learnBorder and frame.learnBorder._frame then frame.learnBorder._frame:Hide() end

    -- A spec with no list never reaches RebuildSlots, and a zero-sized frame is one Unlock
    -- Mode cannot pick up, so position it now regardless.
    ApplyPosition()
    ApplyTextLayout()
    return frame
end

local function ApplySize()
    if not frame then return end
    if frame.reminder then frame.reminder:SetFont(AlertFont(), REMINDER_SIZE, "OUTLINE") end
    if frame.castTarget then frame.castTarget:SetFont(AlertFont(), REMINDER_SIZE, "OUTLINE") end
    if frame.learnTag then frame.learnTag:SetFont(AlertFont(), 12, "OUTLINE") end
    local t = TRDB()
    local size = t.iconSize or DEFAULTS.iconSize
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
    ApplyTextLayout()
end

-------------------------------------------------------------------------------
--  Rebuilding the slot list
-------------------------------------------------------------------------------
-- Talent state is plain, so slot setup is decided in the clear; the secret half only touches alpha.
local function RebuildSlots(fp, keepIfEmpty, presetOverride)
    -- A general rebuild waits for a live callout to end (HideReminder): it would swap that
    -- callout's slots for the default list and blank what is on screen.
    if shownForEvent and not keepIfEmpty then
        ns.slotsStale = true
        return
    end
    -- A warning with no usable defensive must leave the current display intact.
    if keepIfEmpty then
        if not frame then return false end
        local candidateList = EffectiveList(specID, currentEncounter, fp, presetOverride)
        if not candidateList then return false end
        local found = false
        for i = 1, #candidateList do
            local sid = candidateList[i]
            if IsSpellAvailable(sid) and not IsSpellDisabled(sid) then
                found = true
                break
            end
        end
        if not found then return false end
    end
    activeSlots = 0
    if not frame then return end

    -- Call Together must read the preset the slots came from, which a boss or ability can
    -- override, not the spec's active one.
    local list, _, presetKey = EffectiveList(specID, currentEncounter, fp, presetOverride)
    ns.slotsPreset = presetKey
    -- No auto-seeding: Robin wants every preset built deliberately in Setup, per spec.
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
            -- GetSpellInfo is empty for an uncached spell; GetSpellTexture usually has it.
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            local iconID = info and info.iconID
            if not iconID and C_Spell and C_Spell.GetSpellTexture then
                local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
                if ok then iconID = tex end
            end
            slot.iconID = iconID or 134400
            slot.icon:SetTexture(slot.iconID)
            slot.label:SetText(CalloutFor(spellID, info and info.name))
        end
    end

    for i = 1, #slots do
        slots[i]:SetAlpha(0)
    end
    ApplySize()
    return true
end

-------------------------------------------------------------------------------
--  The priority pick
-------------------------------------------------------------------------------
-- N-way exclusive select with no branch on a secret. `eligible` ("nobody above has won") is
-- plain 1 on the first pass and secret after; ev(ready, eligible, 0) lights a slot only when
-- ready and still eligible. Every slot is set on every pass: Blizzard's own comment in
-- EncounterTimelineTemplates warns that skipping setters leaks the secret via call count.
local EnsureChargeState, ChargesAvailable

local function ApplyPriorityAlpha()
    local ev = C_CurveUtil.EvaluateColorValueFromBoolean
    local eligible = 1

    for i = 1, activeSlots do
        local slot = slots[i]

        -- Charges first: holding 1 of 2 leaves a recharge timer active, which the cooldown
        -- duration reads as not ready.
        EnsureChargeState(slot.spellID)
        local charges = ChargesAvailable(slot.spellID)
        local dur = (not charges) and C_Spell.GetSpellCooldownDuration(slot.spellID, true) or nil
        -- ignoreGCD=true is load-bearing: by default the duration covers the GCD and every
        -- defensive reads unavailable mid-fight. The handle is plain; IsZero() is the secret.

        if charges then
            -- Tracked from the player's own casts, so plain even in restricted content.
            local ready = charges > 0
            slot:SetAlpha(ready and eligible or 0)
            if ready then eligible = 0 end
        elseif dur and dur.IsZero then
            local ready = dur:IsZero()
            -- Not SetAlphaFromBoolean: it documents its alpha default as 255, an ambiguous scale.
            slot:SetAlpha(ev(ready, eligible, 0))
            eligible = ev(ready, 0, eligible)
        else
            -- MayReturnNothing: a ready spell returns nil (plain), so nil means ready.
            slot:SetAlpha(eligible)
            eligible = 0
        end
    end

    -- Leftover eligibility is "nobody was ready". Set unconditionally to avoid the call-count leak.
    if frame and frame.fallback then
        if TRDB().fallbackOn == false then
            frame.fallback:SetAlpha(0)
        else
            frame.fallback:SetAlpha(eligible)
        end
    end
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
ns.PerBossSet = PerBossSet

-- profile.customReminders[encounterID][uid] = { name, preset, trigger = {...}, dur }.
-- Older entries carry a `msg` string instead of `preset` and still display it verbatim.
local function CustomRemindersTable(create, enc)
    return PerBossSet("customReminders", create, enc)
end

-- What BigWigs/DBM have broadcast for this boss (plain keys and strings), so the reminder
-- editor can offer a pick list. Empty for a boss nobody here has pulled.
local function BossModCatalogueTable(create, enc)
    return PerBossSet("bwCatalogue", create, enc)
end
ns.BossModCatalogueTable = BossModCatalogueTable

-- profile.abilityBindings[specKey][enc][sid] = { enabled, mode, preset, ... }, keyed by the
-- id Setup's row shows (journal id, or the BigWigs option id when a module is installed).
-- Only access through ns.BindingForBossModKey / ns.EnsureBinding, which bridge the two id
-- spaces via ns.BOSSMOD_KEY_TO_JOURNAL. Per spec because preset keys are spec-local; the
-- old shared shape let one spec overwrite another's settings.
local function AbilityBindingsTable(create, enc)
    local t = TRDB()
    if type(t.abilityBindings) ~= "table" then
        if not create then return nil end
        t.abilityBindings = {}
    end
    if specID == 0 then return nil end
    local specKey = tostring(specID)
    local bySpec = t.abilityBindings[specKey]
    if type(bySpec) ~= "table" then
        if not create then return nil end
        bySpec = {}
        t.abilityBindings[specKey] = bySpec
    end
    local encKey = tostring(enc or 0)
    if type(bySpec[encKey]) ~= "table" then
        if not create then return nil end
        bySpec[encKey] = {}
    end
    return bySpec[encKey]
end
ns.AbilityBindingsTable = AbilityBindingsTable

-- A binding another spec owns whose scope names our role or class.
function ns.InheritedBinding(enc, sid)
    local t = TRDB()
    local all = t.abilityBindings
    if type(all) ~= "table" then return nil end
    local encKey, mySpec = tostring(enc or 0), tostring(specID)
    for specKey, bySpec in pairs(all) do
        if specKey ~= mySpec and type(bySpec) == "table" then
            local byEnc = bySpec[encKey]
            local b = type(byEnc) == "table" and byEnc[sid]
            if b == nil and type(byEnc) == "table" and ns.BOSSMOD_KEY_TO_JOURNAL then
                local jid = ns.BOSSMOD_KEY_TO_JOURNAL[sid]
                if jid then b = byEnc[jid] end
            end
            if type(b) == "table" and ns.BindingSharedToMe(b) then return b end
        end
    end
    return nil
end

-- Forward-declared: without it RecordBossModKey threw on a nil global whenever trace was on.
local AppendLog

-- enc is the broadcasting module's own encounter, for a key sent before our ENCOUNTER_START.
local function RecordBossModKey(mod, key, text, kind, enc)
    if type(key) ~= "number" then return end
    enc = currentEncounter or enc
    if not enc then return end
    local cat = BossModCatalogueTable(true, enc)
    if not cat then return end
    local entry = cat[key]
    if not entry then
        cat[key] = { mod = mod, kind = kind, text = text, seen = 1, stage = currentStage }
        if TRDB().trace then
            AppendLog({ kind = "key", sid = key, mod = mod, tankPath = kind })
        end
    else
        entry.mod, entry.kind = mod, kind
        -- Most recent wins: a bar's "(3)" occurrence suffix drifts pull to pull.
        if type(text) == "string" and text ~= "" then entry.text = text end
        if currentStage then entry.stage = currentStage end
        entry.seen = (entry.seen or 0) + 1
    end
end

ns.CustomRemindersTable = CustomRemindersTable

local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

-- UnitGUID is SecretWhenUnitIdentityRestricted, so it is cached the first time it reads plain.
local playerGUID
local function PlayerGUID()
    if playerGUID then return playerGUID end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and not (issecretvalue and issecretvalue(guid)) and type(guid) == "string" then
        playerGUID = guid
    end
    return playerGUID
end
ns.PlayerGUID = PlayerGUID

-- GUIDs on boss1-5, cached for the per-combat-log-line aura check and refreshed from
-- INSTANCE_ENCOUNTER_ENGAGE_UNIT.
ns.bossGUIDs = {}
function ns.RefreshBossGUIDs()
    wipe(ns.bossGUIDs)
    for i = 1, 5 do
        local unit = BOSS_UNITS[i]
        if UnitExists(unit) then
            local ok, guid = pcall(UnitGUID, unit)
            if ok and not (issecretvalue and issecretvalue(guid)) and type(guid) == "string" then
                ns.bossGUIDs[guid] = true
            end
        end
    end
end

-- true/false, or nil when both reads are secret. Threat status (confirmed plain in raids)
-- first; the target match covers content where threat is secret, a separate gate
-- (SecretWhenUnitThreatStateRestricted vs SecretWhenUnitComparisonRestricted).
-- Not a closure so the pcall below allocates nothing per broadcast.
local function ReadTankedVerdict(unit)
    local status = UnitThreatSituation("player", unit)
    local statusKnown = not (issecretvalue and issecretvalue(status))
    if statusKnown then
        return type(status) == "number" and status >= 2
    end
    local same = UnitIsUnit(unit .. "target", "player")
    local sameKnown = not (issecretvalue and issecretvalue(same))
    if sameKnown then return same == true end
    return nil
end

local function UnitTankedVerdict(unit)
    local ok, verdict = pcall(ReadTankedVerdict, unit)
    if not ok then return nil end
    return verdict
end

-- Per-slot verdicts for the refusal log: "not tanking" and "secret" need different fixes.
local function BossThreatSummary()
    local out
    for i = 1, 5 do
        local unit = BOSS_UNITS[i]
        if UnitExists(unit) then
            out = (out and out .. "," or "")
                .. ("%s=%s"):format(unit, tostring(UnitTankedVerdict(unit)))
        end
    end
    return out or "no boss units"
end

-- Fails open on an unknown verdict or no boss units: a spare callout is cheaper than a death.
local function TankingSomeBoss()
    local sawBoss, unknown = false, false
    for i = 1, 5 do
        local unit = BOSS_UNITS[i]
        if UnitExists(unit) then
            sawBoss = true
            local verdict = UnitTankedVerdict(unit)
            if verdict == true then return true end
            if verdict == nil then unknown = true end
        end
    end
    if not sawBoss or unknown then return true end
    return false
end

-- Set by FireBigWigsAbility, read by LogCallout so a wrong call can be diagnosed from
-- /nutank calls after the pull.
local lastAggroCheck   -- { sid, verdict, path }

-- Multi-boss fights make "tanking some boss" the wrong question, so the casting unit is
-- checked when known. Second return names the path: "boss:<unit>", "owner-gone", "nocache"
-- or "fallback". In raids every boss GUID reads secret (confirmed on The Coiled Altar), so
-- the curated owner map, which names the boss slot, is the only path that works there.
local castSourceGUID = {}
-- UnitThreatSituation drops below 2 for the real tank mid-cast, across stage changes and
-- while untargetable (live on Ula'tek), so a refusal is only believed if the player was
-- not seen tanking that unit within the grace.
-- ns fields, not chunk locals: this chunk is at the 200-local ceiling.
ns.TANKED_GRACE = 6
ns.lastTankedAt = {}

-- Sampled off bar traffic: busters come 25-30s apart, so a sample taken only at fire time
-- was always older than the grace.
function ns.SampleTanking()
    local now = GetTime()
    for i = 1, 5 do
        local unit = BOSS_UNITS[i]
        if UnitExists(unit) and UnitTankedVerdict(unit) then ns.lastTankedAt[unit] = now end
    end
end

local function TankingCaster(sid)
    local ownerSlot = ns.TANK_ABILITY_OWNER_UNIT and ns.TANK_ABILITY_OWNER_UNIT[sid]
    if ownerSlot then
        local unit = BOSS_UNITS[ownerSlot]
        if unit and UnitExists(unit) then
            local verdict = UnitTankedVerdict(unit)
            if verdict == nil then return true, "boss:" .. unit .. ":unreadable" end
            if verdict then
                ns.lastTankedAt[unit] = GetTime()
                return true, "boss:" .. unit
            end
            if (GetTime() - (ns.lastTankedAt[unit] or 0)) <= ns.TANKED_GRACE then
                return true, "boss:" .. unit .. ":recent"
            end
            return false, "boss:" .. unit
        end
        -- Owner dead or not out yet; DBM's Twin Fangs module handles it the same way.
        return TankingSomeBoss(), "owner-gone"
    end

    local guid = castSourceGUID[sid]
    if not guid then return TankingSomeBoss(), "nocache" end
    for i = 1, 5 do
        local unit = BOSS_UNITS[i]
        if UnitExists(unit) then
            local ok, unitGUID = pcall(UnitGUID, unit)
            if ok and not (issecretvalue and issecretvalue(unitGUID)) and unitGUID == guid then
                local verdict = UnitTankedVerdict(unit)
                if verdict == nil then return true, "boss:" .. unit .. ":unreadable" end
                return verdict, "boss:" .. unit
            end
        end
    end
    return TankingSomeBoss(), "fallback"
end

-- Tracked from the combat log, not GetPlayerAuraBySpellID: that is RequiresNonSecretAura and
-- returned nothing on Mythic while Ardent Defender was up. No remaining-time threshold:
-- every duration return can be secret, so an aura that is up counts as covering outright.
local playerAuraUp = {}   -- [spellID] = true while up

local bigDefSeen = 0
-- Own-cast cover window, the last rung: CLEU registration is illegal in restricted content,
-- but UNIT_SPELLCAST_SUCCEEDED is not. 10s silenced a pre-pop pull callout twice on Ula'tek,
-- so it went back to 6 (longer than press-to-hit, shorter than any buster cycle).
local OWN_CAST_COVER_DEFAULT = 6
local ownCastAt = {}   -- [spellID] = GetTime() of our own last cast of it

-- AuraIsBigDefensive accepts a secret spellID and returns a plain boolean, so it still
-- answers for an aura whose identity is secret. GetAuraDataByIndex is RequiresUnitAuraAccess
-- and may be refused, hence the pcall; bigDefSeen tells /nutank whether this path ever worked.
local function BigDefensiveUp()
    if not (AuraUtil and AuraUtil.IsBigDefensive
        and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return false
    end
    -- A secret entry is skipped, only a plain nil ends the list: stopping at the first
    -- non-table missed Ardent Defender behind a secret aura on Rav'i.
    local ok, found = pcall(function()
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if type(aura) == "table" then
                if AuraUtil.IsBigDefensive(aura) == true then return true end
            elseif not (issecretvalue and issecretvalue(aura)) then
                return false
            end
        end
        return false
    end)
    if ok and found == true then
        bigDefSeen = bigDefSeen + 1
        return true
    end
    return false
end

-- Second and third returns name the covering spell and rung; a skip is otherwise invisible.
local function CoveredByActiveDefensive(fp, presetOverride)
    local now = GetTime()
    if BigDefensiveUp() then return true, nil, "bigdef" end
    local list = EffectiveList(specID, currentEncounter, fp, presetOverride) or {}
    local eligible = 0
    for i = 1, #list do
        local sid = list[i]
        if IsSpellAvailable(sid) and not IsSpellDisabled(sid) then
            eligible = eligible + 1
            if eligible > MAX_SLOTS then break end
            if playerAuraUp[sid] then return true, sid, "aura" end
            local window = TRDB().coveredCastWindow or OWN_CAST_COVER_DEFAULT
            if window > 0 and ownCastAt[ns.CooldownKey(sid)] and (now - ownCastAt[ns.CooldownKey(sid)]) < window then
                return true, sid, "cast"
            end
            -- A buff applied before tracking could see it (reload, pre-pull).
            if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                local ok, exists = pcall(function()
                    return type(C_UnitAuras.GetPlayerAuraBySpellID(sid)) == "table"
                end)
                if ok and exists then return true, sid, "poll" end
            end
        end
    end
    return false
end


-- The engine gate (SetEventIconTextures) is no longer applied: ns.AbilityEnabledForBinding
-- silences abilities upstream, text and voice included. It is still probed by `canGate`
-- and exercised by /nutank gate.
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
-- No sound API accepts a secret, so sound uses C_EncounterEvents.SetEventSound against the
-- static event records, whose TankRole bit is not secret. It cannot know whether a
-- defensive is ready: sound says when, the icon says whether.
local soundError               -- surfaced on the options page

-- The engine keeps a registered sound until it is cleared, so every registration is tracked.
ns.soundEvents = {}
ns.soundGeneration = 0

function ns.ClearEventSounds()
    ns.soundGeneration = ns.soundGeneration + 1
    ns.soundFile = nil
    for id in pairs(ns.soundEvents) do
        pcall(C_EncounterEvents.SetEventSound, id,
            Enum.EncounterEventSoundTrigger.OnTimelineEventHighlight, nil)
        ns.soundEvents[id] = nil
    end
end

local function ResolveSoundFile()
    local key = TRDB().soundKey
    if not key or key == "none" then return nil end
    local value = ns.UI.SoundPathFor(key)
    -- SetEventSound silently ignores a SoundKitID, which LSM can hand out.
    if type(value) == "string" then return value end
    return nil
end

-- Chunked: GetEventList is the whole encounter-event database, not the current pull.
-- Measured live: the engine plays a registered sound at most once per encounter, and
-- re-registering (even clear then set) does not change that.
local function RegisterEventSounds()
    soundError = nil
    ns.ClearEventSounds()
    if not (TRDB().enabled and TRDB().soundOn) then return end
    if not (canSound and TimelineAvailable()) then return end
    if ns.BossSource() ~= "timeline" then
        soundError = "Per-ability sounds ride the Blizzard timeline. Boss Addon is set to "
            .. "a boss mod, so they are off."
        return
    end
    if not canSound then
        soundError = "This client does not support per-ability sounds."
        return
    end

    -- No warning for encounterTimelineEnabled 0: measured false, sounds still play.

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

    -- Optional data file.
    local curatedTank = ns.TANK_ABILITIES
    local sound = { file = file, volume = 1 }
    local i, total = 1, #ids
    local generation = ns.soundGeneration

    local function Step()
        if generation ~= ns.soundGeneration then return end
        -- ~870 events, re-run on ENCOUNTER_START: 200 per frame hitched visibly, 50 left
        -- early abilities unregistered for ~0.3s. Measure (MeasureCall on one Step) before
        -- changing it.
        local stop = math.min(i + 99, total)
        while i <= stop do
            local info = C_EncounterEvents.GetEventInfo(ids[i])

            -- Blizzard's bit OR our list: the bit alone flags only 13 of this season's 23
            -- tank busters.
            local flagged = info and info.icons and bit.band(info.icons, mask) ~= 0
            local curated = info and info.spellID and curatedTank
                and curatedTank[info.spellID] ~= nil

            if (flagged or curated)
                and not ns.IsAbilityHealerFiltered(currentEncounter, info.spellID)
                and pcall(C_EncounterEvents.SetEventSound, ids[i], trigger, sound) then
                ns.soundEvents[ids[i]] = true
            end
            i = i + 1
        end
        if i <= total then C_Timer.After(0, Step) end
    end

    ns.soundFile = file
    Step()
end

-------------------------------------------------------------------------------
--  Self-tracked cooldowns (what lets the voice work in combat)
-------------------------------------------------------------------------------
-- Readiness is secret in combat but the player's own casts are not, so the voice branches
-- on GetTime() + cooldown recorded from UNIT_SPELLCAST_SUCCEEDED. Corrected by: learned
-- totals (talent reductions) recorded whenever the cooldown is readable; the plain nil
-- signal (no duration object = not on cooldown) on every SPELL_UPDATE_COOLDOWN; and a full
-- resync whenever cooldowns are readable.
local readyAt = {}          -- [list spellID] = GetTime() at which it is back up

-------------------------------------------------------------------------------
--  Charges
-------------------------------------------------------------------------------
-- Seconds, for spells GetSpellBaseCooldown misreports (0 for Divine Shield, 8 for Guardian
-- of Ancient Kings). Cooldown for the plain model, starting per-charge recharge for charge
-- spells until the client reports the real one. Use the full untalented figure: 180 for
-- Guardian returned a charge early on Kings Rest; too long is the safe direction.
-- Declared above the charge code so EnsureChargeState sees it as an upvalue.
local KNOWN_BASE_COOLDOWN = {
    [1966] = 15,      -- Feint: recharge fallback when charge duration is unavailable
    [642] = 300,      -- Divine Shield
    [86659] = 300,    -- Guardian of Ancient Kings
}

function ns.CooldownKey(sid)
    return ns.cooldownAliases and ns.cooldownAliases[sid] or sid
end

-- The cooldown accessor misreads charge spells both ways (1 of 2 held reads unavailable,
-- 0 held can read ready). Only maxCharges and isActive (false = at maximum) are
-- NeverSecret; currentCharges is not, so the count is tracked from the player's own casts.
local chargeState = {}
local chargeMemory = {} -- Same live counter, retained across temporary shape loss.

-- Recorded even without trace. Plain classified values only, never raw API fields.
function ns.RecordChargeTransition(sid, reason, before, tick, st)
    if reason ~= "own cast" and before == st.count
        and (tick == st.tick or st.count == st.max) then return end
    local t = TRDB()
    if type(t.chargeAudit) ~= "table" then t.chargeAudit = {} end
    local log = t.chargeAudit
    log[#log + 1] = {
        stamp = date and date("%H:%M:%S") or "?", build = ns.CODE_BUILD,
        sid = sid, reason = reason, before = before, after = st.count,
        oldTick = tick, tick = st.tick, at = GetTime(), recharge = st.recharge,
        source = st.rechargeSrc,
    }
    while #log > 80 do table.remove(log, 1) end
end

function ns.AppendChargeAudit(out)
    local log = TRDB().chargeAudit
    if type(log) ~= "table" then return end
    out[#out + 1] = "Charge model transitions (automatic, last 80):"
    for i = 1, #log do
        local e = log[i]
        out[#out + 1] = ("%s build=%s spell=%d %s: %s -> %d, anchor age %.1f -> %.1f, recharge %.1f (%s)"):format(
            e.stamp, tostring(e.build), e.sid, e.reason, tostring(e.before), e.after,
            e.at - (e.oldTick or e.at), e.at - e.tick, e.recharge, tostring(e.source))
    end
end

local CooldownRunning

-- Third return false means the read failed, as opposed to a valid read confirming max < 2;
-- only the latter may wipe the tracked count (see EnsureChargeState).
local function ReadChargeShape(sid)
    if not (C_Spell and C_Spell.GetSpellCharges) then return nil, nil, false end

    local ok, info = pcall(C_Spell.GetSpellCharges, sid)
    if not ok or type(info) ~= "table" then return nil, nil, false end

    -- The rest of this struct is secret in restricted content and a wrong field read raises.
    local got, max, active = pcall(function() return info.maxCharges, info.isActive end)
    if not got then return nil, nil, false end
    if type(max) ~= "number" or max < 2 then return nil, nil, true end

    return max, active == true, true
end

-- GetSpellChargeDuration and the duration object's getters carry no
-- SecretWhenCooldownsRestricted, so the real recharge (and how far through it is) is
-- readable while one runs (MayReturnNothing at full charges). A duration object is not
-- necessarily a Lua table, so it is not type-checked.
local function ReadDurationObject(fn, ...)
    if not fn then return nil end
    local ok, dur = pcall(fn, ...)
    if not ok or not dur then return nil end
    local got, total = pcall(function() return dur:GetTotalDuration() end)
    if not got or (issecretvalue and issecretvalue(total)) then return nil end
    if type(total) ~= "number" or total <= 1.5 then return nil end

    local okRem, remaining = pcall(function() return dur:GetRemainingDuration() end)
    if not okRem or (issecretvalue and issecretvalue(remaining)) then return total end
    if type(remaining) ~= "number" or remaining < 0 or remaining > total then return total end
    return total, remaining
end

-- The cooldown-accessor stand-in is floored at the seed: it reported 8s for Guardian of
-- Ancient Kings on The Coiled Altar and the spell was called all fight with no charges.
-- GetSpellChargeDuration describes the recharge itself, so it is taken as it comes.
local function ReadChargeRecharge(sid)
    if not C_Spell then return nil end
    local total, remaining = ReadDurationObject(C_Spell.GetSpellChargeDuration, sid)
    if total then return total, remaining end
    total, remaining = ReadDurationObject(C_Spell.GetSpellCooldownDuration, sid, true)
    if not total then return nil end
    local seed = KNOWN_BASE_COOLDOWN[sid] or 0
    -- No remaining with a floored total: the mismatched anchor reads as several landings.
    -- Third return marks the seed, which must never be persisted as clientRecharge.
    if total < seed then return seed, nil, true end
    return total, remaining, false
end

function EnsureChargeState(sid)
    sid = ns.CooldownKey(sid)
    local max, active, ok = ReadChargeShape(sid)
    if not ok then
        -- Keep the tracked state: wiping on one dropped read rebuilt it at full charges.
        return chargeState[sid]
    end
    if not max then
        chargeState[sid] = nil
        return nil
    end

    local st = chargeState[sid]
    if not st then
        local retained = chargeMemory[sid]
        if retained and retained.witnessed then
            st = retained
            chargeState[sid] = st
            ns.RecordChargeTransition(sid, "restore", nil, nil, st)
        end
    end
    if st and st.max ~= max then
        local before, oldTick = st.count, st.tick
        -- A larger maximum is not evidence that new charges are available. If
        -- the old stack was full, its idle clock cannot earn the new charge.
        if st.count == st.max and max > st.max then
            st.tick, st.rechargeStart = GetTime(), nil
        end
        st.max, st.count = max, math.min(st.count, max)
        ns.RecordChargeTransition(sid, "shape change", before, oldTick, st)
    end
    if not st then
        -- GetSpellBaseCooldown is never used for charge spells (8s for Guardian of
        -- Ancient Kings): measured recharge or no climb.
        local t = TRDB()
        local learned = type(t.learned) == "table" and t.learned[tostring(sid)] or nil
        -- Feint's legacy learned value measured time between observations (334s), not
        -- its recharge.
        if sid == 1966 then learned = nil end
        -- Exempt from the seed floor: flooring a client-stated 180s Guardian recharge to
        -- 300s put the count two minutes behind on Kings Rest.
        local fromClient = type(t.clientRecharge) == "table" and t.clientRecharge[tostring(sid)] or nil
        st = {
            -- Recharging on first sight starts at zero, the only guess that cannot
            -- overcount (isActive never says how many are missing; max-1 was tried).
            max = max, count = (active or ReadChargeRecharge(sid) ~= nil) and 0 or max, tick = GetTime(),
            -- Zero means no climb. Learned figures are floored at the seed: measured off
            -- isActive, they lie for a talent-granted extra charge.
            recharge = fromClient or math.max(learned or 0, KNOWN_BASE_COOLDOWN[sid] or 0),
            -- For /nutank cds: a wrong recharge is invisible from the callout itself.
            rechargeSrc = fromClient and "client"
                or (math.max(learned or 0, KNOWN_BASE_COOLDOWN[sid] or 0) <= 0
                and "none")
                or ((learned or 0) >= (KNOWN_BASE_COOLDOWN[sid] or 0) and "learned" or "seed"),
        }
        chargeState[sid], chargeMemory[sid] = st, st
        ns.RecordChargeTransition(sid, "initialize", nil, nil, st)
    end
    return st
end

function ChargesAvailable(sid)
    sid = ns.CooldownKey(sid)
    local st = chargeState[sid]
    if not st then return nil end
    local before, oldTick = st.count, st.tick

    local _, active = ReadChargeShape(sid)

    -- The client's rate wins and is persisted, since it is only readable while recharging.
    -- Not gated on isActive: GetSpellCharges declines in a real key, which is what left the
    -- rate at the 300s seed on Kings Rest. An answer proves a recharge is running.
    local real, remaining, floored = ReadChargeRecharge(sid)
    if real then
        active = true
        st.recharge, st.rechargeSrc = real, floored and "seed" or "client"
        if not floored then
            local t = TRDB()
            if type(t.clientRecharge) ~= "table" then t.clientRecharge = {} end
            t.clientRecharge[tostring(sid)] = real
        end
        -- A landing shows as the client's recharge start jumping forward by one recharge.
        -- Re-anchoring st.tick at zero count instead pinned the count at 0 (Rav'i).
        if remaining then
            local start = GetTime() - (real - remaining)
            if st.rechargeStart then
                local landed = math.floor((start - st.rechargeStart) / real + 0.5)
                if landed > 0 then st.count = math.min(st.max, st.count + landed) end
            end
            st.rechargeStart = start
            st.tick = start
        end
    end

    -- currentCharges is secret only while cooldowns are restricted; otherwise it is the answer.
    if CanNameSpellAloud(sid) then
        local okCur, cur = pcall(function() return C_Spell.GetSpellCharges(sid).currentCharges end)
        if okCur and not (issecretvalue and issecretvalue(cur))
            and type(cur) == "number" and cur >= 0 and cur <= st.max then
            -- Consume completed intervals, or the next sealed read credits them again.
            if not remaining and st.recharge > 0 and cur < st.max then
                local now = GetTime()
                local elapsed = math.max(0, math.floor((now - st.tick) / st.recharge))
                if cur > st.count and elapsed < cur - st.count then
                    -- Early refill/reset: unknown phase, start a fresh interval.
                    st.tick, st.rechargeStart = now, nil
                elseif elapsed > 0 then
                    local advance = elapsed * st.recharge
                    st.tick = st.tick + advance
                    if st.rechargeStart then st.rechargeStart = st.rechargeStart + advance end
                end
            end
            if cur < st.count then st.tick = GetTime() end
            st.count, st.witnessed = cur, true
            if cur == st.max then
                st.tick, st.missingSince, st.rechargeStart = GetTime(), nil, nil
            end
            ns.RecordChargeTransition(sid, "readable count", before, oldTick, st)
            return st.count
        end
    end

    -- An inactive flag does not prove every charge is back, and no recharge is learned from it.

    if st.recharge > 0 and st.count < st.max then
        local gained = math.floor((GetTime() - st.tick) / st.recharge)
        if gained > 0 then
            st.count = math.min(st.max, st.count + gained)
            st.tick  = st.tick + gained * st.recharge
            if st.rechargeStart then
                st.rechargeStart = st.rechargeStart + gained * st.recharge
            end
        end
    end

    -- No optimistic max-1 floor: isActive reads the same with both charges out, so it
    -- called a defensive that was down. With no rate at all, zero stands.

    -- isActive is a hard ceiling: something is recharging, so the stack cannot be full.
    if active and st.count >= st.max then
        st.count = st.max - 1
    end

    -- No floor for an inactive cooldown either: it bypassed the recharge deadline.
    ns.RecordChargeTransition(sid, "reconcile", before, oldTick, st)
    return st.count
end
local castToBase = {}       -- cast-time override id -> the id the list stores

-- Every configured spell, not just the drawn preset: bosses and custom reminders can pick
-- another preset, and a spell may be pressed before its first warning.
ns.trackedCooldownSpells = {}
local function RebuildCastMap()
    local aliases, configured = {}, {}
    local function Root(sid)
        while aliases[sid] and aliases[sid] ~= sid do sid = aliases[sid] end
        return sid
    end
    local function Add(sid)
        if type(sid) ~= "number" or sid <= 0 or configured[sid] then return end
        configured[sid] = true
        aliases[sid] = aliases[sid] or sid
        if C_Spell and C_Spell.GetOverrideSpell then
            local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
            if ok and not (issecretvalue and issecretvalue(ov))
                and type(ov) == "number" and ov > 0 and ov ~= sid then
                aliases[ov] = aliases[ov] or ov
                local base, replacement = Root(sid), Root(ov)
                if base ~= replacement then aliases[replacement] = base end
            end
        end
    end
    local function AddList(list)
        if type(list) ~= "table" then return end
        for i = 1, #list do Add(list[i]) end
    end
    for i = 1, activeSlots do Add(slots[i].spellID) end
    local presets = PresetsTable(specID, false)
    if presets then
        for _, preset in pairs(presets) do
            if type(preset) == "table" then AddList(preset.list) end
        end
    end
    -- Older per-boss/per-ability lists still participate in EffectiveList.
    local legacy = TRDB().bossLists
    if type(legacy) == "table" then
        local prefix = tostring(specID) .. ":"
        for key, list in pairs(legacy) do
            if type(key) == "string" and key:sub(1, #prefix) == prefix then AddList(list) end
        end
    end

    -- All aliases first, or iteration order can create two counters for one ability.
    local merged, deadlines, casts, roots = {}, {}, {}, {}
    for sid in pairs(aliases) do
        local root = Root(sid)
        roots[sid] = root
        local previous = castToBase[sid] or sid
        local state = chargeState[previous]
        local retained = chargeMemory[previous]
        if not state and retained and retained.witnessed then state = retained end
        local kept = merged[root]
        -- Disagreeing counters: keep the lower count, the later anchor on a tie.
        if state and (not kept or state.count < kept.count
            or (state.count == kept.count and state.tick > kept.tick)) then
            merged[root] = state
        end
        if readyAt[previous] then
            deadlines[root] = math.max(deadlines[root] or 0, readyAt[previous])
        end
        if ownCastAt[previous] then
            casts[root] = math.max(casts[root] or 0, ownCastAt[previous])
        end
    end
    wipe(castToBase)
    wipe(ns.trackedCooldownSpells)
    for sid, root in pairs(roots) do castToBase[sid] = root end
    ns.cooldownAliases = castToBase
    for sid, root in pairs(roots) do
        if sid == root then
            if merged[root] then
                chargeState[root], chargeMemory[root] = merged[root], merged[root]
            end
            readyAt[root], ownCastAt[root] = deadlines[root], casts[root]
            ns.trackedCooldownSpells[#ns.trackedCooldownSpells + 1] = root
        end
    end
    for i = 1, #ns.trackedCooldownSpells do
        local sid = ns.trackedCooldownSpells[i]
        pcall(EnsureChargeState, sid)
        pcall(ChargesAvailable, sid)
    end
end

-- Persisted cast/callout log for checking a bad call afterwards. Capped since it lives in
-- SavedVariables; a trace keeps far more to cover a whole key.
function AppendLog(entry)
    local CALL_LOG_MAX, TRACE_LOG_MAX = 30, 600
    local t = TRDB()
    if type(t.callLog) ~= "table" then t.callLog = {} end
    local log = t.callLog
    entry.stamp = date and date("%H:%M:%S") or "?"
    entry.enc, entry.stage = currentEncounter, currentStage
    log[#log + 1] = entry
    local cap = t.trace and TRACE_LOG_MAX or CALL_LOG_MAX
    while #log > cap do table.remove(log, 1) end
end

-- Shared by /nutank calls and the export. Plain text: the export has to survive a paste.
local function LogLine(e)
    local function nameOf(id)
        local info = id and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        return (info and info.name) or tostring(id)
    end
    local head = ("%s enc=%s stage=%s"):format(e.stamp, tostring(e.enc), tostring(e.stage))
    if e.kind == "cast" then
        return head .. " -- CAST " .. nameOf(e.sid)
    elseif e.kind == "enc" then
        return head .. " -- ENCOUNTER " .. tostring(e.text)
    elseif e.kind == "key" then
        return ("%s -- KEY %s %s (%s/%s)"):format(head, tostring(e.sid), nameOf(e.sid),
            tostring(e.mod), tostring(e.tankPath))
    elseif e.kind == "quiet" then
        return ("%s -- icon-only for %s (voice repeat-muted, trigger %s)"):format(head,
            nameOf(e.sid), nameOf(e.tankSid))
    elseif e.kind == "drop" then
        return ("%s -- dropped broadcast for %s (%s)"):format(head, nameOf(e.sid),
            tostring(e.text))
    elseif e.kind == "bosscast" then
        return ("%s -- BOSS CAST %s on %s (%s)"):format(head,
            e.sid and nameOf(e.sid) or "secret id", tostring(e.unit), e.text or "?")
    elseif e.kind == "aside" then
        return head .. " -- " .. nameOf(e.sid) .. " stepped aside to its Ability Reminder"
    elseif e.kind == "cancel" then
        return ("%s -- cancelled pending callout for %s (bar '%s' stopped early)"):format(
            head, nameOf(e.sid), tostring(e.text))
    elseif e.kind == "schedule" then
        return ("%s -- SCHEDULE %s bar='%s' duration=%.1f approx=%s delay=%.1f%s"):format(
            head, nameOf(e.sid), tostring(e.text), e.duration, tostring(e.isApprox), e.delay,
            e.existingFireIn and (" (replaced one %.1fs out)"):format(e.existingFireIn) or "")
    elseif e.kind == "aggro" then
        return ("%s -- BLOCKED %s -- not tanking the caster (%s) -- %s"):format(head,
            nameOf(e.sid), tostring(e.tankPath), tostring(e.text))
    elseif e.kind == "skip" then
        return ("%s -- skipped %s -- already covered by %s (%s)"):format(head,
            nameOf(e.tankSid), nameOf(e.sid), tostring(e.tankPath))
    end
    return ("%s -- %s %s -- running=%s%s readyIn=%s secrecy=%s%s%s"):format(head,
        e.kind == "test" and "TEST-called" or "called", nameOf(e.sid),
        tostring(e.running), e.charges and (" charges=" .. e.charges) or "",
        e.readyAtDelta and ("%.1fs"):format(e.readyAtDelta) or "n/a", tostring(e.secrecy),
        e.tankPath and (" tankCheck=%s(%s)"):format(e.tankPath, nameOf(e.tankSid)) or "",
        (e.castTracked ~= nil and (" castTracked=" .. tostring(e.castTracked)) or "")
            .. (e.lastOwnCastAgo and (" lastCast=%.1fs ago"):format(e.lastOwnCastAgo) or "")
            .. (e.withSids and (" with=" .. e.withSids) or "")
            .. (e.auraUp and (" auraUp=" .. e.auraUp) or "")
            .. (e.chargeModel and ("\n    charges: " .. e.chargeModel) or ""))
end

local function NoteOwnCast(castSpellID)
    local sid = castSpellID and castToBase[castSpellID]
    if not sid then return end
    AppendLog({ kind = "cast", sid = sid })
    ownCastAt[sid] = GetTime()

    -- Established here too, or a charge spell's first cast of a session falls through to
    -- the readyAt model below.
    EnsureChargeState(sid)
    local st = chargeState[sid]
    local retained = chargeMemory[sid]
    if not st and retained and retained.witnessed then st = retained end
    if st then
        local before, oldTick = st.count, st.tick
        -- Spend from the tracked count; sampling post-cast state first would spend twice.
        if st.recharge > 0 and st.count < st.max then
            local gained = math.floor((GetTime() - st.tick) / st.recharge)
            if gained > 0 then
                st.count = math.min(st.max, st.count + gained)
                st.tick = st.tick + gained * st.recharge
                if st.rechargeStart then
                    st.rechargeStart = st.rechargeStart + gained * st.recharge
                end
            end
        end
        -- The recharge clock starts on the drop from maximum, not on every cast. A cast at
        -- zero spent a landing the estimate had not seen, so that landing is retired.
        if st.count >= st.max or st.count == 0 then
            st.tick = GetTime()
            st.missingSince = GetTime()
            st.rechargeStart = nil
        end
        st.count = math.max(0, st.count - 1)
        st.witnessed = true
        ns.RecordChargeTransition(sid, "own cast", before, oldTick, st)
        -- A retained counter without a live shape still needs the deadline below.
        if chargeState[sid] then return end
    end

    local t = TRDB()
    local learned = type(t.learned) == "table" and t.learned[tostring(sid)] or nil
    local baseMs = GetSpellBaseCooldown and GetSpellBaseCooldown(sid)
    -- GetSpellBaseCooldown reports 0 for talent/aura cooldowns (Divine Shield); leaving
    -- readyAt unset kept calling a just-pressed spell. ResyncModel clears an over-long guess.
    local UNKNOWN_COOLDOWN = 30

    local secs
    if learned then
        secs = learned
    elseif KNOWN_BASE_COOLDOWN[sid] then
        secs = KNOWN_BASE_COOLDOWN[sid]
    elseif type(baseMs) == "number" and baseMs > 0 then
        -- Base ignores talent reduction and cannot self-correct while sealed, so trim by the
        -- largest common tank reduction (Unbreakable Spirit, 30%) until a total is learned.
        secs = (baseMs / 1000) * 0.7
    else
        secs = UNKNOWN_COOLDOWN
    end
    readyAt[sid] = GetTime() + secs

    -- The 1.5s floor keeps a GCD-length reading from overwriting a real cooldown.
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

-- These three hang off ns rather than being file locals: this chunk is at Lua's 200-local
-- ceiling. Not a closure so ResyncSpell's pcall allocates nothing per spell.
function ns.ReadPlainCooldown(dur)
    if not dur or not dur.GetRemainingDuration then return 0 end
    return dur:GetRemainingDuration() or 0,
        (dur.GetTotalDuration and dur:GetTotalDuration()) or nil
end

ns.sidKeys = {}

function ns.LearnTotal(sid, total)
    local key = ns.sidKeys[sid]
    if not key then key = tostring(sid); ns.sidKeys[sid] = key end
    local t = TRDB()
    if type(t.learned) ~= "table" then t.learned = {} end
    if t.learned[key] ~= total then t.learned[key] = total end
end

local function ResyncSpell(sid)
    sid = ns.CooldownKey(sid)
    -- Every pass: a talent swap can add or remove charges.
    EnsureChargeState(sid)

    local cs = chargeState[sid]
    if cs then
        -- Through ReadChargeRecharge for its seed floor: this read is where Guardian of
        -- Ancient Kings' 8 second cooldown got in.
        local total = ReadChargeRecharge(sid)
        if total then
            cs.recharge, cs.rechargeSrc = total, "learned"
            ns.LearnTotal(sid, total)
        end
        return
    end

    -- No duration object is plain even in restricted content and means the spell is up.
    local live = C_Spell.GetSpellCooldownDuration(sid, true)
    if not live then readyAt[sid] = 0 end

    -- The pcall guards against the classification changing mid-read.
    if CanNameSpellAloud(sid) then
        local ok, rem, total = pcall(ns.ReadPlainCooldown, live)
        if ok and type(rem) == "number" then
            readyAt[sid] = GetTime() + math.max(0, rem)
        end

        -- Learned here too: casts are usually sealed, but the tail often runs into plain time.
        if ok and type(total) == "number" and total > 1.5 then
            ns.LearnTotal(sid, total)
        end
    end
end

local function ResyncModel()
    for i = 1, #ns.trackedCooldownSpells do
        ResyncSpell(ns.trackedCooldownSpells[i])
    end
end

-- SPELL_UPDATE_COOLDOWN arrives in bursts, so one pass per frame.
ns.resyncQueued = false
function ns.RunQueuedResync()
    ns.resyncQueued = false
    ResyncModel()
end
function ns.ResyncModelSoon()
    if ns.resyncQueued then return end
    ns.resyncQueued = true
    C_Timer.After(0, ns.RunQueuedResync)
end

-- Blizzard's CooldownViewer definition: not isOnGCD and isActive, both NeverSecret on
-- SpellCooldownInfo, so this answers in restricted content. Keep Blizzard's operand order:
-- the GCD test short-circuits, the other way round can raise. nil when it cannot answer.
function CooldownRunning(sid)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, running = pcall(function()
        local info = C_Spell.GetSpellCooldown(sid)
        if type(info) ~= "table" then return nil end
        return (not info.isOnGCD) and info.isActive
    end)
    if not ok or type(running) ~= "boolean" then return nil end
    return running
end

-- Shared by the voice pick and preset-bound custom reminders; keep it one ladder. Callers
-- pcall it: IsZero can raise if the classification changes mid-read.
-- A ready spell still returns a duration object; IsZero() separates ready from running
-- and is secret only while cooldowns are restricted, so it is legal behind
-- CanNameSpellAloud. Sealed and unwitnessed defaults to ready.
local function SpellReady(sid, now)
    sid = ns.CooldownKey(sid)
    local charges = ChargesAvailable(sid)
    if charges then return charges > 0 end

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
-- "Game Default" stores no id and follows Blizzard's Text to Speech panel; an uninstalled
-- stored voice falls back rather than going silent. Cached because GetTtsVoices builds a
-- table per call. Blizzard's TTS panel raises no event on a voice change, so closing it or
-- Settings drops the cache; not combat start, where re-reading stalled every pull.
-- Upvalues in a do block rather than file locals: this chunk is at Lua's 200-local ceiling.
do
    local cachedWant, cachedID

    function ns.InvalidateTTSVoice()
        cachedWant, cachedID = nil, nil
    end

    local hookVoicePanels = CreateFrame("Frame")
    hookVoicePanels:RegisterEvent("PLAYER_LOGIN")
    hookVoicePanels:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        for _, panel in ipairs({ _G.SettingsPanel, _G.TextToSpeechFrame }) do
            panel:HookScript("OnHide", ns.InvalidateTTSVoice)
        end
    end)

    function ns.TTSVoiceID()
        local want = TRDB().ttsVoiceID
        if cachedID and cachedWant == want then return cachedID end
        if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then return 0 end
        local voices = C_VoiceChat.GetTtsVoices()
        local resolved
        if want and voices then
            for i = 1, #voices do
                if voices[i].voiceID == want then
                    resolved = want
                    break
                end
            end
        end
        if not resolved and TextToSpeech_GetSelectedVoice then
            local ok, voice = pcall(TextToSpeech_GetSelectedVoice, Enum.TtsVoiceType.Standard)
            if ok and voice and voice.voiceID then resolved = voice.voiceID end
        end
        if not resolved then
            resolved = (voices and voices[1] and voices[1].voiceID) or 0
        end
        -- The voice list can be empty early in a session; do not cache a guess from it.
        if voices and #voices > 0 then cachedWant, cachedID = want, resolved end
        return resolved
    end
end

-- Game Default is keyed "" since a dropdown cannot carry nil as a value.
function ns.TTSVoiceChoices()
    local values, order = { [""] = "Game Default" }, { "" }
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local voices = C_VoiceChat.GetTtsVoices()
        for i = 1, #(voices or {}) do
            local v = voices[i]
            if v and v.voiceID and v.name then
                values[v.voiceID] = v.name
                order[#order + 1] = v.voiceID
            end
        end
    end
    return values, order
end

local function Speak(text)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) or not text or text == "" then return end
    -- (voiceID, text, rate, volume, overlap). The third argument is the rate, as in
    -- Blizzard's TextToSpeechFrame.lua, despite an EllesmereUI note saying it must be 1.
    -- Synthesis blocks the calling thread, so a slower rate is a longer stall. 0 is normal.
    local rate = 0
    if C_TTSSettings and C_TTSSettings.GetSpeechRate then
        rate = C_TTSSettings.GetSpeechRate() or 0
    end
    -- Only `text` may carry a secret; every other argument is NeverSecret.
    -- debugprofilestop is read as a delta and never restarted: the timer is global.
    local p = ns.speakProf
    local before = p and debugprofilestop() or 0
    pcall(C_VoiceChat.SpeakText, ns.TTSVoiceID(), text,
        rate, TRDB().voiceVol or 100, true)
    if p then
        local ms = debugprofilestop() - before
        p.ttsN, p.ttsSum = p.ttsN + 1, p.ttsSum + ms
        if ms > p.ttsMax then p.ttsMax = ms end
    end
end

-- Group channels only: SAY would carry it to strangers.
-- Upvalue in a do block rather than a file local: this chunk is at Lua's 200-local ceiling.
do
    local lastAt = 0
    function ns.AnnounceExternalToChat()
        if not TRDB().externalChat then return end
        local now = GetTime()
        if now - lastAt < 3 then return end
        local channel
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
        elseif IsInRaid() then channel = "RAID"
        elseif IsInGroup() then channel = "PARTY" end
        if not channel then return end
        lastAt = now
        -- Bare SendChatMessage is a deprecation shim behind loadDeprecationFallbacks.
        if C_ChatInfo and C_ChatInfo.SendChatMessage then
            pcall(C_ChatInfo.SendChatMessage, "EXTERNAL!", channel)
        elseif SendChatMessage then
            pcall(SendChatMessage, "EXTERNAL!", channel)
        end
    end
end

local function Announce(spellID, text)
    local key = ns.SoundFor(spellID)
    if key then
        local value = ns.UI.SoundPathFor(key)
        if value then
            ns.UI._PlayLSMSound(value)
            return
        end
        -- The chosen file is gone (SharedMedia pack removed): speak instead.
    end
    Speak(text)
end

-- Repeat suppression for the same pick. Same trigger: a resynced or double-reported bar,
-- seen up to ~10s apart live, hence 12. Different triggers: two casts at the same moment
-- (Entombed Sentinels), kept short so busters seconds apart both announce.
-- On ns rather than chunk locals: this file is at the 200-local ceiling.
ns.SUPPRESS_REPEAT_WINDOW = 12
ns.SUPPRESS_CROSS_TRIGGER_WINDOW = 3
local lastAnnouncedSpellID, lastAnnouncedAt = nil, 0
local lastAnnouncedTrigger

-- Every charge spell on the list, not just the winner, since a loser leaves no trace.
-- An anchor age falling to ~0 between entries with no cast means the state was rebuilt.
local function ChargeModelSnapshot()
    local out
    for i = 1, activeSlots do
        local s = slots[i] and slots[i].spellID
        local st = s and chargeState[ns.CooldownKey(s)]
        if st then
            out = (out and out .. " " or "") .. ("%d=%d/%d %ds(%s) age=%ds cdRunning=%s"):format(
                s, ChargesAvailable(s) or 0, st.max, st.recharge or 0,
                tostring(st.rechargeSrc), GetTime() - (st.tick or GetTime()),
                tostring(CooldownRunning(s)))
        end
    end
    return out
end

local function LogCallout(sid, partners)
    local st = chargeState[ns.CooldownKey(sid)]
    local running = CooldownRunning(sid)
    -- Shows whether Skip When Already Covered saw a buff land.
    local auraUp
    for i = 1, activeSlots do
        local s = slots[i].spellID
        if playerAuraUp[s] then auraUp = (auraUp and auraUp .. "," or "") .. s end
    end
    AppendLog({
        auraUp = auraUp,
        kind = ns.testFiring and "test" or "call",
        sid = sid,
        charges = st and ("%d/%d"):format(ChargesAvailable(sid) or 0, st.max) or nil,
        chargeModel = ChargeModelSnapshot(),
        castTracked = castToBase[sid] ~= nil,
        lastOwnCastAgo = ownCastAt[ns.CooldownKey(sid)] and (GetTime() - ownCastAt[ns.CooldownKey(sid)]) or nil,
        running = running == nil and "unreadable" or tostring(running),
        readyAtDelta = readyAt[ns.CooldownKey(sid)] and (readyAt[ns.CooldownKey(sid)] - GetTime()) or nil,
        secrecy = SecrecyLevelName(sid),
        -- Test fires skip the aggro gate, so lastAggroCheck would be stale there.
        tankSid = (not ns.testFiring) and lastAggroCheck and lastAggroCheck.sid or nil,
        tankPath = (not ns.testFiring) and lastAggroCheck and lastAggroCheck.path or nil,
        withSids = partners and table.concat(partners, ",") or nil,
    })
end

-- Ready members of the pick's Call Together group, in list order. A member that is down is
-- skipped: being in a group must never silence a callout. pcall'd so a throw cannot take
-- the callout with it.
-- ns functions rather than chunk locals: this file is at the 200-local ceiling.
function ns.TogetherPartners(picked, presetKey, now)
    if not (picked and presetKey) then return nil end
    now = now or GetTime()
    local ok, out = pcall(function()
        if not ns.CalledTogetherInPreset(specID, presetKey, picked) then return nil end
        local partners
        for i = 1, activeSlots do
            local sid = slots[i].spellID
            if sid ~= picked and ns.CalledTogetherInPreset(specID, presetKey, sid)
                and SpellReady(sid, now) then
                partners = partners or {}
                partners[#partners + 1] = sid
            end
        end
        return partners
    end)
    return ok and out or nil
end

-- Spoken in list order so it matches the preset row whichever member won. A muted member
-- stays out of the spoken line but keeps its glow.
function ns.SetCalloutLine(picked, partners)
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(picked)
    local own = CalloutFor(picked, info and info.name)
    if not partners then return own end
    local said
    for i = 1, activeSlots do
        local sid = slots[i].spellID
        local part = sid == picked
        if not part then
            for j = 1, #partners do
                if partners[j] == sid then part = true break end
            end
        end
        if part and not ns.IsAudioOff(sid) then
            local si = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            local one = CalloutFor(sid, si and si.name)
            said = said and (said .. " and " .. one) or one
        end
    end
    return said or own
end

-- triggerSid: the boss ability this callout is for, keying the repeat windows.
local function SpeakCallout(triggerSid)
    local t = TRDB()
    if not t.voiceOn or activeSlots == 0 then return end

    -- /nutank speaktime times the pick here and the speech in Speak separately.
    local prof = ns.speakProf
    local pickedAt = prof and debugprofilestop() or 0

    ResyncModel()
    local now = GetTime()

    -- pcall'd: an error mid-loop once skipped the fallback and the result was silence.
    local ok, picked = pcall(function()
        for i = 1, activeSlots do
            local sid = slots[i].spellID
            if SpellReady(sid, now) then return sid end
        end
    end)

    if prof then
        local ms = debugprofilestop() - pickedAt
        prof.pickN, prof.pickSum = prof.pickN + 1, prof.pickSum + ms
        if ms > prof.pickMax then prof.pickMax = ms end
    end

    -- A thrown pick is printed, or the fallback hides it. A secret-carrying error raises
    -- again on tostring.
    if not ok then
        local why = picked
        if issecretvalue and issecretvalue(why) then
            why = "the error itself carries a secret"
        end
        ns.Print("|cffff6060pick failed|r, using the fallback: " .. tostring(why))
        picked = nil
    end

    if picked then
        local partners = ns.TogetherPartners(picked, ns.slotsPreset, now)

        -- Outside the audio gate: a muted entry still wins and still glows.
        ns.StartCDMGlow(picked)
        if partners then
            for i = 1, #partners do ns.StartCDMGlow(partners[i], true) end
        end
        -- A muted winner means silence, not the next one down.
        if not ns.IsAudioOff(picked) then
            local sinceLast = now - lastAnnouncedAt
            if picked == lastAnnouncedSpellID and
                ((triggerSid == lastAnnouncedTrigger and sinceLast < ns.SUPPRESS_REPEAT_WINDOW)
                    or (triggerSid ~= lastAnnouncedTrigger
                        and sinceLast < ns.SUPPRESS_CROSS_TRIGGER_WINDOW)) then
                if t.trace then AppendLog({ kind = "quiet", sid = picked, tankSid = triggerSid }) end
                return
            end
            lastAnnouncedSpellID, lastAnnouncedTrigger, lastAnnouncedAt = picked, triggerSid, now
            LogCallout(picked, partners)
            Announce(picked, ns.SetCalloutLine(picked, partners))
        end
        return
    end

    -- Per ability, falling back to the spec-wide toggle (a test fire has no triggerSid).
    if ns.ExternalCallFor(currentEncounter, triggerSid) then
        if not ns.IsAudioOff(0) then Announce(0, t.voiceNone) end
        -- Outside the audio gate: silencing the callout should not silence the chat call.
        ns.AnnounceExternalToChat()
    elseif ok then
        return "waiting"
    end
end

-------------------------------------------------------------------------------
--  Showing and hiding
-------------------------------------------------------------------------------
-- Visibility is driven by plain data only: SetShown is AllowedWhenUntainted and would error
-- on a secret.

-- Printed in report headers so "is the current code loaded" is answered outright.
local function BuildString()
    local toc = (C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(ns.MODULE_KEY, "Version")) or "unknown"
    -- The TOC half only moves on release; ns.CODE_BUILD moves whenever the Lua does.
    return ns.CODE_BUILD and (toc .. " code " .. ns.CODE_BUILD) or toc
end

-- Never tostring an error straight into a message: an error raised by a secret carries it.
-- issecretvalue() is the guard that matters: tostring() on a secret returns a secret
-- string that rides through format and .. until the display call silently drops the line.
local function ErrText(err)
    if issecretvalue and issecretvalue(err) then
        return "unreadable (the error itself carries a secret)"
    end
    local ok, text = pcall(function() return tostring(err) end)
    return ok and text or "unreadable"
end

-- Options window open, respected by every hide path. Declared here because reads above
-- the rest of the preview state compiled to a nil global.
local previewing = false

-- GetSpellID can come back secret in restricted content, so every read is screened.
function ns.CDMButtonForSpell(spellID)
    if not spellID then return nil end
    local viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer",
                      "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    for i = 1, #viewers do
        local viewer = _G[viewers[i]]
        if viewer and viewer.GetItemFrames then
            local ok, items = pcall(viewer.GetItemFrames, viewer)
            if ok and type(items) == "table" then
                for j = 1, #items do
                    local item = items[j]
                    if item and item.GetSpellID then
                        local ok2, sid = pcall(item.GetSpellID, item)
                        if ok2 and not (issecretvalue and issecretvalue(sid))
                            and type(sid) == "number" and sid == spellID then
                            return item
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- The glow rides our own frame anchored over the button, never a child of Blizzard's:
-- CooldownViewerSecure tables refuse tainted access. One anchor per Call Together member.
do
    local glowing = {}
    local GLOW_COLOR = { 1, 0.82, 0, 1 }

    function ns.StopCDMGlow()
        local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
        for i = #glowing, 1, -1 do
            local anchor = glowing[i]
            if LCG then pcall(LCG.PixelGlow_Stop, anchor) end
            anchor:Hide()
            glowing[i] = nil
        end
    end

    -- keep = add to what is already lit, for the rest of a set.
    function ns.StartCDMGlow(spellID, keep)
        if not TRDB().cdmGlow then return end
        if not keep then ns.StopCDMGlow() end
        local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
        if not LCG then return end
        local btn = ns.CDMButtonForSpell(spellID)
        if not btn then return end
        if type(ns.cdmGlowFrames) ~= "table" then ns.cdmGlowFrames = {} end
        local anchor = ns.cdmGlowFrames[#glowing + 1]
        if not anchor then
            anchor = CreateFrame("Frame", nil, UIParent)
            anchor:SetFrameStrata("HIGH")
            ns.cdmGlowFrames[#glowing + 1] = anchor
        end
        anchor:ClearAllPoints()
        anchor:SetAllPoints(btn)
        anchor:Show()
        glowing[#glowing + 1] = anchor
        LCG.PixelGlow_Start(anchor, GLOW_COLOR)
    end
end

local function HideReminder()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    ns.activeAuthoredReminder = nil
    shownForEvent = nil
    -- Undo any Preview-specific elevation so a real fight never inherits it.
    if frame then frame:SetFrameStrata("HIGH") end
    if textFrame then textFrame:SetFrameStrata("HIGH") end
    ns.StopCDMGlow()
    if frame then
        if frame.reminder then frame.reminder:Hide() end
        if frame.castTarget then frame.castTarget:Hide() end
        frame:Hide()
    end
    if textFrame then textFrame:Hide() end
    if bar then bar:Hide() end
    if ns.slotsStale then
        ns.slotsStale = nil
        RebuildSlots()
    end
end

-- Alpha may be secret; when it cannot be read, the timed display stays.
function ns.HideIfCalloutPressed(castSpellID)
    if TRDB().hideOnCast ~= true or not shownForEvent then return end
    local sid = castSpellID and castToBase[castSpellID]
    if not sid then return end
    for i = 1, activeSlots do
        local slot = slots[i]
        if slot.spellID == sid then
            local ok, alpha = pcall(slot.GetAlpha, slot)
            if ok and not (issecretvalue and issecretvalue(alpha))
                and type(alpha) == "number" and alpha > 0 then
                HideReminder()
                return
            end
        end
    end
end

-- The target name and class are secret: the name goes straight into its own font string,
-- the class into GetClassColor then SetTextColor. Only UnitShouldDisplaySpellTargetName is
-- plain. Same shape as Blizzard's cast bar. The voice cannot follow any of it.
function ns.ShowCastTargetOn(unit, allowed)
    if not frame or type(unit) ~= "string" then return false end
    if not (UnitShouldDisplaySpellTargetName and UnitSpellTargetName) then return false end
    if not allowed then return false end

    local named = ns.CastNamesATarget(unit)
    if not named and frame.castTarget then frame.castTarget:Hide() end

    if named and frame.castTarget then
        local gotName, name = pcall(UnitSpellTargetName, unit)
        if gotName and name ~= nil then
            frame.castTarget:SetText(name)
            -- Reset first: the class lookup can return nothing.
            frame.castTarget:SetTextColor(1, 1, 1, 1)
            if UnitSpellTargetClass and C_ClassColor and C_ClassColor.GetClassColor then
                local gotColour, colour = pcall(function()
                    return C_ClassColor.GetClassColor(UnitSpellTargetClass(unit))
                end)
                if gotColour and colour then
                    pcall(function() frame.castTarget:SetTextColor(colour:GetRGB()) end)
                end
            end
            if ns.PlaceCastTargetLine then ns.PlaceCastTargetLine() end
            frame.castTarget:Show()
        end
    end

    return named
end
-- Plain, so callers can ask before drawing a callout at all.
function ns.CastNamesATarget(unit)
    if type(unit) ~= "string" or not UnitShouldDisplaySpellTargetName then return false end
    -- False also covers "not casting" and "casting at nobody".
    local ok, show = pcall(UnitShouldDisplaySpellTargetName, unit)
    return ok and show == true
end
-- The Says row's Preview button.
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
    ns.activeAuthoredReminder = nil
    shownForEvent = nil
    frame:Show()
    if textFrame then textFrame:Show() end
    SpeakCallout()

    local t2 = TRDB()
    if not (t2.showIcon or t2.showText or t2.voiceOn) then
        ns.Print("|cffff6060icon, text and voice are all switched off|r -- there is nothing "
            .. "for this test to show. Play a Sound is engine-driven and only fires on a "
            .. "real boss.")
    end
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(TRDB().lingerSec or DEFAULTS.lingerSec, HideReminder)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local watcher

local function BossAllowed()
    local t = TRDB()
    if not (currentEncounter and type(t.bossOff) == "table") then return true end
    return t.bossOff[tostring(currentEncounter)] ~= true
end

-- The timeline also carries respawn timers and other non-encounter events.
local function InEncounter()
    if C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress then
        return C_InstanceEncounter.IsEncounterInProgress()
    end
    return currentEncounter ~= nil
end
ns.InEncounter = InEncounter
ns.BossAllowed = BossAllowed
function ns.CurrentEncounter() return currentEncounter end

local function EngineAvailable()
    return ns.BossSource() ~= "timeline" or TimelineAvailable()
end

local function ShouldRun()
    return TRDB().enabled == true and canSelect
        and activeSlots > 0 and EngineAvailable() and BossAllowed()
end

-------------------------------------------------------------------------------
--  Custom reminders: pull, BigWigs/DBM message and BigWigs/DBM timer triggers
-------------------------------------------------------------------------------
-- Never gated on ShouldRun()/activeSlots: these work with an empty priority list.
local function CustomRemindersAllowed()
    return TRDB().enabled == true and BossAllowed()
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

-- Per-uid occurrence count for the "Nth cast" counter, reset every pull.
local customCounters = {}
-- Cached at ENCOUNTER_START for OnCombatLog's hot path.
local hasCustomReminders = false
local hasRaidReminders = false

local function RefreshCustomRemindersFlag()
    local set = currentEncounter and CustomRemindersTable(false, currentEncounter)
    hasCustomReminders = set ~= nil and next(set) ~= nil
    -- Cached, so every raid-reminder edit path must call this refresh.
    local rr = currentEncounter and ns.RaidRemindersTable
        and ns.RaidRemindersTable(false, currentEncounter)
    hasRaidReminders = rr ~= nil and next(rr) ~= nil
    -- Resolved through ns: defined further down the file, and it no-ops before then.
    if ns.RefreshCastWatch then ns.RefreshCastWatch() end
end
ns.RefreshCustomRemindersFlag = RefreshCustomRemindersFlag

-- On ns rather than local: the main chunk is at Lua's 200-local ceiling.
function ns.PickFromList(list)
    if type(list) ~= "table" then return nil end
    local now = GetTime()
    -- SpellReady can raise if a cooldown's classification changes mid-read.
    local ok, picked = pcall(function()
        for i = 1, #list do
            local sid = list[i]
            if IsSpellAvailable(sid) then
                ResyncSpell(sid)
                if SpellReady(sid, now) then return sid end
            end
        end
    end)
    return ok and picked or nil
end

-- Resolved against the current spec: preset keys are per spec.
local function PickFromPreset(presetKey)
    local presets = PresetsTable(specID, false)
    local p = presets and presets[presetKey]
    return ns.PickFromList(p and p.list)
end

function ns.PlayReminderSound(r)
    if not r.sound then return end
    local path = ns.UI.SoundPathFor(r.sound)
    if path then ns.UI._PlayLSMSound(path) end
end

-- Preview failures are printed rather than leaving a silent icon unexplained.
function ns.SpeakReminderTTS(r, overrideText, preview)
    if not (r and r.tts) then return end
    local text = overrideText or r.text
    if not (text and text ~= "") then return end
    local function Unavailable(message)
        if preview then ns.Print(message) end
    end
    if not (C_VoiceChat and C_VoiceChat.SpeakText and C_VoiceChat.GetTtsVoices) then
        return Unavailable("TTS is unavailable in this client.")
    end
    local voices = C_VoiceChat.GetTtsVoices()
    if not voices or #voices == 0 then
        return Unavailable("No TTS voices are available. Check WoW's Text to Speech settings.")
    end
    local voiceID = ns.TTSVoiceID()
    if not voiceID then return Unavailable("No TTS voice is selected.") end
    local rate = (C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or 0
    local volume = TRDB().voiceVol or 100
    if volume <= 0 then
        return Unavailable("Voice Volume is zero. Raise it under Smart Reminders > Setup > Sounds and Voice.")
    end
    -- Blizzard's documented order is voiceID, text, rate, volume, overlap.
    local ok = pcall(C_VoiceChat.SpeakText, voiceID, text, rate, volume, false)
    if not ok then return Unavailable("WoW could not start TTS playback. Check its Text to Speech settings.") end
end

-- The spell a defensive-bound reminder would call, so text and icon cannot disagree.
-- On ns rather than local: the main chunk is at Lua's 200-local ceiling.
function ns.ResolveReminderSpell(r, presetKey)
    if not r then return nil end
    if r.abilitySpellID then
        local list = EffectiveList(specID, currentEncounter, tostring(r.abilitySpellID))
        local picked = ns.PickFromList(list)
        if picked then return picked end
    end
    -- The caller's key wins: it is the preset the slots were actually built from.
    presetKey = presetKey or r.preset
    if presetKey then return PickFromPreset(presetKey) end
    return nil
end

-- Authored reminders draw on the defensive alert itself, never a second frame.
-- opts: fp, preset, text, dur, audio, preview, resolveFrom.
local function ShowOnAlert(opts)
    if not frame then Reminder.Create() end
    if not frame then return false end

    if opts.preset or opts.fp then
        if not RebuildSlots(opts.fp or "authored", true, opts.preset) then return false end
        ApplyPriorityAlpha()
        ClearTankGate()
        if frame.reminder then frame.reminder:Hide() end
    elseif frame.reminder and type(opts.text) == "string" and opts.text ~= "" then
        -- Blank the slots, or a line-only reminder shows the last preset's defensive.
        for i = 1, #slots do slots[i]:SetAlpha(0) end
        activeSlots = 0
        if frame.fallback then frame.fallback:SetAlpha(0) end
        ns.slotsStale = true
        frame.reminder:SetText(opts.text)
        frame.reminder:Show()
    else
        return false
    end

    -- Cleared on every fire, or a re-armed display inherits the last cast's target name.
    if frame.castTarget then frame.castTarget:Hide() end

    -- ApplyReminderFilter reads this to pull a live callout that was just filtered out.
    ns.activeAuthoredReminder = opts.resolveFrom
    -- Marks the alert occupied so a rebuild or the options preview cannot pull it.
    shownForEvent = "authored"
    -- The editor's Preview fires from a FULLSCREEN_DIALOG modal; HideReminder drops it back.
    if opts.preview then
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        if textFrame then textFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
    end
    frame:Show()
    if textFrame then textFrame:Show() end

    if opts.audio then
        local spoken, resolved = opts.text, true
        if opts.resolveFrom and (opts.preset or opts.fp) then
            local picked = ns.ResolveReminderSpell(opts.resolveFrom, opts.preset)
            -- The full Call Together line, read from the slots RebuildSlots just filled.
            local named = picked and ns.SetCalloutLine(picked,
                ns.TogetherPartners(picked, ns.slotsPreset))
            if named and named ~= "" then spoken = named else resolved = false end
        end
        -- Unresolved means nothing on the list is up, so the audio stays silent too.
        if resolved then
            ns.PlayReminderSound(opts.audio)
            ns.SpeakReminderTTS(opts.audio, spoken, opts.preview)
        elseif TRDB().trace then
            AppendLog({ kind = "drop",
                sid = opts.resolveFrom.trigger and opts.resolveFrom.trigger.spellID,
                text = "authored callout silent; nothing on the preset is ready" })
        end
    end

    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer((type(opts.dur) == "number" and opts.dur > 0)
        and opts.dur or 3, HideReminder)
    return true
end

local function FireCustomReminder(r)
    if not r then return end
    return ShowOnAlert({
        fp = r.abilitySpellID and tostring(r.abilitySpellID) or nil,
        preset = r.preset,
        text = (type(r.msg) == "string" and r.msg ~= "" and r.msg) or r.name,
        dur = r.dur,
        audio = r,
        resolveFrom = r,
    })
end

-- Shared by the real fire path and the editor's Preview.
function ns.DisplayReminder(r)
    if not ns.IsReminderEnabled(r) then return end
    if r.defensive then
        if r.specID and r.specID ~= specID then return end
        if not CustomRemindersAllowed() then return end
        return ns.FireMessageDefensive(r)
    end
    return FireCustomReminder(r)
end

function ns.PreviewCustomReminder(r)
    ns.DisplayReminder(r)
end

-- Tracked so they can be cancelled (untracked, a 4:30 reminder fired after a 0:40 wipe).
-- "pull" timers die on encounter boundaries; "stage" timers also on a stage change or
-- module disable. ns fields, not chunk locals: this chunk is at the 200-local ceiling.
ns.trackedReminderTimers = {}

function ns.IsCurrentCustomReminder(r, set)
    if not ns.IsReminderEnabled(r) or (r.specID and r.specID ~= specID) then return false end
    if set ~= CustomRemindersTable(false, currentEncounter) then return false end
    for _, current in pairs(set or {}) do
        if current == r then return true end
    end
    return false
end

function ns.PruneCustomReminderTimers()
    local timers = ns.trackedReminderTimers
    for i = #timers, 1, -1 do
        local entry = timers[i]
        if (entry.reminder and not ns.IsCurrentCustomReminder(entry.reminder, entry.reminderSet))
            or (entry.valid and not entry.valid()) then
            entry.handle:Cancel()
            table.remove(timers, i)
        end
    end
end

-- Creates the timer itself so a timer that fires can drop its own entry.
function ns.TrackReminderTimer(scope, delay, fn, reminder, valid)
    if reminder and not ns.IsReminderEnabled(reminder) then return end
    if valid and not valid() then return end
    local list = ns.trackedReminderTimers
    local entry = { scope = scope, reminder = reminder, valid = valid,
        reminderSet = reminder and CustomRemindersTable(false, currentEncounter) }
    entry.handle = C_Timer.NewTimer(delay, function()
        for i = #list, 1, -1 do
            if list[i] == entry then table.remove(list, i) break end
        end
        if reminder and not ns.IsCurrentCustomReminder(reminder, entry.reminderSet) then return end
        if valid and not valid() then return end
        fn()
    end)
    list[#list + 1] = entry
    return entry.handle
end

function ns.CancelTrackedReminderTimers(scope)
    local t = ns.trackedReminderTimers
    for i = #t, 1, -1 do
        if scope == nil or t[i].scope == scope then
            local h = t[i].handle
            if h.Cancel then h:Cancel() end
            table.remove(t, i)
        end
    end
end

-- Returns true only when a callout went up right now; the cast-target display keys off it.
local function ActivateCustomReminder(r, scope)
    if not ns.IsReminderEnabled(r) then return end
    local delays = ParseDelayList(r.trigger and r.trigger.delay)
    if not delays then
        return ns.DisplayReminder(r) == true
    end
    -- The regen listener may be absent, so combat is rechecked when the timer fires.
    local combat = (scope == "combat")
    for i = 1, #delays do
        ns.TrackReminderTimer(scope or "pull", delays[i], function()
            if combat and not InCombatLockdown() then return end
            ns.DisplayReminder(r)
        end, r)
    end
end

-- Boss cast triggers use UNIT_SPELLCAST_*: CLEU is unavailable in restricted content.
-- Keyed by spell id so the handler never compares the event spellID, which is
-- SecretWhenUnitSpellCastRestricted.
function ns.RefreshCastWatch()
    local index, any = {}, false
    local set = currentEncounter and CustomRemindersTable(false, currentEncounter)
    if set then
        for uid, r in pairs(set) do
            local trig = r.trigger
            local kind = trig and trig.type
            if r.enabled ~= false and (kind == "caststart" or kind == "castend")
               and type(trig.spellID) == "number" then
                local entry = index[trig.spellID]
                if not entry then entry = {}; index[trig.spellID] = entry end
                entry[kind] = entry[kind] or {}
                entry[kind][#entry[kind] + 1] = { uid = uid, r = r }
                any = true
            end
        end
    end
    -- No trash rules: their cast ids are secret, so the lookup never matched (removed after 1.4.1).
    ns.watchedCasts = index

    -- Armed for the target name alone: the cast id is secret for any unit not the player
    -- or pet, but naming the target never needed it. Bounded to an encounter.
    if currentEncounter and TRDB().castTargetBoss then any = true end

    if any and not ns.castWatcher then
        ns.castWatcher = CreateFrame("Frame")
        ns.castWatcher:SetScript("OnEvent", function(_, event, unit, _, spellID)
            ns.OnBossCast(event, unit, spellID)
        end)
    end
    if ns.castWatcher then
        if any then
            -- Not RegisterUnitEvent: it takes only a couple of units.
            ns.castWatcher:RegisterEvent("UNIT_SPELLCAST_START")
            ns.castWatcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        else
            ns.castWatcher:UnregisterAllEvents()
        end
    end
end

-- Cast end is SUCCEEDED only: an interrupted cast never happened.
function ns.OnBossCast(event, unit, spellID)
    -- Unit filter first: every cast in the group lands here. Plain find, not a pattern,
    -- since this is the per-event cost.
    if type(unit) ~= "string" then return end
    local isBoss = unit:find("boss", 1, true) == 1
    if not (isBoss or unit:find("nameplate", 1, true) == 1) then return end
    if not CustomRemindersAllowed() then return end

    -- The cast target goes onto the alert already on screen, unmatched to its ability
    -- (the id is secret), so boss units only, where there is one caster. Every branch is
    -- traced: each silent outcome looks identical in play.
    if event == "UNIT_SPELLCAST_START" and isBoss then
        local why
        if not TRDB().castTargetBoss then why = "target display off"
        elseif not shownForEvent then
            -- Asked even with no alert, so a trace shows which abilities name a target.
            why = TRDB().trace and ns.CastNamesATarget(unit)
                and "no alert, but this cast names somebody" or "no alert to name"
        elseif ns.ShowCastTargetOn(unit, true) then why = "target named"
        else why = "cast names nobody" end
        if TRDB().trace then AppendLog({ kind = "bosscast", unit = unit, text = why }) end
    end

    local index = ns.watchedCasts
    if not index then return end
    -- Screened before the lookup: a secret cannot be used as a table key.
    local plain = not (issecretvalue and issecretvalue(spellID)) and spellID or nil
    local entry = plain and index[plain]
    -- Traced on both paths: a miss is otherwise indistinguishable from no cast.
    if TRDB().trace then
        -- Never the raw id: a secret must not reach callLog in SavedVariables.
        AppendLog({ kind = "bosscast", sid = plain, unit = unit,
            text = entry and "matched" or "not watched" })
    end
    if not entry then return end

    local list = entry[event == "UNIT_SPELLCAST_START" and "caststart" or "castend"]
    if not list then return end

    for i = 1, #list do
        local uid, r = list[i].uid, list[i].r
        local hit = true
        if r.trigger.counter and r.trigger.counter ~= "" then
            customCounters[uid] = (customCounters[uid] or 0) + 1
            hit = CheckCounterCondition(ParseCounterCondition(r.trigger.counter),
                customCounters[uid])
        end
        if hit then
            local shown = ActivateCustomReminder(r)
            -- Only once a callout is up, and start only: on SUCCEEDED the unit has stopped
            -- casting and the client reports no target.
            if shown and event == "UNIT_SPELLCAST_START" then
                ns.ShowCastTargetOn(unit, TRDB().castTargetBoss)
            end
        end
    end
end

-- The pull clocks, for the observed-timing recorder.
function ns.PullContext()
    return currentEncounterStartedAt, currentDifficultyID, currentStage, currentStageAt
end

-- Read at event time, never cached: Setup changes it live. With no saved pick it follows
-- the installed boss mod, resolved live and never written, so the observed timeline
-- records without Setup ever being opened.
function ns.BossSource()
    local saved = TRDB().bossSource
    if saved and not (saved == "timeline" and not TimelineAvailable()) then return saved end
    if _G.BigWigsLoader then return "bigwigs" end
    if _G.DBM then return "dbm" end
    return "timeline"
end

-- kind: "pull" | "cast" | "aura". "cast"/"aura" are legacy combat-log triggers, still honored.
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

-- Time In Combat triggers (stored under PerBossSet's "0" bucket when not on a boss).
function ns.CheckCombatReminders()
    -- Retired trigger; saved records are retained for manual editing.
end

function ns.CheckBossCombatReminders()
    -- Retired trigger; saved records are retained for manual editing.
end

-------------------------------------------------------------------------------
--  Custom reminders: BigWigs/DBM message and timer triggers
-------------------------------------------------------------------------------
-- Latched on the first message so running both BigWigs and DBM does not fire twice.
local bwActiveMod

-- Keyed by uid .. "|" .. mod .. ":" .. bar text: stop/pause events only carry the text.
local bwPendingTimers = {}
ns.pendingCustomReminderOwners = {}


-- Keys end in "|mod:identity". An exact identity cancels that bar only; "" cancels every bar
-- from the mod.
local function CancelBossModTimers(mod, text)
    local tag = "|" .. mod .. ":"
    local suffix = tag .. tostring(text)
    for k, handle in pairs(bwPendingTimers) do
        local hit
        if text == "" then
            hit = k:find(tag, 1, true) ~= nil
        else
            hit = k:sub(-#suffix) == suffix
        end
        if hit then
            if handle.Cancel then handle:Cancel() end
            bwPendingTimers[k] = nil
            ns.pendingCustomReminderOwners[k] = nil
        end
    end
end

function ns.HasMessageDefensive(encounterID, sid)
    local set = CustomRemindersTable(false, encounterID)
    if not set then return false end
    for _, r in pairs(set) do
        if r.defensive and r.enabled ~= false and (not r.specID or r.specID == specID)
            and r.trigger and r.trigger.type == "bwmsg" then
            -- The catalogue saves DBM's raw id; HandleBigWigsAbility asks with the BigWigs key.
            local key = r.trigger.spellID
            if key == sid or (ns.DBM_TO_BIGWIGS and ns.DBM_TO_BIGWIGS[key] == sid) then
                return true
            end
        end
    end
    return false
end

local function CheckBossModMessage(mod, key, encounterID, retried)
    if TRDB().trace then
        AppendLog({ kind = "drop", sid = key, text = "message check: mod=" .. mod
            .. " expectedEncounter=" .. tostring(encounterID) .. " cached=" .. tostring(hasCustomReminders)
            .. " retry=" .. tostring(retried) })
    end
    -- Boss mods can announce opening casts before our ENCOUNTER_START has run, so retry
    -- next frame. DBM names no encounter, so any early DBM message is retried.
    local early
    if encounterID then
        early = currentEncounter ~= encounterID or not hasCustomReminders
    else
        early = currentEncounter == nil and CustomRemindersAllowed()
    end
    if early then
        if not retried then
            C_Timer.After(0, function()
                if currentEncounter ~= nil
                    and (encounterID == nil or currentEncounter == encounterID) then
                    CheckBossModMessage(mod, key, encounterID, true)
                end
            end)
        end
        return
    end
    if bwActiveMod and bwActiveMod ~= mod then return end
    if type(key) ~= "number" then return end
    if not (hasCustomReminders and CustomRemindersAllowed()) then return end
    local set = CustomRemindersTable(false, currentEncounter)
    if not set then return end
    local matched = false
    for uid, r in pairs(set) do
        local trig = r.trigger
        if r.enabled ~= false and (not r.specID or r.specID == specID)
            and trig and trig.type == "bwmsg" and trig.spellID == key then
            matched = true
            local hit = true
            if trig.counter and trig.counter ~= "" then
                customCounters[uid] = (customCounters[uid] or 0) + 1
                hit = CheckCounterCondition(ParseCounterCondition(trig.counter), customCounters[uid])
            end
            if TRDB().trace then
                AppendLog({ kind = "drop", sid = key, text = "message matched: " .. (r.name or "Reminder")
                    .. " counterPassed=" .. tostring(hit) .. " delay=" .. tostring(trig.delay)
                    .. " preset=" .. tostring(r.preset) })
            end
            if hit then ActivateCustomReminder(r) end
        end
    end
    if not matched and TRDB().trace then
        AppendLog({ kind = "drop", sid = key, text = "message: no enabled reminder matched" })
    end
    if matched and not bwActiveMod then bwActiveMod = mod end
end

-- barIdentity is what the mod's stop/pause event hands back: bar text for BigWigs, timer
-- ID for DBM. A "(3)" count in the bar text overrides our own tally for the counter.
local function CheckBossModTimerStart(mod, key, barIdentity, duration, text, retried)
    if type(key) ~= "number" or type(duration) ~= "number" then return end
    -- An engage bar can arrive before our ENCOUNTER_START: retried next frame.
    if currentEncounter == nil then
        if not retried and CustomRemindersAllowed() then
            local at = GetTime()
            C_Timer.After(0, function()
                if currentEncounter ~= nil then
                    CheckBossModTimerStart(mod, key, barIdentity, duration - (GetTime() - at),
                        text, true)
                end
            end)
        end
        return
    end
    if bwActiveMod and bwActiveMod ~= mod then return end
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
            if hit and ns.IsReminderEnabled(r) then
                local barKey = uid .. "|" .. mod .. ":" .. tostring(barIdentity)
                -- Some modules resync a running bar; do not stack a second pending fire.
                local old = bwPendingTimers[barKey]
                if old and old.Cancel then old:Cancel() end
                local fireDelay = math.max(duration - trig.timeleft, 0.01)
                ns.pendingCustomReminderOwners[barKey] = r
                bwPendingTimers[barKey] = C_Timer.NewTimer(fireDelay, function()
                    bwPendingTimers[barKey] = nil
                    ns.pendingCustomReminderOwners[barKey] = nil
                    if ns.IsCurrentCustomReminder(r, set) then ActivateCustomReminder(r) end
                end)
            end
        end
    end
    if matched and not bwActiveMod then bwActiveMod = mod end
end

-- kind: "applied" | "removed" | "stacks" (SPELL_AURA_APPLIED_DOSE). Boss means one of
-- boss1-5, not a hostile-NPC flag that would catch trash. Stack counts come off the combat
-- log: C_UnitAuras errors on a boss unit in restricted content. For "stacks", trig.counter
-- is a threshold on amount (">=3"), not an occurrence tally.
local function CheckAuraReminder(kind, destGUID, spellID, amount)
    if not (hasCustomReminders and CustomRemindersAllowed()) then return end
    if type(spellID) ~= "number" or type(destGUID) ~= "string" then return end
    -- Ahead of the GUID tests, which otherwise ran on every aura line.
    local set = CustomRemindersTable(false, currentEncounter)
    if not set then return end
    local isPlayer = destGUID == PlayerGUID()
    local isBoss = not isPlayer and ns.bossGUIDs[destGUID] == true
    if not (isPlayer or isBoss) then return end
    for uid, r in pairs(set) do
        local trig = r.trigger
        if r.enabled ~= false and trig and trig.type == "aura" and trig.spellID == spellID
           and (trig.auraEvent or "applied") == kind
           and (trig.target == "player") == isPlayer then
            local hit = true
            if kind == "stacks" then
                hit = type(amount) == "number"
                    and CheckCounterCondition(ParseCounterCondition(trig.counter), amount)
            elseif trig.counter and trig.counter ~= "" then
                customCounters[uid] = (customCounters[uid] or 0) + 1
                hit = CheckCounterCondition(ParseCounterCondition(trig.counter), customCounters[uid])
            end
            if hit then ActivateCustomReminder(r) end
        end
    end
end

-------------------------------------------------------------------------------
--  BigWigs/DBM-driven primary callout
-------------------------------------------------------------------------------
-- BigWigs/DBM hand over a plain spell id, so this decides directly off it.
local lastBWSid, lastBWAt = nil, 0

-- Role and class are OR'd; no scope means private to the owning spec.
function ns.BindingSharedToMe(b)
    local scope = b and b.scope
    if type(scope) ~= "table" then return false end
    if type(scope.roles) == "table" and ns.playerRole and scope.roles[ns.playerRole] then return true end
    if type(scope.classes) == "table" and ns.playerClass and scope.classes[ns.playerClass] then return true end
    return false
end

-- Migration from abilityBindings[enc][sid] to [specKey][enc][sid]. Owner is build 0901a's
-- scope.specs when present, else whoever logs in first; scope.specs is then dropped.
-- Run at login, not in TRDB: the profile is often prepared before the spec is known.
function ns.MigrateBindingScopes()
    if specID == 0 then return end
    local t = TRDB()
    if t.bindingsBySpec then return end
    local all = t.abilityBindings
    if type(all) ~= "table" then
        t.bindingsBySpec = true
        return
    end

    local backup, moved, rebuilt = {}, 0, {}
    for encKey, bySpell in pairs(all) do
        if type(bySpell) == "table" then
            local encCopy = {}
            for sid, b in pairs(bySpell) do
                if type(b) == "table" then
                    local copy = {}
                    for k, v in pairs(b) do copy[k] = v end
                    encCopy[sid] = copy

                    local owners = {}
                    if type(b.scope) == "table" and type(b.scope.specs) == "table" then
                        for id in pairs(b.scope.specs) do owners[#owners + 1] = tostring(id) end
                    end
                    if #owners == 0 then owners[1] = tostring(specID) end

                    if type(b.scope) == "table" then
                        b.scope.specs = nil
                        if not next(b.scope) then b.scope = nil end
                    end

                    for _, specKey in ipairs(owners) do
                        rebuilt[specKey] = rebuilt[specKey] or {}
                        rebuilt[specKey][encKey] = rebuilt[specKey][encKey] or {}
                        -- Each owner gets its own copy, or the aliasing comes back.
                        local own = {}
                        for k, v in pairs(b) do own[k] = v end
                        if type(b.scope) == "table" then
                            local sc = {}
                            for k, v in pairs(b.scope) do sc[k] = v end
                            own.scope = sc
                        end
                        rebuilt[specKey][encKey][sid] = own
                        moved = moved + 1
                    end
                end
            end
            backup[encKey] = encCopy
        end
    end

    t.abilityBindings = rebuilt
    if moved > 0 and t.preSpecBindings == nil then t.preSpecBindings = backup end
    t.bindingsBySpec = true
    t.scopeMigrated = nil
    if moved > 0 then
        ns.Print(("|cffffa300%d saved abilities|r now belong to the spec that made them. Other specs start clean -- your originals are kept if this guessed wrong.")
            :format(moved))
    end
end

-- Engine sids are always the boss-mod broadcast key, while Setup rows may store the
-- journal id; ns.BOSSMOD_KEY_TO_JOURNAL bridges the confirmed mismatches.
-- On ns rather than local: the main chunk is at Lua's 200-local ceiling.
function ns.BindingForBossModKey(enc, sid)
    local bindings = AbilityBindingsTable(false, enc)
    local b
    if bindings then
        b = bindings[sid]
        if b == nil and ns.BOSSMOD_KEY_TO_JOURNAL then
            local jid = ns.BOSSMOD_KEY_TO_JOURNAL[sid]
            if jid then b = bindings[jid] end
        end
    end
    -- Our own spec's binding wins; a share from another spec only fills the gap.
    if b == nil then b = ns.InheritedBinding(enc, sid) end
    return b
end

-- Tells a genuinely empty page from one whose work sits under another spec.
function ns.OwnBindingCount(encSet)
    if specID == 0 then return 0 end
    local t = TRDB()
    local n = 0
    local all = type(t.abilityBindings) == "table" and t.abilityBindings or nil
    local mine = all and all[tostring(specID)]
    if type(mine) == "table" then
        for eKey, bySpell in pairs(mine) do
            if type(bySpell) == "table" and (not encSet or encSet[eKey]) then
                for _ in pairs(bySpell) do n = n + 1 end
            end
        end
    end
    -- Message reminders count too, as in ns.SpecsWithBindings.
    local sets = type(t.customReminders) == "table" and t.customReminders or {}
    for eKey, set in pairs(sets) do
        if type(set) == "table" and (not encSet or encSet[eKey]) then
            for _, r in pairs(set) do
                if type(r) == "table" and r.defensive and r.specID == specID
                    and r.trigger and r.trigger.type == "bwmsg" then
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- Feeds the Copy From Spec picker. encSet must match the one CopyBindingsFromSpec gets.
function ns.SpecsWithBindings(encounterID, encSet)
    local t = TRDB()
    local all = type(t.abilityBindings) == "table" and t.abilityBindings or {}
    local mine, counts = tostring(specID), {}
    local encKey = tostring(encounterID or 0)
    local function Count(specKey, eKey)
        if specKey == mine or (encSet and not encSet[eKey]) then return end
        local c = counts[specKey]
        if not c then c = { total = 0, here = 0 }; counts[specKey] = c end
        c.total = c.total + 1
        if eKey == encKey then c.here = c.here + 1 end
    end
    for specKey, byEnc in pairs(all) do
        if type(byEnc) == "table" then
            for eKey, bySpell in pairs(byEnc) do
                if type(bySpell) == "table" then
                    for _ in pairs(bySpell) do Count(specKey, eKey) end
                end
            end
        end
    end
    -- Message reminders sit under the boss with a specID field, not under the spec key.
    local sets = type(t.customReminders) == "table" and t.customReminders or {}
    for eKey, set in pairs(sets) do
        if type(set) == "table" then
            for _, r in pairs(set) do
                if type(r) == "table" and r.defensive and r.specID
                    and r.trigger and r.trigger.type == "bwmsg" then
                    Count(tostring(r.specID), eKey)
                end
            end
        end
    end
    local out = {}
    for specKey, c in pairs(counts) do
        out[#out + 1] = { key = specKey, name = ns.SpecName(specKey), here = c.here, total = c.total }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Additive: an ability this spec already has is left alone. Copied, never shared by
-- reference. encounterID limits it to one boss, encSet to a page's set of encounters.
function ns.CopyBindingsFromSpec(fromSpecKey, encounterID, encSet)
    if specID == 0 then return 0, 0, 0 end
    local t = TRDB()
    local mine = tostring(specID)
    local encKey = encounterID and tostring(encounterID) or nil
    local copied, skipped, reminders = 0, 0, 0

    local all = type(t.abilityBindings) == "table" and t.abilityBindings or nil
    local src = all and all[fromSpecKey]
    -- A message-reminder-only spec has no binding table; skip just this pass.
    if type(src) == "table" then
        all[mine] = all[mine] or {}
        local dst = all[mine]
        for eKey, bySpell in pairs(src) do
            if (not encKey or eKey == encKey) and (not encSet or encSet[eKey])
                and type(bySpell) == "table" then
                dst[eKey] = dst[eKey] or {}
                for sid, b in pairs(bySpell) do
                    if type(b) == "table" then
                        if dst[eKey][sid] ~= nil then
                            skipped = skipped + 1
                        else
                            local copy = {}
                            for k, v in pairs(b) do copy[k] = v end
                            if type(b.scope) == "table" then
                                local sc = {}
                                for k, v in pairs(b.scope) do sc[k] = v end
                                copy.scope = sc
                            end
                            dst[eKey][sid] = copy
                            copied = copied + 1
                        end
                    end
                end
            end
        end
    end

    -- Message reminders, keyed by message key. `have` is built once so a source with two
    -- variants on one key brings both.
    local presets = PresetsTable(specID, false)
    local sets = type(t.customReminders) == "table" and t.customReminders or {}
    for eKey, set in pairs(sets) do
        if (not encKey or eKey == encKey) and (not encSet or encSet[eKey]) and type(set) == "table" then
            local have, fresh = {}, {}
            for _, r in pairs(set) do
                if type(r) == "table" and r.defensive and r.trigger and r.trigger.type == "bwmsg"
                    and (not r.specID or r.specID == specID) then
                    have[r.trigger.spellID] = true
                end
            end
            for _, r in pairs(set) do
                if type(r) == "table" and r.defensive and r.trigger and r.trigger.type == "bwmsg"
                    and tostring(r.specID) == fromSpecKey then
                    if have[r.trigger.spellID] then
                        skipped = skipped + 1
                    else
                        local copy = {}
                        for k, v in pairs(r) do copy[k] = v end
                        copy.trigger = {}
                        for k, v in pairs(r.trigger) do copy.trigger[k] = v end
                        copy.specID = specID
                        -- Preset keys are per spec; a stale key would never call anything.
                        if not (presets and presets[copy.preset]) then
                            copy.preset = ActivePresetKey(specID)
                        end
                        fresh[#fresh + 1] = copy
                    end
                end
            end
            for i = 1, #fresh do
                local key
                repeat key = "r" .. math.floor(GetTime() * 1000) .. math.random(1, 9999) until set[key] == nil
                set[key] = fresh[i]
                reminders = reminders + 1
            end
        end
    end
    return copied, skipped, reminders
end

-- Migrates a binding saved under the journal alias onto the new key rather than shadowing
-- it with an empty table (Possession Barrage moved to BigWigs' 1292036).
function ns.EnsureBinding(enc, sid)
    local bindings = AbilityBindingsTable(true, enc)
    -- Spec unresolved: a throwaway table, not persisted.
    if not bindings then return {} end
    if bindings[sid] then return bindings[sid] end
    local jid = ns.BOSSMOD_KEY_TO_JOURNAL and ns.BOSSMOD_KEY_TO_JOURNAL[sid]
    if jid and bindings[jid] then
        bindings[sid] = bindings[jid]
        bindings[jid] = nil
        return bindings[sid]
    end
    bindings[sid] = {}
    return bindings[sid]
end

--- Clears the journal alias too, or AbilityAdded keeps answering true.
function ns.RemoveBinding(enc, sid)
    local bindings = ns.AbilityBindingsTable(false, enc)
    if not bindings then return end
    bindings[sid] = nil
    local jid = ns.BOSSMOD_KEY_TO_JOURNAL and ns.BOSSMOD_KEY_TO_JOURNAL[sid]
    if jid then bindings[jid] = nil end
end

-- Per-ability override, else the base slider. Negative (override only) calls out that many
-- seconds after the hit (requested for Rav'i's Triple Shot).
function ns.LeadTimeFor(enc, sid)
    local binding = ns.BindingForBossModKey(enc, sid)
    if binding and binding.leadTime then return binding.leadTime end
    return TRDB().leadTime or 3
end

-- Whether "call for an external" fires for this ability; binding first, then spec toggle.
function ns.ExternalCallFor(enc, sid)
    local binding = ns.BindingForBossModKey(enc, sid)
    if binding and binding.external ~= nil then return binding.external end
    return TRDB().fallbackOn ~= false
end

function ns.IsAbilityHealerFiltered(enc, sid)
    if ns.HealerRemindersEnabled() then return false end
    local binding = ns.BindingForBossModKey(enc, sid)
    return binding ~= nil and binding.healerReminder == true
end

-- Nothing calls out until deliberately added; the curated tank list only marks the picker.
function ns.AbilityEnabledForBinding(enc, sid, raw)
    local b = ns.BindingForBossModKey(enc, sid)
    if b and b.enabled ~= nil then return b.enabled and (raw or ns.IsReminderEnabled(b)) end
    return false
end

function ns.AbilityAdded(enc, sid)
    return ns.BindingForBossModKey(enc, sid) ~= nil
end

-- sid is a real spellID (BigWigs key or DBM spellId). Everything is evaluated at fire
-- time, since tanking, cover and the binding can all change across a bar.
local function FireBigWigsAbility(sid, lateRetry, reminder)
    if reminder and not ns.IsReminderEnabled(reminder) then return end
    if lateRetry then
        if not (frame and TRDB().enabled and TRDB().voiceOn
            and ShouldRun() and InEncounter()) then return end
        -- The visible slots can belong to another warning; an empty retry changes nothing.
        local list = EffectiveList(specID, currentEncounter, tostring(sid))
        if not list then return end
        local configured, ready = false, false
        local now = GetTime()
        for i = 1, #list do
            local spellID = list[i]
            if IsSpellAvailable(spellID) and not IsSpellDisabled(spellID) then
                configured = true
                ResyncSpell(spellID)
                if SpellReady(spellID, now) then ready = true break end
            end
        end
        if not configured then return end
        if not ready then return "waiting" end
    end
    if reminder then
        -- Not InEncounter(): the progress API can still be false for an opening message.
        if not (frame and TRDB().enabled and (ns.testFiring or (canSelect and BossAllowed() and currentEncounter ~= nil))) then
            if TRDB().trace then AppendLog({ kind = "drop", sid = sid,
                text = "message fire gated: frame=" .. tostring(frame ~= nil)
                    .. " enabled=" .. tostring(TRDB().enabled) .. " canSelect=" .. tostring(canSelect)
                    .. " bossAllowed=" .. tostring(BossAllowed()) .. " encounter=" .. tostring(InEncounter()) }) end
            return
        end
    elseif not ns.AbilityEnabledForBinding(currentEncounter, sid) then return end
    -- In Custom Reminder mode the priority pick steps aside for that reminder.
    do
        local binding = ns.BindingForBossModKey(currentEncounter, sid)
        if not reminder and binding and binding.mode == "custom" then
            AppendLog({ kind = "aside", sid = sid })
            return
        end
    end
    if not ns.testFiring then
        -- Pretend Tank lets a non-tank run the engine on a live pull: the aggro check still
        -- runs and logs its verdict but does not stop the callout. Role gates only this
        -- aggro check (tank specs only); a manual toggle once left it on after a respec.
        local pretend = TRDB().pretendTank
        if isTank then
            local verdict, path = TankingCaster(sid)
            lastAggroCheck = { sid = sid, verdict = verdict, path = pretend and not verdict
                and ("pretend/" .. tostring(path)) or path }
            if not verdict and not pretend then
                -- Never refuse silently: 37 broadcasts once left no trace at all.
                AppendLog({ kind = "aggro", sid = sid, tankPath = path,
                    tankSid = sid, text = BossThreatSummary() })
                return
            end
        else
            lastAggroCheck = nil
        end
    end

    -- Before rebuilding: a skipped warning must not erase the previous callout.
    if not ns.testFiring and TRDB().coveredSkip ~= false then
        local covered, bySid, how = CoveredByActiveDefensive(tostring(sid), reminder and reminder.preset)
        if covered then
            AppendLog({ kind = "skip", sid = bySid or sid, tankSid = sid, tankPath = how })
            return
        end
    end

    if not RebuildSlots(tostring(sid), true, reminder and reminder.preset) then
        if reminder and TRDB().trace then AppendLog({ kind = "drop", sid = sid,
            text = "message: preset has no available configured spells" }) end
        return
    end

    ApplyPriorityAlpha()
    ClearTankGate()
    -- Set before frame:Show(), or closing Setup mid-fight pulls a live callout.
    ns.activeAuthoredReminder = reminder or ns.BindingForBossModKey(currentEncounter, sid)
    shownForEvent = sid
    if frame.castTarget then frame.castTarget:Hide() end
    frame:Show()
    if textFrame then textFrame:Show() end
    -- Otherwise the repeat window mutes a message reminder after its own ability's bar.
    if reminder then lastAnnouncedSpellID = nil end
    local result = SpeakCallout(sid)
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer((reminder and reminder.dur) or TRDB().lingerSec or DEFAULTS.lingerSec, HideReminder)
    return result
end

function ns.FireMessageDefensive(r)
    if not ns.IsReminderEnabled(r) then return end
    if TRDB().trace then AppendLog({ kind = "drop", sid = r.trigger and r.trigger.spellID,
        text = "message defensive dispatch: " .. (r.name or "Reminder") }) end
    if not r.preset then return end
    local sid = r.trigger and r.trigger.spellID
    if type(sid) ~= "number" then return end
    return FireBigWigsAbility(sid, false, r)
end

-- Setup's per-ability Test button, through FireBigWigsAbility minus the gates a test cannot
-- satisfy. BigWigs' own test mode never broadcasts real boss spell ids.
-- On ns: the main chunk is at Lua's 200-local ceiling.
function ns.TestFireAbility(enc, sid, reminder)
    if not TRDB().enabled then
        ns.Print("switch the reminder on first.")
        return
    end
    if reminder and (not ns.IsReminderEnabled(reminder) or (reminder.specID and reminder.specID ~= ns.CurrentSpec())) then
        ns.Print("this message reminder is disabled or belongs to another spec.")
        return
    end
    if not reminder and not ns.AbilityEnabledForBinding(enc, sid) then
        ns.Print("this ability is toggled off for this boss, so it will not call out.")
        return
    end
    local binding = ns.BindingForBossModKey(enc, sid)
    if not reminder and binding and binding.mode == "custom" then
        ns.Print("this ability is set to Ability Reminder; the generic callout stays quiet for it.")
        return
    end
    RefreshSpec()
    ns.Apply()
    local priorEnc = currentEncounter
    currentEncounter = enc
    ns.testFiring = true
    lastAnnouncedSpellID = nil
    shownForEvent = nil -- a previous successful test must not hide a failed one
    local ok, err = pcall(FireBigWigsAbility, sid, false, reminder)
    ns.testFiring = nil
    currentEncounter = priorEnc
    if not ok then error(err, 0) end
    if shownForEvent ~= sid then
        ns.Print("nothing on your priority list is talented for this spec, so there is nothing to call.")
    elseif not TRDB().voiceOn then
        ns.Print("voice is off, so the test shows the icon only.")
    end
    if not reminder and ns.HasMessageDefensive(enc, sid) then
        ns.Print("this tests the bar callout; the ability's messages fire the reminder under BOSS REMINDERS, which has its own Test.")
    end
end

-- Per channel so the tank engine and NaowhForever_RaidReminders.lua never collide.
-- One pending fire per cast: Nek'zali's Possession Barrage broadcasts a rough bar and then
-- an accurate one for the same cast, and the later arrival wins.
local pendingBWFires = { tank = {} }   -- [channel][sid] = { [identity] = {fireAt, timer} }

-- Two boss mods timing one cast land within a frame; the next occurrence is a cooldown away.
local SAME_CAST_WINDOW = 2

-- Exported so the raid-reminder engine shares the duplicate/resync handling.
-- isApprox: true for BigWigs :CDBar (next cast), false for :Bar/:CastBar, nil from DBM
-- (treated as a cooldown). Only same-flavour entries share identities, or a debuff bar
-- under the ability's key (Rav'i's "Debuffs (N)") cancels a cast still coming.
function ns.ScheduleBWFire(channel, sid, duration, barIdentity, lead, fireFn, isApprox, valid)
    local fires = pendingBWFires[channel]
    if not fires then fires = {} pendingBWFires[channel] = fires end
    local sidFires = fires[sid]
    if not sidFires then sidFires = {} fires[sid] = sidFires end
    -- lead 0 waits the whole bar; only a lead past the bar's length fires now. A negative
    -- lead (per ability only) waits that long past the bar's end.
    if type(lead) ~= "number" then lead = 0 end
    local delay = (lead < duration) and (duration - lead) or 0.01
    local key = barIdentity or false
    local fireAt = GetTime() + delay

    -- Shows whether a later stop cancels this bar or one already superseded.
    if TRDB().trace then
        local existing = sidFires[key]
        AppendLog({ kind = "schedule", sid = sid, text = tostring(barIdentity),
            duration = duration, isApprox = isApprox, delay = delay,
            existingFireIn = existing and (existing.fireAt - GetTime()) or nil })
    end

    -- Same cast (within SAME_CAST_WINDOW): collapse, and the survivor answers to both
    -- identities, since a stop from BigWigs (bar text) or DBM (timer id) names only its own.
    -- Pending fire later: a stale estimate, cancelled. Pending fire earlier: a cast still
    -- coming, kept; cancelling it dropped the callout for the hit that needed it.
    local uptime = (isApprox == false)
    local aliases = { [key] = true }
    for otherKey, f in pairs(sidFires) do
        if math.abs(f.fireAt - fireAt) <= SAME_CAST_WINDOW then
            if f.timer.Cancel then f.timer:Cancel() end
            if f.uptime == uptime then
                for k in pairs(f.aliases) do aliases[k] = true end
            end
            sidFires[otherKey] = nil
        elseif f.fireAt > fireAt then
            if f.timer.Cancel then f.timer:Cancel() end
            sidFires[otherKey] = nil
        elseif TRDB().trace then
            AppendLog({ kind = "drop", sid = sid,
                text = ("kept a fire %.1fs out, this bar is %.1fs out"):format(
                    f.fireAt - GetTime(), delay) })
        end
    end

    local entry = { fireAt = fireAt, aliases = aliases, uptime = uptime, valid = valid,
        approx = (isApprox == true) }
    entry.endsAt = GetTime() + duration
    local function finish()
        for k in pairs(aliases) do
            if sidFires[k] == entry then sidFires[k] = nil end
        end
    end
    local function attempt()
        if valid and not valid() then finish(); return end
        -- Stays indexed while waiting so stops and resets still cancel the retry.
        if entry.late and GetTime() >= entry.endsAt then
            if TRDB().trace then
                AppendLog({ kind = "drop", sid = sid, text = "late-ready window expired" })
            end
            finish()
            return
        end
        local result = fireFn(sid, entry.late)
        local remaining = entry.endsAt - GetTime()
        if channel == "tank" and result == "waiting" and remaining > 0 then
            if not entry.late and TRDB().trace then
                AppendLog({ kind = "drop", sid = sid,
                    text = "no cooldown ready; waiting until bar expiry" })
            end
            entry.late = true
            entry.timer = C_Timer.NewTimer(math.min(0.1, remaining), attempt)
        else
            finish()
        end
    end
    entry.timer = C_Timer.NewTimer(delay, attempt)
    -- A kept entry under a reused identity: same bar if still running, so it ends; else a
    -- call still due after impact (negative lead), re-keyed so resets still reach it.
    for k in pairs(aliases) do
        local prev = sidFires[k]
        if prev and prev ~= entry then
            if prev.endsAt <= GetTime() then
                local own = {}
                prev.aliases[own] = true
                sidFires[own] = prev
            elseif prev.timer.Cancel then
                prev.timer:Cancel()
            end
        end
        sidFires[k] = entry
    end
end

-- Settings changes can invalidate raid work without ending the encounter.
function ns.PrunePendingBWFires()
    for _, fires in pairs(pendingBWFires) do
        for _, sidFires in pairs(fires) do
            for key, entry in pairs(sidFires) do
                if entry.valid and not entry.valid() then
                    entry.timer:Cancel()
                    sidFires[key] = nil
                end
            end
        end
    end
end

function ns.ApplyReminderFilter()
    ns.PruneCustomReminderTimers()
    ns.PrunePendingBWFires()
    for key, reminder in pairs(ns.pendingCustomReminderOwners) do
        if not ns.IsReminderEnabled(reminder) then
            local handle = bwPendingTimers[key]
            if handle then handle:Cancel() end
            bwPendingTimers[key] = nil
            ns.pendingCustomReminderOwners[key] = nil
        end
    end
    if ns.activeAuthoredReminder and not ns.IsReminderEnabled(ns.activeAuthoredReminder) then
        HideReminder()
    end
    if ns.HideFilteredRaidReminders then ns.HideFilteredRaidReminders() end
    if ns.Integrations then ns.Integrations.Refresh() end
    if ns.BossSource and ns.BossSource() == "timeline" then RegisterEventSounds() end
end

function ns.HandleBigWigsAbility(sid, duration, barIdentity, isRetry, isApprox)
    if type(sid) ~= "number" or sid <= 0 then return end
    if not (frame and TRDB().enabled) then return end
    if InEncounter() then ns.SampleTanking() end
    if not (ShouldRun() and InEncounter()) then
        -- Boss mods broadcast engage bars inside their own ENCOUNTER_START, before ours
        -- (Fresh Meat). One next-frame retry, so a broadcast outside an encounter cannot loop.
        if not InEncounter() and not isRetry then
            C_Timer.After(0, function()
                ns.HandleBigWigsAbility(sid, duration, barIdentity, true, isApprox)
            end)
            return
        end
        if TRDB().trace then
            AppendLog({ kind = "drop", sid = sid,
                text = not InEncounter() and "not in encounter" or "engine gated" })
        end
        return
    end
    if not ns.AbilityEnabledForBinding(currentEncounter, sid) then return end
    -- Duplicates and next occurrences both arrive `lead` seconds after our fire; only the
    -- presence of a duration separates them.
    local lead = ns.LeadTimeFor(currentEncounter, sid)

    if type(duration) == "number" and duration > 0.5 then
        -- Not repeat-guarded: the next bar starts as the hit lands, and the guard swallowed
        -- it (Kings Rest's Golden Serpent). ScheduleBWFire collapses real duplicates.
        ns.ScheduleBWFire("tank", sid, duration, barIdentity, lead, function(fireSid, lateRetry)
            lastBWSid, lastBWAt = fireSid, GetTime()
            return FireBigWigsAbility(fireSid, lateRetry)
        end, isApprox, function()
            return ns.AbilityEnabledForBinding(currentEncounter, sid)
        end)
    else
        -- A message reminder under BOSS REMINDERS owns this ability's messages.
        if ns.HasMessageDefensive(currentEncounter, sid) then return end
        -- A Message is the cast landing, so the guard is safe here. Floored at 4s: Rav'i's
        -- Triple Shot sends a second message at the end of its 2s cast.
        if sid == lastBWSid and (GetTime() - lastBWAt) < math.max(lead + 1, 4) then return end

        -- Cancel a pending bar fire for this same cast (Entombed Sentinels pairs a bar with
        -- a same-key Message), but never one for the next occurrence: that cancelled every
        -- other Triple Shot callout on Rav'i.
        local sidFires = pendingBWFires.tank and pendingBWFires.tank[sid]

        -- With a negative lead a pending bar owns the delayed fire; this Message is its
        -- completion echo and would otherwise fire at impact and again after the delay.
        if lead < 0 and sidFires then
            for _, f in pairs(sidFires) do
                if not f.uptime then return end
            end
        end

        if sidFires then
            local thisCastUntil = GetTime() + lead + SAME_CAST_WINDOW
            for key, f in pairs(sidFires) do
                if f.fireAt <= thisCastUntil then
                    if f.timer.Cancel then f.timer:Cancel() end
                    sidFires[key] = nil
                end
            end
        end
        lastBWSid, lastBWAt = sid, GetTime()
        FireBigWigsAbility(sid)
    end
end

-- A stopped or paused bar cancels its fire on every channel, except an approx (:CDBar)
-- bar, whose stop means the module is done guessing: The Hoardmonger stops all three
-- estimate bars 11s in and nothing replaces them. Unflagged DBM entries still cancel.
-- Known cost: an estimate retired by a phase change still fires at its rough time.
local function CancelPendingBWFire(barIdentity)
    if barIdentity == nil then return end
    for _, fires in pairs(pendingBWFires) do
        for sid, sidFires in pairs(fires) do
            local f = sidFires[barIdentity]
            if f then
                if f.approx and not f.late then
                    if TRDB().trace then
                        AppendLog({ kind = "drop", sid = sid,
                            text = ("kept estimate fire, bar '%s' stopped %.1fs before it"):format(
                                tostring(barIdentity), f.fireAt - GetTime()) })
                    end
                else
                    if f.timer.Cancel then f.timer:Cancel() end
                    -- Logged: from outside it looks like a fire never scheduled.
                    AppendLog({ kind = "cancel", sid = sid,
                        text = ("%s (%.1fs before it would have fired)"):format(
                            tostring(barIdentity), f.fireAt - GetTime()) })
                    -- Every alias, not just the one the stop arrived under.
                    for k in pairs(f.aliases) do
                        if sidFires[k] == f then sidFires[k] = nil end
                    end
                end
            end
        end
    end
end

local function CancelAllPendingBWFires()
    for _, fires in pairs(pendingBWFires) do
        for sid, sidFires in pairs(fires) do
            local logged
            for key, f in pairs(sidFires) do
                if f.timer.Cancel then f.timer:Cancel() end
                -- One line per sid, trace only.
                if not logged and TRDB().trace then
                    logged = true
                    AppendLog({ kind = "cancel", sid = sid, text = "encounter reset" })
                end
                sidFires[key] = nil
            end
            fires[sid] = nil
        end
    end
end

-- Both dispatchers register a plain function, so the message name is the first argument
-- (confirmed against BigWigs' and DBM's dispatch code).
-- An unflagged bar is read as an uptime (the buff the cast applied) only when a flagged
-- :CDBar for the same key is expiring now or already has a pending callout; without this
-- reminders fired again when the buff expired. Rav'i's "Debuffs (1)" bar under Triple
-- Shot's key needs the pending test, not the timing window.
local bwCdEndsAt = {}

-- Verified ordinary-Bar uptimes, encounter-scoped and matched on the module's rename slot,
-- not English text or duration alone. XathuuxTheAnnihilator:DemonicRageTimeline emits slot
-- 3 as a message and a 15s Bar after its 4s CastBar. Slot 1 is the countdown's base label.
ns.bossModUptimeRules = {
    [3103] = { [474197] = { rename = 3, duration = 15, message = true } },
}

function ns.IsVerifiedBossModUptime(module, key, text, duration, isApprox)
    local encounterRules = ns.bossModUptimeRules[currentEncounter]
    local rule = encounterRules and encounterRules[key]
    if not rule or type(module) ~= "table" or module.engageId ~= currentEncounter
        or type(module.GetRename) ~= "function" then return false end
    if duration ~= nil then
        if isApprox ~= false or duration ~= rule.duration then return false end
    elseif not rule.message then
        return false
    end
    local ok, label = pcall(module.GetRename, module, key, rule.rename)
    local baseOK, base = pcall(module.GetRename, module, key, 1)
    if not ok or not baseOK or (issecretvalue and (issecretvalue(label) or issecretvalue(base)))
        or type(label) ~= "string" or type(base) ~= "string" or label == base
        or text ~= label then return false end
    if TRDB().trace then
        AppendLog({ kind = "drop", sid = key, text = "verified uptime: " .. label })
    end
    return true
end

local function NoteBossModBar(key, duration, isApprox)
    if isApprox and type(duration) == "number" and duration > 0 then
        bwCdEndsAt[key] = GetTime() + duration
    end
end

-- Only a pending cooldown-bar entry counts; nearly every timed key has some pending entry.
local function IsUptimeBar(key, isApprox)
    if isApprox then return false end
    for _, fires in pairs(pendingBWFires) do
        local sidFires = fires[key]
        if sidFires then
            for _, f in pairs(sidFires) do
                if not f.uptime then return true end
            end
        end
    end
    local UPTIME_MATCH_WINDOW = 1.5
    local endsAt = bwCdEndsAt[key]
    return endsAt ~= nil and math.abs(GetTime() - endsAt) <= UPTIME_MATCH_WINDOW
end

local function OnBigWigsEvent(event, ...)
    if ns.BossSource() ~= "bigwigs" then return end
    -- Cataloguing ignores hasCustomReminders: the picker exists to create the first one.
    if event == "BigWigs_Message" then
        local module, key, text = ...
        if issecretvalue and issecretvalue(key) then return end
        -- Target messages may include a secret player name. Match the readable
        -- option key, keeping protected text out of filters and SavedVariables.
        if issecretvalue and issecretvalue(text) then text = nil end
        if ns.IsVerifiedBossModUptime(module, key, text) then return end
        if CustomRemindersAllowed() then
            RecordBossModKey("BW", key, text, "message", type(module) == "table" and module.engageId or nil)
        end
        if ns.ObserveCast then ns.ObserveCast(key, "BW", nil, nil) end
        ns.HandleBigWigsAbility(key)
        if ns.HandleRaidReminderAbility then ns.HandleRaidReminderAbility(key) end
        CheckBossModMessage("BW", key, type(module) == "table" and module.engageId or nil)
    elseif event == "BigWigs_Timer" then
        -- Bar and CDBar always publish this; CastBar publishes BigWigs_CastTimer.
        -- StartBar mixes all three and double-warned Chillstorm's cast/debuff bar.
        local module, key, duration, _, text, _, _, isApprox = ...
        if issecretvalue and (issecretvalue(key) or issecretvalue(text) or issecretvalue(duration)) then return end
        if key == nil then return end
        if ns.IsVerifiedBossModUptime(module, key, text, duration, isApprox) then return end
        if CustomRemindersAllowed() then
            RecordBossModKey("BW", key, text, "timer", type(module) == "table" and module.engageId or nil)
        end
        if IsUptimeBar(key, isApprox) then
            if TRDB().trace then
                AppendLog({ kind = "drop", sid = key, text = "uptime bar" })
            end
            return
        end
        NoteBossModBar(key, duration, isApprox)
        if ns.ObserveCast then ns.ObserveCast(key, "BW", duration, text) end
        ns.HandleBigWigsAbility(key, duration, text, nil, isApprox)
        if ns.HandleRaidReminderAbility then ns.HandleRaidReminderAbility(key, duration, text) end
        CheckBossModTimerStart("BW", key, text, duration, text)
    elseif event == "BigWigs_StopBar" or event == "BigWigs_PauseBar" then
        local _, text = ...
        if issecretvalue and issecretvalue(text) then return end
        if ns.ObserveCancel then ns.ObserveCancel(text) end
        CancelPendingBWFire(text)
        if not hasCustomReminders then return end
        CancelBossModTimers("BW", text)
    elseif event == "BigWigs_StopBars" or event == "BigWigs_OnBossDisable" then
        CancelAllPendingBWFires()
        -- A wipe disables the module before ENCOUNTER_END; the stage is over.
        currentStage = nil
        currentStageAt = nil
        if ns.ObserveCancelAll then ns.ObserveCancelAll() end
        ns.CancelTrackedReminderTimers("stage")
        if not hasCustomReminders then return end
        CancelBossModTimers("BW", "")
    elseif event == "BigWigs_SetStage" then
        -- (module, stage). Only a change arms stage triggers, which also dedupes two mods.
        local _, stage = ...
        if issecretvalue and issecretvalue(stage) then return end
        if type(stage) == "number" and stage ~= currentStage then
            currentStage = stage
            currentStageAt = GetTime()
            ns.CancelTrackedReminderTimers("stage")
            if ns.CheckRaidReminderStageTriggers then
                ns.CheckRaidReminderStageTriggers(stage)
            end
        end
    end
end

local function OnDBMEvent(event, ...)
    if ns.BossSource() ~= "dbm" then return end
    -- DBM ids are normalized to BigWigs ids (ns.DBM_TO_BIGWIGS) only for
    -- HandleBigWigsAbility; cataloguing and custom reminders keep DBM's raw id.
    if event == "DBM_Announce" then
        local _, _, _, spellId = ...
        if issecretvalue and issecretvalue(spellId) then return end
        if CustomRemindersAllowed() then RecordBossModKey("DBM", spellId, nil, "message") end
        if ns.ObserveCast then ns.ObserveCast(spellId, "DBM", nil, nil) end
        ns.HandleBigWigsAbility(ns.DBM_TO_BIGWIGS and ns.DBM_TO_BIGWIGS[spellId] or spellId)
        -- Raid Reminders are BigWigs-only by design (see ShowRaidReminderEditor).
        CheckBossModMessage("DBM", spellId)
    elseif event == "DBM_TimerBegin" or event == "DBM_TimerStart" then
        local id, msg, duration, _, _, spellId = ...
        if issecretvalue and (issecretvalue(spellId) or issecretvalue(id) or issecretvalue(duration)) then return end
        if CustomRemindersAllowed() then RecordBossModKey("DBM", spellId, msg, "timer") end
        -- DBM's stop/pause hands back the timer ID, so that is the cancellation identity.
        if ns.ObserveCast then ns.ObserveCast(spellId, "DBM", duration, id) end
        ns.HandleBigWigsAbility(ns.DBM_TO_BIGWIGS and ns.DBM_TO_BIGWIGS[spellId] or spellId, duration, id)
        CheckBossModTimerStart("DBM", spellId, id, duration, msg)
    elseif event == "DBM_TimerStop" or event == "DBM_TimerPause" then
        local id = ...
        if issecretvalue and issecretvalue(id) then return end
        if ns.ObserveCancel then ns.ObserveCancel(id) end
        CancelPendingBWFire(id)
        if not hasCustomReminders then return end
        CancelBossModTimers("DBM", id)
    elseif event == "DBM_SetStage" then
        -- (mod, modId, stage, encounterID, stageTotality)
        local _, _, stage = ...
        if issecretvalue and issecretvalue(stage) then return end
        if type(stage) == "number" and stage ~= currentStage then
            currentStage = stage
            currentStageAt = GetTime()
            ns.CancelTrackedReminderTimers("stage")
            if ns.CheckRaidReminderStageTriggers then
                ns.CheckRaidReminderStageTriggers(stage)
            end
        end
    end
end

local bwHooked, dbmHooked = false, false
local function RegisterBossModHooks()
    if _G.BigWigsLoader and not bwHooked then
        local ok = pcall(function()
            local BWL = _G.BigWigsLoader
            BWL.RegisterMessage(ns, "BigWigs_Message", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_Timer", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_StopBar", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_PauseBar", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_StopBars", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_OnBossDisable", OnBigWigsEvent)
            BWL.RegisterMessage(ns, "BigWigs_SetStage", OnBigWigsEvent)
        end)
        bwHooked = ok and true or false
    end
    if _G.DBM and not dbmHooked then
        local ok = pcall(function()
            local D = _G.DBM
            -- Current DBM fires DBM_TimerBegin; DBM_TimerStart is the older name.
            D:RegisterCallback("DBM_Announce", OnDBMEvent)
            D:RegisterCallback("DBM_TimerBegin", OnDBMEvent)
            D:RegisterCallback("DBM_TimerStart", OnDBMEvent)
            D:RegisterCallback("DBM_TimerStop", OnDBMEvent)
            D:RegisterCallback("DBM_TimerPause", OnDBMEvent)
            D:RegisterCallback("DBM_SetStage", OnDBMEvent)
        end)
        dbmHooked = ok and true or false
    end
end
ns.RegisterBossModHooks = RegisterBossModHooks

-- CLEU stays registered for the whole session (its registration cannot be toggled from
-- insecure code in restricted content), so runActive mirrors ShouldRun() as a plain read.
local runActive = false

local cleuLines, cleuUsable, cleuOwnAuras = 0, 0, 0

local function OnCombatLog()
    -- Fires for every combat log line; outside an encounter it costs one read.
    -- hasRaidReminders is cached, so any new raid-reminder write path must call
    -- RefreshCustomRemindersFlag.
    if currentEncounter == nil then return end
    -- Counted above the secrecy filter so /nutank can tell "never arrived" from "all secret".
    cleuLines = cleuLines + 1
    local _, sub, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId, _, _, _, amount = C_CombatLog.GetCurrentEventInfo()
    if issecretvalue and (issecretvalue(sub) or issecretvalue(spellId) or issecretvalue(destGUID)
        or issecretvalue(amount)) then
        return
    end
    cleuUsable = cleuUsable + 1

    -- Feeds TankingCaster. A secret sourceGUID skips only this.
    if type(spellId) == "number" and (sub == "SPELL_CAST_START" or sub == "SPELL_CAST_SUCCESS")
        and not (issecretvalue and issecretvalue(sourceGUID)) then
        castSourceGUID[spellId] = sourceGUID
    end

    -- Feeds CoveredByActiveDefensive.
    if runActive and type(spellId) == "number" and destGUID == PlayerGUID() then
        if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
            playerAuraUp[spellId] = true
            cleuOwnAuras = cleuOwnAuras + 1
        elseif sub == "SPELL_AURA_REMOVED" then
            playerAuraUp[spellId] = nil
        end
    end

    if hasRaidReminders and ns.CheckRaidReminderAuraTriggers and type(spellId) == "number" then
        if sub == "SPELL_AURA_APPLIED" then
            ns.CheckRaidReminderAuraTriggers("applied", destGUID, spellId)
        elseif sub == "SPELL_AURA_REMOVED" then
            ns.CheckRaidReminderAuraTriggers("removed", destGUID, spellId)
        end
    end

    if hasCustomReminders and type(spellId) == "number" then
        if sub == "SPELL_CAST_SUCCESS" then
            CheckCustomReminders("cast", spellId)
        elseif sub == "SPELL_AURA_APPLIED" then
            CheckCustomReminders("aura", spellId)
            CheckAuraReminder("applied", destGUID, spellId)
        elseif sub == "SPELL_AURA_REMOVED" then
            CheckAuraReminder("removed", destGUID, spellId)
        elseif sub == "SPELL_AURA_APPLIED_DOSE" then
            CheckAuraReminder("stacks", destGUID, spellId, amount)
        end
    end

end


local cleuRegistered = false

local function UpdateEventRegistration()
    if not watcher then return end

    -- Above the ShouldRun gate. Registering CLEU while restricted throws
    -- ADDON_ACTION_FORBIDDEN, which pcall cannot catch, and IsCombatLogRestricted() is
    -- accurate (true even in a capital city, measured). Latched: unregistering is forbidden too.
    if not cleuRegistered then
        local restricted = C_CombatLog and C_CombatLog.IsCombatLogRestricted
            and C_CombatLog.IsCombatLogRestricted()
        -- Forever has no C_CombatLog.GetCurrentEventInfo and no deprecated global for it.
        if (restricted == false or restricted == nil) and C_CombatLog and C_CombatLog.GetCurrentEventInfo then
            watcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            cleuRegistered = true
        end
    end

    -- Cast history must survive gaps between bosses, so only these two gate it.
    if TRDB().enabled and #ns.trackedCooldownSpells > 0 then
        watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    else
        watcher:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
        watcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end

    -- Forever has no encounter timeline, so these cannot wait for ShouldRun(): the pull
    -- triggers and boss-mod reminders only need to know which encounter is underway.
    watcher:RegisterEvent("ENCOUNTER_START")
    watcher:RegisterEvent("ENCOUNTER_END")

    if not ShouldRun() then
        runActive = false
        -- CLEU is never unregistered: toggling it in restricted content (ENCOUNTER_START
        -- calls this) is forbidden and uncatchable, not only under InCombatLockdown().
        watcher:UnregisterEvent("PLAYER_ALIVE")
        watcher:UnregisterEvent("PLAYER_UNGHOST")
        -- ENCOUNTER_START/END stay registered: ShouldRun() depends on the boss they
        -- establish, so dropping them latched the feature off after the first kill.
        HideReminder()
        return
    end

    watcher:RegisterEvent("PLAYER_ALIVE")
    watcher:RegisterEvent("PLAYER_UNGHOST")

    runActive = true
end

-- Once per session. Only Combat Warnings stops the data; the timeline display toggle does not.
local warnedCombatWarnings = false
local saidAudioOnly = false

local function WarnIfMuted()
    if warnedCombatWarnings or not TRDB().enabled then return end
    if not CombatWarningsOff() then return end
    warnedCombatWarnings = true
    ns.Print("|cffff6060Boss Warnings are turned off|r, so the game sends no timeline data and "
        .. "the tank reminder cannot fire. Turn it back on in Options, Advanced, Combat Warnings, "
        .. "Enable Boss Warnings. Hiding the timeline itself is fine and changes nothing here.")
end

-- No fallback to the timeline by design. Once per session.
local warnedNoBossMod = false
-- On ns rather than staying local: the main chunk is already at Lua's 200-local ceiling.
function ns.WarnIfNoBossMod()
    if warnedNoBossMod or not TRDB().enabled then return end
    local source = ns.BossSource()
    if source == "timeline" then return end
    if (source == "bigwigs" and _G.BigWigsLoader) or (source == "dbm" and _G.DBM) then return end
    warnedNoBossMod = true
    ns.Print(("|cffff6060Boss Addon is set to %s, but it is not loaded|r -- callouts have "
        .. "nothing to listen to. Install it, or switch Boss Addon in the Smart "
        .. "Reminders settings."):format(
        source == "bigwigs" and "BigWigs" or "DBM"))
end

function ns.Apply()
    if ns.Integrations then ns.Integrations.Refresh() end
    ns.PruneCustomReminderTimers()
    ns.PrunePendingBWFires()
    -- Even while off: the list is built before enabling, and an unknown spec refuses adds.
    RefreshSpec()

    if not TRDB().enabled then
        activeSlots = 0
        HideReminder()
        UpdateEventRegistration()
        ns.ClearEventSounds()
        return
    end

    ProbeCapabilities()
    RefreshSpec()
    Reminder.Create()
    ApplyPosition()
    -- A profile switch does not recreate the frame, so the color is reapplied here.
    ApplyDefensiveTextColor()
    RebuildSlots()
    RebuildCastMap()
    ResyncModel()
    UpdateEventRegistration()
    WarnIfMuted()
    ns.WarnIfNoBossMod()

    if not (ns.soundFile and ns.soundFile == ResolveSoundFile() and TRDB().soundOn
        and ns.BossSource() == "timeline" and ns.HealerRemindersEnabled()) then
        RegisterEventSounds()
    end
end

-------------------------------------------------------------------------------
--  Preview
-------------------------------------------------------------------------------
-- previewing (declared above) says the options window is open; previewPin says the player
-- wants the stand-in shown. On by default: testers could not find the preview.
local previewPin = true
-- Held by anchor config mode (Customize Anchors), independent of the window.
local configPreview = false

local function UpdatePreview()
    if not ((TRDB().enabled and previewing and previewPin) or configPreview) then
        -- A mouse-enabled alert in a fight would eat clicks.
        if frame then
            frame:EnableMouse(false)
            frame:SetScript("OnMouseDown", nil)
            frame:SetScript("OnDragStart", nil)
            frame:SetScript("OnDragStop", nil)
        end
        if frame and not shownForEvent then frame:Hide() end
        if textFrame and not shownForEvent then textFrame:Hide() end
        if bar and not shownForEvent then bar:Hide() end
        return
    end

    Reminder.Create()
    RebuildSlots()

    -- Draggable only while previewing; the position saves to Unlock Mode's slot.
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function(self, button)
        if configPreview and self._configHandle and button == "LeftButton" then
            ns.UI.SelectMover(self._configHandle)
        end
    end)
    frame:SetScript("OnDragStart", function(self)
        if configPreview and self._configHandle then
            ns.UI.StartMoverDrag(self._configHandle)
        elseif not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if configPreview and self._configHandle then
            ns.UI.StopMoverDrag(self._configHandle)
            return
        end
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point then
            TRDB().pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
        ApplyPosition()
    end)


    -- An empty or fully switched-off list previews a stand-in in slot 1, so Show Icon
    -- and the size/position tools work before any ability has been enabled.
    local slot = slots[1]
    if activeSlots == 0 then
        slot = slot or CreateSlot(1)
        slot.spellID = nil
        slot.iconID = 134400
        slot.icon:SetTexture("Interface\\Icons\\Ability_Warrior_ShieldWall")
        slot.label:SetText("Defensive")
        ApplySize()
    end
    slot:SetAlpha(1)
    slot.icon:SetAlpha(1)
    -- Config mode forces every channel visible: on a fresh install they all ship off.
    slot.icon:SetShown((TRDB().showIcon or configPreview) and true or false)
    if slot.label then
        if activeSlots > 0 then
            local sid = slot.spellID
            local si = sid and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            slot.label:SetText(CalloutFor(sid, si and si.name))
        end
        slot.label:SetShown((TRDB().showText or configPreview) and true or false)
    end
    if frame.fallback then frame.fallback:SetAlpha(0) end
    if TRDB().showBar or configPreview then
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

function ns.SetDefensiveAnchorConfigShown(shown)
    configPreview = shown and true or false
    UpdatePreview()
end

function ns.GetDefensiveAlertFrame()
    return frame, bar
end

function ns.RefreshDefensivePreview()
    ApplySize()
    UpdatePreview()
end

function ns.ApplyDefensiveAlertPosition()
    ApplyPosition()
end

-------------------------------------------------------------------------------
--  Diagnostics
-------------------------------------------------------------------------------
-- Everything that can make a capture worthless, stated up front.
local function DiagProblems()
    local t, out = TRDB(), {}
    if t.enabled ~= true then
        out[#out + 1] = "the reminder is switched OFF -- turn it on in Smart Reminders"
    end
    if activeSlots == 0 then
        out[#out + 1] = "priority list is EMPTY for this spec, so nothing can ever be "
            .. "called -- add defensives in Smart Reminders first"
    end
    -- No "step outside" advice: the client refuses the registration everywhere.
    if watcher and not watcher:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
        out[#out + 1] = "the client refuses the combat log to addons in this build, so Skip "
            .. "When Already Covered has no aura data -- it runs on your own casts instead, "
            .. "for " .. tostring(TRDB().coveredCastWindow or OWN_CAST_COVER_DEFAULT)
            .. "s after you press one"
    end
    if not EngineAvailable() then
        out[#out + 1] = "there is no boss timeline here and no BigWigs or DBM to follow"
    end
    return out
end

SLASH_NAOWHUITANK1 = "/nutank"
SlashCmdList["NAOWHUITANK"] = function(msg)
    msg = msg or ""
    local arg = msg:lower():match("^%s*(%S*)")
    -- Case preserved: the remainder names the pack.
    local rest = msg:match("^%s*%S*%s+(.-)%s*$")
    ProbeCapabilities()
    RefreshSpec()

    if arg == "pretendtank" then
        local t = TRDB()
        t.pretendTank = not t.pretendTank and true or nil
        if t.pretendTank then
            ns.Print("|cffF0A830PRETEND TANK ON|r -- callouts now fire for tank busters even "
                .. "though you are not tanking. For testing only; turn it back off before "
                .. "playing normally. The aggro check still records what it WOULD have said.")
            local problems = DiagProblems()
            for i = 1, #problems do ns.Print("  |cffff6060still blocked:|r " .. problems[i]) end
        else
            ns.Print("|cff6DD09APretend Tank off|r -- back to normal tank-only behaviour.")
        end
        return
    end

    -- For pack contributors handing work back. The Profiles tab refuses a pack-derived
    -- profile and deliberately does not name this command: that leaked a licensed pack.
    if arg == "share" then
        if not ns.ExportPack then
            ns.Print("this build has no profile export.")
            return
        end
        local packName = (rest and rest ~= "") and rest or "Naowh"
        local str, err = ns.ExportPack(packName,
            UnitName and UnitName("player"), true)
        if not str then ns.Print("|cffff6060" .. tostring(err) .. "|r") return end
        if ns.ShowDiagExport then
            ns.ShowDiagExport(str)
            ns.Print("your whole active profile, ready to send back. It is marked as worked "
                .. "on from their pack, so they can see what it is.")
        else
            ns.Print("|cffff6060nowhere to show the string in this build.|r")
        end
        return
    end

    -- Persisted, not per session: a key run can span a reload.
    if arg == "trace" then
        local t = TRDB()
        t.trace = not t.trace and true or nil
        if t.trace then
            if type(t.callLog) == "table" then wipe(t.callLog) end
            ns.Print("|cff6DD09Atrace ON|r -- run your key, then /nutank trace again to stop "
                .. "and /nutank export to get the text to send.")
            local problems = DiagProblems()
            for i = 1, #problems do
                ns.Print("  |cffff6060this trace will capture nothing:|r " .. problems[i])
            end
        else
            ns.Print(("|cffF0A830trace OFF|r -- %d entries recorded. /nutank export opens them "
                .. "in a copyable box."):format(type(t.callLog) == "table" and #t.callLog or 0))
        end
        return
    end

    -- Times choosing the defensive vs speaking it. Session flag, deliberately not saved.
    if arg == "speaktime" then
        local pr = ns.speakProf
        if not pr then
            ns.speakProf = { pickN = 0, pickSum = 0, pickMax = 0,
                             ttsN = 0, ttsSum = 0, ttsMax = 0 }
            ns.Print("|cff6DD09Acallout timing ON|r -- pull once, then /nutank speaktime "
                .. "again to stop and read it.")
            if not TRDB().voiceOn then
                ns.Print("  |cffff6060this will record nothing:|r Speak Which Defensive to "
                    .. "Use is off, and that switch gates the whole callout.")
            end
            return
        end
        ns.speakProf = nil
        if pr.pickN == 0 then
            ns.Print("|cffF0A830callout timing OFF|r -- no callouts fired, so there is "
                .. "nothing to report.")
            return
        end
        ns.Print((ns.Color("accent", "callout timing") .. " (build %s), %d callout(s):")
            :format(BuildString(), pr.pickN))
        ns.Print(("  choosing the defensive: avg %.2fms, worst %.2fms, total %.0fms")
            :format(pr.pickSum / pr.pickN, pr.pickMax, pr.pickSum))
        if pr.ttsN > 0 then
            ns.Print(("  speaking it: avg %.2fms, worst %.2fms, total %.0fms, %d utterance(s)")
                :format(pr.ttsSum / pr.ttsN, pr.ttsMax, pr.ttsSum, pr.ttsN))
        else
            ns.Print("  speaking it: never reached -- every callout was suppressed or muted.")
        end
        -- Windows synthesises on the calling thread, so SpeakText time is a client stall.
        local worst = pr.ttsMax > pr.pickMax and "speaking" or "choosing"
        ns.Print(("  worst single frame was |cffF0A830%s|r, at %.2fms.")
            :format(worst, math.max(pr.ttsMax, pr.pickMax)))
        return
    end

    if arg == "export" then
        local t = TRDB()
        local log = type(t.callLog) == "table" and t.callLog or {}
        local out = {}
        out[#out + 1] = ("build %s | spec %d | tank %s | pretendTank %s | slots %d | trace %s"):format(
            BuildString(), specID, tostring(isTank), tostring(t.pretendTank and true or false),
            activeSlots, tostring(t.trace and true or false))
        -- restrictedHere reads true everywhere; kept to show if that ever changes.
        out[#out + 1] = ("combat log registered=%s inInstance=%s restrictedHere=%s lines=%d usable=%d ownAuras=%d"):format(
            tostring(watcher:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")),
            tostring(IsInInstance()),
            tostring(C_CombatLog and C_CombatLog.IsCombatLogRestricted
                and C_CombatLog.IsCombatLogRestricted()),
            cleuLines, cleuUsable, cleuOwnAuras)
        out[#out + 1] = ("timeline=%s aggroGate=%s coveredSkip=%s leadTime=%s"):format(
            tostring(TimelineAvailable()), tostring(isTank), tostring(t.coveredSkip ~= false),
            tostring(t.leadTime))
        out[#out + 1] = ("%d entries"):format(#log)
        local problems = DiagProblems()
        for i = 1, #problems do out[#out + 1] = "PROBLEM: " .. problems[i] end
        if #log == 0 and #problems == 0 then
            out[#out + 1] = "PROBLEM: nothing recorded, but the setup looks able to call -- "
                .. "either no pull happened while tracing, or no boss mod broadcast a "
                .. "curated ability (check /nutank keys during a pull)"
        end
        for i = 1, #log do out[#out + 1] = LogLine(log[i]) end
        ns.AppendChargeAudit(out)
        local text = table.concat(out, "\n")
        if ns.ShowDiagExport then
            ns.ShowDiagExport(text)
        else
            ns.Print(text)
        end
        return
    end

    if arg == "observed" then
        -- Falls back to the last pull: ENCOUNTER_END nils currentEncounter.
        local enc = currentEncounter
        if not enc and ns.ObservedLastPull then enc = ns.ObservedLastPull() end
        if not enc then
            ns.Print("no pull to report yet. Fight a boss with BigWigs or DBM running, or "
                .. "open the Ability Reminders tab to browse what has been recorded.")
            return
        end
        local diffs = ns.ObservedDifficulties and ns.ObservedDifficulties(enc) or {}
        if #diffs == 0 then
            ns.Print(("nothing recorded for encounter %s yet. Recording rides the boss "
                .. "mods, so it needs Boss Addon set to BigWigs or DBM (currently %s), and "
                .. "a real boss encounter -- trash fires no encounter events."):format(
                tostring(enc), ns.BossSource()))
            return
        end
        if not currentEncounter then
            ns.Print((ns.Color("muted", "last pull, encounter %s")):format(tostring(enc)))
        end
        for _, d in ipairs(diffs) do
            local block = ns.ObservedFor(enc, tonumber(d.key))
            local name = GetDifficultyInfo and GetDifficultyInfo(tonumber(d.key))
            ns.Print((ns.Color("accent", "observed") .. " %s (%s): %d pull(s), longest %.0fs"):format(
                tostring(name or "?"), d.key, block.pulls or 0, block.longest or 0))
            for sid, list in pairs(block.casts or {}) do
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                local parts = {}
                for i = 1, #list do
                    local s = list[i]
                    if s and s.t then
                        parts[#parts + 1] = ("%d:%04.1f%s"):format(math.floor(s.t / 60),
                            s.t % 60, (s.stage and s.stage > 1) and ("(P" .. s.stage .. ")") or "")
                    end
                end
                ns.Print(("  %d %s -- %s"):format(sid, (info and info.name) or "?",
                    table.concat(parts, ", ")))
            end
        end
        return
    end

    if arg == "keys" then
        local enc = currentEncounter
        local cat = enc and BossModCatalogueTable(false, enc)
        if not cat or not next(cat) then
            ns.Print(enc
                and ("nothing recorded for encounter %s yet. Either no boss mod broadcast "
                    .. "anything, or this ran outside a pull."):format(tostring(enc))
                or "not in an encounter, so there is nothing to attribute keys to. Run this "
                    .. "during or right after a pull.")
            return
        end
        ns.Print((ns.Color("accent", "boss mod keys") .. " seen this pull (encounter %s):"):format(tostring(enc)))
        for key, e in pairs(cat) do
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(key)
            local curated = ns.TANK_ABILITIES and ns.TANK_ABILITIES[key]
            local on = ns.AbilityEnabledForBinding(enc, key)
            local binding = ns.BindingForBossModKey(enc, key)
            local verdict
            if on and binding and binding.mode == "custom" then
                verdict = ns.Color("muted", "steps aside to its Ability Reminder")
            elseif on then
                verdict = "|cff6DD09Awould call|r"
            else
                verdict = "|cffff6060OFF for this boss|r"
            end
            ns.Print(("  %d %s -- %s/%s x%d -- %s, %s"):format(
                key, (info and info.name) or "?", tostring(e.mod), tostring(e.kind),
                e.seen or 0,
                curated and "in the tank list" or ns.Color("muted", "not a tank ability"),
                verdict))
        end
        return
    end

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
                -- bit.band on a secret raises. Reduced to a plain number inside the guard,
                -- or a secret boolean escapes and throws outside the pcall.
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

    -- NeverSecret defensives keep voice working in combat; ContextuallySecret ones do not.
    -- Run once at rest and once mid-pull.
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
            ns.Print(("%d. %s -- secrecy=%s speakable_now=%s"):format(
                i, (info and info.name) or sid, SecrecyLevelName(sid), tostring(CanNameSpellAloud(sid))))
        end
        return
    end

    -- Which spell ids carry the defensive flags is client data; dumps them for the picker.
    if arg == "defensives" then
        local shown = 0
        for _, slot in ipairs({ INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) do
            local link = GetInventoryItemLink("player", slot)
            if link and C_Item and C_Item.GetItemSpell then
                local spellName, spellID = C_Item.GetItemSpell(link)
                ns.Print(("trinket slot %d: %s -> %s"):format(slot, link,
                    spellID and ("%s (%d)"):format(tostring(spellName), spellID) or "no on-use spell"))
            else
                ns.Print(("trinket slot %d: empty"):format(slot))
            end
        end
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

    -- Checks the generated ns.TANK_ABILITIES (Tactyks' sheet) against the Dungeon Journal's
    -- role flags, which proved right over the sheet for Triple Shot. Boss-mod GetOptions
    -- role tags are too sparse to settle this.
    if arg == "tanksheet" then
        local cache = ns.ScrapeBosses and ns.ScrapeBosses()
        if not cache then
            ns.Print("the journal has not been scraped yet -- open a Dungeon Bosses or "
                .. "Raid Bosses page once, then retry.")
            return
        end
        local extrasFor = {}
        for i = 1, #cache.instances do
            local inst = cache.instances[i]
            for j = 1, #inst.bosses do
                local abilities = inst.bosses[j].abilities
                for k = 1, #abilities do
                    local a = abilities[k]
                    if a.spellID then extrasFor[a.spellID] = a.extras end
                end
            end
        end
        -- Only these are role flags; Heroic, Deadly, Magic and the rest are not.
        local ROLE_FLAGS = { "Tank", "Dps", "Healer" }
        local function NamesARole(extras)
            for i = 1, #ROLE_FLAGS do
                if extras:find(ROLE_FLAGS[i], 1, true) then return true end
            end
            return false
        end

        local checked, agree, contra, unconfirmed, noData = 0, 0, 0, 0, 0
        local contraLines, unconfLines = {}, {}
        local curated = ns.TANK_ABILITIES or {}
        local ids = {}
        for sid in pairs(curated) do ids[#ids + 1] = sid end
        table.sort(ids)
        ns.Print((ns.Color("accent", "tank sheet cross-check") .. " against %d journal-scraped bosses:")
            :format(#cache.instances))
        for i = 1, #ids do
            local sid = ids[i]
            checked = checked + 1
            local extras = extrasFor[sid]
            local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            local name = (si and si.name) or tostring(sid)
            if extras == nil then
                noData = noData + 1
            elseif extras:find("Tank", 1, true) then
                agree = agree + 1
            elseif NamesARole(extras) then
                contra = contra + 1
                contraLines[#contraLines + 1] =
                    ("  |cffff6060%s|r (%d) -- journal says: %s"):format(name, sid, extras)
            else
                -- Not evidence against: Apex Predator lands here, yet BigWigs calls it tank_combo.
                unconfirmed = unconfirmed + 1
                unconfLines[#unconfLines + 1] =
                    ("  %s (%d) -- no role flag%s"):format(name, sid,
                        extras ~= "" and (", only: " .. extras) or "")
            end
        end

        if contra > 0 then
            ns.Print("|cffff6060contradicted|r -- the journal names a different role:")
            for i = 1, #contraLines do ns.Print(contraLines[i]) end
        end
        if unconfirmed > 0 then
            ns.Print("|cffffc000unconfirmed|r -- no role flag either way, check the boss mod "
                .. "before changing anything:")
            for i = 1, #unconfLines do ns.Print(unconfLines[i]) end
        end
        ns.Print(("%d checked: %d confirmed, %d contradicted, %d unconfirmed, %d not in this "
            .. "season's journal pool"):format(checked, agree, contra, unconfirmed, noData))
        if contra == 0 then
            ns.Print("nothing the journal actively contradicts.")
        end
        if noData > 0 then
            ns.Print("open more Dungeon Bosses and Raid Bosses pages to cover the rest.")
        end
        return
    end

    -- Retired with the fingerprint engine. trace and export came back as spellID recorders
    -- and are handled above.
    if arg == "mute" or arg == "unmute" or arg == "tank" or arg == "untank"
        or arg == "learn" or arg == "marked" or arg == "muted" then
        ns.Print("/nutank " .. arg .. " was part of the old fingerprint engine and has been "
            .. "retired. Enable or disable an ability from Setup's own checklist instead.")
        return
    end

    -- What the pick would decide right now, from the same SpellReady the voice uses.
    if arg == "cds" then
        RefreshSpec()
        ns.Apply()
        if activeSlots == 0 then
            ns.Print("nothing on your priority list is talented, so there is nothing to read. "
                .. "Add defensives in Smart Reminders, or check you are on the right spec.")
            return
        end
        ResyncModel()
        local now, anyReady = GetTime(), false
        ns.Print((ns.Color("accent", "cooldowns") .. " (build %s), in priority order:"):format(BuildString()))
        for i = 1, activeSlots do
            local sid = slots[i].spellID
            local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            local ok, ready = pcall(SpellReady, sid, now)
            if ok and ready then anyReady = true end
            local st = chargeState[ns.CooldownKey(sid)]
            local detail = st
                and ("%d/%d charges, recharge %s (%s)"):format(
                    ChargesAvailable(sid) or 0, st.max,
                    st.recharge > 0 and ("%.0fs"):format(st.recharge) or "unknown",
                    st.rechargeSrc == "client" and "|cff6DD09Aclient|r"
                        or ("|cffF0A830" .. tostring(st.rechargeSrc) .. "|r"))
                or (CooldownRunning(sid) == nil and "cooldown unreadable, using the estimate"
                    or "cooldown read directly")
            ns.Print(("  %d. %s -- %s (%s)"):format(i, (info and info.name) or tostring(sid),
                ok and (ready and "|cff6DD09AREADY|r" or "|cffff6060on cooldown|r")
                    or "|cffff6060read failed|r", detail))
        end
        if anyReady then
            ns.Print("  at least one is up, so a callout now would name it, not an external.")
        else
            ns.Print("  nothing is up, so a callout now WOULD say " .. tostring(TRDB().voiceNone) .. ".")
        end
        return
    end

    if arg == "calls" then
        local log = TRDB().callLog
        if not (log and #log > 0) then
            ns.Print("nothing logged yet this session.")
            return
        end
        for i = 1, #log do
            ns.Print(LogLine(log[i]))
        end
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
                .. "NaowhForever_Bosses.lua is missing from the addon folder.")
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
            -- GetAlpha is SecretReturnsForAspect once applied, so a refused read means the
            -- gate is live.
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

    if arg == "" and ns.ToggleOptionsWindow then
        ns.ToggleOptionsWindow("Smart Reminders/Settings")
        return
    end
    if arg ~= "status" then
        ns.Print("unknown command '" .. arg .. "' -- /nutank status for diagnostics, or see below.")
    end

    ns.Print(("build: %s"):format(BuildString()))
    ns.Print(("tank reminder: enabled=%s spec=%d tank=%s slots=%d"):format(
        tostring(TRDB().enabled), specID, tostring(isTank), activeSlots))
    if TRDB().pretendTank then
        ns.Print("|cffF0A830PRETEND TANK IS ON|r -- the aggro gate is ignored, so abilities "
            .. "call whether or not you hold the boss. /nutank pretendtank turns it off.")
    end
    ns.Print(("boss addon: %s"):format(ns.BossSource()))
    if currentEncounter then
        local diffName = currentDifficultyID and GetDifficultyInfo
            and GetDifficultyInfo(currentDifficultyID)
        ns.Print(("pull: enc=%s elapsed=%.1fs difficulty=%s(%s) stage=%s%s"):format(
            tostring(currentEncounter),
            currentEncounterStartedAt and (GetTime() - currentEncounterStartedAt) or -1,
            tostring(diffName or "?"), tostring(currentDifficultyID),
            tostring(currentStage),
            currentStageAt and (" stageElapsed=%.1fs"):format(GetTime() - currentStageAt) or ""))
    end
    ns.Print(("timeline: available=%s bossWarnings=%s timelineDisplay=%s"):format(
        tostring(TimelineAvailable()),
        CombatWarningsOff() and "|cffff6060OFF|r" or "on",
        TimelineDisplayOff() and "off (fine -- data still flows)" or "on"))
    ns.Print(("engine: select=%s gate=%s bar=%s sound=%s"):format(
        tostring(canSelect and true or false), tostring(canGate and true or false),
        tostring(canBar and true or false), tostring(canSound and true or false)))
    -- The counters only move during an encounter, so zero outside a pull says nothing.
    ns.Print(("aura cover: bigDefensiveHits=%d (Blizzard's own classification; 0 all pull "
        .. "means the aura enumeration is refused here)"):format(bigDefSeen))
    ns.Print(("combat log: registered=%s inInstance=%s restrictedHere=%s lines=%d usable=%d ownAuras=%d playerGUID=%s"):format(
        watcher:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") and "true"
            or "|cffff6060false|r",
        tostring(IsInInstance()),
        tostring(C_CombatLog and C_CombatLog.IsCombatLogRestricted
            and C_CombatLog.IsCombatLogRestricted()),
        cleuLines, cleuUsable, cleuOwnAuras,
        PlayerGUID() and "readable" or "|cffff6060UNREADABLE|r"))
    ns.Print("usage: /nutank status | observed | cds | calls | keys | trace | export | pretendtank | test | catalogue | gate | secrecy | bosses | defensives | tanksheet")
end

-------------------------------------------------------------------------------
--  "Add a Defensive" picker
-------------------------------------------------------------------------------
-- Candidates come from the client, so the addon still ships no spell list: the Cooldown
-- Manager's Essential/Utility sets (spec-correct, but not split offensive/defensive) and
-- C_UnitAuras.AuraIsBigDefensive for the defensive axis. That is an aura flag, so each
-- candidate is tested on its cast id, override and linked ids.

-- The picker's Show All toggle; declared here for the fallback collector below.
local pickerShowAll = false

local bigDefCache = {}

-- Externals are flagged big-defensive too (Pain Suppression), so they are excluded.
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

local function InfoIsExternal(info)
    if IsExternalDefensive(info.spellID) then return true end
    if info.overrideSpellID and IsExternalDefensive(info.overrideSpellID) then return true end
    local linked = info.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do
            if IsExternalDefensive(linked[i]) then return true end
        end
    end
    -- Catches externals Blizzard's own flag misses.
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

    -- No selfAura/hasAura fallback: Divine Shield and Ardent Defender report hasAura=false,
    -- and selfAura alone pulls in Consecration and Divine Steed.
    return false
end

-- Fallback for a client without the Cooldown Manager.
local function CollectFromSpellbook(seen, list, out)
    local MIN_BASE_CD_MS = 30000
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

-- nil = the spec default; set = a per-boss override.
local pickerEncounter

local function TargetList(create)
    if pickerEncounter then return BossList(specID, pickerEncounter, create) end
    return UserList(specID, create)
end

-- True for the inline editor, which lists every defensive whether listed or not.
local collectAll = false

ns.InfoIsDefensive = InfoIsDefensive

local function CollectCandidates()
    local out, seen = {}, {}
    local list = (not collectAll) and TargetList(false) or nil

    -- Equipped trinket on-use effects, read off the item and left for the player to judge.
    for _, slot in ipairs({ INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) do
        local link = GetInventoryItemLink("player", slot)
        if link and C_Item and C_Item.GetItemSpell then
            local spellName, spellID = C_Item.GetItemSpell(link)
            if spellID and not seen[spellID] then
                seen[spellID] = true
                if not (list and ns.ListIndexOf(list, spellID)) then
                    local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                    local base = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
                    out[#out + 1] = {
                        id   = spellID,
                        name = spellName or (si and si.name) or ("Spell " .. spellID),
                        icon = si and si.iconID,
                        cd   = (type(base) == "number" and base) or 0,
                    }
                end
            end
        end
    end

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

    if #out == 0 then
        CollectFromSpellbook(seen, list, out)
    end

    table.sort(out, function(a, b)
        if a.cd ~= b.cd then return a.cd > b.cd end
        return a.name < b.name
    end)
    return out
end

local pickPopup
local ShowPicker

local function AddSpell(spellID)
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

    local dimmer, panel = ns.MakeModal(380, 460, "defensivePicker")

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
                row.hl = ns.Solid(row, "BACKGROUND", ns.THEME.accentSoft, 0.10)
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
local textPopup

-- A SharedMedia sound, or text to speak; "Speak the text instead" is the no-sound entry.
local function ShowCalloutEditor(title, current, onAccept, spellID)
    if not textPopup then
        local dimmer, panel = ns.MakeModal(400, 240, "calloutEditor")

        local head = ns.Font(panel, 14, "OUTLINE")
        head:SetPoint("TOP", panel, "TOP", 0, -16)

        local modeHolder = CreateFrame("Frame", nil, panel)
        modeHolder:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -46)
        modeHolder:SetSize(356, 22)

        -- Sound and text controls share one slot; only one is shown.
        local soundLbl = ns.Font(panel, 11, nil, ns.THEME.muted)
        soundLbl:SetPoint("TOPLEFT", modeHolder, "BOTTOMLEFT", 0, -16)
        soundLbl:SetText("Sound")

        local ddHolder = CreateFrame("Frame", nil, panel)
        ddHolder:SetPoint("TOPLEFT", soundLbl, "BOTTOMLEFT", 0, -4)
        ddHolder:SetSize(356, 30)

        local textLbl = ns.Font(panel, 11, nil, ns.THEME.muted)
        textLbl:SetPoint("TOPLEFT", modeHolder, "BOTTOMLEFT", 0, -16)
        textLbl:SetText("Spoken text")

        -- The one hand-built widget: the factory has no text input.
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
            -- Both halves land together on Save; text mode clears the sound.
            ns.SetSoundFor(textPopup._spellID,
                (textPopup._mode == "sound") and textPopup._soundKey or nil)
            dimmer:Hide()
            if textPopup._onAccept then textPopup._onAccept(box:GetText()) end
        end

        local hear = ns.Button(panel, "Hear it", 96, 26, function()
            local key = (textPopup._mode == "sound") and textPopup._soundKey or nil
            local EUI = ns.UI
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

    -- Refilled per open: SharedMedia may have registered more by now.
    local paths, names, order = ns.SoundChoices()
    tp._paths = paths
    -- nil, not "none": a truthy placeholder would open every callout in sound mode.
    tp._soundKey = ns.SoundFor(tp._spellID)

    tp._mode = tp._soundKey and "sound" or "text"
    tp._firstSound = order and order[1] or nil

    local EUI = ns.UI
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

    -- On means spoken text, off means a sound file.
    if not tp._modeToggle and EUI and EUI.BuildToggleControl then
        local tg, _, tgSnap = EUI.BuildToggleControl(tp.modeHolder,
            tp.modeHolder:GetFrameLevel() + 5,
            function() return tp._mode == "text" end,
            function(v)
                tp._mode = v and "text" or "sound"
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
        if not tp._dd then
            tp._names, tp._order = {}, {}
            tp._dd = EUI.BuildDropdownControl(tp.ddHolder, 356, tp.panel:GetFrameLevel() + 8,
                tp._names, tp._order,
                function() return tp._soundKey or tp._firstSound end,
                function(v)
                    tp._soundKey = v   -- held until Save
                    tp._mode = "sound"
                    tp._sync()
                end)
            tp._dd:SetPoint("TOPLEFT", tp.ddHolder, "TOPLEFT", 0, 0)
        end
        wipe(tp._names)
        wipe(tp._order)
        for k, v in pairs(names) do tp._names[k] = v end
        for i = 1, #order do tp._order[i] = order[i] end
        tp._dd._refreshLabel()
    end
    Sync()

    tp.dimmer:Show()
    tp.box:SetFocus()
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
-- Every builder returns the raw running y; the window's page wrapper takes math.abs of it.
-------------------------------------------------------------------------------
--  Settings (declared in NaowhForever_SmartRemindersSettings.lua)
-------------------------------------------------------------------------------

-- The module's switch in the options window.
function ns.SetEnabled(v)
    TRDB().enabled = v
    ns.Apply()
    UpdatePreview()
end

local function RefitAlert() ApplySize(); UpdatePreview() end
local function RelayoutAlert() ApplyTextLayout(); UpdatePreview() end

ns.SmartReminderApply = {
    bossSource = function() ns.Apply() end,
    showIcon = RefitAlert, showText = RefitAlert, fontName = RefitAlert,
    iconSize = RefitAlert, textSize = RefitAlert, textSide = RelayoutAlert,
    cdmGlow = function(v) if not v then ns.StopCDMGlow() end end,
    soundOn = function() RegisterEventSounds() end,
    soundKey = function() RegisterEventSounds() end,
    defensiveTextColorOn = function() ApplyDefensiveTextColor() end,
    defensiveTextColor = function() ApplyDefensiveTextColor() end,
    castTargetBoss = function() if ns.RefreshCastWatch then ns.RefreshCastWatch() end end,
}

function ns.DefensivePreviewPinned() return previewPin end
function ns.SetDefensivePreviewPinned(v) previewPin = v and true or false; UpdatePreview() end
function ns.CombatWarningsOff() return CombatWarningsOff() end
function ns.SoundError() return soundError end

-- Alone on its page: RenderPresetListEditor's returned height runs short once the
-- spare-defensives column gets long, so nothing may stack below it.
function ns.BuildPresetListSettings(parent, y)
    local EUI = ns.UI
    local W   = EUI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "PRESET LIST (THIS SPEC)", y); y = y - h

    if ns.RenderPresetListEditor then
        y = ns.RenderPresetListEditor(parent, y, W, EUI, specID)
    end

    return y
end

function ns.BuildPresetsPage(parent, yOffset)
    local EUI = ns.UI
    if EUI.ClearContentHeader then EUI:ClearContentHeader() end
    RefreshSpec()

    local y = yOffset
    if ns.BuildPresetListSettings then y = ns.BuildPresetListSettings(parent, y) end
    return math.abs(y)
end

function ns.BuildBossTabPage(parent, yOffset, isRaid)
    local EUI = ns.UI
    if EUI.ClearContentHeader then EUI:ClearContentHeader() end
    RefreshSpec()

    local y = yOffset
    if ns.BuildBossListPage then
        y = ns.BuildBossListPage(parent, y, isRaid)
    end
    return math.abs(y)
end

-- Every major defensive the player has, regardless of what is already on a list.
function ns.AllDefensives(forSpec, encounterID)
    RefreshSpec()
    local prevEnc, prevAll = pickerEncounter, collectAll
    pickerEncounter, collectAll = encounterID, true
    local ok, out = pcall(CollectCandidates)
    pickerEncounter, collectAll = prevEnc, prevAll
    return ok and out or {}
end

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

-- User-added spell IDs per spec, for anything Blizzard's classification misses.
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

-- Auto-populated abilities come back on rebuild, so removing one records a hide.
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

function ns.ResolveSpell(text)
    local sid = tonumber(text and tostring(text):match("^%s*(%d+)%s*$"))
    if not sid or sid <= 0 then return nil end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    if not info then return nil end
    return sid, info
end

-- Spell ID 0 is the "nothing is up" fallback line.
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

-- Only the sound key is stored, so switching back to speech keeps the typed text.
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

-- Fresh tables per call: the SharedMedia appender mutates in place and caches by
-- table identity, so handing the same tables to two dropdowns collapses them into one.
function ns.SoundChoices()
    local EUI = ns.UI
    if not (EUI and EUI.BuildAlertSoundTables) then return nil end
    local paths, names, order = EUI.BuildAlertSoundTables()
    if EUI.AppendSharedMediaSounds then EUI.AppendSharedMediaSounds(paths, names, order) end
    names["none"] = nil
    for i = #order, 1, -1 do
        if order[i] == "none" then table.remove(order, i) end
    end
    return paths, names, order
end

-- For the pack exporter. `pos` is not in DEFAULTS, so the exporter takes it separately.
function ns.SettingKeys()
    local out = {}
    for k in pairs(DEFAULTS) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function ns.SettingDefault(key)
    return DEFAULTS[key]
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
    if ns.Integrations then ns.Integrations.Refresh() end
    ns.PruneCustomReminderTimers()
    ns.PrunePendingBWFires()
    RebuildSlots()
    RebuildCastMap()
    UpdateEventRegistration()
    UpdatePreview()
    RefreshCustomRemindersFlag()
end

-------------------------------------------------------------------------------
--  Reset / re-apply
-------------------------------------------------------------------------------
-- Re-apply is owned by the core's QueueReapply.

function ns.Reset()
    HideReminder()
    activeSlots = 0
    ns.ClearEventSounds()
    ns.SettingsRoot().tankReminder = nil
    ns.PruneCustomReminderTimers()
    ns.PrunePendingBWFires()
    ApplySize()
    ApplyPosition()
    ApplyTextLayout()
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
-- Static, not under ShouldRun(): custom reminders work without a priority list.
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Refreshes ns.bossGUIDs; static for the same reason.
watcher:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
-- A boss that phases in becomes targetable without the engage list changing; Blizzard's
-- boss frames (TargetFrame.lua) refresh on this too.
watcher:RegisterEvent("UNIT_TARGETABLE_CHANGED")
watcher:RegisterEvent("VOICE_CHAT_TTS_VOICES_UPDATE")

watcher:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    -- First, and gated before the pcall: the most frequent event in the game.
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if currentEncounter == nil
            or not (runActive or hasCustomReminders or hasRaidReminders) then
            return
        end
        local okL, errL = pcall(OnCombatLog)
        if not okL then
            ns.Print("|cffff6060combat log watch failed|r: " .. ErrText(errL))
        end
        return
    end

    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        ns.RefreshBossGUIDs()
        return
    end

    if event == "UNIT_TARGETABLE_CHANGED" then
        -- Fires for every tracked unit, nameplates included.
        if currentEncounter ~= nil and type(arg1) == "string"
            and arg1:find("boss", 1, true) == 1 then
            ns.RefreshBossGUIDs()
        end
        return
    end

    if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        -- Dying resets much of a kit, which the model cannot see.
        wipe(readyAt)
        ResyncModel()
        return
    end

    if event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        local starting = (event == "ENCOUNTER_START")
        -- Commit before the clocks are cleared: the recorder measures against them.
        if not starting and ns.ObserveCommitPull then
            ns.ObserveCommitPull(arg1, arg3)
        end
        currentEncounter = starting and arg1 or nil
        ns.RefreshBossGUIDs()
        -- Timeline sounds have no per-fire callback, so the healer opt-out re-registers here.
        if not ns.HealerRemindersEnabled() and ns.BossSource() == "timeline" then
            RegisterEventSounds()
        end
        -- Payload is encounterID, name, difficultyID, groupSize.
        currentEncounterStartedAt = starting and GetTime() or nil
        currentDifficultyID = starting and arg3 or nil
        if starting and ns.ObserveBeginPull then ns.ObserveBeginPull() end
        if TRDB().trace then
            AppendLog({ kind = "enc", text = ("%s %s %s"):format(
                event == "ENCOUNTER_START" and "START" or "END",
                tostring(arg1), tostring(arg2)) })
        end
        -- Boss death does not reset the player's cooldowns; keep witnessed deadlines.
        wipe(ns.lastTankedAt)
        lastAnnouncedSpellID = nil
        RebuildSlots()
        RebuildCastMap()
        UpdateEventRegistration()

        wipe(customCounters)
        bwActiveMod = nil
        currentStage = nil
        currentStageAt = nil
        -- By scope: "combat" timers count from entering combat and survive a pull.
        ns.CancelTrackedReminderTimers("pull")
        ns.CancelTrackedReminderTimers("stage")
        ns.CancelTrackedReminderTimers("bosscombat")
        for k, handle in pairs(bwPendingTimers) do
            if handle.Cancel then handle:Cancel() end
            bwPendingTimers[k] = nil
            ns.pendingCustomReminderOwners[k] = nil
        end
        wipe(bwCdEndsAt)
        CancelAllPendingBWFires()
        for k in pairs(castSourceGUID) do
            castSourceGUID[k] = nil
        end
        -- A missed SPELL_AURA_REMOVED must not carry "still covered" into the next pull.
        for k in pairs(playerAuraUp) do
            playerAuraUp[k] = nil
        end
        RefreshCustomRemindersFlag()
        if event == "ENCOUNTER_START" then
            RegisterBossModHooks()   -- in case BigWigs/DBM loaded after this addon did
            CheckCustomReminders("pull", nil)
            ns.CheckBossCombatReminders()
            if ns.CheckRaidReminderPullTriggers then ns.CheckRaidReminderPullTriggers() end
        end

        -- After RebuildSlots: activeSlots is the previous list's until then.
        if event == "ENCOUNTER_START" and TRDB().enabled == true then
            local why
            if not canSelect then why = "this client lacks the cooldown API"
            elseif activeSlots == 0 then why = "no priority list for this spec (or nothing on it is talented)"
            elseif not EngineAvailable() then
                why = "there is no boss timeline here and no BigWigs or DBM to follow"
            elseif not BossAllowed() then why = "this boss is switched off in Smart Reminders"
            end
            if not why then
                local t2 = TRDB()
                if not (t2.showIcon or t2.showText or t2.voiceOn or t2.soundOn) then
                    why = "icon, text, voice and sound are ALL switched off"
                elseif not (t2.showIcon or t2.showText or t2.voiceOn)
                    and not saidAudioOnly then
                    -- Legitimate configuration, so once per session.
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
        NoteOwnCast(arg3)   -- (unit, castGUID, spellID)
        ns.HideIfCalloutPressed(arg3)
        return
    end

    -- Spec-bound profiles take effect here. No return: PLAYER_LOGIN has its own handler below.
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOGIN"
        or event == "PLAYER_ENTERING_WORLD" then
        RefreshSpec()
        if ns.ApplySpecProfile then ns.ApplySpecProfile(specID) end
    end

    if event == "PLAYER_REGEN_DISABLED" then
        -- An ns field, not a chunk local: this chunk is at the 200-local ceiling.
        ns.combatStartedAt = GetTime()
        ns.CheckCombatReminders()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" or event == "SPELL_UPDATE_COOLDOWN" then
        if event == "SPELL_UPDATE_COOLDOWN" then ns.ResyncModelSoon() else ResyncModel() end
        if event == "PLAYER_REGEN_ENABLED" then
            ns.CancelTrackedReminderTimers("combat")
            -- A combat log toggle skipped because of combat lockdown lands here.
            UpdateEventRegistration()
        end
        return
    end

    if event == "VOICE_CHAT_TTS_VOICES_UPDATE" then
        ns.InvalidateTTSVoice()
        return
    end


    if event == "PLAYER_LOGIN" then
        RegisterBossModHooks()
        if ns.ObservedPrune then ns.ObservedPrune() end
        local EUI = ns.UI
        if EUI and EUI.RegisterOnShow then
            EUI:RegisterOnShow(function() previewing = true; UpdatePreview() end)
        end
        if EUI and EUI.RegisterOnHide then
            EUI:RegisterOnHide(function()
                previewing = false
                UpdatePreview()
                if ns.HideRaidReminderAnchorConfig then ns.HideRaidReminderAnchorConfig(true) end
            end)
        end
        -- Read only, never written.
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

    -- SPELLS_CHANGED and TRAIT_CONFIG_UPDATED arrive in bursts; one Apply covers them.
    ns.QueueReapply()
end)
