-- Native aura sounds for debuff alerts. No aura data is read.
local ns = _G.NaowhForever
local I = {}
ns.Integrations = I
local sounds = {}
-- No per-spec rule cap: AddAuraSound has no documented limit and returns nil on refusal,
-- which is reported below. The old cap of 32 also counted trash rules.

-- Racial callouts that must stay quiet while the racial is unavailable. The client plays
-- these itself, so the FILE is muted instead: each needs its own file, plus a preview copy.
local RACIALS = {
    ["voice:stoneform-ready"] = { spellID = 20594, name = "Stoneform",
        preview = "voice:stoneform-preview" },
    ["voice:shadowmeld-ready"] = { spellID = 58984, name = "Shadowmeld",
        preview = "voice:shadowmeld-preview" },
}
-- Registration key -> the racial sound it belongs to, for the pending-changes comparison.
local gatedSounds = {}
local racialState = {}
for key in pairs(RACIALS) do racialState[key] = {} end
local events, racialEventsOn
local racialEvents = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELLS_CHANGED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function Table(v)
    return Plain(v) and type(v) == "table" and (not canaccesstable or canaccesstable(v))
end
local function Number(v, low, high)
    return Plain(v) and type(v) == "number" and v == v and v >= low and v <= high
end
function I.Spec()
    local index = C_SpecializationInfo.GetSpecialization()
    return index and C_SpecializationInfo.GetSpecializationInfo(index) or 0
end
function I.Rules(create)
    local db, spec = ns.DB(), tostring(I.Spec())
    if create then
        db.integrationRules = db.integrationRules or {}
        db.integrationRules[spec] = db.integrationRules[spec] or {}
    end
    return db.integrationRules and db.integrationRules[spec]
