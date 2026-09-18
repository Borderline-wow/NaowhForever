-- Trash callouts and the real cast.
--
-- A trash rule is a prediction: it fires seconds before the ability goes out, which is the
-- whole reason it is useful and also the reason it can never say who the ability is on. At
-- the moment it shows, nobody is casting and the client has nothing to answer with. The
-- cast arrives later, on a nameplate unit, and that is the only moment the question can be
-- asked at all. This suite covers the second look.
local f = assert(io.open(arg[1] or "NaowhUI_SmartReminders.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local CHUNK = table.concat({
    Slice("function ns.CastNamesATarget(", "-- Previews one custom line"),
    Slice("function ns.RepeatIntegrationReminderOnCast(", "-- The editor"),
    Slice("function ns.RefreshCastWatch(", "-- Cast end is SUCCEEDED only"),
    Slice("function ns.OnBossCast(", "-- Which single source drives callouts"),
}, "\n")

local function Rule()
    return { name = "Rule", trigger = { type = "exboss", spellID = 111, mapID = 0, timeleft = 5 },
        display = { type = "icon", text = "Use a defensive", dur = 3, sound = "none" } }
end

local function Fixture()
    local e = { db = { castTargetTrash = true }, shown = {},
        targets = {}, eligible = true, names = true, watcher = {} }
    local env = {
        TRDB = function() return e.db end,
        CustomRemindersAllowed = function() return e.allowed ~= false end,
        CustomRemindersTable = function() return e.encounterSet end,
        currentEncounter = nil,
        customCounters = {},
        ParseCounterCondition = function() return nil end,
        CheckCounterCondition = function() return true end,
        AppendLog = function() end,
        ActivateCustomReminder = function(r) e.authored = r; return true end,
        UnitShouldDisplaySpellTargetName = function(unit)
            e.askedAbout = unit
            return e.names
        end,
        ShowOnAlert = function(opts)
            if e.refuse then return false end
            e.shown[#e.shown + 1] = opts
            return true
        end,
        CreateFrame = function()
            local w = e.watcher
            w.registered = {}
            w.SetScript = function() end
            w.RegisterEvent = function(_, ev) w.registered[ev] = true end
            w.UnregisterAllEvents = function() w.registered = {}; w.off = true end
            return w
        end,
    }
    e.ns = {
        Integrations = {
            Eligible = function() return e.eligible end,
            CastWatchRules = function() return e.index end,
        },
        ShowCastTargetOn = function(unit) e.targets[#e.targets + 1] = unit; return true end,
    }
    setmetatable(env, { __index = _G })
    local chunk = assert(loadstring("local ns = ...\n" .. CHUNK))
    setfenv(chunk, env)
    chunk(e.ns)
    e.env = env
    -- One trash rule on spell 111, the way RefreshCastWatch would have indexed it.
    e.rule = Rule()
    e.index = { [111] = { { uid = "i1", r = e.rule } } }
    e.ns.RefreshCastWatch()
    return e
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("the warning is repeated when the ability is actually cast, and then named", function()
    local e = Fixture()
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate3", 111)
    assert(#e.shown == 1, "the callout comes back up for the cast")
    assert(e.shown[1].resolveFrom == e.rule)
    assert(e.shown[1].text == "Use a defensive" and e.shown[1].dur == 3)
    assert(e.targets[1] == "nameplate3", "and the name is written on top of it")
    assert(e.askedAbout == "nameplate3")
end)

Case("a boss unit works the same as a nameplate", function()
    local e = Fixture()
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "boss1", 111)
    assert(#e.shown == 1 and e.targets[1] == "boss1")
end)

Case("a cast by anyone in the group is not a boss cast", function()
    local e = Fixture()
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "party2", 111)
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "player", 111)
    assert(#e.shown == 0 and #e.targets == 0)
end)

Case("the repeat is silent, because the warning already spoke", function()
    local e = Fixture()
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(e.shown[1].audio == nil, "saying it twice is worse than saying it once")
end)

Case("a rule may ask for the sound again anyway", function()
    local e = Fixture()
    e.rule.display.castAudio = true
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(e.shown[1].audio == e.rule.display)
end)

Case("cast end is not a moment at which anybody is casting", function()
    local e = Fixture()
    e.ns.OnBossCast("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", 111)
    assert(#e.shown == 0 and #e.targets == 0, "the cast is over; there is nobody to name")
end)

Case("an ability that names nobody is not repeated at all", function()
    local e = Fixture()
    e.names = false
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(#e.shown == 0, "a repeat carrying no name is just the same warning twice")
    assert(#e.targets == 0)
end)

Case("trash targeting off means the repeat has nothing to add", function()
    local e = Fixture()
    e.db.castTargetTrash = nil
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(#e.shown == 0 and e.askedAbout == nil, "and the client is not asked either")
end)

Case("the boss switch does not speak for trash", function()
    -- The two sources are asked for on their own pages. Turning boss casts on says
    -- nothing about whether trash rules should start repeating.
    local e = Fixture()
    e.db.castTargetTrash, e.db.castTargetBoss = nil, true
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(#e.shown == 0 and #e.targets == 0)
end)

Case("a rule that turned the repeat off is left alone", function()
    local e = Fixture()
    e.rule.display.castRepeat = false
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(#e.shown == 0 and #e.targets == 0)
end)

Case("eligibility is rechecked at the cast, not trusted from the index", function()
    local e = Fixture()
    -- The healer opt-out moves without zoning or an edit, so nothing rebuilds the index.
    e.eligible = false
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(#e.shown == 0 and #e.targets == 0)
end)

Case("a refused callout does not get a name written onto whatever is showing", function()
    local e = Fixture()
    e.refuse = true
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(#e.targets == 0, "the name would have landed on the previous alert")
end)

Case("the addon being switched off stops it before anything is asked", function()
    local e = Fixture()
    e.allowed = false
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(#e.shown == 0 and e.askedAbout == nil)
end)

Case("a spell nobody watches is ignored", function()
    local e = Fixture()
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 999)
    assert(#e.shown == 0)
end)

Case("the watcher never registers while trash targeting is off", function()
    -- The index is the gate: with no trash rules in it and no encounter, there is nothing
    -- waiting on a cast, so the events come off entirely rather than firing for nothing.
    local e = Fixture()
    e.db.castTargetTrash = nil
    e.ns.RefreshCastWatch()
    assert(e.watcher.off and next(e.watcher.registered) == nil)
    assert(e.ns.watchedCasts[111] == nil)
end)

Case("trash turns the watcher on where there is no encounter at all", function()
    local e = Fixture()
    assert(e.env.currentEncounter == nil, "this is the case boss reminders never covered")
    assert(e.watcher.registered.UNIT_SPELLCAST_START, "the events have to be live for trash")
    assert(e.ns.watchedCasts[111].trashcast[1].r == e.rule)

    -- And off again once the last rule goes, rather than listening to every cast forever.
    e.index = nil
    e.ns.RefreshCastWatch()
    assert(e.watcher.off and next(e.watcher.registered) == nil)
    assert(e.ns.watchedCasts[111] == nil)
end)

Case("an authored cast reminder on the same spell still fires", function()
    local e = Fixture()
    e.ns.watchedCasts[111].caststart = { { uid = "c1", r = { trigger = {} } } }
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 111)
    assert(e.authored, "the authored reminder is not swallowed by the trash branch")
    assert(#e.shown == 1, "and the trash repeat still drew first")
    assert(#e.targets == 2, "each asks for the name after drawing, so the last one wins")
end)

-- The half that survives the secret. A boss cast can never be identified: its spell id is
-- secret for any unit that is not the player or their pet, so nothing can match it to the
-- reminder that warned about it. Whether it names somebody is plain, though, and the alert
-- is already on screen, so the name goes on without the two ever being matched.
Case("a boss cast names the target on the alert already showing", function()
    local e = Fixture()
    e.db.castTargetBoss = true
    e.env.shownForEvent = "authored"
    -- 999 is watched by nothing, and nothing could watch it. That is the point.
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "boss1", 999)
    assert(#e.targets == 1 and e.targets[1] == "boss1")
end)

Case("with no alert up there is nothing to write on", function()
    local e = Fixture()
    e.db.castTargetBoss = true
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "boss1", 999)
    assert(#e.targets == 0)
end)

Case("a cast naming nobody leaves the alert as it is", function()
    local e = Fixture()
    e.db.castTargetBoss, e.names = true, false
    e.env.shownForEvent = "authored"
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "boss1", 999)
    assert(#e.targets == 0, "clearing would drop a name an earlier cast put there")
end)

Case("trash casts are not decorated on a guess", function()
    -- A pack has several casters and no way to say which one the alert is about.
    local e = Fixture()
    e.db.castTargetBoss = true
    e.env.shownForEvent = "authored"
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "nameplate1", 999)
    assert(#e.targets == 0)
end)

Case("the boss switch off means no name", function()
    local e = Fixture()
    e.env.shownForEvent = "authored"
    e.ns.OnBossCast("UNIT_SPELLCAST_START", "boss1", 999)
    assert(#e.targets == 0)
end)

Case("the watcher arms for the name alone, with nothing indexed", function()
    local e = Fixture()
    e.index = nil
    e.env.currentEncounter = 3456
    e.db.castTargetBoss = true
    e.ns.RefreshCastWatch()
    assert(e.watcher.registered.UNIT_SPELLCAST_START,
        "there is nothing to index, so the index cannot be the gate here")
    assert(e.ns.watchedCasts and next(e.ns.watchedCasts) == nil)
end)

print(count .. " trash cast target regressions passed")
