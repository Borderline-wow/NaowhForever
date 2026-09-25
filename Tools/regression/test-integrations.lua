local root = arg[1] or "."
local function Fixture()
    local e = { now = 0, map = 1877, kind = "party", spec = 250, timers = {}, shown = {}, added = {}, removed = {}, hooks = {},
        registered = {}, muteCalls = {}, mutedBy = {}, known = true, dead = false, usable = true,
        cooldown = { isActive = false, isEnabled = true }, restrictions = {} }
    local db = { enabled = true, integrationRules = { ["250"] = {} } }
    local ns = { UI = {}, trackedReminderTimers = {} }
    ns.DB = function() return db end
    ns.IsReminderEnabled = function(r) return r.enabled ~= false and not (e.healerOff and r.healerReminder) end
    ns.DisplayRaidReminder = function(r) e.shown[#e.shown + 1] = r end
    ns.HideIntegrationReminders = function() e.hidden = true end
    ns.ResolveReminderSpell = function() return e.picked end
    ns.InEncounter = function() return e.encounter end
    ns.PlayReminderSound = function(d) e.previewSound = true; e.previewKey = d.sound end
    ns.UI.SoundPathFor = function(key)
        if key == "voice:stoneform-ready" then return "stoneform-ready.ogg" end
        if key == "voice:shadowmeld-ready" then return "shadowmeld-ready.ogg" end
        return key == "test" and "Interface/AddOns/Test/test.ogg"
    end
    local env = setmetatable({ NaowhForever = ns, Enum = { UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 } },
        GetTime = function() return e.now end,
        C_SpecializationInfo = { GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return e.spec end },
        GetInstanceInfo = function() return "Dungeon", e.kind, 8, "", 5, 0, false, e.map end,
        InCombatLockdown = function() return e.combat end,
        C_Spell = { GetSpellInfo = function() return { name = "Anti-Magic Shell" } end,
            -- Per spell where a case says so, falling back to the shared answer.
            GetSpellCooldown = function(id)
                if e.cooldowns and e.cooldowns[id] ~= nil then return e.cooldowns[id] end
                return e.cooldown
            end,
            IsSpellUsable = function(id)
                if e.usables and e.usables[id] ~= nil then return e.usables[id] end
                return e.usable
            end },
        C_SpellBook = { IsSpellKnown = function(id)
            if e.knowns and e.knowns[id] ~= nil then return e.knowns[id] end
            return e.known
        end },
        UnitIsDeadOrGhost = function() return e.dead end,
        MuteSoundFile = function(path)
            e.muted = true; e.mutedBy[path] = true; e.muteCalls[#e.muteCalls + 1] = path
        end,
        UnmuteSoundFile = function(path)
            e.muted = false; e.mutedBy[path] = false; e.muteCalls[#e.muteCalls + 1] = path
        end,
        C_RestrictedActions = { GetAddOnRestrictionState = function(kind) return e.restrictions[kind] or 0 end },
        CreateFrame = function() return { SetScript = function(_, _, f) e.event = f end,
            RegisterEvent = function(_, event) e.registered[event] = true end,
            UnregisterEvent = function(_, event) e.registered[event] = nil end } end,
        issecretvalue = function(v) return v == e.secret end,
        canaccesstable = function(v) return v ~= e.forbidden end,
        C_UnitAuras = { AddAuraSound = function(trigger, info)
            assert(not e.combat and not e.encounter and not e.restrictions[0] and not e.restrictions[1])
            e.added[#e.added + 1] = { trigger = trigger, info = info }; return #e.added
        end, RemoveAuraSound = function(id)
            assert(not e.combat and not e.encounter); e.removed[#e.removed + 1] = id
        end },
    }, { __index = _G })
    env._G = env
    env.Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, Map = 4 }
    env.Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }
    e.secret, e.forbidden = {}, {}
    local chunk = assert(loadfile(root .. "/NaowhForever_Integrations.lua")); setfenv(chunk, env); chunk()
    e.I, e.ns, e.env, e.db = ns.Integrations, ns, env, db
    function e:rule(kind)
        return { name = "Test", enabled = true, trigger = { type = kind or "exboss", spellID = 123,
            mapID = 1877, timeleft = 5, target = "player", auraEvent = "Added" },
            display = { type = "icon", text = "Defensive", dur = 3, sound = "test" } }
    end
    return e
end
local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end
Case("invalid edited aura IDs are rejected without replacing saved rule", function()
    local e = Fixture(); local r = e:rule("auraSound")
    local ok, uid = e.I.Save(nil, r); assert(ok)
    for _, field in ipairs({ "spellID", "mapID" }) do
        local edited = e:rule("auraSound"); edited.trigger[field] = nil
        assert(not e.I.Save(uid, edited))
        assert(e.I.Rules(false)[uid] == r)
    end
end)

Case("aura registration deduplicates and supports each trigger and party unit", function()
    local e = Fixture(); local r = e:rule("auraSound")
    e.I.Save(nil, r); e.I.Refresh(); assert(#e.added == 1 and e.added[1].trigger == 0)
    e.I.Save(nil, r); assert(#e.added == 1)
    local other = e:rule("auraSound"); other.trigger.auraEvent = "Removed"; other.trigger.target = "party"
    e.I.Save(nil, other); assert(#e.added == 5 and e.added[2].trigger == 2)
    other = e:rule("auraSound"); other.trigger.auraEvent = "ApplicationsIncreased"
    e.I.Save(nil, other); assert(#e.added == 6 and e.added[6].trigger == 1)
end)
Case("aura changes defer through combat then remove disabled rules", function()
    local e = Fixture(); local r = e:rule("auraSound"); r.healerReminder = true
    e.I.Save(nil, r); e.combat = true; e.healerOff = true; e.I.Refresh()
    assert(#e.removed == 0 and e.I.auraStatus:find("pending"))
    e.combat = false; e.I.Refresh(); assert(#e.removed == 1)
end)
Case("bundled voices resolve and register without SharedMedia", function()
    local e = Fixture()
    local file = assert(io.open(root .. "/NaowhForever_Widgets.lua", "rb"))
    local source = file:read("*a"); file:close()
    local start = assert(source:find("local bundledVoices =", 1, true))
    local chunk = assert(loadstring("local ns = ...; local UI = ns.UI; " .. source:sub(start)))
    setfenv(chunk, e.env); chunk(e.ns)
    local paths, names, order = e.ns.UI.BuildAlertSoundTables()
    assert(#order == 4 and order[1] == "none")
    assert(e.ns.UI.SoundPathFor("none") == nil and e.ns.UI.SoundPathFor("missing") == nil)
    for index = 2, #order do
        local key = order[index]
        assert(names[key]:find("Voice:", 1, true))
        assert(e.ns.UI.SoundPathFor(key) == paths[key])
        local relative = assert(paths[key]:match("NaowhForever\\(.+)$")):gsub("\\", "/")
        local sound = assert(io.open(root .. "/" .. relative, "rb"))
        assert(sound:read(4) == "OggS"); sound:close()
        local r = e:rule("auraSound"); r.display.sound = key
        assert(e.I.Save(nil, r))
        assert(e.added[index - 1].info.soundFileName == paths[key])
    end
end)
Case("aura profile and instance changes clear registrations", function()
    local e = Fixture(); e.I.Save(nil, e:rule("auraSound"))
    e.kind = "none"; e.I.Refresh(); assert(#e.removed == 1)
    e.kind = "party"; e.I.Refresh(); assert(#e.added == 2)
    e.db.integrationRules = {}; e.I.Refresh(); assert(#e.removed == 2)
end)
Case("malformed rules are rejected, and a spec may hold as many good ones as it likes", function()
    local e = Fixture(); local r = e:rule(); r.trigger.spellID = 0/0; assert(not e.I.Save(nil,r))
    r=e:rule("auraSound"); r.display.sound="none"; assert(not e.I.Save(nil,r))
    -- Well past the cap this addon used to impose on itself. The client decides what it
    -- will register, and says so; the addon does not decide for it in advance.
    for i = 1, 120 do assert(e.I.Save(nil, e:rule()), "rule " .. i) end
    local n = 0
    for _ in pairs(e.I.Rules(false)) do n = n + 1 end
    assert(n == 120)
end)
Case("the retired cast switches are still validated, so old rules still load", function()
    local e = Fixture()
    local r = e:rule(); r.display.castRepeat = "no"
    assert(not e.I.Save(nil, r))
    r = e:rule(); r.display.castAudio = 1
    assert(not e.I.Save(nil, r))
    r = e:rule(); r.display.castRepeat = false; r.display.castAudio = true
    assert(e.I.Save(nil, r))
end)
Case("shared packs validate integration rules, IDs and size before import", function()
    local e=Fixture()
    local f=assert(io.open(root.."/NaowhForever_Packs.lua","rb"))
    local source=f:read("*a"); f:close()
    local first=assert(source:find("local SECTIONS =",1,true))
    local last=assert(source:find("-- LibSerialize's Deserialize",first,true))
    local chunk=assert(loadstring(source:sub(first,last-1).."\nreturn ValidData"))
    e.env.ns=e.ns; setfenv(chunk,e.env); local valid=chunk()
    local data={ integrationRules={ ["250"]={ i1=e:rule(), i2=e:rule("auraSound") } } }
    assert(valid(data))
    data.integrationRules["250"].i2.trigger.mapID="1877"; assert(not valid(data))
    data.integrationRules["250"].i2.trigger.mapID=1877
    data.integrationRules["250"][1]=e:rule(); assert(not valid(data))
    data.integrationRules["250"][1]=nil
    -- A pack may carry far more than a spec used to be allowed, but not an unbounded table.
    for i=3,120 do data.integrationRules["250"]["i"..i]=e:rule() end
    assert(valid(data), "a large but sane pack is still a valid pack")
    for i=121,502 do data.integrationRules["250"]["i"..i]=e:rule() end
    assert(not valid(data), "past the sanity bound it is refused")
end)
Case("Stoneform follows cooldown events in combat without re-registering", function()
    local e = Fixture(); local r = e:rule("auraSound"); r.display.sound = "voice:stoneform-ready"
    assert(e.I.Save(nil, r)); assert(e.muted == false and e.registered.SPELL_UPDATE_COOLDOWN)
    e.combat = true; e.cooldown.isActive = true
    e.event(nil, "SPELL_UPDATE_COOLDOWN", 20594); assert(e.muted == true)
    local calls = #e.muteCalls
    e.event(nil, "SPELL_UPDATE_COOLDOWN", 123); assert(#e.muteCalls == calls)
    e.cooldown.isActive = false; e.event(nil, "SPELL_UPDATE_COOLDOWN", 20594)
    assert(e.muted == false and #e.added == 1 and #e.removed == 0)
    e.I.Refresh(); assert(e.muted == false and #e.added == 1)
end)
Case("Stoneform fails silent for unknown, dead, unusable and secret readiness", function()
    for _, what in ipairs({ "unknown", "dead", "unusable", "secret", "missing", "held" }) do
        local e = Fixture(); local r = e:rule("auraSound"); r.display.sound = "voice:stoneform-ready"
        e.I.Save(nil, r)
        if what == "unknown" then e.known = false
        elseif what == "dead" then e.dead = true
        elseif what == "unusable" then e.usable = false
        elseif what == "secret" then e.usable = e.secret
        elseif what == "missing" then e.cooldown = nil
        else e.cooldown.isEnabled = false end
        e.event(nil, "SPELL_UPDATE_USABLE"); assert(e.muted == true, what)
    end
end)
Case("Stoneform preview never unmutes the registered file", function()
    local e = Fixture(); local r = e:rule("auraSound"); r.display.sound = "voice:stoneform-ready"
    e.cooldown.isActive = true; e.I.Save(nil, r)
    local calls = #e.muteCalls; e.I.Preview(r)
    assert(e.previewKey == "voice:stoneform-preview" and e.muted and #e.muteCalls == calls)
end)
Case("Stoneform disable in combat silences stale rules until cleanup", function()
    local e = Fixture(); local r = e:rule("auraSound"); r.display.sound = "voice:stoneform-ready"
    e.I.Save(nil, r); e.combat = true; e.db.enabled = false; e.I.Refresh()
    assert(e.muted and not e.registered.SPELL_UPDATE_COOLDOWN and #e.removed == 0)
    e.combat = false; e.I.Refresh()
    assert(e.muted == false and #e.removed == 1)
end)
Case("Stoneform rejects party rules and remains idle for ordinary sounds", function()
    local e = Fixture(); e.I.Save(nil, e:rule("auraSound"))
    assert(#e.muteCalls == 0 and not e.registered.SPELL_UPDATE_COOLDOWN)
    local r = e:rule("auraSound"); r.display.sound = "voice:stoneform-ready"; r.trigger.target = "party"
    assert(not e.I.Save(nil, r))
end)
Case("Shadowmeld gates on its own racial, and the two are independent", function()
    local e = Fixture()
    local stone = e:rule("auraSound"); stone.display.sound = "voice:stoneform-ready"
    local meld = e:rule("auraSound"); meld.display.sound = "voice:shadowmeld-ready"
    meld.trigger.spellID = 456
    assert(e.I.Save(nil, stone)); assert(e.I.Save(nil, meld))
    assert(#e.added == 2 and e.registered.SPELL_UPDATE_COOLDOWN)

    local function MutedFor(file)
        local state
        for _, path in ipairs(e.muteCalls) do
            if path == file then state = e.mutedBy[path] end
        end
        return state
    end
    -- Shadowmeld on cooldown, Stoneform still up: only one of the two goes quiet.
    e.cooldowns = { [58984] = { isActive = true, isEnabled = true } }
    e.event(nil, "SPELL_UPDATE_COOLDOWN")
    assert(MutedFor("shadowmeld-ready.ogg") == true, "Shadowmeld should be muted")
    assert(MutedFor("stoneform-ready.ogg") == false, "Stoneform should still be audible")
    -- And back again when it comes off cooldown.
    e.cooldowns = nil
    e.event(nil, "SPELL_UPDATE_COOLDOWN")
    assert(MutedFor("shadowmeld-ready.ogg") == false)
end)
Case("Shadowmeld preview uses its own file and rejects a party rule", function()
    local e = Fixture()
    local r = e:rule("auraSound"); r.display.sound = "voice:shadowmeld-ready"
    e.cooldown.isActive = true
    assert(e.I.Save(nil, r))
    local calls = #e.muteCalls
    e.I.Preview(r)
    assert(e.previewKey == "voice:shadowmeld-preview" and #e.muteCalls == calls,
        "the preview must not touch the registered file")
    local party = e:rule("auraSound")
    party.display.sound = "voice:shadowmeld-ready"; party.trigger.target = "party"
    assert(not e.I.Save(nil, party), "a racial you cast on yourself cannot answer for a party debuff")
end)
Case("a racial with nothing left registered hands its file back unmuted", function()
    local e = Fixture()
    local r = e:rule("auraSound"); r.display.sound = "voice:shadowmeld-ready"
    e.cooldown.isActive = true
    e.I.Save(nil, r)
    assert(e.mutedBy["shadowmeld-ready.ogg"] == true)
    e.db.integrationRules = {}
    e.I.Refresh()
    assert(e.mutedBy["shadowmeld-ready.ogg"] == false, "it must not stay silenced for everything else")
end)
Case("forced restrictions defer registration without combat lockdown", function()
    for _, kind in ipairs({ 0, 1 }) do
        local e = Fixture(); e.restrictions[kind] = 2
        e.I.Save(nil, e:rule("auraSound")); assert(#e.added == 0 and e.I.auraStatus:find("pending"))
        e.restrictions[kind] = nil
        e.event(nil, "ADDON_RESTRICTION_STATE_CHANGED", kind, 0); assert(#e.added == 1)
    end
end)
-- Copy From Spec on the Trash & Debuff page. Rules are stored per spec, so a second spec
-- starts empty and the whole dungeon has to be rebuilt by hand without this.
local function CopyFixture()
    local e = Fixture()
    e.ns.SpecName = function(k) return "Spec " .. tostring(k) end
    e.db.integrationRules["581"] = {}
    return e
end
local function RuleCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
Case("rules copy across as independent entries on fresh uids", function()
    local e = CopyFixture()
    local src = e:rule()
    src.name = "Knock"
    e.db.integrationRules["581"] = { i1 = src }
    e.db.integrationRules["250"] = { i1 = e:rule("auraSound") }
    local copied, skipped = e.I.CopyRulesFromSpec("581", "exboss")
    assert(copied == 1 and skipped == 0)
    local mine = e.db.integrationRules["250"]
    assert(RuleCount(mine) == 2 and mine.i1.trigger.type == "auraSound")
    local landed
    for _, r in pairs(mine) do if r.name == "Knock" then landed = r end end
    assert(landed and landed ~= src and landed.trigger ~= src.trigger and landed.display ~= src.display)
    assert(landed.trigger.spellID == 123 and landed.display.text == "Defensive")
    assert(RuleCount(e.db.integrationRules["581"]) == 1, "the source spec keeps its own")
end)
Case("a rule this spec already has for that ability is left alone", function()
    local e = CopyFixture()
    e.db.integrationRules["581"] = { i1 = e:rule() }
    e.db.integrationRules["250"] = { i1 = e:rule() }
    local copied, skipped = e.I.CopyRulesFromSpec("581", "exboss")
    assert(copied == 0 and skipped == 1)
    assert(RuleCount(e.db.integrationRules["250"]) == 1)
end)
Case("same spell on a different map or aura event is its own rule", function()
    local e = CopyFixture()
    local other = e:rule("auraSound")
    other.trigger.auraEvent = "Removed"
    local elsewhere = e:rule()
    elsewhere.trigger.mapID = 2000
    e.db.integrationRules["581"] = { i1 = other, i2 = elsewhere }
    e.db.integrationRules["250"] = { i1 = e:rule("auraSound"), i2 = e:rule() }
    -- One of each kind, so each half is copied by the page that owns it.
    local copied, skipped = e.I.CopyRulesFromSpec("581", "auraSound")
    assert(copied == 1 and skipped == 0, "a different aura event is its own rule")
    copied, skipped = e.I.CopyRulesFromSpec("581", "exboss")
    assert(copied == 1 and skipped == 0, "and so is a different map")
    assert(RuleCount(e.db.integrationRules["250"]) == 4)
end)
Case("each page copies only its own kind of rule", function()
    local e = CopyFixture()
    local trash = e:rule()
    local debuff = e:rule("auraSound")
    debuff.trigger.spellID = 456
    e.db.integrationRules["581"] = { i1 = trash, i2 = debuff }

    -- The trash page's button takes trash rules and leaves the debuff alert behind.
    local copied = e.I.CopyRulesFromSpec("581", "exboss")
    assert(copied == 1)
    local mine = e.db.integrationRules["250"]
    assert(RuleCount(mine) == 1)
    for _, r in pairs(mine) do assert(r.trigger.type == "exboss") end

    -- The debuff page's button takes the other one.
    copied = e.I.CopyRulesFromSpec("581", "auraSound")
    assert(copied == 1 and RuleCount(mine) == 2)
    local kinds = {}
    for _, r in pairs(mine) do kinds[r.trigger.type] = true end
    assert(kinds.exboss and kinds.auraSound)
end)
Case("the picker counts only the kind the page asked about", function()
    local e = CopyFixture()
    local debuff = e:rule("auraSound")
    debuff.trigger.spellID = 456
    e.db.integrationRules["581"] = { i1 = e:rule(), i2 = e:rule(), i3 = debuff }
    local trashSpecs = e.I.SpecsWithRules("exboss")
    assert(#trashSpecs == 1 and trashSpecs[1].total == 2)
    local debuffSpecs = e.I.SpecsWithRules("auraSound")
    assert(#debuffSpecs == 1 and debuffSpecs[1].total == 1)
end)
Case("a spec with only the other kind is not offered at all", function()
    local e = CopyFixture()
    e.db.integrationRules["581"] = { i1 = e:rule("auraSound") }
    assert(#e.I.SpecsWithRules("exboss") == 0, "nothing to copy means nothing to pick")
    assert(#e.I.SpecsWithRules("auraSound") == 1)
end)
Case("two callouts on one ability at different warning times both come across", function()
    local e = CopyFixture()
    local early, late = e:rule(), e:rule()
    early.trigger.timeleft, late.trigger.timeleft = 8, 2
    e.db.integrationRules["581"] = { i1 = early, i2 = late }
    local copied, skipped = e.I.CopyRulesFromSpec("581", "exboss")
    assert(copied == 2 and skipped == 0)
    assert(RuleCount(e.db.integrationRules["250"]) == 2)
    -- And a repeat press still recognises both as already here.
    local again, skippedAgain = e.I.CopyRulesFromSpec("581", "exboss")
    assert(again == 0 and skippedAgain == 2)
end)
Case("a copy is no longer cut short by a cap", function()
    local e = CopyFixture()
    local src, mine = {}, {}
    for i = 1, 5 do
        local r = e:rule(); r.trigger.spellID = 1000 + i
        src["i" .. i] = r
    end
    for i = 1, 30 do
        local r = e:rule(); r.trigger.spellID = 2000 + i
        mine["i" .. i] = r
    end
    e.db.integrationRules["581"], e.db.integrationRules["250"] = src, mine
    local copied, skipped = e.I.CopyRulesFromSpec("581", "exboss")
    assert(copied == 5 and skipped == 0, "every source rule comes across")
    assert(RuleCount(e.db.integrationRules["250"]) == 35)
end)
Case("an invalid source rule is passed over", function()
    local e = CopyFixture()
    local bad = e:rule(); bad.display.dur = 99
    local good = e:rule(); good.trigger.spellID = 999
    e.db.integrationRules["581"] = { i1 = bad, i2 = good }
    local copied = e.I.CopyRulesFromSpec("581", "exboss")
    assert(copied == 1 and RuleCount(e.db.integrationRules["250"]) == 1)
end)
Case("the picker lists other specs with counts and never this one", function()
    local e = CopyFixture()
    e.db.integrationRules["250"] = { i1 = e:rule() }
    e.db.integrationRules["581"] = { i1 = e:rule(), i2 = e:rule("auraSound") }
    e.db.integrationRules["104"] = {}
    -- Two rules saved there, but only one of the kind this picker was opened for.
    local specs = e.I.SpecsWithRules("exboss")
    assert(#specs == 1 and specs[1].key == "581" and specs[1].total == 1)
end)
Case("copying from a spec with nothing saved changes nothing", function()
    local e = CopyFixture()
    e.db.integrationRules["250"] = { i1 = e:rule() }
    local copied, skipped = e.I.CopyRulesFromSpec("999", "exboss")
    assert(copied == 0 and skipped == 0)
    assert(RuleCount(e.db.integrationRules["250"]) == 1)
end)

print(count .. " integration regressions passed")
