-- Optional trash predictions and native aura sounds. No aura data is read.
local ns = _G.NaowhUITankReminder
local I = {}
ns.Integrations = I
local pending, sounds = {}, {}
local delivered = setmetatable({}, { __mode = "k" })
local hooked, running = nil, false
local revision = 0
local MAX_RULES = 32
local STONEFORM = 20594
local STONEFORM_SOUND = "voice:stoneform-ready"
local gatedSounds = {}
local events, stoneformEnabled, stoneformOwned, stoneformMuted
local stoneformEvents = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELLS_CHANGED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function Table(v)
    return Plain(v) and type(v) == "table" and (not canaccesstable or canaccesstable(v))
end
local function Number(v, low, high)
    return Plain(v) and type(v) == "number" and v == v and v >= low and v <= high
end
function I.Spec()
    local index = GetSpecialization()
    return index and GetSpecializationInfo(index) or 0
end
function I.Rules(create)
    local db, spec = ns.DB(), tostring(I.Spec())
    if create then
        db.integrationRules = db.integrationRules or {}
        db.integrationRules[spec] = db.integrationRules[spec] or {}
    end
    return db.integrationRules and db.integrationRules[spec]
end
-- Read the installed timer provider's static catalogue; never copy or modify it.
-- Its dungeon keys are challenge IDs, while reminder filters are instance IDs.
function I.Catalogue()
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetTrashCDDataRoot) ~= "function"
        or type(api.GetEncounterDataRoot) ~= "function" then return {} end
    local ok, trash = pcall(api.GetTrashCDDataRoot)
    local mapsOK, encounter = pcall(api.GetEncounterDataRoot)
    if not ok or not mapsOK or not Table(trash) or not Table(encounter) then return {} end
    local byName, out = {}, {}
    for key, row in pairs(encounter.maps or encounter) do
        if type(row) == "table" and type(row.mapName) == "string" then
            local id = tonumber(row.instanceID or row.instanceId or row.mapID or key)
            if id then
                local prior = byName[row.mapName]
                if prior ~= nil and prior ~= id then byName[row.mapName] = false
                else byName[row.mapName] = id end
            end
        end
    end
    for key, dungeon in pairs(trash) do
        local instanceID = type(dungeon) == "table" and byName[dungeon.mapName]
        if instanceID then
            local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo(tonumber(key))
            local entry = { id = instanceID, name = name or dungeon.mapName, abilities = {} }
            local seen = {}
            for npcID, mob in pairs(dungeon.mobs or {}) do
                for spellID in pairs(mob.spells or {}) do
                    if type(spellID) == "number" and not seen[spellID] then
                        seen[spellID] = true
                        local info = C_Spell and C_Spell.GetSpellInfo(spellID)
                        local locale = (_G.EXBOSS_TRASH_CD_LOCALE or {})[npcID] or {}
                        entry.abilities[#entry.abilities + 1] = { spellID = spellID,
                            name = info and info.name or ("Spell " .. spellID),
                            icon = info and info.iconID,
                            mob = locale[GetLocale()] or locale.enUS or ("NPC " .. npcID) }
                    end
                end
            end
            table.sort(entry.abilities, function(a, b)
                if a.name == b.name then return a.spellID < b.spellID end
                return a.name < b.name
            end)
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
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
    if d.type ~= "icon" and d.type ~= "text" then return false end
    if d.spellID ~= nil and (not Number(d.spellID, 1, 100000000) or d.spellID % 1 ~= 0) then return false end
    if r.preset ~= nil and (type(r.preset) ~= "string" or #r.preset > 120) then return false end
    if d.sound == STONEFORM_SOUND and (t.type ~= "auraSound" or t.target ~= "player") then return false end
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
local function ClearPending(id)
    local entries = pending[id]
    pending[id] = nil
    if entries then
        for _, e in pairs(entries) do if e.handle then e.handle:Cancel() end end
    end
end
local function ClearAll()
    for id in pairs(pending) do ClearPending(id) end
    ns.PruneCustomReminderTimers()
end
local function Display(rule, preview)
    local d = {}
    for k, v in pairs(rule.display) do d[k] = v end
    if rule.preset then
        local picked = ns.ResolveReminderSpell(rule)
        if not picked then return end
        d.spellID = picked
        local info = C_Spell.GetSpellInfo(picked)
        if info and Plain(info.name) then d.text = info.name end
    end
    ns.DisplayRaidReminder({ enabled = true, healerReminder = rule.healerReminder, display = d,
        integration = true, integrationPreview = preview or nil }, preview)
end
function I.Preview(rule)
    if not I.ValidRule(rule) or not ns.IsReminderEnabled(rule, true) then return end
    if rule.trigger.type == "auraSound" then
        -- Preview has a separate file: never unmute a live registration for a test.
        if rule.display.sound == STONEFORM_SOUND then
            ns.PlayReminderSound({ sound = "voice:stoneform-preview" })
        else ns.PlayReminderSound(rule.display) end
    else
        ns.HideIntegrationReminders(true)
        Display(rule, true)
    end
end
local function TimerAt(scheduler, id)
    local all = scheduler:GetActiveTimers()
    return Table(all) and all[id] or nil
end
function I.ObserveTimer(scheduler, id)
    if not running or not Number(id, 1, 1000000000) then return end
    local timer = TimerAt(scheduler, id)
    if not Table(timer) or not Plain(timer.source) or timer.source ~= "trash"
        or not Number(timer.spellID, 1, 100000000) or not Number(timer.castTime, 0, 10000000000) then return end
    local rules = I.Rules(false)
    local at, generation = timer.castTime, revision
    local anchor
    if Plain(timer.trashFixedCombatTimeline) and timer.trashFixedCombatTimeline == true then
        anchor = at
    elseif Table(timer.trashRuntime) and Table(timer.trashRuntime.nextSpellAnchorAt) then
        local value = timer.trashRuntime.nextSpellAnchorAt[timer.spellID]
        if Number(value, 0, 10000000000) then anchor = value end
    end
    for uid, rule in pairs(rules or {}) do
        local prior = delivered[timer] and delivered[timer][rule]
        -- Anchor changes identify a new observed cast cycle. Without an anchor,
        -- keep deadline corrections quiet until the previously announced cycle ends.
        local alreadyDelivered = prior and ((anchor ~= nil and prior.anchor == anchor)
            or (anchor == nil and (prior.at == at or GetTime() < prior.at)))
        if alreadyDelivered then prior.at = at end
        if Eligible(rule, "exboss") and rule.trigger.spellID == timer.spellID
            and not alreadyDelivered then
            local old = pending[id] and pending[id][uid]
            if not old or old.at ~= at or old.anchor ~= anchor or old.rule ~= rule then
                if old and old.handle then old.handle:Cancel() end
                local entry = { at = at, anchor = anchor, rule = rule }
                pending[id] = pending[id] or {}
                pending[id][uid] = entry
                local function Valid()
                    if not running or revision ~= generation or I.Rules(false) ~= rules
                        or rules[uid] ~= rule or not Eligible(rule, "exboss")
                        or not pending[id] or pending[id][uid] ~= entry then return false end
                    local current = TimerAt(scheduler, id)
                    return Table(current) and current == timer and Plain(current.castTime) and current.castTime == at
                        and Plain(current.source) and current.source == "trash"
                end
                local delay = at - GetTime() - rule.trigger.timeleft
                if at > GetTime() then
                    local tracked = ns.TrackReminderTimer("exboss", math.max(0.01, delay), function()
                        entry.handle = nil
                        if Valid() then
                            entry.fired = true
                            delivered[timer] = delivered[timer] or setmetatable({}, { __mode = "k" })
                            delivered[timer][rule] = { at = at, anchor = anchor }
                            Display(rule)
                        end
                    end, nil, Valid)
                    entry.handle = tracked and tracked.handle
                end
            end
        end
    end
    ns.PruneCustomReminderTimers()
end
local function Connect()
    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if not scheduler or type(scheduler.GetActiveTimers) ~= "function"
        or type(scheduler.RegisterTrashLocalTimer) ~= "function"
        or type(scheduler._RemoveActiveTimerByID) ~= "function" then
        I.trashStatus = "Trash timer engine unavailable. Enable a compatible timer engine to use predictions."
        return
    end
    if hooked and hooked ~= scheduler then
        I.trashStatus = "The trash timer engine changed; reload before using trash alerts."
        return
    end
    if not hooked then
        -- Compatibility adapter for the inspected Exboss scheduler. Post-hooks only;
        -- no method replacement, foreign state mutation, inferred spell IDs or polling.
        hooked = scheduler
        hooksecurefunc(scheduler, "RegisterTrashLocalTimer", function(self, runtime, _, spell)
            if not running or not Table(runtime) or not Table(spell)
                or not Number(spell.spellID, 1, 100000000) then return end
            local ids = runtime.localTimerIDsBySpellID
            if Table(ids) then I.ObserveTimer(self, ids[spell.spellID]) end
        end)
        -- Fixed combat timelines advance in place without RegisterTrashLocalTimer.
        if type(scheduler._AdvanceTrashFixedCombatTimeline) == "function" then
            hooksecurefunc(scheduler, "_AdvanceTrashFixedCombatTimeline", function(self, timer)
                if running and Table(timer) and Number(timer.id, 1, 1000000000) then
                    I.ObserveTimer(self, timer.id)
                end
            end)
        end
        hooksecurefunc(scheduler, "_RemoveActiveTimerByID", function(_, id)
            if not running or not Number(id, 1, 1000000000) then return end
            ClearPending(id)
            ns.PruneCustomReminderTimers()
        end)
    end
    I.trashStatus = "Trash timers connected. Alerts predict readiness, not a confirmed cast."
    local all = scheduler:GetActiveTimers()
    if Table(all) then for id in pairs(all) do I.ObserveTimer(scheduler, id) end end
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
local function StoneformReady()
    if not (C_SpellBook and C_SpellBook.IsSpellKnown and C_Spell
        and C_Spell.GetSpellCooldown and C_Spell.IsSpellUsable and UnitIsDeadOrGhost) then return false, "API unavailable" end
    local known, dead = C_SpellBook.IsSpellKnown(STONEFORM), UnitIsDeadOrGhost("player")
    if not Plain(known) or known ~= true then return false, "spell not known or unreadable" end
    if not Plain(dead) or dead ~= false then return false, "dead or unreadable player state" end
    local cd = C_Spell.GetSpellCooldown(STONEFORM)
    if not Table(cd) or not Plain(cd.isActive) or not Plain(cd.isEnabled) then return false, "cooldown unreadable" end
    if cd.isActive ~= false or cd.isEnabled ~= true then return false, "cooldown active or on hold" end
    local usable = C_Spell.IsSpellUsable(STONEFORM)
    if not Plain(usable) then return false, "usability unreadable" end
    if usable ~= true then return false, "spell unusable" end
    return true, "ready"
end
local function UpdateStoneform()
    if not stoneformOwned then return end
    local ready, reason = false, "configuration pending or disabled"
    if stoneformEnabled then ready, reason = StoneformReady() end
    local muted = not ready
    I.stoneformStatus = "Stoneform: " .. reason
    if muted ~= stoneformMuted then
        local path = ns.UI.SoundPathFor(STONEFORM_SOUND)
        if muted then MuteSoundFile(path) else UnmuteSoundFile(path) end
        stoneformMuted = muted
    end
    if I.OnStatusChanged then I.OnStatusChanged() end
end
local function SetStoneformEnabled(enabled)
    enabled = enabled and MuteSoundFile ~= nil and UnmuteSoundFile ~= nil or false
    if enabled ~= stoneformEnabled then
        stoneformEnabled = enabled
        for _, event in ipairs(stoneformEvents) do
            if enabled then events:RegisterEvent(event) else events:UnregisterEvent(event) end
        end
    end
    UpdateStoneform()
end
local function RefreshSounds()
    -- Pending edits must not leave a stale profile's racial callout audible.
    SetStoneformEnabled(false)
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound
        and Enum and Enum.UnitAuraSoundTrigger) then
        I.auraStatus = "Aura sounds require the Retail AddAuraSound API."
        return
    end
    local wanted, missing, ruleCount = {}, false, 0
    for _, rule in pairs(I.Rules(false) or {}) do
        ruleCount = ruleCount + 1
        if ruleCount > MAX_RULES then wanted = {}; missing = true; break end
        if Eligible(rule, "auraSound") then
            local t, path = rule.trigger, ns.UI.SoundPathFor(rule.display.sound)
            local gated = rule.display.sound == STONEFORM_SOUND
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
        SetStoneformEnabled(any and matched)
        I.auraStatus = "Sound changes pending until combat and encounter restrictions end. Existing registrations remain active."
        return
    end
    for key, id in pairs(sounds) do
        if not wanted[key] then
            C_UnitAuras.RemoveAuraSound(id); sounds[key] = nil; gatedSounds[key] = nil
        end
    end
    local count, failed, gatedCount = 0, false, 0
    for key, request in pairs(wanted) do
        if request.gated and not stoneformOwned then
            stoneformOwned = true
            UpdateStoneform()
        end
        if not sounds[key] then sounds[key] = C_UnitAuras.AddAuraSound(request.trigger, request.info) end
        if sounds[key] then count = count + 1 else failed = true end
        if sounds[key] and request.gated then
            gatedCount = gatedCount + 1; gatedSounds[key] = true
        end
    end
    SetStoneformEnabled(gatedCount > 0)
    if gatedCount == 0 and stoneformOwned then
        UnmuteSoundFile(ns.UI.SoundPathFor(STONEFORM_SOUND))
        stoneformOwned, stoneformMuted = nil, nil
        I.stoneformStatus = nil
    end
    I.auraStatus = missing and "Some rules could not load: check selected sound files and the 32-rule limit."
        or failed and "Some aura sounds were not accepted by the client."
        or (count .. " aura sound registrations active. Changes apply outside combat.")
