-- The onboarding against thousands of random players, on the real engine, module list, presets and
-- Setups.lua (Tools/regression/setup_world.lua): random profiles, skins and module flips, module
-- addons enabled, loaded or not, for every character or for one. Each run checks the picks and the
-- summary against its own reading of the rules, applies, sometimes reloads, and sometimes restores:
-- every applied state is what the summary showed, Restore puts everything back, dependencies always
-- hold, and in one character's mode every C_AddOns call names its GUID (otherwise none does).
-- From the repo root: lua5.1 Tools/regression/test-setup-fuzz.lua [seed] [runs]
local SEED, RUNS = tonumber(arg[1]) or 20261009, tonumber(arg[2]) or 3000
local World = dofile("Tools/regression/setup_world.lua")
local checks, run, where = 0, 0, ""
local function check(label, ok)
    if not ok then error(("run %d (seed %d)%s: %s"):format(run, SEED, where, label), 2) end
    checks = checks + 1
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and Copy(v) or v end
    return out
end

local function Chance(p) return math.random() < p end

local MODULES = World().MODULES
local NEEDS = {}
for _, mod in ipairs(MODULES) do NEEDS[mod.addon] = mod.needs or {} end

local function Needs(addon, out)
    out = out or {}
    for _, need in ipairs(NEEDS[addon]) do
        if not out[need] then
            out[need] = true
            Needs(need, out)
        end
    end
    return out
end

local function Settled(w, on)
    local changed = true
    while changed do
        changed = false
        for id, item in pairs(w.ns.Setup.ITEMS) do
            if on[id] then
                for need in pairs(Needs(item.addon)) do
                    for other, it in pairs(w.ns.Setup.ITEMS) do
                        if it.addon == need and not on[other] then on[id], changed = false, true end
                    end
                end
            end
        end
    end
    return on
end

