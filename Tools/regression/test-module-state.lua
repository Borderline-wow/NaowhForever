-- Run with Lua 5.1 from the repository root: a module's on/off follows the profile. The profile's
-- switches and this character's AddOn list are reconciled at login and on a profile switch (a new
-- character, an AddOn list changed by hand, a profile changed on another character), and a module
-- turned on or off writes both.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local World = dofile("Tools/regression/setup_world.lua")
local MACROS, BARS, JOURNAL = "NaowhForever_Macros", "NaowhForever_ActionBars", "NaowhForever_DungeonJournal"
local GEAR, COMBAT = "NaowhForever_GearSets", "NaowhForever_Combat"
local COMBAT_IDS = { "gearSets", "blessings", "auraBuffs", "threatMeter", "pvp", "swingTimer" }
local BIS, INSPECT, DISC = "NaowhForever_BiS", "NaowhForever_GroupInspect", "NaowhForever_Discovery"
local QOL = "NaowhForever_QoL"

local function All(value)
    local out = {}
    for _, mod in ipairs(World().MODULES) do out[mod.addon] = value end
    return out
end

local function Game(root, account)
    return World({ enabled = All(true), loaded = All(true), root = root or {},
        account = account or { onboardingSeen = true } })
end

local function Writes(w)
    local list = {}
    for _, call in ipairs(w.calls) do
        if call.name == "EnableAddOn" or call.name == "DisableAddOn" then list[#list + 1] = call end
    end
    return list
end

local function Count(list, pick)
    local n = 0
    for _, call in ipairs(list) do if pick(call) then n = n + 1 end end
    return n
end

do
    local w = Game({ macros = { enabled = false } }, {})
    check("an account that has not seen the onboarding is left to it", w.ns.ReconcileModules() == 0
        and #Writes(w) == 0 and w.account.moduleList == nil and #w.reloads == 0)
end

do
    local w = Game({ macros = { enabled = false }, actionBars = { enabled = false } })
    check("a new character follows the profile: two modules off", w.ns.ReconcileModules() == 2)
    check("in its own AddOn list", not w.enabled[MACROS] and not w.enabled[BARS] and w.enabled[JOURNAL])
    check("naming the character, never every character", #Writes(w) == 2 and Count(Writes(w), w.ForMe) == 2)
    check("the profile is as it was", w.root.macros.enabled == false and w.root.actionBars.enabled == false)
    check("and one reload is offered", #w.reloads == 1)
    check("nothing differs at the next check: no call, no prompt", w.ns.ReconcileModules() == 0
        and #Writes(w) == 2 and #w.reloads == 1)
end

do
    local w = Game({ actionBars = { enabled = true } })
    w.enabled[BARS] = false
    check("an addon turned off before this change, its switch left on: adopted, not turned back on",
        w.ns.ReconcileModules() == 0 and #Writes(w) == 0 and #w.reloads == 0 and w.root.actionBars.enabled == false)
    w.enabled[JOURNAL] = false
    w.ns.ReconcileModules()
    check("a module that was never switched takes the list's state", w.root.journal.enabled == false)
    check("a module off by default, its addon on, is left as it is", w.root.journeys == nil
        and w.enabled.NaowhForever_Journeys)
end

do
    local w = Game()
    w.ns.ReconcileModules()
    w.enabled[JOURNAL] = false
    check("an AddOn list changed by hand since: the profile adopts it", w.ns.ReconcileModules() == 0
        and w.root.journal.enabled == false and #Writes(w) == 0)
    w.enabled[JOURNAL] = true
    w.ns.ReconcileModules()
    check("and adopts it going back on", w.root.journal.enabled == true and w.enabled[JOURNAL] and #Writes(w) == 0)
end

do
    local w = Game()
    w.ns.ReconcileModules()
    w.root.macros = { enabled = false }
    check("a profile changed since (another character): applied to the list", w.ns.ReconcileModules() == 1
        and not w.enabled[MACROS] and Count(Writes(w), w.ForMe) == 1 and #w.reloads == 1)
    check("and the next check is quiet", w.ns.ReconcileModules() == 0 and #w.reloads == 1)
end

do
    local w = Game({ qol = { groupInspect = true } })
    w.ns.ReconcileModules()
    w.root.qol.bis = false
    w.ns.ReconcileModules()
    check("a module its profile turns off takes the module that needs it", not w.enabled[BIS] and not w.enabled[INSPECT]
        and w.root.qol.groupInspect == false)
    w.root.qol.bis = true
    w.ns.ReconcileModules()
    check("the module that needs it stays off until it is turned on", w.enabled[BIS] and not w.enabled[INSPECT])
end

do
    local w = Game({ qol = { gearSets = false } })
    check("a Combat module its profile turns off: its switch only, the Combat addon stays for the rest",
        w.ns.ReconcileModules() == 0 and w.enabled[COMBAT] and #Writes(w) == 0 and not w.On("gearSets")
        and w.On("blessings"))
    w.ns.SetModuleState(w.Item("pvp").addon, false)
    check("one switched off: its switch only, Combat stays on for the rest", w.enabled[COMBAT] and not w.On("pvp")
        and w.On("swingTimer"))
    for _, id in ipairs(COMBAT_IDS) do w.ns.SetModuleState(w.Item(id).addon, false) end
    local last = Writes(w)[#Writes(w)]
    check("all six off: the Combat addon goes off for this character", not w.enabled[COMBAT]
        and last.name == "DisableAddOn" and last.addon == COMBAT and w.ForMe(last) and w.root.pvp.enabled == false)
    w.ns.SetModuleState(GEAR, true)
    check("one back on brings the Combat addon back", w.enabled[COMBAT] and w.On("gearSets") and not w.On("pvp"))
end

do
    local w = Game({ qol = { gearSets = false, blessings = false }, auraBuffs = { enabled = false },
        threatMeter = { enabled = false }, pvp = { enabled = false }, swingTimer = { enabled = false } })
    check("a profile with all six Combat modules off takes the Combat addon out of the list",
        w.ns.ReconcileModules() == 1 and not w.enabled[COMBAT] and #w.reloads == 1)
    check("and the next check is quiet", w.ns.ReconcileModules() == 0 and #w.reloads == 1)
    w.root.pvp.enabled = true
    check("a profile that turns one back on puts the Combat addon back", w.ns.ReconcileModules() == 1
        and w.enabled[COMBAT] and w.On("pvp") and not w.On("swingTimer"))
end

do
    local w = Game({ macros = { enabled = false } })
    w.ns.ReconcileModules(true)
    check("quiet: the list changes, no prompt", not w.enabled[MACROS] and #w.reloads == 0)
end

do
    local w = Game({ macros = { enabled = false } })
    w.combat = true
    w.ns.ReconcileModules()
    local watch
    for _, frame in ipairs(w.frames) do if frame.events.PLAYER_REGEN_ENABLED then watch = frame end end
    check("in combat the prompt waits", #w.reloads == 0 and watch ~= nil)
    w.combat = false
    watch.onEvent(watch, "PLAYER_REGEN_ENABLED")
    check("and comes once combat ends", #w.reloads == 1 and not watch.events.PLAYER_REGEN_ENABLED)
end

do
    local w = Game({ macros = { enabled = false } })
    local login
    for _, frame in ipairs(w.frames) do if frame.events.PLAYER_LOGIN then login = frame end end
    check("the core checks once, at login", login ~= nil and #w.timers == 0)
    login.onEvent(login, "PLAYER_LOGIN")
    check("a moment after it", #w.timers == 1 and not login.events.PLAYER_LOGIN and w.enabled[MACROS])
    w.timers[1]()
    check("the list matches the profile", not w.enabled[MACROS] and #w.reloads == 1)
end

do
    local w = Game()
    w.ns.SetModuleState(MACROS, false)
    check("turned off: this character's list and the profile", not w.enabled[MACROS] and w.root.macros.enabled == false
        and Writes(w)[#Writes(w)].who == "Player-4613-006EB819")
    w.ns.SetModuleState(MACROS, true)
    check("and back on", w.enabled[MACROS] and w.root.macros.enabled == true)
    w.loaded[BARS] = false
    w.Session()
    w.ns.SetModuleState(BARS, false)
    w.ns.SetModuleState(BARS, true)
    check("a module whose addon is not loaded keeps its switch in the profile too", w.root.actionBars.enabled == true)
    w.ns.SetModuleState("NaowhForever_Discovery", true)
    check("including one that is off by default", w.root.discovery.enabled == true)
    w.ns.ReconcileModules()
    check("and the next check agrees", #w.reloads == 0)
end

do
    local w = Game()
    for _, addon in ipairs(w.ns.LinkedAddons(QOL, false)) do w.ns.SetModuleState(addon, false) end
    check("QoL off takes only its own addon out of the list: the Top Bar is part of it", not w.enabled[QOL]
        and #w.ns.LinkedAddons(QOL, false) == 1 and w.root.qol.enabled == false)
end

do
    local w = Game({ discovery = { enabled = true } })
    w.ns.ConfirmReload = function(text) w.reloads[#w.reloads + 1] = text end
    w.ns.UsePreset("minimalist", false)
    check("Minimalist from the Setups card also takes its modules out of the AddOn list", not w.enabled[DISC]
        and not w.enabled["NaowhForever_GroupInspect"] and not w.enabled[MACROS] and w.enabled["NaowhForever_BiS"])
    check("with the one reload prompt", #w.reloads == 1)
end

do
    local w = Game({}, { welcomeSeen = true })
    local Setup = w.ns.Setup
    local picks = Setup.Fresh()
    Setup.Toggle(picks, "macros", false)
    Setup.Apply(picks)
    check("the onboarding turning a module off writes the profile's switch", w.root.macros.enabled == false
        and not w.enabled[MACROS])
end

print(("test-module-state: %d checks passed"):format(checks))
