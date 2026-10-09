-- Tailor my setup against thousands of random players: random answers, characters, switches,
-- module addons enabled, loaded or not, presets and review corrections, on the real setup engine
-- and the options window's real module code (Core/Options/Window.lua). Every plan is checked
-- for its rules, applied, reloaded, planned again and restored. Half the runs set up one character
-- (an alt's own setup): every enable, disable and state call names its GUID, other characters'
-- addons never change; the other half never names a character. From the repo root:
-- lua5.1 Tools/regression/test-setup-fuzz.lua [seed] [runs]
local SEED, RUNS = tonumber(arg[1]) or 20261008, tonumber(arg[2]) or 3000
local GUID = "Player-4613-006EB819"
local checks, run, where = 0, 0, ""
local function check(label, ok)
    if not ok then error(("run %d (seed %d)%s: %s"):format(run, SEED, where, label), 2) end
    checks = checks + 1
end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local window = Read("Core/Options/Modules.lua")
local function Slice(source, a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end
local MODULE_LIST = Slice(window, "local MODULES = {", "\n}\n") .. "\n}\n"
local MODULE_NAMES = assert(window:match("\n(local QOL = .-\n)\nlocal SYSTEM_PAGES"), "Modules named values")
local MODULE_CODE = MODULE_NAMES .. MODULE_LIST
    .. Slice(window, "local function DisplayName(mod)", "local function SetModuleOn(mod, on)")

local MODULES = assert(loadstring(MODULE_LIST .. "\nreturn MODULES"))()
local OWNED = {}
local function Own(addon, path)
    local dir = path:match("^(.*/)") or ""
    if path:match("%.xml$") then
        for kind, file in Read(path):gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
            if kind == "Script" or kind == "Include" then Own(addon, dir .. file:gsub("\\", "/")) end
        end
    elseif path:match("%.lua$") then
        for name in Read(path):gmatch("\nns%.(%w+Settings)%s*=") do OWNED[name] = addon end
    end
end
for _, mod in ipairs(MODULES) do
    if mod.addon then
        for line in Read(mod.addon .. "/" .. mod.addon .. ".toc"):gmatch("[^\n]+") do
            local file = line:match("^%s*(.-)%s*$")
            if not file:match("^#") and file:match("%.%a+$") then
                Own(mod.addon, mod.addon .. "/" .. file:gsub("\\", "/"))
            end
        end
    end
end

local Setup
do
    local env = setmetatable({ ns = {}, CopyTable = CopyTable }, { __index = _G })
    env._G = { NaowhForever = env.ns }
    local chunk = assert(loadfile("Core/Onboarding/Setup.lua"))
    setfenv(chunk, env)
    chunk()
    Setup = env.ns.Setup
end

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local THEME_AT = {}
for i, theme in ipairs(Setup.THEMES) do THEME_AT[theme] = i end
local PURIST = {}
for _, id in ipairs(Setup.PURIST) do PURIST[id] = true end

local function Chance(p) return math.random() < p end
local function Pick(list) return list[math.random(#list)] end

local function Answers()
    local answers = {}
    for _, q in ipairs(Setup.QUESTIONS) do
        if q.one then
            if Chance(0.85) then answers[q.id] = Pick(q.answers)[1] end
        elseif Chance(0.9) then
            local picked = {}
            if q.id == "addons" and Chance(0.2) then
                picked.none = true
            else
                for _, a in ipairs(q.answers) do
                    if not a.none and Chance(0.35) then picked[a[1]] = true end
                end
            end
            answers[q.id] = picked
        end
    end
    return answers
end

local function Store(world, key)
    local s = { key = key }
    function s.Get(k)
        local values = world.root[key]
        local v = type(values) == "table" and values[k]
        if v == nil then v = world.defaults[key][k] end
        return v
    end
    function s.Set(k, v)
        if type(world.root[key]) ~= "table" then world.root[key] = {} end
        world.root[key][k] = v
    end
    function s.Default(k) return world.defaults[key][k] end
    return s
end

local function Value(item)
    if item.off then return Chance(0.3) and item.off or "aim" end
    return Chance(0.5)
end

local function World()
    local world = { root = {}, defaults = {}, account = {}, enabled = {}, loaded = {}, found = {} }
    local ns = { PRESETS = {}, L = function(s) return s end }
    world.ns = ns
    local stores = {}
    for _, item in pairs(Setup.ITEMS) do
        if item.store then stores[item.store] = true end
    end
    for _, mod in ipairs(MODULES) do
        if mod.settings then stores[mod.settings] = true end
        if mod.addon then
            world.enabled[mod.addon] = Chance(0.7)
            world.loaded[mod.addon] = world.enabled[mod.addon] and Chance(0.9)
        end
    end
    local dbOf = {}
    for _, mod in ipairs(MODULES) do
        for _, item in pairs(Setup.ITEMS) do
            if mod.addon and item.addon == mod.addon and mod.settings then dbOf[mod.settings] = item.db end
        end
    end
    for name in pairs(stores) do
        local key = dbOf[name] or name:gsub("Settings$", ""):lower()
        world.defaults[key] = {}
        world.root[key] = {}
        world[name] = Store(world, key)
    end
    for _, item in pairs(Setup.ITEMS) do
        local key = (item.store or "") ~= "" and world[item.store].key
        if key then
            world.defaults[key][item.key] = item.off and "aim" or OWNED[item.store] == nil and Value(item) or false
            if Chance(0.4) then world.root[key][item.key] = Value(item) end
            for _, other in ipairs(item.also or {}) do world.defaults[key][other] = false end
            for k in pairs(item.set or {}) do world.defaults[key][k] = "ask" end
        end
    end
    for _, mod in ipairs(MODULES) do
        if mod.settings then
            local key = world[mod.settings].key
            local switch = mod.enabledKey or "enabled"
            world.defaults[key][switch] = Chance(0.5)
            if Chance(0.5) then world.root[key][switch] = Chance(0.6) end
        end
    end
    world.root.qol = world.root.qol or {}
    world.root.qol.preset = Pick({ "minimalist", "recommended", "custom" })
    for _, preset in ipairs({ "minimalist", "recommended" }) do
        local profile = {}
        for _, item in pairs(Setup.ITEMS) do
            local db = item.db or (item.store and world[item.store].key)
            if db and Chance(0.7) then
                profile[db] = profile[db] or {}
                profile[db][item.key] = Value(item)
            end
        end
        ns.PRESETS[preset] = { name = preset, profile = profile }
    end
    for _, addons in pairs(Setup.DETECT) do
        for _, addon in ipairs(addons) do
            if Chance(0.15) then world.found[addon[1]] = true end
        end
    end
    world.class = Pick(CLASSES)
    ns.QoLSettings = world.QoLSettings
    ns.SettingsRoot = function() return world.root end
    ns.AccountSettings = function() return world.account end
    ns.ActiveProfileName = function() return "Default" end
    ns.DB = function() return world.root end
    world.Session = function()
        for name, owner in pairs(OWNED) do ns[name] = world.loaded[owner] and world[name] or nil end
        for name in pairs(stores) do
            if not OWNED[name] then ns[name] = world[name] end
        end
    end
    world.Session()
    world.character = Chance(0.5)
    world.others = {}
    for addon, on in pairs(world.enabled) do
        world.others[addon] = on
        if world.character then world.others[addon] = Chance(0.7) end
    end
    local C_AddOns = {
        GetAddOnEnableState = function(a, who)
            if who then return world.enabled[a] and 2 or 0 end
            if world.enabled[a] and world.others[a] then return 2 end
            return (world.enabled[a] or world.others[a]) and 1 or 0
        end,
        EnableAddOn = function(a, who)
            world.enabled[a] = true
            if not who then world.others[a] = true end
        end,
        DisableAddOn = function(a, who)
            world.enabled[a] = false
            if not who then world.others[a] = false end
        end,
        IsAddOnLoaded = function(a) return world.found[a] == true or world.loaded[a] == true end,
    }
    local env = setmetatable({ ns = ns, C_AddOns = C_AddOns, unpack = unpack }, { __index = _G })
    local chunk = assert(loadstring(MODULE_CODE))
    setfenv(chunk, env)
    chunk()
    local function Watched(name)
        return function(a, ...)
            local count, who = select("#", ...), ...
            if world.character then
                check(name .. " names this character", count == 1 and who == GUID)
            else
                check(name .. " is for every character", count == 0)
            end
            return C_AddOns[name](a, ...)
        end
    end
    local watched = { GetAddOnEnableState = Watched("GetAddOnEnableState"), EnableAddOn = Watched("EnableAddOn"),
        DisableAddOn = Watched("DisableAddOn"), IsAddOnLoaded = C_AddOns.IsAddOnLoaded }
    local sEnv = setmetatable({ ns = ns, CopyTable = CopyTable, C_AddOns = watched,
        UnitClass = function() return world.class, world.class end,
        UnitGUID = function(unit) return unit == "player" and GUID or nil end }, { __index = _G })
    sEnv._G = { NaowhForever = ns }
    local setup = assert(loadfile("Core/Onboarding/Setup.lua"))
    setfenv(setup, sEnv)
    setup()
    world.Setup = ns.Setup
    world.Setup.ForCharacter(world.character)
    world.Reload = function()
        for _, mod in ipairs(MODULES) do
            if mod.addon then world.loaded[mod.addon] = world.enabled[mod.addon] end
        end
        world.Session()
    end
    return world
end

local function ByID(entries)
    local by = {}
    for _, e in ipairs(entries) do by[e.id] = e end
    return by
end

local function LinksHold(entries)
    local by = ByID(entries)
    for _, e in ipairs(entries) do
        for _, need in ipairs(e.on and e.needs or {}) do
            if by[need] and not by[need].on then return false, e.id .. " is on without " .. need end
        end
    end
    return true
end

local function Expected(entries)
    local by, want = ByID(entries), {}
    local function Add(id)
        if want[id] or not by[id] then return end
        want[id] = true
        for _, need in ipairs(by[id].needs or {}) do Add(need) end
    end
    for id, item in pairs(Setup.ITEMS) do
        if PURIST[id] or item.quiet then Add(id) end
    end
    return want
end

local function ModuleOf(addon)
    for id, item in pairs(Setup.ITEMS) do
        if item.addon == addon then return id end
    end
end

local function CheckPlan(world, answers, entries)
    local by, seen = ByID(entries), {}
    local ctx = world.Setup.Context()
    for _, e in ipairs(entries) do
        check("each switch listed once: " .. e.id, not seen[e.id])
        seen[e.id] = true
        check(e.id .. ": in a theme, in order", THEME_AT[e.theme] ~= nil)
        check(e.id .. ": says why", type(e.why) == "string" and e.why ~= "")
        check(e.id .. ": on, now and suggest are yes or no", type(e.on) == "boolean" and type(e.now) == "boolean"
            and type(e.suggest) == "boolean")
    end
    for id in pairs(Setup.ITEMS) do
        check(id .. ": listed exactly when it is here", (by[id] ~= nil) == (ctx.read(id) ~= nil))
    end
    for i = 2, #entries do
        check("sorted by theme", THEME_AT[entries[i - 1].theme] <= THEME_AT[entries[i].theme])
    end
    local ok, why = LinksHold(entries)
    check("nothing on without what it needs: " .. tostring(why), ok)
    local purist = answers.amount == "purist"
    if purist then
        local want = Expected(entries)
        for _, e in ipairs(entries) do
            check("a purist gets exactly the purist list: " .. e.id, e.on == (want[e.id] == true) and not e.mine)
        end
    else
        for _, id in ipairs(Setup.CORE) do
            check("the core is suggested: " .. id, not by[id] or by[id].suggest)
        end
        if type(answers.addons) == "table" and answers.addons.guide then
            for _, id in ipairs(Setup.OVERLAP.guide.off) do
                check("a quest guide keeps " .. id .. " off", not by[id] or not by[id].suggest)
            end
        end
    end
    local on, off, stay = world.Setup.Counts(entries)
    check("the counts add up", on + off + stay == #entries)
end

local function CheckApplied(world, entries)
    local mods = {}
    for _, mod in ipairs(world.ns.ModuleAddons()) do mods[mod.addon] = mod end
    for _, e in ipairs(entries) do
        local item = Setup.ITEMS[e.id]
        if item.addon then
            check(e.id .. ": its addon enabled exactly when on", world.enabled[item.addon] == e.on)
            if e.on then
                local mod = mods[item.addon]
                local switch = mod.store and mod.store.Get(mod.key) or world.root[item.db] and world.root[item.db][item.key]
                check(e.id .. ": and its switch on", switch == true)
            end
        else
            check(e.id .. ": its switch as planned", world.Setup.Context().read(e.id) == e.on)
        end
    end
    for _, mod in ipairs(MODULES) do
        if mod.addon and world.enabled[mod.addon] then
            for _, need in ipairs(mod.needs or {}) do
                check(mod.addon .. " enabled with what it needs, " .. need, world.enabled[need])
            end
        end
    end
end

math.randomseed(SEED)
local covered = {}
for _, mod in ipairs(MODULES) do
    if mod.addon then
        covered[mod.addon] = ModuleOf(mod.addon) ~= nil
        check("every module addon is in the setup: " .. mod.addon, covered[mod.addon])
    end
end
for _, mod in ipairs(MODULES) do
    local id = mod.addon and ModuleOf(mod.addon)
    if id then
        check(id .. ": the setup turns on the switch the module reads", Setup.ITEMS[id].key == (mod.enabledKey or "enabled")
            and (mod.settings == nil or Setup.ITEMS[id].db ~= nil))
    end
end

local flips, reloads, characterRuns = 0, 0, 0
for i = 1, RUNS do
    run = i
    local world = World()
    local answers = Answers()
    where = " amount=" .. tostring(answers.amount) .. " class=" .. world.class
        .. (world.character and " for this character" or "")
    local entries = world.Setup.Plan(answers, world.Setup.Context())
    CheckPlan(world, answers, entries)
    local flipped = Chance(0.4)
    if flipped then
        for _ = 1, math.random(1, 6) do
            local e = Pick(entries)
            local on = not e.on
            world.Setup.Toggle(entries, e.id, on)
            flips = flips + 1
            check("a flipped switch takes: " .. e.id, ByID(entries)[e.id].on == on)
            local ok, why = LinksHold(entries)
            check("a flip keeps what it needs, or takes what needs it: " .. tostring(why), ok)
        end
    end
    local before = { root = CopyTable(world.root), enabled = CopyTable(world.enabled), others = CopyTable(world.others) }
    local needsReload = world.Setup.NeedsReload(entries)
    local reload = world.Setup.Apply(entries)
    if reload then reloads = reloads + 1 end
    local moved = {}
    for _, e in ipairs(entries) do
        local addon = Setup.ITEMS[e.id].addon
        if addon and world.Setup.Differs(e) then
            local links = {}
            for _, l in ipairs(world.ns.LinkedAddons(addon, e.on)) do
                links[#links + 1] = l .. "=" .. tostring(world.loaded[l])
            end
            moved[#moved + 1] = ("%s %s->%s loaded=%s [%s]"):format(e.id, tostring(e.now), tostring(e.on),
                tostring(e.loaded), table.concat(links, " "))
        end
    end
    check("the button said whether it reloads: " .. table.concat(moved, ", "), reload == needsReload)
    check("applied: your setup is marked as your own", world.root.qol.preset == "custom")
    for _, e in ipairs(entries) do
        local pick = Setup.ITEMS[e.id].pick
        if pick then
            check(e.id .. ": picked on, the pick is left for its panel, as a plain QoL key", (world.root.qol[pick] == true) == e.on)
        end
    end
    if world.character then
        characterRuns = characterRuns + 1
        check("for this character: every other character's addons as they were", Same(world.others, before.others))
    end
    world.Reload()
    CheckApplied(world, entries)
    local again = world.Setup.Plan(answers, world.Setup.Context())
    if not flipped then
        local left = {}
        for _, e in ipairs(again) do
            if world.Setup.Differs(e) then left[#left + 1] = e.id .. (e.on and "+" or "-") .. (e.idle and "idle" or "") end
        end
        check("planned again after applying: nothing left to change: " .. table.concat(left, " "), #left == 0)
    end
    check("it can be undone", world.Setup.CanRestore())
    world.Setup.Restore()
    check("undone: every switch as it was", Same(world.root, before.root))
    check("undone: every module addon as it was", Same(world.enabled, before.enabled))
    check("undone: other characters' addons as they were", Same(world.others, before.others))
end

print(("test-setup-fuzz: %d runs (seed %d, %d for one character), %d review flips, %d reloads, %d checks passed")
    :format(RUNS, SEED, characterRuns, flips, reloads, checks))