end
function I.Refresh()
    revision = revision + 1
    running = false
    ClearAll()
    if ns.HideIntegrationReminders then ns.HideIntegrationReminders() end
    local n = 0
    for _, rule in pairs(I.Rules(false) or {}) do
        n = n + 1
        if n > MAX_RULES then
            running = false
            I.trashStatus = "Too many rules; maximum 32 per spec."
            break
        end
        if Eligible(rule, "exboss") then running = true end
    end
    if running then Connect()
    elseif n <= MAX_RULES then I.trashStatus = "No enabled trash rules for this instance and spec." end
    RefreshSounds()
    if I.OnStatusChanged then I.OnStatusChanged() end
end
function I.Save(uid, rule)
    if not I.ValidRule(rule) then return false, "Check IDs, timing and sound. Stoneform voice requires Unit: Me." end
    local rules = I.Rules(true)
    if not uid then
        local count = 0
        for _ in pairs(rules) do count = count + 1 end
        if count >= MAX_RULES then return false, "Maximum 32 rules per spec." end
        local index = 1
        while rules["i" .. index] do index = index + 1 end
        uid = "i" .. index
    end
    rules[uid] = rule
    I.Refresh()
    return true, uid
end
events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name, state)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if (name ~= Enum.AddOnRestrictionType.Combat and name ~= Enum.AddOnRestrictionType.Encounter)
            or state ~= Enum.AddOnRestrictionState.Inactive then return end
    end
    for _, gateEvent in ipairs(stoneformEvents) do
        if event == gateEvent then UpdateStoneform(); return end
    end
    if event == "ADDON_LOADED" and name ~= "EXBoss" and name ~= "NaowhSmartReminders" then return end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and name ~= "player" then return end
    I.Refresh()
end)
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_END", "PLAYER_SPECIALIZATION_CHANGED", "ADDON_LOADED" }) do events:RegisterEvent(event) end
if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState then
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
end