local function Listed(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

local function PresetWants(w, key)
    local preset, on = w.ns.PRESETS[key], {}
    for id, item in pairs(w.ns.Setup.ITEMS) do
        if preset.modules then
            on[id] = Listed(preset.modules, item.addon)
        else
            local values = preset.profile[item.db]
            local v = values and values[item.key]
            if v == nil then v = w.ns.FEATURES[item.db][item.key] end
            on[id] = v == true
        end
    end
    return Settled(w, on)
end

local function NowOn(w)
    local on = {}
    for id in pairs(w.ns.Setup.ITEMS) do on[id] = w.On(id) == true end
    return on
end

local function Random()
    local enabled, others, loaded = {}, {}, {}
    for _, mod in ipairs(MODULES) do
        enabled[mod.addon] = Chance(0.7)
        others[mod.addon] = Chance(0.7)
        loaded[mod.addon] = enabled[mod.addon] and Chance(0.85) or Chance(0.05)
    end
    local character = Chance(0.5)
    local root = { qol = { characterPanel = Chance(0.6), inspectPanel = Chance(0.6),
        preset = ({ "minimalist", "recommended", "custom" })[math.random(3)], questRewards = { [7] = 9 } },
        tankReminder = { leadTime = 3 } }
    local w = World({ enabled = enabled, others = character and others or enabled, loaded = loaded, root = root,
        character = character, account = { welcomeSeen = Chance(0.5) or nil, skin = Chance(0.3) and "classic" or nil } })
    for _, item in pairs(w.ns.Setup.ITEMS) do
        if Chance(0.4) then
            if type(w.root[item.db]) ~= "table" then w.root[item.db] = {} end
            w.root[item.db][item.key] = Chance(0.5)
        end
    end
    return w
end

local function PicksHold(w, modules)
    for id, item in pairs(w.ns.Setup.ITEMS) do
        if modules[id] then
            for need in pairs(Needs(item.addon)) do
                for other, it in pairs(w.ns.Setup.ITEMS) do
                    if it.addon == need and not modules[other] then return false, id .. " without " .. other end
                end
            end
        end
    end
    return true
end

local function NamesOf(w, ids)
    local set = {}
    for _, m in ipairs(w.ns.Setup.Modules()) do
        if ids[m.id] then set[m.name] = true end
    end
    return set
end

local function SetOf(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

local function Calls(w, from)
    for i = from, #w.calls do
        local c = w.calls[i]
        if w.character and not w.ForMe(c) then return false, c.name .. " " .. c.addon .. " without the GUID" end
        if not w.character and not w.ForEveryone(c) then return false, c.name .. " " .. c.addon .. " named someone" end
    end
    return true
end

math.randomseed(SEED)
local applied, reloads, restores, characterRuns, flips = 0, 0, 0, 0, 0
for i = 1, RUNS do
    run = i
    local w = Random()
    local Setup = w.ns.Setup
    if w.character then characterRuns = characterRuns + 1 end
    local picks = Setup.Fresh()
    local keys = { Setup.KEEP }
    for _, key in ipairs(w.ns.PRESETS.order) do keys[#keys + 1] = key end
    Setup.PickProfile(picks, keys[math.random(#keys)])
    if Chance(0.5) then picks.skin = Chance(0.5) and "classic" or "" end
    local items = {}
    for id in pairs(Setup.ITEMS) do items[#items + 1] = id end
    table.sort(items)
    for _ = 1, math.random(0, 6) do
        local id = items[math.random(#items)]
        Setup.Toggle(picks, id, not picks.modules[id])
        flips = flips + 1
        local ok, why = PicksHold(w, picks.modules)
        check("a flip keeps every module with what it needs: " .. tostring(why), ok)
    end
    where = (" profile=%s skin=%q%s"):format(picks.profile, picks.skin, w.character and " for one character" or "")
    local preset = picks.profile ~= Setup.KEEP
    local before = Settled(w, NowOn(w))
    local base = preset and PresetWants(w, picks.profile) or before
    local ok, why = PicksHold(w, picks.modules)
    check("the picks hold every dependency: " .. tostring(why), ok)
    local plan = Setup.Plan(picks)
    local wantOn, wantOff = {}, {}
    for _, id in ipairs(items) do
        if picks.modules[id] and not before[id] then wantOn[id] = true end
        if not picks.modules[id] and before[id] then wantOff[id] = true end
    end
    check("the summary lists exactly what turns on", Same(SetOf(plan.on), NamesOf(w, wantOn)))
    check("and exactly what turns off", Same(SetOf(plan.off), NamesOf(w, wantOff)))
    check("it names the profile, or keeps yours", plan.profile == (preset and w.ns.PRESETS[picks.profile].name or nil))
    local skinNow = w.account.skin == "classic" and "classic" or ""
    check("it says whether the skin changes", plan.skinChanged == (picks.skin ~= skinNow))
    local reload = preset or plan.skinChanged
    for _, id in ipairs(items) do
        local item = Setup.ITEMS[id]
        local loaded, enabled = w.loaded[item.addon], w.enabled[item.addon]
        if picks.modules[id] and not loaded then reload = true end
        if not picks.modules[id] and loaded and (preset and enabled or w.On(id)) then reload = true end
    end
    check("it knows whether a reload is needed", plan.reload == (reload == true))
    check("it changes something exactly when the summary shows something", plan.changes
        == (preset or plan.skinChanged or #plan.on + #plan.off > 0))
    if plan.changes then
        applied = applied + 1
        local snap = { root = Copy(w.root), enabled = Copy(w.enabled), others = Copy(w.others), skin = w.account.skin }
        local from = #w.calls + 1
        local got = Setup.Apply(picks)
        check("Apply reloads exactly when the summary said", got == plan.reload)
        local okCalls, whyCalls = Calls(w, from)
        check("C_AddOns calls name this character exactly in its mode: " .. tostring(whyCalls), okCalls)
        if w.character then check("other characters' addons untouched", Same(w.others, snap.others)) end
        check("the skin is the one picked", (w.account.skin == "classic" and "classic" or "") == picks.skin)
        local custom = not Same(picks.modules, base)
        local marker = w.root.qol and w.root.qol.preset
        if custom then
            check("modules moved off the profile: marked as your own", marker == "custom")
        elseif preset then
            check("the profile as it came: its name", marker == picks.profile)
        else
            check("nothing moved: the name stays", marker == snap.root.qol.preset)
        end
        if got then reloads = reloads + 1; w.Reload() end
        for _, id in ipairs(items) do
            local item = Setup.ITEMS[id]
            check(id .. ": on exactly as picked", w.On(id) == picks.modules[id])
            if picks.modules[id] or preset then
                check(id .. ": its addon enabled exactly as picked", w.enabled[item.addon] == picks.modules[id])
            end
        end
        for _, id in ipairs(items) do
            if w.On(id) then
                for need in pairs(Needs(Setup.ITEMS[id].addon)) do
                    check(id .. " on with " .. need .. " enabled", w.enabled[need])
                end
            end
        end
        for _, panel in ipairs({ { "characterPanel", "characterPanelPicked" }, { "inspectPanel", "inspectPanelPicked" } }) do
            local want = picks.modules.bis and w.ns.QoLSettings.Get(panel[1]) == true
            check(panel[1] .. ": picked exactly when it is left on with the BiS List", (w.root.qol[panel[2]] == true) == want)
        end
        check("what you saved stays", w.root.qol.questRewards[7] == 9 and w.root.tankReminder.leadTime == 3)
        check("read again, your setup is what you picked", Same(Setup.ModuleDefaults(Setup.KEEP), picks.modules))
        if Chance(0.6) then
            restores = restores + 1
            check("it can be undone", Setup.CanRestore())
            from = #w.calls + 1
            check("undone", Setup.Restore())
            check("undone: every setting as it was", Same(w.root, snap.root))
            check("undone: every module addon as it was", Same(w.enabled, snap.enabled) and Same(w.others, snap.others))
            check("undone: the skin as it was", w.account.skin == snap.skin)
            okCalls, whyCalls = Calls(w, from)
            check("Restore names the character exactly in its mode: " .. tostring(whyCalls), okCalls)
            check("and is used up", not Setup.CanRestore())
        end
    else
        check("nothing to change: a fresh reading agrees", Same(Setup.ModuleDefaults(Setup.KEEP), picks.modules))
    end
    local okCalls, whyCalls = Calls(w, 1)
    check("every call this run in its mode: " .. tostring(whyCalls), okCalls)
end

print(("test-setup-fuzz: %d runs (seed %d, %d for one character), %d applied, %d flips, %d reloads, %d restores, %d checks passed")
    :format(RUNS, SEED, characterRuns, applied, flips, reloads, restores, checks))