end
function I.ValidRule(r)
    if not Table(r) or not Table(r.trigger) or not Table(r.display) then return false end
    local t, d = r.trigger, r.display
    if t.type ~= "exboss" and t.type ~= "auraSound" then return false end
    if not Number(t.spellID, 1, 100000000) or t.spellID % 1 ~= 0
        or not Number(t.mapID, 0, 1000000) or t.mapID % 1 ~= 0 then return false end
    if type(r.name) ~= "string" or #r.name > 120 then return false end
    if r.enabled ~= nil and type(r.enabled) ~= "boolean" then return false end
    if r.healerReminder ~= nil and type(r.healerReminder) ~= "boolean" then return false end
    if not Number(d.dur, 1, 15) or type(d.text) ~= "string" or #d.text > 200 then return false end
    if d.sound ~= nil and (type(d.sound) ~= "string" or #d.sound > 200) then return false end
    if d.tts ~= nil and type(d.tts) ~= "boolean" then return false end
    if d.castRepeat ~= nil and type(d.castRepeat) ~= "boolean" then return false end
    if d.castAudio ~= nil and type(d.castAudio) ~= "boolean" then return false end
    if d.type ~= "icon" and d.type ~= "text" then return false end
    if d.spellID ~= nil and (not Number(d.spellID, 1, 100000000) or d.spellID % 1 ~= 0) then return false end
    if r.preset ~= nil and (type(r.preset) ~= "string" or #r.preset > 120) then return false end
    -- A racial you cast on yourself cannot answer for a debuff on somebody else.
    if RACIALS[d.sound] and (t.type ~= "auraSound" or t.target ~= "player") then return false end
    -- ExBoss trash rules no longer run, but still validate so older profiles and packs import.
    if t.type == "exboss" then return Number(t.timeleft, 0, 30) end
    return (t.target == "player" or t.target == "party")
        and (t.auraEvent == "Added" or t.auraEvent == "ApplicationsIncreased" or t.auraEvent == "Removed")
        and type(d.sound) == "string" and d.sound ~= "none" and d.sound ~= ""
end
local function Map()
    local _, kind, _, _, _, _, _, id = GetInstanceInfo()
    return id, kind
end
local function Eligible(r, kind)
    if not I.ValidRule(r) or r.trigger.type ~= kind or not ns.IsReminderEnabled(r)
        or ns.DB().enabled ~= true then return false end
    local map, instance = Map()
    return (instance == "party" or instance == "raid")
        and (r.trigger.mapID == 0 or r.trigger.mapID == map)
end
function I.Preview(rule)
    if not I.ValidRule(rule) or rule.trigger.type ~= "auraSound"
        or not ns.IsReminderEnabled(rule, true) then return end
    -- Preview has a separate file: never unmute a live registration for a test.
    local racial = RACIALS[rule.display.sound]
    if racial then
        ns.PlayReminderSound({ sound = racial.preview })
    else ns.PlayReminderSound(rule.display) end
end
local function RestrictionBusy()
    local api, types = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
    if not (api and api.GetAddOnRestrictionState and types) then return false end
    return api.GetAddOnRestrictionState(types.Combat) ~= Enum.AddOnRestrictionState.Inactive
        or api.GetAddOnRestrictionState(types.Encounter) ~= Enum.AddOnRestrictionState.Inactive
end
local function AuraBusy()
    return InCombatLockdown() or (ns.InEncounter and ns.InEncounter()) or RestrictionBusy()
end
-- Every rung reads a plain value or refuses: an unreadable cooldown is not a ready racial.
local function RacialReady(spellID)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown and C_Spell
        and C_Spell.GetSpellCooldown and C_Spell.IsSpellUsable and UnitIsDeadOrGhost) then return false, "API unavailable" end
    local known, dead = C_SpellBook.IsSpellKnown(spellID), UnitIsDeadOrGhost("player")
    if not Plain(known) or known ~= true then return false, "spell not known or unreadable" end
    if not Plain(dead) or dead ~= false then return false, "dead or unreadable player state" end
    local cd = C_Spell.GetSpellCooldown(spellID)
    if not Table(cd) or not Plain(cd.isActive) or not Plain(cd.isEnabled) then return false, "cooldown unreadable" end
    if cd.isActive ~= false or cd.isEnabled ~= true then return false, "cooldown active or on hold" end
    local usable = C_Spell.IsSpellUsable(spellID)
    if not Plain(usable) then return false, "usability unreadable" end
    if usable ~= true then return false, "spell unusable" end
    return true, "ready"
end
local function RacialStatusLine()
    local parts = {}
    for key, racial in pairs(RACIALS) do
        local st = racialState[key]
        if st.owned and st.reason then parts[#parts + 1] = racial.name .. ": " .. st.reason end
    end
    table.sort(parts)
    I.racialStatus = #parts > 0 and table.concat(parts, "  ") or nil
end
local function UpdateRacial(key)
    local st = racialState[key]
    if not st.owned then return end
    local ready, reason = false, "configuration pending or disabled"
    if st.enabled then ready, reason = RacialReady(RACIALS[key].spellID) end
    local muted = not ready
    if muted ~= st.muted then
        local path = ns.UI.SoundPathFor(key)
        if muted then MuteSoundFile(path) else UnmuteSoundFile(path) end
        st.muted = muted
    end
    -- Runs dozens of times a second in combat. Keyed on reason, not `muted`: several
    -- reasons mean muted and the status line names which one.
    if reason == st.reason then return end
    st.reason = reason
    RacialStatusLine()
    if I.OnStatusChanged then I.OnStatusChanged() end
end
-- The readiness events are shared, so they follow whether ANY racial is being gated rather
-- than being registered once per racial on the same frame.
local function SyncRacialEvents()
    local any = false
    for key in pairs(RACIALS) do
        if racialState[key].enabled then any = true end
    end
    if any == racialEventsOn then return end
    racialEventsOn = any
    for _, event in ipairs(racialEvents) do
        if any then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
end
local function SetRacialEnabled(key, enabled)
    enabled = enabled and MuteSoundFile ~= nil and UnmuteSoundFile ~= nil or false
    racialState[key].enabled = enabled
    SyncRacialEvents()
    UpdateRacial(key)
end
local function SetAllRacialsEnabled(enabled)
    for key in pairs(RACIALS) do SetRacialEnabled(key, enabled) end
end
local function RefreshSounds()
    -- Pending edits must not leave a stale profile's racial callout audible.
    SetAllRacialsEnabled(false)
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound
        and Enum and Enum.UnitAuraSoundTrigger) then
        I.auraStatus = "Aura sounds require the Retail AddAuraSound API."
        return
    end
    local wanted, missing = {}, false
    for _, rule in pairs(I.Rules(false) or {}) do
        if Eligible(rule, "auraSound") then
            local t, path = rule.trigger, ns.UI.SoundPathFor(rule.display.sound)
            local gated = RACIALS[rule.display.sound] and rule.display.sound or nil
            if gated and not (MuteSoundFile and UnmuteSoundFile) then path = nil end
            if type(path) == "string" and path ~= "" then
                local units = t.target == "party" and { "party1", "party2", "party3", "party4" } or { "player" }
                for _, unit in ipairs(units) do
                    local key = unit .. ":" .. t.spellID .. ":" .. t.auraEvent .. ":" .. path
                    wanted[key] = { trigger = Enum.UnitAuraSoundTrigger[t.auraEvent], gated = gated,
                        info = { unitToken = unit, spellID = t.spellID, soundFileName = path, outputChannel = "Master" } }
                end
            else
                missing = true
            end
        end
    end
    if AuraBusy() then
        local matched, any = true, false
        for key in pairs(gatedSounds) do
            any = true
            if not wanted[key] or not wanted[key].gated then matched = false end
        end
        for key, request in pairs(wanted) do
            if request.gated and not gatedSounds[key] then matched = false end
        end
        SetAllRacialsEnabled(any and matched)
        I.auraStatus = "Sound changes pending until combat and encounter restrictions end. Existing registrations remain active."
        return
    end
    for key, id in pairs(sounds) do
        if not wanted[key] then
            C_UnitAuras.RemoveAuraSound(id); sounds[key] = nil; gatedSounds[key] = nil
        end
    end
    local count, failed, live = 0, false, {}
    for key, request in pairs(wanted) do
        local st = request.gated and racialState[request.gated]
        if st and not st.owned then
            st.owned = true
            UpdateRacial(request.gated)
        end
        if not sounds[key] then sounds[key] = C_UnitAuras.AddAuraSound(request.trigger, request.info) end
        if sounds[key] then count = count + 1 else failed = true end
        if sounds[key] and request.gated then
            live[request.gated] = true
            gatedSounds[key] = request.gated
        end
    end
    for racialKey in pairs(RACIALS) do
        SetRacialEnabled(racialKey, live[racialKey] == true)
        local st = racialState[racialKey]
        -- Handing the file back unmuted: a racial nothing is registered for any more must
        -- not leave its clip silenced for everything else that might play it.
        if not live[racialKey] and st.owned then
            UnmuteSoundFile(ns.UI.SoundPathFor(racialKey))
            st.owned, st.muted, st.reason = nil, nil, nil
        end
    end
    RacialStatusLine()
    I.auraStatus = missing and "Some rules could not load: check the selected sound files."
        or failed and "Some aura sounds were not accepted by the client."
        or (count .. " aura sound registrations active. Changes apply outside combat.")
end
function I.Refresh()
    RefreshSounds()
    -- The cast watch is built from these rules, and this is the one place that knows they
    -- changed: zoning, a spec swap and every edit all land here.
    if ns.RefreshCastWatch then ns.RefreshCastWatch() end
    if I.OnStatusChanged then I.OnStatusChanged() end
end
function I.Save(uid, rule)
    if not I.ValidRule(rule) then return false, "Check IDs, timing and sound. Stoneform voice requires Unit: Me." end
    local rules = I.Rules(true)
    if not uid then
        local index = 1
        while rules["i" .. index] do index = index + 1 end
        uid = "i" .. index
    end
    rules[uid] = rule
    I.Refresh()
    return true, uid
end

-- Every trigger field is in the key: one ability may deliberately have several rules
-- (player gain vs party loss, or callouts at eight seconds and at two).
local function RuleKey(r)
    local t = r.trigger
    return table.concat({ tostring(t.type), tostring(t.spellID), tostring(t.mapID),
        tostring(t.target), tostring(t.auraEvent), tostring(t.timeleft) }, ":")
end

local function CopyRule(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, inner in pairs(v) do out[k] = CopyRule(inner) end
    return out
end

-- kind is "exboss" or "auraSound". Each page copies only its own kind; the Trash button
-- used to drag debuff alerts across with it.
local function OfKind(rule, kind)
    return Table(rule) and Table(rule.trigger)
        and (not kind or rule.trigger.type == kind)
end

function I.SpecsWithRules(kind)
    local db = ns.DB()
    local all = Table(db.integrationRules) and db.integrationRules or {}
    local mine, out = tostring(I.Spec()), {}
    for specKey, rules in pairs(all) do
        if specKey ~= mine and Table(rules) then
            local n = 0
            for _, r in pairs(rules) do if OfKind(r, kind) then n = n + 1 end end
            if n > 0 then
                out[#out + 1] = { key = specKey, name = ns.SpecName(specKey), total = n }
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Additive, like the boss pages' Copy From Spec: existing rules for an ability are left
-- alone. Copies land on fresh uids since uids are sequential per spec. The third return
-- is always zero, kept for callers of the old capped signature.
function I.CopyRulesFromSpec(fromSpecKey, kind)
    local db = ns.DB()
    local all = Table(db.integrationRules) and db.integrationRules or nil
    local src = all and all[fromSpecKey]
    if not Table(src) then return 0, 0, 0 end
    local dst = I.Rules(true)
    if not Table(dst) then return 0, 0, 0 end

    local have = {}
    for _, r in pairs(dst) do
        if OfKind(r, kind) then have[RuleKey(r)] = true end
    end

    local uids = {}
    for uid in pairs(src) do uids[#uids + 1] = tostring(uid) end
    table.sort(uids)

    local copied, skipped, noRoom, index = 0, 0, 0, 1
    for i = 1, #uids do
        local r = src[uids[i]]
        if OfKind(r, kind) and I.ValidRule(r) then
            local key = RuleKey(r)
            if have[key] then
                skipped = skipped + 1
            else
                while dst["i" .. index] do index = index + 1 end
                dst["i" .. index] = CopyRule(r)
                have[key], copied = true, copied + 1
            end
        end
    end
    -- Once, not per rule: Refresh tears down and rebuilds every registration.
    if copied > 0 then I.Refresh() end
    return copied, skipped, noRoom
end
events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name, state)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if (name ~= Enum.AddOnRestrictionType.Combat and name ~= Enum.AddOnRestrictionType.Encounter)
            or state ~= Enum.AddOnRestrictionState.Inactive then return end
    end
    for _, gateEvent in ipairs(racialEvents) do
        if event == gateEvent then
            for key in pairs(RACIALS) do UpdateRacial(key) end
            return
        end
    end
    if event == "ADDON_LOADED" and name ~= "NaowhForever" then return end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and name ~= "player" then return end
    I.Refresh()
end)
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_END", "PLAYER_SPECIALIZATION_CHANGED", "ADDON_LOADED" }) do events:RegisterEvent(event) end
if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState then
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
end
