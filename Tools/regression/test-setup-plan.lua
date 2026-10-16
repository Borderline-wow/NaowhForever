-- The onboarding's engine (Core/Onboarding/Setup.lua) on the real module list, presets and Setups.lua:
-- each module's item, the defaults each step starts from, the dependencies, the summary's plan,
-- Apply, Restore, the character and inspect panel picks, and one character's own setup.
-- From the repo root: lua5.1 Tools/regression/test-setup-plan.lua
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local World = dofile("Tools/regression/setup_world.lua")
local MINIMALIST_ON = { qol = true, journal = true, bis = true }

local function All(value)
    local out = {}
    for _, mod in ipairs(World().MODULES) do out[mod.addon] = value end
    return out
end

local function Game(opts)
    opts = opts or {}
    opts.enabled = opts.enabled or All(true)
    opts.loaded = opts.loaded or All(true)
    return World(opts)
end

local function Names(list)
    return table.concat(list, ",")
end

local function Count(t)
    local n = 0
    for _, v in pairs(t) do if v then n = n + 1 end end
    return n
end

do
    local w = Game()
    local Setup, MODULES = w.ns.Setup, {}
    for _, mod in ipairs(w.MODULES) do if not mod.inQoL then MODULES[#MODULES + 1] = mod end end
    local byAddon, seen = {}, {}
    for id, item in pairs(Setup.ITEMS) do
        byAddon[item.addon] = id
        check(id .. ": its blurb is one short ASCII sentence", type(item.blurb) == "string" and #item.blurb <= 50
            and not item.blurb:find("[\128-\255]") and item.blurb:sub(-1) == "." and not item.blurb:sub(1, -2):find("[%.!?]"))
        check(id .. ": its switch is a feature switch", rawget(w.ns.FEATURES[item.db], item.key) ~= nil)
    end
    for _, mod in ipairs(MODULES) do
        local id = byAddon[mod.addon]
        check("every module in the options' list has its item: " .. mod.addon, id ~= nil)
        check(id .. ": the switch the module reads", Setup.ITEMS[id].key == (mod.enabledKey or "enabled"))
        local art = mod.navIcon and io.open("Core/Media/Navigation/" .. mod.navIcon .. ".tga", "rb")
        if art then art:close() end
        check(mod.addon .. ": an icon of its own, drawn", art ~= nil)
        seen[id] = true
    end
    check("and no item for a module that is not there", Count(seen) == Count(Setup.ITEMS))
    local list = Setup.Modules()
    check("the modules step lists every module, in the options' order", #list == #MODULES)
    for i, m in ipairs(list) do
        check(m.id .. ": in order, named as the options name it", m.addon == MODULES[i].addon
            and m.name == (MODULES[i].name == "QoL" and "Quality of Life" or MODULES[i].name))
    end
end

do
    local w = Game()
    local Setup = w.ns.Setup
    check("an account never set up starts on Minimalist", Setup.DefaultProfile() == "minimalist")
    w.account.welcomeSeen = true
    check("one that has seen the onboarding (or the old welcome) keeps its own", Setup.DefaultProfile() == Setup.KEEP)
    w.account.welcomeSeen, w.account.setupBefore = nil, {}
    check("and one with a backup from an earlier Apply", Setup.DefaultProfile() == Setup.KEEP)
    check("the skin starts as the one in use", Setup.Fresh().skin == "")
    w.account.skin = "forever"
    check("Forever in use: Forever", Setup.Fresh().skin == "forever")
    check("two skins to pick from", #Setup.SKINS == 2 and Setup.SKINS[2] == "forever")
    w.account.skin = "nonsense"
    check("anything else: Naowh", Setup.Fresh().skin == "")
end

do
    local w = Game()
    local Setup = w.ns.Setup
    local minimal = Setup.ModuleDefaults("minimalist")
    local on = {}
    for id, value in pairs(minimal) do if value then on[#on + 1] = id end end
    table.sort(on)
    check("Minimalist pre-selects Quality of Life, the Dungeon Journal and the BiS List: " .. Names(on),
        Names(on) == "bis,journal,qol")
    for id, item in pairs(Setup.ITEMS) do
        local listed = false
        for _, addon in ipairs(w.ns.PRESETS.minimalist.modulesOff) do listed = listed or addon == item.addon end
        check("the list is the preset's own: " .. id, listed == not MINIMALIST_ON[id])
    end
    local starter = Game({ root = w.env.CopyTable(w.ns.STARTER.profile) })
    for id in pairs(Setup.ITEMS) do
        check("a new install's switches agree with Minimalist: " .. id, starter.Switch(id) == (MINIMALIST_ON[id] == true))
    end
    local recommended = Setup.ModuleDefaults("recommended")
    local P = w.ns.PRESETS.recommended.profile
    for _, item in pairs(Setup.ITEMS) do
        local v = P[item.db] and P[item.db][item.key]
        if v == nil then v = w.ns.FEATURES[item.db][item.key] end
        local id
        for k, it in pairs(Setup.ITEMS) do if it == item then id = k end end
        check(id .. ": Recommended pre-selects what its switches say", recommended[id] == (v == true))
    end
    for id in pairs(Setup.ITEMS) do
        check("Everything Enabled pre-selects every module: " .. id, recommended[id] == true)
    end
end

do
    local enabled = All(true)
    enabled.NaowhForever_Training, enabled.NaowhForever_QoL = false, false
    local w = Game({ enabled = enabled, root = { discovery = { enabled = true }, journal = { enabled = false } } })
    local mine = w.ns.Setup.ModuleDefaults(w.ns.Setup.KEEP)
    check("keep mine: a module whose addon is off is off", mine.training == false)
    check("one switched on in the profile is on, one switched off is off", mine.discovery and mine.journal == false)
    check("one left alone follows its default", mine.threatMeter == true and mine.groupInspect == false)
end

do
    local w = Game()
    local Setup = w.ns.Setup
    local picks = Setup.Fresh()
    Setup.PickProfile(picks, "recommended")
    Setup.Toggle(picks, "professions", false)
    check("Professions off leaves the Training Planner on", picks.modules.training)
    Setup.Toggle(picks, "training", true)
    check("the Training Planner does not bring Professions", not picks.modules.professions)
    Setup.Toggle(picks, "groupInspect", true)
    Setup.Toggle(picks, "bis", false)
    check("the BiS List off takes Group Inspect", not picks.modules.bis and not picks.modules.groupInspect)
    Setup.Toggle(picks, "nothing", true)
    check("an unknown module changes nothing", picks.modules.nothing == nil)
    local edited = picks.modules
    Setup.PickProfile(picks, "recommended")
    check("picking the same profile keeps the edits", picks.modules == edited)
    Setup.PickProfile(picks, "minimalist")
    check("another profile starts its modules again", picks.modules ~= edited and picks.modules.bis
        and not picks.modules.professions)
end

do
    local w = Game({ account = { welcomeSeen = true } })
    local Setup = w.ns.Setup
    local picks = Setup.Fresh()
    local plan = Setup.Plan(picks)
    check("keep mine, same skin, no flips: nothing changes, no reload", not plan.changes and not plan.reload
        and plan.profile == nil and #plan.on == 0 and #plan.off == 0)
    Setup.Toggle(picks, "pvp", true)
    plan = Setup.Plan(picks)
    check("a loaded module switched on: listed, no reload", plan.changes and Names(plan.on) == "PvP"
        and not plan.reload)
    w.loaded.NaowhForever_Combat = false
    check("not loaded: it needs a reload", Setup.Plan(picks).reload)
    w.loaded.NaowhForever_Combat = true
    Setup.Toggle(picks, "pvp", false)
    Setup.Toggle(picks, "professions", false)
    plan = Setup.Plan(picks)
    check("a loaded module turned off: listed, with a reload", Names(plan.off) == "Professions" and plan.reload)
    Setup.Toggle(picks, "professions", true)
    Setup.Toggle(picks, "actionBars", false)
    plan = Setup.Plan(picks)
    check("a Utilities module turned off while Utilities is loaded: listed, no reload", Names(plan.off) == "Action Bars"
        and not plan.reload)
    Setup.Toggle(picks, "actionBars", true)
    w.loaded.NaowhForever_BiS = false
    Setup.Toggle(picks, "groupInspect", true)
    check("Group Inspect picked with Utilities loaded but the BiS List not: a reload", Setup.Plan(picks).reload)
    Setup.Toggle(picks, "groupInspect", false)
    Setup.Toggle(picks, "bis", true)
    w.loaded.NaowhForever_BiS = true
    Setup.Toggle(picks, "swingTimer", false)
    plan = Setup.Plan(picks)
    check("a Combat module turned off while Combat is loaded: listed, no reload", Names(plan.off) == "Swing Timer"
        and not plan.reload)
    Setup.Toggle(picks, "swingTimer", true)
    picks.skin = "forever"
    plan = Setup.Plan(picks)
    check("a new skin: listed and reloads", plan.changes and plan.skinChanged and plan.reload and plan.skin == "forever")
    picks.skin = ""
    Setup.PickProfile(picks, "recommended")
    plan = Setup.Plan(picks)
    check("a profile: named, with a reload", plan.profile == "Everything Enabled" and plan.reload)
end

local function Applied(w, picks)
    local plan = w.ns.Setup.Plan(picks)
    local reload = w.ns.Setup.Apply(picks)
    check("Apply's reload is the plan's", reload == plan.reload)
    return plan, reload
end

do
    local w = Game({ root = { qol = { questRewards = { [1] = 2 }, xpBar = false }, discovery = { enabled = true },
        completo = { enabled = true } }, account = { welcomeSeen = true } })
    local Setup = w.ns.Setup
    local before = w.ns.SettingsRoot()
    local wasOn, wasOff = 0, 0
    for id in pairs(Setup.ITEMS) do
        if MINIMALIST_ON[id] then
            if not w.On(id) then wasOff = wasOff + 1 end
        elseif w.On(id) then
            wasOn = wasOn + 1
        end
    end
    local picks = Setup.Fresh()
    Setup.PickProfile(picks, "minimalist")
    local plan = Applied(w, picks)
    check("Minimalist: the summary turns off every other module that was on, and on the rest of its own",
        #plan.off == wasOn and wasOn > 0 and #plan.on == wasOff)
    for id in pairs(Setup.ITEMS) do
        check("Minimalist, applied: " .. id .. (MINIMALIST_ON[id] and " enabled" or " disabled"),
            w.On(id) == (MINIMALIST_ON[id] == true))
    end
    check("for every character", w.others.NaowhForever_Discovery == false and w.others.NaowhForever_QoL == true)
    check("no call named a character", (function()
        for _, c in ipairs(w.calls) do if not w.ForEveryone(c) then return false end end
        return #w.calls > 0
    end)())
    check("the preset is the profile now, the player's own data kept", w.root.qol.preset == "minimalist"
        and w.root.qol.questRewards[1] == 2 and w.root == before)
    check("its switches say the same: off for the rest", w.root.completo.enabled == false
        and w.root.discovery.enabled == false and w.root.qol.groupInspect == false and w.root.qol.bis == true
        and w.root.threatMeter.enabled == false and w.root.journal.enabled == true)
    check("a backup of what was there", w.account.setupBefore and w.account.setupBefore.root.qol.xpBar == false
        and w.account.setupBefore.addons.NaowhForever_PvP == true and w.account.setupBefore.skin == "")
    check("Minimalist has both panels off: neither is picked", w.root.qol.characterPanelPicked == nil
        and w.root.qol.inspectPanelPicked == nil)
    w.Reload()
    for id in pairs(Setup.ITEMS) do
        check("after the reload " .. id .. " is as the summary said", w.On(id) == (MINIMALIST_ON[id] == true))
    end
    check("and it can be undone", Setup.CanRestore() and Setup.Restore())
    check("undone: the profile, the addons and the skin as they were", w.root.qol.preset == nil
        and w.root.qol.xpBar == false and w.enabled.NaowhForever_Combat and w.others.NaowhForever_Combat
        and w.account.skin == nil and w.account.setupBefore == nil and not Setup.CanRestore())
end

do
    local w = Game({ character = true, account = { welcomeSeen = true } })
    local Setup = w.ns.Setup
    local others = {}
    for k, v in pairs(w.others) do others[k] = v end
    local picks = Setup.Fresh()
    Setup.PickProfile(picks, "minimalist")
    Applied(w, picks)
    for id in pairs(Setup.ITEMS) do
        check("Minimalist for one character: " .. id, w.On(id) == (MINIMALIST_ON[id] == true))
    end
    local same = true
    for k, v in pairs(others) do same = same and w.others[k] == v end
    check("every other character keeps its addons", same)
    check("every C_AddOns call named this character", (function()
        for _, c in ipairs(w.calls) do if not w.ForMe(c) then return false end end
        return #w.calls > 0
    end)())
    check("the backup knows whose it was", w.account.setupBefore.character == w.GUID)
    w.calls = {}
    Setup.ForCharacter(false)
    check("restored for that character, whatever the mode now", Setup.Restore() and w.enabled.NaowhForever_Combat
        and (function()
            for _, c in ipairs(w.calls) do if not w.ForMe(c) then return false end end
            return #w.calls > 0
        end)())
end

do
    local enabled = All(true)
    local w = Game({ enabled = enabled, loaded = enabled, account = { welcomeSeen = true },
        root = { pvp = { enabled = false }, qol = { characterPanel = true, inspectPanel = false, groupInspect = true } } })
    local Setup = w.ns.Setup
    local picks = Setup.Fresh()
    Setup.Toggle(picks, "pvp", true)
    local plan = Applied(w, picks)
    check("keep mine: one loaded module on, live, no reload", Names(plan.on) == "PvP" and not plan.reload
        and w.root.pvp.enabled == true)
    check("switched through its store, so it starts now", w.changed[1] == "pvp.enabled=true")
    check("the modules moved off the setup: marked as your own", w.root.qol.preset == "custom")
    check("the character panel on: picked, so it takes over without asking; the inspect panel off: not",
        w.root.qol.characterPanelPicked == true and w.root.qol.inspectPanelPicked == nil)
    Setup.Restore()
    local off = All(true)
    off.NaowhForever_BiS = false
    local w2 = Game({ enabled = off, loaded = off, account = { welcomeSeen = true }, root = { qol = {} } })
    local picks2 = w2.ns.Setup.Fresh()
    w2.ns.Setup.Toggle(picks2, "groupInspect", true)
    plan = Applied(w2, picks2)
    check("a module that needs an addon that is off: both on, with a reload", plan.reload
        and Names(plan.on) == "BiS List,Group Inspect" and w2.On("groupInspect")
        and w2.enabled.NaowhForever_BiS and w2.enabled.NaowhForever_Utilities)
    Setup.Restore()
    picks = Setup.Fresh()
    Setup.Toggle(picks, "bis", false)
    plan = Applied(w, picks)
    check("the BiS List off: Group Inspect with it, a reload, no panel pick", plan.reload
        and Names(plan.off) == "BiS List,Group Inspect" and not w.enabled.NaowhForever_BiS
        and not w.On("groupInspect") and w.root.qol.characterPanelPicked == nil)
end

do
    local w = Game({ account = { welcomeSeen = true } })
    local Setup = w.ns.Setup
    local picks = Setup.Fresh()
    picks.skin = "forever"
    check("a new skin: applied, with a reload", select(2, Applied(w, picks)) and w.account.skin == "forever")
    check("only the skin changed: the setup's name stays", w.root.qol == nil or w.root.qol.preset == nil)
    Setup.Restore()
    check("restored: back to Naowh", w.account.skin == nil)
    w.account.skin = "forever"
    w.account.setupBefore = { profile = "Default", root = {}, addons = {} }
    Setup.Restore()
    check("a backup from before skins were saved leaves the skin alone", w.account.skin == "forever")
    w.account.setupBefore = { profile = "Other", root = {}, addons = {} }
    check("a backup of another profile is not restored here", not Setup.CanRestore() and not Setup.Restore())
end

do
    local w = Game({ account = { welcomeSeen = true } })
    local Setup = w.ns.Setup
    local picks = Setup.Fresh()
    Setup.PickProfile(picks, "recommended")
    Applied(w, picks)
    check("Everything Enabled with no flips: its own name stays", w.root.qol.preset == "recommended")
    check("the character and inspect panels on in it, with the BiS List: both picked",
        w.root.qol.characterPanelPicked == true and w.root.qol.inspectPanelPicked == true)
end

do
    local w = Game({ account = { welcomeSeen = true }, root = { discovery = { enabled = true } } })
    w.ns.ApplyPreset("minimalist")
    local on = {}
    for id, value in pairs(w.ns.Setup.ModuleDefaults(w.ns.Setup.KEEP)) do if value then on[#on + 1] = id end end
    table.sort(on)
    check("Minimalist from the Profiles page's Setups card: the same modules on, the rest off: " .. Names(on),
        Names(on) == "bis,journal,qol")
    local tip = w.ns.PresetChanges("recommended")
    check("and its hover names what Everything Enabled turns back on", tip:find("Group Inspect", 1, true) ~= nil)
    w = Game({ account = { welcomeSeen = true }, root = { discovery = { enabled = true } } })
    check("the hover for Minimalist names the modules it turns off", w.ns.PresetChanges("minimalist")
        :find("Recommended turns off: ", 1, true) ~= nil and w.ns.PresetChanges("minimalist"):find("Discovery", 1, true))
    local enabled, loaded = All(true), All(true)
    enabled.NaowhForever_DungeonJournal, loaded.NaowhForever_DungeonJournal = false, false
    enabled.NaowhForever_Discovery, loaded.NaowhForever_Discovery = false, false
    w = Game({ account = { welcomeSeen = true }, enabled = enabled, loaded = loaded })
    w.ns.ConfirmReload = function() end
    check("the hover counts a module whose addon is not loaded", w.ns.PresetChanges("minimalist")
        :find("Dungeon Journal", 1, true) ~= nil and not w.ns.PresetChanges("minimalist"):find("Discovery", 1, true))
    w.ns.UsePreset("minimalist", false)
    check("the Setups card enables the addons it turns on, and only those", w.enabled.NaowhForever_DungeonJournal
        and not w.enabled.NaowhForever_Discovery and w.root.journal.enabled == true)
end

do
    local enabled = All(true)
    enabled.NaowhForever_Combat = false
    local w = Game({ enabled = enabled, character = true, account = { welcomeSeen = true },
        root = { qol = { blessings = true }, pvp = { enabled = false } } })
    local Setup = w.ns.Setup
    local picks = Setup.Fresh()
    check("Combat disabled here: its modules start off, whatever their switches", picks.modules.blessings == false
        and picks.modules.swingTimer == false)
    Setup.Toggle(picks, "pvp", true)
    Applied(w, picks)
    check("one Combat module on brings Combat back for this character", w.enabled.NaowhForever_Combat and w.On("pvp"))
    check("and the ones left off stay off, their switches cleared", not w.On("blessings") and not w.On("swingTimer")
        and w.root.qol.blessings == false)
end

print("PASS setup plan: " .. checks .. " checks")
