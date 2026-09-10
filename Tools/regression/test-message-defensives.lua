local f = assert(io.open(arg[1] or "NaowhUI_SmartReminders.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end
local function Fixture()
    local e = { now = 0, timers = {}, calls = 0, builds = 0, allowed = true,
        set = { one = { defensive = true, specID = 250, preset = "mobility", dur = 7,
            trigger = { type = "bwmsg", spellID = 123, delay = "2" } } } }
    local env = { ns = {}, specID = 250, currentEncounter = 3202,
        hasCustomReminders = true, customCounters = {}, canSelect = true,
        frame = { Show = function() e.shown = true end },
        GetTime = function() return e.now end,
        TRDB = function() return { enabled = true, coveredSkip = false } end,
        CustomRemindersTable = function(_, enc) return enc == 3202 and e.set end,
        CustomRemindersAllowed = function() return e.allowed end,
        BossAllowed = function() return e.allowed end,
        InEncounter = function() return true end,
        ShouldRun = function() return false end, -- no active default preset required
        RebuildSlots = function(_, _, preset) e.builds = e.builds + 1; e.preset = preset; return true end,
        ApplyPriorityAlpha = function() end, ClearTankGate = function() end,
        SpeakCallout = function() e.calls = e.calls + 1 end,
        HideReminder = function() e.shown = false end, DEFAULTS = { lingerSec = 3 },
        AppendLog = function() end,
        ParseCounterCondition = function(v) return tonumber(v) end,
        CheckCounterCondition = function(want, count) return want == count end,
        C_Timer = { NewTimer = function(delay, fn)
            local t = { at = e.now + delay, fn = fn, Cancel = function(t) t.cancelled = true end }
            e.timers[#e.timers + 1] = t; return t
        end },
    }
    env.ns.BindingForBossModKey = function() return { mode = "custom" } end
    setmetatable(env, { __index = _G })
    local code = Slice("local function ParseDelayList(", "local function ParseCounterCondition(")
        .. Slice("function ns.DisplayReminder(", "-- The editor's Preview button")
        .. Slice("ns.trackedReminderTimers = {}", "-- Boss cast triggers.")
        .. "\nlocal bwActiveMod\n"
        .. Slice("function ns.HasMessageDefensive(", "-- barIdentity is whatever")
        .. Slice("local function FireBigWigsAbility(", "-- Setup's per-ability Test button.")
        .. Slice("function ns.HandleBigWigsAbility(", "-- A bar that stops or pauses")
        .. "\nreturn CheckBossModMessage"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    e.message = chunk(); e.ns = env.ns; e.env = env
    function e:advance(at)
        while true do
            local nextTimer
            for _, t in ipairs(self.timers) do
                if not t.cancelled and t.at <= at and (not nextTimer or t.at < nextTimer.at) then nextTimer = t end
            end
            if not nextTimer then break end
            nextTimer.cancelled = true; self.now = nextTimer.at; nextTimer.fn()
        end
        self.now = at
    end
    return e
end
local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end
Case("bar alone never schedules opted-in ability", function()
    local e = Fixture(); e.ns.HandleBigWigsAbility(123, 30, "bar")
    e:advance(40); assert(e.calls == 0 and #e.timers == 0)
end)
Case("message delay uses shared defensive display and selected preset", function()
    local e = Fixture(); e.message("BW", 123); e:advance(1.9); assert(e.calls == 0)
    e:advance(2); assert(e.calls == 1 and e.shown and e.preset == "mobility")
    e:advance(8.9); assert(e.shown); e:advance(9); assert(not e.shown)
end)
Case("DBM messages use the same delay", function()
    local e = Fixture(); e.message("DBM", 123); e:advance(2); assert(e.calls == 1)
end)
Case("no matching message means no call", function()
    local e = Fixture(); e.message("BW", 456); e:advance(20); assert(e.calls == 0)
end)
Case("encounter reset cancels pending message delay", function()
    local e = Fixture(); e.message("BW", 123); e.ns.CancelTrackedReminderTimers()
    e:advance(20); assert(e.calls == 0)
end)
Case("disabling before delay expires prevents display", function()
    local e = Fixture(); e.message("BW", 123); e.set.one.enabled = false
    e:advance(20); assert(e.calls == 0)
end)
Case("master gating is rechecked at delayed fire", function()
    local e = Fixture(); e.message("BW", 123); e.allowed = false
    e:advance(20); assert(e.calls == 0)
end)
Case("another spec neither suppresses bars nor fires the reminder", function()
    local e = Fixture(); e.set.one.specID = 581
    assert(not e.ns.HasMessageDefensive(3202, 123))
    e.message("BW", 123); e:advance(20); assert(e.calls == 0)
end)
Case("existing bindings keep their route when opt-in is disabled", function()
    local e = Fixture(); e.set.one.enabled = false
    assert(not e.ns.HasMessageDefensive(3202, 123))
    assert(not e.ns.HasMessageDefensive(3202, 456))
end)
Case("both boss mods do not double-fire a message", function()
    local e = Fixture(); e.message("BW", 123); e.message("DBM", 123)
    e:advance(2); assert(e.calls == 1)
end)
Case("message occurrence counter is applied before delay", function()
    local e = Fixture(); e.set.one.trigger.counter = "2"
    e.message("BW", 123); e:advance(3); assert(e.calls == 0)
    e.message("BW", 123); e:advance(5); assert(e.calls == 1)
end)
Case("blank delay fires immediately", function()
    local e = Fixture(); e.set.one.trigger.delay = nil; e.message("BW", 123)
    assert(e.calls == 1)
end)
Case("unrelated runtime refresh preserves pending message delay", function()
    local e = Fixture(); e.message("BW", 123)
    e.env.RebuildCastMap = function() end
    e.env.UpdateEventRegistration = function() end
    e.env.UpdatePreview = function() end
    e.env.RefreshCustomRemindersFlag = function() end
    local first = assert(source:find("function ns.RefreshRuntime()", 1, true))
    local last = assert(source:find("\nend", first, true))
    local chunk = assert(loadstring(source:sub(first, last+3))); setfenv(chunk,e.env); chunk()
    e.ns.RefreshRuntime(); e:advance(2); assert(e.calls == 1)
end)
for _, change in ipairs({ "delete", "replace", "disable", "profile" }) do
    Case("pending reminder cancelled after " .. change, function()
        local e = Fixture(); e.message("BW",123)
        if change == "delete" then e.set.one = nil
        elseif change == "replace" then e.set.one = { enabled = true }
        elseif change == "disable" then e.set.one.enabled = false
        else e.set = {} end
        e.ns.PruneCustomReminderTimers(); e:advance(3)
        assert(e.calls == 0 and #e.ns.trackedReminderTimers == 0)
    end)
end
Case("preset in use cannot be deleted even with a disabled reminder", function()
    local presets = { mobility = {}, other = {} }
    local reminder = { preset = "mobility", specID = 250, enabled = false, name = "Stomp" }
    local db = { customReminders = { ["3202"] = { one = reminder } } }
    local env = { ns = { Print = function() end }, PresetsTable = function() return presets end,
        TRDB = function() return db end, ActivePresetKey = function() end }
    setmetatable(env, { __index = _G })
    local chunk = assert(loadstring(Slice("function ns.DeletePreset(", "local function UserList(")))
    setfenv(chunk, env); chunk()
    assert(env.ns.DeletePreset(250, "mobility") == false and presets.mobility)
    reminder.preset = "other"
    assert(env.ns.DeletePreset(250, "mobility") == true and not presets.mobility)
end)
Case("opening message waits for encounter setup once", function()
    local e = Fixture()
    e.env.C_Timer.After = function(delay, fn) e.env.C_Timer.NewTimer(delay, fn) end
    e.env.currentEncounter, e.env.hasCustomReminders = nil, false
    e.message("BW", 123, 3202)
    e.env.currentEncounter, e.env.hasCustomReminders = 3202, true
    e:advance(2); assert(e.calls == 1)
end)
Case("opening message cannot leak into another encounter", function()
    local e = Fixture()
    e.env.C_Timer.After = function(delay, fn) e.env.C_Timer.NewTimer(delay, fn) end
    e.env.currentEncounter, e.env.hasCustomReminders = nil, false
    e.message("BW", 123, 3202)
    e.env.currentEncounter, e.env.hasCustomReminders = 999, true
    e:advance(20); assert(e.calls == 0)
end)
Case("opening message fires when progress API lags encounter start", function()
    local e = Fixture(); e.set.one.trigger.delay = nil
    e.env.InEncounter = function() return false end
    e.message("BW", 123, 3202)
    assert(e.calls == 1)
end)
Case("defensive cannot fire after tracked encounter ends", function()
    local e = Fixture(); e.env.currentEncounter = nil
    e.env.InEncounter = function() return true end
    e.ns.FireMessageDefensive(e.set.one)
    assert(e.calls == 0)
end)
print(count .. " message defensive regressions passed")
