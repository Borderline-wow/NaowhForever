-- Tailor my setup's rules, Apply and Restore on stubs. From the repo root:
-- lua5.1 Tools/regression/test-setup-plan.lua
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end

local function Load(env)
    env = env or {}
    env.ns = env.ns or {}
    setmetatable(env, { __index = _G })
    env._G = { NaowhForever = env.ns }
    env.CopyTable = CopyTable
    local chunk = assert(loadfile("Core/Onboarding/Setup.lua"))
    setfenv(chunk, env)
    chunk()
    return env.ns.Setup, env
end

local Setup = Load()

check("seven questions", #Setup.QUESTIONS == 7)
for _, q in ipairs(Setup.QUESTIONS) do
    check(q.id .. ": wording is ASCII", not q.title:find("[\128-\255]"))
    if q.one then
        local found = false
        for _, a in ipairs(q.answers) do found = found or a[1] == q.default end
        check(q.id .. ": its default is one of its answers", found)
    end
end
local function Known(list, where)
    for _, id in ipairs(list) do check(where .. ": " .. id .. " is a known switch", Setup.ITEMS[id] ~= nil) end
end
for key, b in pairs(Setup.BUNDLES) do
    Known(b.core, key)
    Known(b.more, key)
    check(key .. " has its reason", type(b.why) == "string" and b.why ~= "")
end
for key, o in pairs(Setup.OVERLAP) do Known(o.off, key) end
for class, list in pairs(Setup.CLASS) do Known(list, class) end
for id, item in pairs(Setup.ITEMS) do
    check(id .. ": a module or a feature", (item.addon and item.db and item.key) or (item.store and item.key))
    if item.needs then check(id .. ": needs a known switch", Setup.ITEMS[item.needs] ~= nil) end
end
for key in pairs(Setup.DETECT) do
    local found = false
    for _, a in ipairs(Setup.QUESTIONS[6].answers) do found = found or a[1] == key end
    check("found addon " .. key .. " is an answer", found)
end

local function Minimalist()
    local v = {}
    for id, item in pairs(Setup.ITEMS) do v[id] = item.addon ~= nil end
    v.pvp, v.completo, v.discovery, v.groupInspect, v.threatMeter = false, false, false, false, false
    v.townMap, v.talentPoints, v.flightTimer, v.flightGames = true, true, true, true
    return v
end

local function Recommended()
    local v = Minimalist()
    v.threatMeter, v.discovery, v.groupInspect = true, true, true
    v.xpBar, v.xpTicker, v.combatAlert, v.lootFeed, v.naowhScore, v.characterPanel = true, true, true, true, true, true
    return v
end

local LINKS = { journal = { "bis" }, bis = { "journal" }, training = { "professions" }, groupInspect = { "bis" } }

local function Ctx(now, mine, class)
    local presets = { minimalist = Minimalist(), recommended = Recommended() }
    return { read = function(id) return now[id] end,
        base = function(preset, id) return presets[preset][id] end,
        mine = function(id) return (mine or {})[id] == true end,
        links = LINKS, class = class or "WARRIOR",
        presetName = function(key) return key == "minimalist" and "Minimalist" or "Recommended" end }
end

local function ByID(entries)
    local by = {}
    for _, e in ipairs(entries) do by[e.id] = e end
    return by
end

local function Turns(by, id)
    local e = by[id]
    if e and e.on ~= e.now then return e.on and "on" or "off" end
end

local CORE = "Core of Naowh Forever."

do
    local entries = Setup.Plan({}, Ctx(Minimalist()))
    local by = ByID(entries)
    local on, off, stay = Setup.Counts(entries)
    check("a fresh Minimalist install, every answer left: the core and the quiet helpers turn on", on == 11
        and off == 0 and stay == #entries - 11 and #entries > 40)
    local quiet = true
    for id, item in pairs(Setup.ITEMS) do
        if item.quiet then quiet = quiet and by[id].on and by[id].why == "Saves you time; the game plays the same." end
    end
    check("a helpful amount turns every quiet helper on, saying why", quiet and by.fastLoot.theme == "Quality of Life")
    local ess = ByID(Setup.Plan({ amount = "essentials" }, Ctx(Minimalist())))
    check("just the essentials: faster looting and selling junk only", ess.fastLoot.on and ess.sellJunk.on
        and not ess.autoRepair.on and not ess.skipCinematics.on and not ess.deleteConfirm.on)
    check("the core: Naowh Score, the character and inspect panels and the loot feed come on",
        Turns(by, "naowhScore") == "on" and Turns(by, "characterPanel") == "on" and Turns(by, "inspectPanel") == "on"
        and Turns(by, "lootFeed") == "on" and by.lootFeed.why == CORE)
    check("the rest of the core is on already and says why", by.journal.why == CORE and by.bis.why == CORE
        and by.flightTimer.why == CORE and by.flightGames.why == CORE and Turns(by, "flightGames") == nil)
    local complete = true
    for _, e in ipairs(entries) do complete = complete and e.theme ~= nil and e.why ~= nil end
    check("every switch has its theme and a reason", complete)
    check("listed by theme, in the review's order", entries[1].theme == Setup.THEMES[1]
        and entries[#entries].theme == Setup.THEMES[#Setup.THEMES])
    for id in pairs(Setup.ITEMS) do check(id .. " has a theme", Setup.THEME_OF[id] ~= nil) end
end

do
    local by = ByID(Setup.Plan({ focus = { dungeons = true } }, Ctx(Minimalist())))
    check("dungeons: the character helpers turn on", Turns(by, "naowhScore") == "on"
        and Turns(by, "characterPanel") == "on" and Turns(by, "restock") == "on" and Turns(by, "mapEntrances") == "on")
    check("dungeons: the reason says why", by.restock.why == "You run dungeons and raids.")
    check("on already: Dungeon Journal is listed and stays, saying why", Turns(by, "journal") == nil
        and by.journal.on and by.journal.why == CORE)
    check("a switch no answer touched stays as the player has it", by.pvp.why == "Stays as you have it."
        and Turns(by, "pvp") == nil)
    by = ByID(Setup.Plan({ amount = "essentials", focus = { dungeons = true } }, Ctx(Recommended())))
    check("just the essentials starts from Minimalist", Turns(by, "xpBar") == "off"
        and by.xpBar.why == "From the Minimalist setup.")
    by = ByID(Setup.Plan({}, Ctx(Recommended())))
    check("a helpful amount keeps an existing setup: nothing it has turns off", Turns(by, "xpBar") == nil
        and Turns(by, "threatMeter") == nil and select(2, Setup.Counts(Setup.Plan({}, Ctx(Recommended())))) == 0)
    local essentials = ByID(Setup.Plan({ amount = "essentials", focus = { dungeons = true } }, Ctx(Minimalist())))
    check("just the essentials: only the core, not the helpers", Turns(essentials, "restock") == nil)
end

do
    local by = ByID(Setup.Plan({ amount = "everything" }, Ctx(Minimalist())))
    check("everything useful starts from Recommended", Turns(by, "threatMeter") == "on"
        and Turns(by, "xpBar") == "on" and by.xpBar.why == "From the Recommended setup.")
end

do
    local by = ByID(Setup.Plan({ focus = { pvp = true }, screen = "clean" }, Ctx(Minimalist())))
    check("a clean screen wins over a bundle's on-screen helper", Turns(by, "combatAlert") == nil
        and Turns(by, "pvp") == "on")
    local now = Minimalist()
    now.lootFeed, now.xpBar = true, true
    by = ByID(Setup.Plan({ screen = "clean" }, Ctx(now)))
    check("a clean screen turns on-screen helpers off", Turns(by, "xpBar") == "off"
        and by.xpBar.why == "You picked a clean screen.")
    check("but never the core: the loot feed stays on", Turns(by, "lootFeed") == nil and by.lootFeed.on
        and by.lootFeed.why == CORE)
    by = ByID(Setup.Plan({ screen = "all" }, Ctx(Minimalist())))
    check("show me everything turns the general helpers on", Turns(by, "combatTimer") == "on"
        and Turns(by, "clock") == "on" and Turns(by, "coTank") == nil)
    by = ByID(Setup.Plan({ amount = "essentials", screen = "clean", group = "solo", classic = "expert" },
        Ctx(Minimalist())))
    check("the most purist answers still keep the core on", by.naowhScore.on and by.characterPanel.on
        and by.inspectPanel.on and by.bis.on and by.journal.on and by.lootFeed.on and by.flightTimer.on
        and by.flightGames.on)
end

do
    local by = ByID(Setup.Plan({ role = { tank = true }, addons = { threat = true } }, Ctx(Minimalist())))
    check("another threat meter keeps ours off, even for a tank", Turns(by, "threatMeter") == nil
        and by.threatMeter.why == "You use a threat meter." and Turns(by, "coTank") == "on")
    local entries = Setup.Plan({ amount = "everything" }, Ctx(Recommended()))
    by = ByID(entries)
    check("with EllesmereUI too the character and inspect panels stay on", by.characterPanel.on
        and by.inspectPanel.on and by.characterPanel.why == CORE)
    by = ByID(Setup.Plan({ focus = { questing = true }, addons = { guide = true } }, Ctx(Minimalist())))
    check("a quest guide keeps quest automation off", Turns(by, "questAuto") == nil and Turns(by, "xpBar") == "on")
end

do
    local now = Minimalist()
    now.professions, now.training, now.bis, now.journal = false, false, false, false
    local ctx = Ctx(now)
    local base = ctx.base
    ctx.base = function(preset, id)
        if id == "professions" then return false end
        return base(preset, id)
    end
    local by = ByID(Setup.Plan({ classic = "new" }, ctx))
    check("new to Classic: the Training Planner, and Professions it needs", Turns(by, "training") == "on"
        and Turns(by, "professions") == "on" and by.professions.why == "Training Planner needs it.")
    by = ByID(Setup.Plan({ group = "always" }, Ctx(now)))
    check("grouping all the time: Group Inspect, and the BiS List it needs", Turns(by, "groupInspect") == "on"
        and Turns(by, "bis") == "on")
    check("modules are marked as modules", by.groupInspect.module and not by.groupInspectShare.module)
end

do
    local now = Minimalist()
    now.xpBar = true
    local by = ByID(Setup.Plan({ screen = "clean" }, Ctx(now, { xpBar = true })))
    check("a switch the player set: their value kept, our suggestion beside it", by.xpBar.mine
        and by.xpBar.on == true and by.xpBar.suggest == false and Turns(by, "xpBar") == nil)
    by = ByID(Setup.Plan({ screen = "clean" }, Ctx(now)))
    check("otherwise it follows our suggestion", Turns(by, "xpBar") == "off" and not by.xpBar.mine)
    by = ByID(Setup.Plan({ focus = { questing = true } }, Ctx(now, { xpBar = true })))
    check("theirs and our suggestion agree: nothing to point out", not by.xpBar.mine and by.xpBar.on)
end

do
    local by = ByID(Setup.Plan({}, Ctx(Minimalist(), nil, "HUNTER")))
    check("a Hunter gets the Pet Tracker", Turns(by, "petTracker") == "on" and by.petTracker.why == "For your class.")
    local now = Minimalist()
    now.rareAlert = nil
    by = ByID(Setup.Plan({ focus = { collecting = true } }, Ctx(now)))
    check("a switch not here (its module off) is not listed", by.rareAlert == nil and Turns(by, "completo") == "on")
end

do
    local entries = Setup.Plan({ focus = { dungeons = true } }, Ctx(Minimalist()))
    local by = ByID(entries)
    local on = Setup.Counts(entries)
    by.naowhScore.on = false
    check("a correction counts: one less turns on", (Setup.Counts(entries)) == on - 1)
    check("no module changes: no reload", not Setup.NeedsReload(entries))
    by.pvp.on = true
    check("a loaded module turning on switches live", not Setup.NeedsReload(entries))
    by.pvp.loaded = false
    check("a module that is not loaded needs a reload to come on", Setup.NeedsReload(entries))
    by.pvp.on, by.pvp.loaded = false, true
    by.journal.on = false
    check("a module turning off needs a reload", Setup.NeedsReload(entries))
end

do
    local by = ByID(Setup.Plan({ amount = "purist", focus = { dungeons = true, questing = true }, role = { tank = true },
        screen = "all", group = "always", classic = "new" }, Ctx(Recommended(), nil, "PALADIN")))
    local kept = true
    for _, id in ipairs({ "bis", "journal", "groupInspect", "characterPanel", "inspectPanel", "flightTimer",
        "flightGames", "groupInspectShare", "naowhScore" }) do
        kept = kept and by[id].on and by[id].why == "Doesn't change how the game plays."
    end
    check("a purist keeps the BiS List, Journal, Group Inspect and its sharing, Naowh Score, both panels,"
        .. " flights and games", kept and by.groupInspectShare.on and by.naowhScore.on)
    check("and every quiet helper", by.fastLoot.on and by.sellJunk.on and by.autoRepair.on and by.skipCinematics.on
        and by.hideTutorials.on and by.mailQuickAttach.on and by.deleteConfirm.on)
    check("and everything else is suggested off", not by.lootFeed.on and not by.threatMeter.on and not by.xpBar.on
        and by.lootFeed.why == "You're a purist.")
    check("the other answers change nothing for a purist", not by.restock.on and not by.coTank.on
        and not by.blessings.on and not by.trainerPopup.on and not by.combatTimer.on)
    check("a purist skips the rest of the questions", Setup.Skips({ amount = "purist" })
        and not Setup.Skips({ amount = "helpful" }) and not Setup.Skips({}))
end

do
    local by = ByID(Setup.Plan({ amount = "purist" }, Ctx(Recommended())))
    check("a purist hides the red error text and keeps the passive pet warning", by.hideErrors.on and by.petPassive.on)
    check("and has no copy tools or campfire quiz", not by.tooltipCopy.on and not by.globalCopy.on and not by.quizCamp.on)
    by = ByID(Setup.Plan({ screen = "clean" }, Ctx(Minimalist())))
    check("a clean screen hides the game's error text, toasts, pop-ups and zone text", by.hideErrors.on
        and by.hideEventToasts.on and by.hideAlerts.on and by.hideZoneText.on and by.hideScreenshot.on
        and by.hideErrors.why == "You picked a clean screen.")
    by = ByID(Setup.Plan({ amount = "everything" }, Ctx(Minimalist())))
    check("everything useful adds the copy tools, the cursor lock and buying at vendors", by.tooltipCopy.on
        and by.globalCopy.on and by.cursorClip.on and by.restockBuy.on and by.globalCopy.why == "You want everything useful.")
    by = ByID(Setup.Plan({ focus = { professions = true } }, Ctx(Minimalist())))
    check("professions add the auction price and the alt helpers", by.ahTooltip.on and by.altCounts.on and by.mailAlts.on
        and by.mailExpiry.on)
    by = ByID(Setup.Plan({ focus = { questing = true } }, Ctx(Minimalist())))
    check("questing keeps your quest reward picks", by.questRewards.on and by.questAuto.on)
    by = ByID(Setup.Plan({ focus = { questing = true }, addons = { guide = true } }, Ctx(Minimalist())))
    check("a quest guide keeps quest automation and reward picks off", not by.questRewards.on and not by.questAuto.on)
    by = ByID(Setup.Plan({ group = "always" }, Ctx(Minimalist())))
    check("grouping all the time shares the quests you take", by.questShare.on)
    by = ByID(Setup.Plan({ classic = "new" }, Ctx(Minimalist(), nil, "WARLOCK")))
    check("new to Classic: the campfire quiz; a warlock: the passive pet warning", by.quizCamp.on and by.petPassive.on)
end

local function Store(key, values, defaults)
    local s = { key = key, values = values, sets = {} }
    function s.Get(k)
        local v = s.values[k]
        if v == nil then v = (defaults or {})[k] end
        return v
    end
    function s.Set(k, v) s.values[k] = v; s.sets[#s.sets + 1] = k end
    function s.Default(k) return (defaults or {})[k] end
    return s
end

local function Game()
    local g = { enabled = { NaowhForever_PvP = true, NaowhForever_Professions = false, NaowhForever_Training = false,
        NaowhForever_BiS = true, NaowhForever_DungeonJournal = true }, profile = "Default",
        loaded = { NaowhForever_PvP = true, NaowhForever_BiS = true, NaowhForever_DungeonJournal = true } }
    g.root = { qol = { xpBar = false, preset = "minimalist", questRewards = { [1] = 2 } }, pvp = { enabled = false } }
    g.account = {}
    g.qol = Store("qol", g.root.qol, { xpBar = true, lootFeed = true, flightGame = "aim", combatLogRaids = "ask",
        combatLogDungeons = "never" })
    g.pvp = Store("pvp", g.root.pvp, { enabled = false })
    local ns = { QoLSettings = g.qol, PvPSettings = g.pvp,
        PRESETS = { minimalist = { name = "Minimalist", profile = { qol = { xpBar = false } } },
            recommended = { name = "Recommended", profile = { qol = { xpBar = true } } } },
        SettingsRoot = function() return g.root end, AccountSettings = function() return g.account end,
        ActiveProfileName = function() return g.profile end }
    function ns.ModuleAddons()
        return {
            { name = "PvP", addon = "NaowhForever_PvP", store = g.pvp, key = "enabled",
              on = g.enabled.NaowhForever_PvP and g.pvp.Get("enabled") == true },
            { name = "Professions", addon = "NaowhForever_Professions", key = "enabled",
              on = g.enabled.NaowhForever_Professions },
            { name = "Training Planner", addon = "NaowhForever_Training", key = "enabled",
              on = g.enabled.NaowhForever_Training },
            { name = "BiS List", addon = "NaowhForever_BiS", store = g.qol, key = "bis", on = g.enabled.NaowhForever_BiS },
            { name = "Dungeon Journal", addon = "NaowhForever_DungeonJournal", key = "enabled",
              on = g.enabled.NaowhForever_DungeonJournal },
        }
    end
    function ns.LinkedAddons(addon, on)
        if addon == "NaowhForever_Training" and on then return { addon, "NaowhForever_Professions" } end
        if addon == "NaowhForever_BiS" and not on then return { addon, "NaowhForever_DungeonJournal" } end
        return { addon }
    end
    g.others, g.calls = CopyTable(g.enabled), {}
    local function Note(name, a, ...)
        g.calls[#g.calls + 1] = { name = name, addon = a, args = select("#", ...), who = (...) }
    end
    local function Switch(on)
        return function(a, ...)
            Note(on and "EnableAddOn" or "DisableAddOn", a, ...)
            g.enabled[a] = on
            if select("#", ...) == 0 then g.others[a] = on end
        end
    end
    local C_AddOns = {
        EnableAddOn = Switch(true),
        DisableAddOn = Switch(false),
        GetAddOnEnableState = function(a, ...)
            Note("GetAddOnEnableState", a, ...)
            if select("#", ...) > 0 then return g.enabled[a] and 2 or 0 end
            if g.enabled[a] and g.others[a] then return 2 end
            return (g.enabled[a] or g.others[a]) and 1 or 0
        end,
        IsAddOnLoaded = function(a) return a == "Omen" or g.loaded[a] == true end,
    }
    g.Setup = Load({ ns = ns, C_AddOns = C_AddOns, UnitClass = function() return "Paladin", "PALADIN" end,
        UnitGUID = function(unit) return unit == "player" and "Player-4613-006EB819" or nil end })
    return g
end

do
    local g = Game()
    local ctx = g.Setup.Context()
    check("context: the character's class", ctx.class == "PALADIN")
    check("context: a feature read from its store", ctx.read("xpBar") == false and ctx.read("lootFeed") == true)
    check("context: a module read from its addon and switch", ctx.read("pvp") == false and ctx.read("training") == false)
    check("context: a module's switch before it loads reads from the profile, off when unset",
        ctx.read("mapEntrances") == false)
    g.root.journal = { mapEntrances = true }
    check("context: and on when the profile has it on", ctx.read("mapEntrances") == true)
    check("context: the preset's value, else the default", ctx.base("recommended", "xpBar") == true
        and ctx.base("minimalist", "lootFeed") == true)
    check("context: the player's own change is against the preset in use", ctx.mine("xpBar") == false)
    g.root.qol.xpBar = true
    check("context: differing from Minimalist is the player's", ctx.mine("xpBar") == true)
    g.root.qol.xpBar = false
    check("found addons: a threat meter, by its name", g.Setup.Detected().threat == "Omen"
        and g.Setup.Detected().guide == nil)
    check("flight games are on unless set to Off", ctx.read("flightGames") == true)
    g.root.qol.flightGame = "off"
    check("set to Off they read as off", ctx.read("flightGames") == false)
    check("a preset's game reads as on", ctx.base("recommended", "flightGames") == true)
end

do
    local g = Game()
    g.root.qol.flightGame = "quiz"
    g.Setup.Apply({ { id = "flightGames", now = true, on = false } })
    check("flight games off: set to Off", g.root.qol.flightGame == "off")
    g.Setup.Apply({ { id = "flightGames", now = false, on = true } })
    check("on again from Off: the default game", g.root.qol.flightGame == "aim")
    g.root.qol.flightGame = "quiz"
    g.Setup.Apply({ { id = "flightGames", now = true, on = true }, { id = "xpBar", now = false, on = true } })
    check("a game the player picked is kept", g.root.qol.flightGame == "quiz")
end

do
    local ctx = Ctx(Minimalist(), { pvp = true })
    ctx.read = function(id) if id == "pvp" then return true end return Minimalist()[id] end
    local by = ByID(Setup.Plan({ amount = "purist" }, ctx))
    check("a purist's setup is the purist list: a module the player turned on turns off", by.pvp.on == false
        and not by.pvp.mine)
    ctx.enabled = function(id) return id == "completo" end
    local entries = Setup.Plan({ amount = "purist" }, ctx)
    by = ByID(entries)
    check("a module switched off but still enabled as an addon turns off", by.completo.idle
        and Setup.Differs(by.completo) and not by.pvp.idle)
    by.completo.on = true
    check("switched on in the review instead: it turns on", (Setup.Counts({ by.completo })) == 1)
    local g = Game()
    g.enabled.NaowhForever_Completo = true
    local reload = g.Setup.Apply({ { id = "completo", now = false, on = false, idle = true } })
    check("applied: its addon is disabled, with no reload needed", g.enabled.NaowhForever_Completo == false
        and reload == false)
end

do
    local by = ByID(Setup.Plan({ focus = { dungeons = true } }, Ctx(Minimalist())))
    check("dungeons and raids: auto combat logging turns on", by.combatLogger.on and by.combatLogger.theme == "Dungeons")
    by = ByID(Setup.Plan({ amount = "purist", focus = { dungeons = true } }, Ctx(Minimalist())))
    check("a purist keeps combat logging as it is", not by.combatLogger.on)
    local g = Game()
    g.Setup.Apply({ { id = "combatLogger", now = false, on = true } })
    check("combat logging on: it logs raids and dungeons", g.root.qol.combatLogger == true
        and g.root.qol.combatLogRaids == "always" and g.root.qol.combatLogDungeons == "always")
    g = Game()
    g.root.qol.combatLogDungeons = "ask"
    g.Setup.Apply({ { id = "combatLogger", now = false, on = true } })
    check("a choice the player made for dungeons is kept", g.root.qol.combatLogDungeons == "ask"
        and g.root.qol.combatLogRaids == "always")
    g.Setup.Apply({ { id = "combatLogger", now = true, on = false } })
    check("turned off, the raid and dungeon choices stay", g.root.qol.combatLogger == false
        and g.root.qol.combatLogRaids == "always")
end

do
    local g = Game()
    local reload = g.Setup.Apply({
        { id = "xpBar", now = false, on = true },
        { id = "questAuto", now = false, on = true },
        { id = "lootFeed", now = true, on = true },
        { id = "pvp", now = false, on = true },
    })
    check("a feature is set in its store", g.root.qol.xpBar == true)
    check("quest automation sets accepting, handing in and picking from NPCs", g.root.qol.questAccept
        and g.root.qol.questTurnIn and g.root.qol.questGossip and g.root.qol.questShare == nil)
    check("a switch that stays is not written", g.root.qol.lootFeed == nil)
    check("a loaded module turns on live, no reload", g.root.pvp.enabled == true and reload == false)
    check("the setup is marked as your own after", g.root.qol.preset == "custom")
    check("what was there before is saved", g.account.setupBefore and g.account.setupBefore.root.qol.xpBar == false
        and g.account.setupBefore.addons.NaowhForever_Professions == false)
    check("player data outside the switches stays", g.root.qol.questRewards[1] == 2)

    reload = g.Setup.Apply({ { id = "training", now = false, on = true } })
    check("a module whose addon is off: it and what it needs are enabled, with a reload", reload
        and g.enabled.NaowhForever_Training and g.enabled.NaowhForever_Professions and g.root.training.enabled == true)
    reload = g.Setup.Apply({ { id = "bis", now = true, on = false } })
    check("a module off: it and what needs it are disabled, with a reload", reload
        and g.enabled.NaowhForever_BiS == false and g.enabled.NaowhForever_DungeonJournal == false)
end

do
    local g = Game()
    g.Setup.Apply({ { id = "xpBar", now = false, on = true }, { id = "pvp", now = false, on = true } })
    g.enabled.NaowhForever_Professions = true
    g.profile = "Other"
    check("restore is for the profile it was saved from", not g.Setup.CanRestore() and not g.Setup.Restore())
    g.profile = "Default"
    local root = g.root
    check("restore puts it back", g.Setup.Restore() and g.root == root and root.qol.xpBar == false
        and root.pvp.enabled == false and root.qol.preset == "minimalist" and root.qol.questRewards[1] == 2)
    check("restore puts the module addons back", g.enabled.NaowhForever_Professions == false)
    check("and is used up", g.account.setupBefore == nil and not g.Setup.CanRestore())
end

local GUID = "Player-4613-006EB819"
local MODULE_IDS = { "pvp", "professions", "training", "bis", "journal", "completo" }

local function ReadAll(g)
    local ctx = g.Setup.Context()
    for _, id in ipairs(MODULE_IDS) do
        ctx.read(id)
        ctx.enabled(id)
    end
    return ctx
end

local function Exercise(g)
    ReadAll(g)
    g.Setup.Apply({ { id = "training", now = false, on = true }, { id = "bis", now = true, on = false } })
    g.Setup.Restore()
end

local function EveryCall(g, test)
    if #g.calls == 0 then return false end
    for _, c in ipairs(g.calls) do
        if not test(c) then return false end
    end
    return true
end

local function ForEveryone(c) return c.args == 0 end
local function ForMe(c) return c.args == 1 and c.who == GUID end

do
    local g = Game()
    Exercise(g)
    check("for every character: no enable, disable or state call names a character", EveryCall(g, ForEveryone))
    g.calls = {}
    g.Setup.ForCharacter(true)
    g.Setup.ForCharacter(false)
    Exercise(g)
    check("this character's mode turned off again: back to every character", EveryCall(g, ForEveryone))
end

do
    local g = Game()
    g.Setup.ForCharacter(true)
    g.others.NaowhForever_Training = true
    g.enabled.NaowhForever_PvP, g.others.NaowhForever_PvP = false, true
    local ctx = ReadAll(g)
    check("this character: a module enabled only for others reads off", ctx.read("training") == false
        and ctx.read("pvp") == false and ctx.enabled("pvp") == false)
    check("and one enabled for it reads by its switch", ctx.read("bis") == true and ctx.enabled("bis") == true)
    local others = CopyTable(g.others)
    local reload = g.Setup.Apply({ { id = "training", now = false, on = true }, { id = "bis", now = true, on = false } })
    check("this character: its modules switch for it", reload and g.enabled.NaowhForever_Training
        and g.enabled.NaowhForever_Professions and g.enabled.NaowhForever_BiS == false
        and g.enabled.NaowhForever_DungeonJournal == false)
    local same = true
    for addon, on in pairs(others) do
        if g.others[addon] ~= on then same = false end
    end
    check("and every other character keeps its own", same)
    check("the backup knows whose it was", g.account.setupBefore.character == GUID
        and g.account.setupBefore.addons.NaowhForever_Training == false)
    check("restore puts back this character's addons", g.Setup.Restore() and g.enabled.NaowhForever_Training == false
        and g.enabled.NaowhForever_Professions == false and g.enabled.NaowhForever_BiS == true
        and g.enabled.NaowhForever_DungeonJournal == true)
    check("every enable, disable and state call named this character", EveryCall(g, ForMe))
    check("one of each was made", (function()
        local seen = {}
        for _, c in ipairs(g.calls) do seen[c.name] = true end
        return seen.EnableAddOn and seen.DisableAddOn and seen.GetAddOnEnableState
    end)())
end

do
    local g = Game()
    g.Setup.ForCharacter(true)
    g.Setup.Apply({ { id = "training", now = false, on = true } })
    g.calls = {}
    g.Setup.ForCharacter(false)
    g.Setup.Restore()
    check("a backup made for this character restores for it, whatever the mode now", EveryCall(g, ForMe)
        and g.enabled.NaowhForever_Training == false)
end

print("PASS setup plan: " .. checks .. " checks")
