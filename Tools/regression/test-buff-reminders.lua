-- Loads NaowhForever_BuffReminders.lua and its data against stubbed aura, bag and group APIs
-- and checks which reminder icons show. Run from the repo root:
-- lua Tools/regression/test-buff-reminders.lua
-- Stands in for a secret value: any field or method use raises, as the client does.
local SECRET = setmetatable({}, { __index = function() error("attempt to index a secret value") end })
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"); f:close()
    return source
end
local DATA = Read("AuraBuffs/NaowhForever_BuffReminderData.lua")
local MODULE = Read("AuraBuffs/NaowhForever_BuffReminders.lua")

-- itemID -> use spell, for the food scan.
local ITEM_SPELLS = { [13931] = 1249513, [2679] = 433, [21023] = 25660 }

local function Recorder(props)
    return setmetatable(props or {}, { __index = function() return function() end end })
end

local function Fixture(opts)
    local settings = opts.settings or {}
    if settings.consumableEntries == nil then
        settings.consumableEntries = {
            { category = "food", itemID = 13931, auras = { 1249520 } },
            { category = "flask", itemID = 13510, auras = { 17626 } },
            { category = "battle", itemID = 13454, auras = { 17539 } },
        }
    end
    local state = {
        now = 1000, secret = false, combat = false, resting = false,
        instance = opts.instance or "none",
        bags = opts.bags or {},                     -- flat list of item IDs
        -- unit -> list of { spellID, seconds left at the start, duration }
        auras = opts.auras or { player = {} },
        group = opts.group,                         -- nil solo, "party" or "raid"
        units = opts.units or {},                   -- unit -> class; player included
        known = opts.known or {},
        reads = 0,
    }
    local timers, frames = {}, {}

    local function NewFrame(template)
        local f
        f = Recorder({ shown = true, events = {}, scripts = {} })
        function f:Show() f.shown = true end
        function f:Hide() f.shown = false end
        function f:SetShown(v) f.shown = v and true or false end
        function f:SetScript(key, fn) f.scripts[key] = fn; if key == "OnEvent" then f.handler = fn end end
        function f:RegisterEvent(e) f.events[e] = true end
        function f:RegisterUnitEvent(e) f.events[e] = true end
        function f:UnregisterAllEvents() f.events = {} end
        function f:CreateTexture()
            local t = Recorder()
            function t:SetTexture(tex) t.texture = tex end
            return t
        end
        if template == "CooldownFrameTemplate" then
            function f:SetCooldown(start, duration) f.cooldown = { start, duration } end
        end
        frames[#frames + 1] = f
        return f
    end

    local S = {}
    function S.Get(k) return settings[k] end
    function S.Set(k, v) settings[k] = v end
    local defaults = {
        enabled = true, food = true, elixirs = true, flasks = true,
        consumablesWhere = "instance", consumablesMinutes = 2,
        onlyIfCarried = true, hideResting = true,
        scrolls = true, scrollsSkipActive = true,
        raidBuffs = false, raidBuffsOwn = true, iconSize = 36,
    }
    for k, v in pairs(defaults) do if settings[k] == nil then settings[k] = v end end

    local ns = {
        AuraBuffSettings = S,
        Apply = function() end,
        ShowRaidReminderAnchorConfig = function() end,
        HideRaidReminderAnchorConfig = function() end,
        Border = function() end, THEME = { bg = {} },
        Solid = function() return Recorder() end,
        Font = function()
            local fs = Recorder()
            function fs:SetText(v) fs.text = v end
            return fs
        end,
        UI = { AttachMover = function() return NewFrame() end },
    }

    local function Count(id)
        local n = 0
        for _, b in ipairs(state.bags) do if b == id then n = n + 1 end end
        return n
    end
    local function Roster()
        local list = {}
        for unit in pairs(state.units) do list[#list + 1] = unit end
        return list
    end
    local env = {
        NUM_BAG_SLOTS = 0,
        UIParent = {},
        GetTime = function() return state.now end,
        InCombatLockdown = function() return state.combat end,
        IsResting = function() return state.resting end,
        IsInInstance = function() return state.instance ~= "none", state.instance end,
        IsInRaid = function() return state.group == "raid" end,
        GetNumGroupMembers = function() return state.group and #Roster() or 0 end,
        UnitClass = function(unit) return "x", state.units[unit] end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsVisible = function() return true end,
        UnitIsUnit = function(a, b) return a == b end,
        C_Secrets = { ShouldAurasBeSecret = function() return state.secret end },
        issecretvalue = function(v) return v == SECRET end,
        C_UnitAuras = {
            GetAuraDataByIndex = function(unit, i)
                if state.secret then error("Auras cannot be accessed when secret while tainted") end
                state.reads = state.reads + 1
                local a = (state.auras[unit] or {})[i]
                if not a then return nil end
                return { spellId = a[1], duration = a[3] or 0,
                    expirationTime = a[2] and 1000 + a[2] or 0 }
            end,
        },
        C_Container = {
            GetContainerNumSlots = function() return #state.bags end,
            GetContainerItemID = function(_, slot) return state.bags[slot] end,
            UseContainerItem = function(bag, slot) state.used = state.bags[slot] end,
        },
        C_Item = {
            GetItemCount = Count,
            GetItemIconByID = function(id) return "item:" .. id end,
            GetItemSpell = function(id)
                if ITEM_SPELLS[id] then return "spell", ITEM_SPELLS[id] end
            end,
        },
        C_Spell = { GetSpellTexture = function(id) return "spell:" .. id end },
        C_SpellBook = { IsSpellKnown = function(id) return state.known[id] == true end },
        C_Timer = {
            After = function(delay, fn) timers[#timers + 1] = { at = state.now + delay, fn = fn } end,
        },
        CreateFrame = function(_, _, _, template) return NewFrame(template) end,
        hooksecurefunc = function(tbl, key, fn)
            local orig = tbl[key]
            tbl[key] = function(...) orig(...); fn(...) end
        end,
    }
    env._G = { NaowhForever = ns }
    setmetatable(env, { __index = _G })
    for _, source in ipairs({ DATA, MODULE }) do
        local chunk
        if setfenv then
            chunk = assert(loadstring(source)); setfenv(chunk, env)
        else
            chunk = assert(load(source, "module", "t", env))
        end
        chunk()
    end

    local t = { state = state, frames = frames }
    function t.Fire(event, ...)
        for _, f in ipairs(frames) do
            if f.events[event] and f.handler then f.handler(f, event, ...) end
        end
    end
    -- Runs every timer due within `seconds`, in order, including ones they add.
    function t.Advance(seconds)
        local stop = state.now + seconds
        while true do
            table.sort(timers, function(a, b) return a.at < b.at end)
            local nextTimer = timers[1]
            if not nextTimer or nextTimer.at > stop then break end
            table.remove(timers, 1)
            state.now = nextTimer.at
            nextTimer.fn()
        end
        state.now = stop
    end
    function t.Set(k, v) S.Set(k, v) end
    function t.Login() t.Fire("PLAYER_LOGIN") end
    -- The textures of the visible reminder icons, left to right, with counts and timers.
    function t.Shown()
        local root
        for _, f in ipairs(frames) do if rawget(f, "mover") then root = f end end
        if not (root and root.shown) then return "" end
        local out = {}
        for _, f in ipairs(frames) do
            if rawget(f, "icon") and rawget(f, "count") and f.shown then
                local s = f.icon.texture
                if rawget(f.count, "text") and f.count.text ~= "" then s = s .. "x" .. f.count.text end
                if rawget(f.timer, "shown") then s = s .. "(t)" end
                out[#out + 1] = s
            end
        end
        return table.concat(out, " ")
    end
    function t.Listening(event)
        for _, f in ipairs(frames) do if f.events[event] and f.handler then return true end end
        return false
    end
    return t
end

local failures = 0
local function Check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(("FAIL %s\n  got:  %s\n  want: %s"):format(label, tostring(got), tostring(want)))
    end
end

-- In a dungeon with buff food, a flask and an elixir carried and nothing up.
do
    local t = Fixture({ instance = "party", bags = { 2679, 13931, 13510, 13454 } })
    t.Login()
    Check("carried consumables", t.Shown(), "item:13931 item:13510 item:13454")
    t.state.auras.player = { { 1249513 }, { 1249520, 1800, 3600 }, { 17626, 7000, 7200 }, { 17539, 3000, 3600 } }
    t.Fire("UNIT_AURA", "player")
    t.Advance(0.5)
    Check("all up", t.Shown(), "")
end

-- Show In: Dungeons & Raids keeps them out of the open world; Everywhere does not.
do
    local t = Fixture({ bags = { 13931, 13510 } })
    t.Login()
    Check("open world, dungeons only", t.Shown(), "")
    t.Set("consumablesWhere", "always")
    Check("everywhere", t.Shown(), "item:13931 item:13510")
    t.Set("consumablesWhere", "raid")
    t.state.instance = "party"
    t.Fire("PLAYER_ENTERING_WORLD")
    t.Advance(0.5)
    Check("raids only, in a dungeon", t.Shown(), "")
    t.state.instance = "raid"
    t.Fire("PLAYER_ENTERING_WORLD")
    t.Advance(0.5)
    Check("raids only, in a raid", t.Shown(), "item:13931 item:13510")
    t.state.resting = true
    t.Fire("PLAYER_UPDATE_RESTING")
    t.Advance(0.5)
    Check("hidden while resting", t.Shown(), "")
end

-- Only If I Carry One: nothing carried shows nothing; off, a generic icon per kind.
do
    local t = Fixture({ instance = "raid", bags = { 2679 } })
    t.Login()
    Check("nothing carried", t.Shown(), "")
    t.Set("onlyIfCarried", false)
    Check("not carried, shown anyway", t.Shown(), "item:13931 item:13510 item:13454")
end

-- Battle and guardian elixirs remain separate, even while one category is active.
do
    local t = Fixture({ instance = "raid", settings = { consumableEntries = {
        { category = "battle", itemID = 13454, auras = { 17539 } },
        { category = "guardian", itemID = 13452, auras = { 17538 } },
    } }, bags = { 13452, 13454 }, auras = { player = { { 17539, 3000, 3600 } } } })
    t.Login()
    Check("guardian missing, battle up", t.Shown(), "item:13452")
end

-- Warn With Minutes Left: a buff under the time shows with its timer; one over it is
-- woken up when it crosses.
do
    local t = Fixture({ instance = "raid", settings = { flasks = false, elixirs = false },
        bags = { 13931 }, auras = { player = { { 1249520, 60, 900 } } } })
    t.Login()
    Check("under two minutes", t.Shown(), "item:13931(t)")
    t.state.auras.player = { { 1249520, 300, 900 } }
    t.Fire("UNIT_AURA", "player")
    t.Advance(0.5)
    Check("five minutes left", t.Shown(), "")
    t.Advance(185)
    Check("woken at two minutes", t.Shown(), "item:13931(t)")
    t.Set("consumablesMinutes", 0)
    Check("0 waits until it is gone", t.Shown(), "")
end

-- Frozen while auras are secret or in combat: no read, the icons keep what they showed.
do
    local t = Fixture({ instance = "raid", settings = { flasks = false, elixirs = false },
        bags = { 13931 } })
    t.Login()
    Check("before the pull", t.Shown(), "item:13931")
    t.state.secret = true
    t.state.auras.player = { { 1249520, 900, 900 } }
    local reads = t.state.reads
    t.Fire("UNIT_AURA", "player")
    t.Fire("UNIT_AURA", SECRET)
    t.Advance(0.5)
    Check("secret: no aura read", t.state.reads, reads)
    Check("secret: frozen", t.Shown(), "item:13931")
    t.state.secret = false
    t.state.combat = true
    t.Fire("BAG_UPDATE_DELAYED")
    t.Advance(0.5)
    Check("combat: no aura read", t.state.reads, reads)
    Check("combat: frozen", t.Shown(), "item:13931")
    t.state.combat = false
    t.Fire("PLAYER_REGEN_ENABLED")
    t.Advance(0.5)
    Check("after combat", t.Shown(), "")
end

-- An empty profile never invents reminders from items in bags.
do
    local t = Fixture({ settings = { consumableEntries = {} }, instance = "raid",
        bags = { 13931, 13510, 13454, 10306 } })
    t.Login()
    Check("empty profile has no automatic reminders", t.Shown(), "")
    Check("empty profile has no aura listener", t.Listening("UNIT_AURA"), false)
    t.Set("consumableEntries", { { category = "scroll", itemID = 10306, auras = { 12176 } } })
    Check("manual scroll added", t.Shown(), "item:10306")
    t.state.auras.player = { { 12176, 1000, 1800 } }
    t.Fire("UNIT_AURA", "player"); t.Advance(0.5)
    Check("manual scroll buff suppresses reminder", t.Shown(), "")
    t.Set("consumableEntries", {})
    Check("removed configuration stays empty", t.Shown(), "")
end

-- Raid buffs: how many are missing each buff you can cast, or any class in the group can.
do
    local t = Fixture({ settings = { raidBuffs = true, scrolls = false },
        group = "party", units = { player = "MAGE", party1 = "WARRIOR", party2 = "PRIEST" },
        known = { [1460] = true },
        auras = { player = {}, party1 = {}, party2 = { { 10938, 3000, 3600 } } } })
    t.Login()
    Check("own: arcane intellect, the warrior skipped", t.Shown(), "spell:10157x2")
    t.Set("raidBuffsOwn", false)
    Check("any class: fortitude too, not divine spirit", t.Shown(), "spell:10157x2 spell:10938x2")
    t.state.auras.party1 = { { 21564, 3000, 3600 } }
    t.state.auras.player = { { 10938, 3000, 3600 }, { 23028, 3000, 3600 } }
    t.state.auras.party2 = { { 10938, 3000, 3600 }, { 10157, 3000, 3600 } }
    t.Fire("UNIT_AURA", "party1")
    t.Advance(0.5)
    Check("everyone buffed", t.Shown(), "")
end

-- Disabled means inactive; Unlock Mode shows a preview to drag.
do
    local t = Fixture({ settings = { enabled = false }, instance = "raid", bags = { 13931 } })
    t.Login()
    Check("disabled: nothing shown", t.Shown(), "")
    Check("disabled: no aura events", t.Listening("UNIT_AURA"), false)
    t.Set("enabled", true)
    Check("enabled: listening", t.Listening("UNIT_AURA"), true)
    Check("enabled: shown", t.Shown(), "item:13931")
end

-- Hover menus offer only carried configured alternatives and validate at click time.
do
    local t = Fixture({ instance = "raid", bags = { 111, 222, 999 }, settings = { consumableEntries = {
        { category = "food", itemID = 111, auras = { 11 } },
        { category = "food", itemID = 222, auras = { 22 } },
        { category = "food", itemID = 333, auras = { 33 } },
    } } })
    t.Login()
    local cell
    for _, f in ipairs(t.frames) do if rawget(f, "items") then cell = f end end
    cell.scripts.OnEnter(cell)
    local popup
    for _, f in ipairs(t.frames) do if rawget(f, "owner") == cell then popup = f end end
    Check("only carried configured choices", #popup.buttons, 2)
    t.state.bags = { 999, 111 }
    popup.buttons[2].scripts.OnClick(popup.buttons[2])
    Check("removed item cannot be used", t.state.used, nil)
    cell.scripts.OnEnter(cell)
    popup.buttons[1].scripts.OnClick(popup.buttons[1])
    Check("moved item found in current bag slot", t.state.used, 111)
    cell.scripts.OnEnter(cell)
    t.Fire("PLAYER_REGEN_DISABLED")
    Check("combat entry closes hover menu", popup.shown, false)
    t.state.used = nil; t.state.combat = true
    popup.buttons[1].scripts.OnClick(popup.buttons[1])
    Check("combat prevents consumption", t.state.used, nil)
end

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("test-buff-reminders: all passed")
