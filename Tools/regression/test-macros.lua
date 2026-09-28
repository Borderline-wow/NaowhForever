-- Loads NaowhForever_Macros.lua against stubbed macro, bag and item APIs and checks what
-- it writes. Run from the repo root: lua Tools/regression/test-macros.lua
local f = assert(io.open(arg[1] or "Macros/NaowhForever_Macros.lua", "rb"))
local source = f:read("*a"); f:close()

local FOOD, DRINK = "Food", "Drink"
-- itemID -> { spell, required level }
local ITEMS = {
    [8079] = { DRINK, 45 },   -- Conjured Crystal Water
    [8766] = { DRINK, 45 },   -- Morning Glory Dew
    [1179] = { DRINK, 5 },    -- Ice Cold Milk
    [8932] = { FOOD, 45 },    -- Alterac Swiss
    [5349] = { FOOD, 1 },     -- Conjured Muffin
    [4599] = { FOOD, 35 },    -- Cured Ham Steak
}

local function Fixture(opts)
    local settings = opts.settings or {}
    local bags = opts.bags or {}            -- flat list of item IDs, one per slot
    local macros, created, edited, deleted, printed = {}, 0, 0, 0, {}
    local combat, group = false, opts.group
    local consts = { MAX_ACCOUNT_MACROS = opts.max or 30 }
    local handler, registered = nil, {}

    local S = {}
    local ns = {
        HEALTHSTONES = { 9421, 5509 },
        HEALING_POTIONS = { 13446, 929 },
        Print = function(msg) printed[#printed + 1] = msg end,
        Apply = function() end,
        UI = {
            STATUS = setmetatable({}, { __index = function() return "" end }),
            ModuleSettings = function(_, defaults)
                function S.Get(k)
                    if settings[k] ~= nil then return settings[k] end
                    return defaults[k]
                end
                function S.Set(k, v) settings[k] = v end
                return S
            end,
        },
    }
    local function Count(id)
        local n = 0
        for _, b in ipairs(bags) do if b == id then n = n + 1 end end
        return n
    end
    local function Find(name)
        for i, m in ipairs(macros) do if m.name == name then return i end end
        return 0
    end
    local env = {
        NUM_BAG_SLOTS = 0,
        Constants = { MacroConsts = consts },
        IsInRaid = function() return group == "raid" end,
        IsInGroup = function() return group ~= nil end,
        C_Container = {
            GetContainerNumSlots = function() return #bags end,
            GetContainerItemID = function(_, slot) return bags[slot] end,
        },
        C_Item = {
            GetItemCount = Count,
            GetItemSpell = function(id) return ITEMS[id] and ITEMS[id][1] end,
            GetItemInfo = function(id)
                return "item", nil, nil, nil, ITEMS[id] and ITEMS[id][2]
            end,
        },
        C_Spell = { GetSpellName = function(id) return id == 433 and FOOD or DRINK end },
        PickupMacro = function(index) assert(index > 0) end,
        GetMacroIndexByName = Find,
        GetMacroBody = function(i) return macros[i].body end,
        GetNumMacros = function() return #macros, 0 end,
        CreateMacro = function(name, _, body, perChar)
            assert(perChar == false, "new macros are General macros")
            assert(#name <= 16, "macro name too long: " .. name)
            assert(#body <= 255, "macro body too long")
            created = created + 1
            macros[#macros + 1] = { name = name, body = body }
        end,
        EditMacro = function(i, _, _, body) edited = edited + 1; macros[i].body = body end,
        DeleteMacro = function(i) deleted = deleted + 1; table.remove(macros, i) end,
        InCombatLockdown = function() return combat end,
        CreateFrame = function()
            return {
                SetScript = function(_, _, fn) handler = fn end,
                RegisterEvent = function(_, event) registered[event] = true end,
            }
        end,
        hooksecurefunc = function(tbl, key, fn)
            local orig = tbl[key]
            tbl[key] = function(...) orig(...); fn(...) end
        end,
    }
    env._G = { NaowhForever = ns }
    setmetatable(env, { __index = _G })
    local chunk
    if setfenv then
        chunk = assert(loadstring(source)); setfenv(chunk, env)
    else
        chunk = assert(load(source, "Macros", "t", env))
    end
    chunk()

    local t = { ns = ns }
    function t.Fire(event) if registered[event] then handler(nil, event) end end
    function t.Set(k, v) S.Set(k, v) end
    function t.Body(name) local i = Find(name); return i > 0 and macros[i].body or nil end
    function t.Combat(on) combat = on end
    function t.Bags(list) bags = list end
    function t.Counts() return created, edited, deleted end
    function t.Profile(new) settings = new; ns.Apply() end
    function t.Group(kind) group = kind end
    function t.SetMax(n) consts.MAX_ACCOUNT_MACROS = n end
    t.printed, t.macros = printed, macros
    return t
end

local failures = 0
local function Check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(("FAIL %s\n  got:  %s\n  want: %s"):format(label, tostring(got), tostring(want)))
    end
end

-- Nothing is written before the world loads, then the chosen macros appear.
do
    local t = Fixture({ settings = { health = true, trinket1 = true }, bags = { 929, 5509 } })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("no writes before PLAYER_ENTERING_WORLD", #t.macros, 0)
    t.Fire("PLAYER_ENTERING_WORLD")
    Check("health, healthstone first", t.Body("NF Health"), "#showtooltip\n/use item:5509")
    Check("trinket 1", t.Body("NF Trinket 1"), "#showtooltip 13\n/use 13")
    Check("mana not made while off", t.Body("NF Mana"), nil)
end

-- Potion First, with a fallback to the other list when the preferred one is empty.
do
    local t = Fixture({ settings = { health = true, healthOrder = "potion" }, bags = { 929, 5509 } })
    t.Fire("PLAYER_ENTERING_WORLD")
    Check("health, potion first", t.Body("NF Health"), "#showtooltip\n/use item:929")
    t.Bags({ 5509 })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("potion first falls back to a stone", t.Body("NF Health"), "#showtooltip\n/use item:5509")
end

-- Food and drink: conjured wins over a higher level, the best level wins otherwise.
do
    local t = Fixture({ settings = { food = true }, bags = { 1179, 8766, 8079, 4599, 8932 } })
    t.Fire("PLAYER_ENTERING_WORLD")
    Check("food and drink", t.Body("NF Food"), "#showtooltip\n/use item:8932\n/use item:8079")
    t.Bags({ 5349, 8932 })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("conjured food first, no drink", t.Body("NF Food"), "#showtooltip\n/use item:5349")
end

-- Nothing carried: no macro is made, and an existing one is left as it was.
do
    local t = Fixture({ settings = { bandage = true }, bags = {} })
    t.Fire("PLAYER_ENTERING_WORLD")
    Check("no bandage macro without bandages", t.Body("NF Bandage"), nil)
    t.Bags({ 14529 })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("bandage on self", t.Body("NF Bandage"), "#showtooltip\n/use [@player] item:14529")
    t.Bags({})
    t.Fire("BAG_UPDATE_DELAYED")
    Check("bandage kept after the last is used", t.Body("NF Bandage"),
        "#showtooltip\n/use [@player] item:14529")
end

-- Combat defers the write until it ends; an unchanged body is not rewritten.
do
    local t = Fixture({ settings = { mana = true }, bags = { 3827 } })
    t.Fire("PLAYER_ENTERING_WORLD")
    t.Combat(true)
    t.Bags({ 3827, 13444 })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("no edit in combat", t.Body("NF Mana"), "#showtooltip\n/use item:3827")
    t.Combat(false)
    t.Fire("PLAYER_REGEN_ENABLED")
    Check("edited after combat", t.Body("NF Mana"), "#showtooltip\n/use item:13444")
    local _, before = t.Counts()
    t.Fire("BAG_UPDATE_DELAYED")
    local _, after = t.Counts()
    Check("unchanged body not rewritten", after, before)
end

-- Turning a macro or the module off deletes it.
do
    local t = Fixture({ settings = { trinket1 = true, trinket2 = true }, bags = {} })
    t.Fire("PLAYER_ENTERING_WORLD")
    t.Set("trinket1", false)
    Check("toggle off deletes", t.Body("NF Trinket 1"), nil)
    Check("other macro stays", t.Body("NF Trinket 2"), "#showtooltip 14\n/use 14")
    t.Set("enabled", false)
    Check("module off deletes", t.Body("NF Trinket 2"), nil)
end

-- Focus body follows its options; the announce channel follows the group.
do
    local t = Fixture({ settings = { focus = true, focusMark = true, focusMarker = 7,
        focusAnnounce = true } })
    t.Fire("PLAYER_ENTERING_WORLD")
    Check("focus solo, no announce", t.Body("NF Focus"),
        "/focus [@mouseover,exists,nodead][]\n/tm [@focus] 7")
    t.Group("party")
    t.Fire("GROUP_ROSTER_UPDATE")
    Check("focus in a party", t.Body("NF Focus"),
        "/focus [@mouseover,exists,nodead][]\n/tm [@focus] 7\n/p Focus: %f")
    t.Group("raid")
    t.Fire("GROUP_ROSTER_UPDATE")
    Check("focus in a raid", t.Body("NF Focus"),
        "/focus [@mouseover,exists,nodead][]\n/tm [@focus] 7\n/ra Focus: %f")
end

-- A profile switch that turns a macro off keeps it; its own switch deletes it.
do
    local t = Fixture({ settings = { health = true, trinket1 = true }, bags = { 5509 } })
    t.Fire("PLAYER_ENTERING_WORLD")
    t.Profile({})
    Check("profile switch keeps the macro", t.Body("NF Trinket 1"), "#showtooltip 13\n/use 13")
    t.Bags({ 929 })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("macro off in this profile is not updated", t.Body("NF Health"),
        "#showtooltip\n/use item:5509")
    t.Profile({ trinket1 = true })
    t.Set("trinket1", false)
    Check("its own switch deletes it", t.Body("NF Trinket 1"), nil)
end

-- Turned off in combat: deleted once combat ends.
do
    local t = Fixture({ settings = { trinket2 = true } })
    t.Fire("PLAYER_ENTERING_WORLD")
    t.Combat(true)
    t.Set("trinket2", false)
    Check("not deleted in combat", t.Body("NF Trinket 2"), "#showtooltip 14\n/use 14")
    t.Combat(false)
    t.Fire("PLAYER_REGEN_ENABLED")
    Check("deleted after combat", t.Body("NF Trinket 2"), nil)
end

-- Full character macros: warned once, nothing made; made once a slot frees up.
do
    local t = Fixture({ settings = { trinket1 = true, trinket2 = true }, max = 0 })
    t.Fire("PLAYER_ENTERING_WORLD")
    t.Fire("BAG_UPDATE_DELAYED")
    Check("nothing made when full", #t.macros, 0)
    Check("warned once", #t.printed, 1)
    t.SetMax(2)
    t.Fire("UPDATE_MACROS")
    Check("made after a macro is deleted", t.Body("NF Trinket 1"), "#showtooltip 13\n/use 13")
end

do
    local t = Fixture({})
    t.Fire("PLAYER_ENTERING_WORLD")
    t.ns.PickupProfileMacro({ name = "Example", body = "/say test", icon = 1 })
    Check("profile macro created", t.Body("Example"), "/say test")
    t.ns.PickupProfileMacro({ name = "Example", body = "/say replaced" })
    Check("name collision preserves existing", t.Body("Example"), "/say test")
    t.ns.PickupProfileMacro({ name = "TooLongBody", body = string.rep("x", 256) })
    Check("oversize macro rejected", t.Body("TooLongBody"), nil)
    t.Combat(true)
    t.ns.PickupManagedMacro("trinket1")
    Check("click in combat does not create", t.Body("NF Trinket 1"), nil)
    t.Combat(false)
    t.ns.PickupManagedMacro("trinket1")
    Check("click creates macro", t.Body("NF Trinket 1"), "#showtooltip 13\n/use 13")
end

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("test-macros: all passed")
