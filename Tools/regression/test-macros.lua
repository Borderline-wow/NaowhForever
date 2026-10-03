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
    local account = {}
    local combat, group = false, opts.group
    local consts = { MAX_ACCOUNT_MACROS = opts.max or 30, MAX_CHARACTER_MACROS = opts.maxChar or 30 }
    local frames = {}
    local function Frame(name)
        local fr = { name = name, events = {}, attrs = {}, shown = true }
        setmetatable(fr, { __index = function() return function() end end })
        function fr:SetScript(k, fn) if k == "OnEvent" then self.handler = fn end end
        function fr:RegisterEvent(event) self.events[event] = true end
        function fr:UnregisterEvent(event) self.events[event] = nil end
        function fr:UnregisterAllEvents() self.events = {} end
        function fr:SetAttribute(k, v) self.attrs[k] = v end
        function fr:Show() self.shown = true end
        function fr:Hide() self.shown = false end
        function fr:SetTexture(v) self.texture = v end
        function fr:SetDesaturated(v) self.desaturated = v end
        function fr:SetText(v) self.text = v end
        function fr:CreateTexture() return Frame() end
        frames[#frames + 1] = fr
        return fr
    end

    local S = {}
    local ns = {
        HEALTHSTONES = { 9421, 5509 },
        HEALING_POTIONS = { 13446, 929 },
        Print = function(msg) printed[#printed + 1] = msg end,
        AccountSettings = function() return account end,
        Apply = function() end,
        ShowRaidReminderAnchorConfig = function() end,
        HideRaidReminderAnchorConfig = function() end,
        Font = function() return Frame() end,
        Border = function() end,
        PixelInset = function() end,
        UI = {
            AttachMover = function() return Frame() end,
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
            GetItemIconByID = function(id) return "icon" .. id end,
            GetItemSpell = function(id) return ITEMS[id] and ITEMS[id][1] end,
            GetItemInfo = function(id)
                return "item", nil, nil, nil, ITEMS[id] and ITEMS[id][2]
            end,
        },
        C_Spell = { GetSpellName = function(id) return id == 433 and FOOD or DRINK end },
        PickupMacro = function(index) assert(index > 0) end,
        GetMacroIndexByName = Find,
        GetMacroBody = function(i) return macros[i].body end,
        GetNumMacros = function()
            local numAccount, numCharacter = 0, 0
            for _, m in ipairs(macros) do
                if m.perChar then numCharacter = numCharacter + 1 else numAccount = numAccount + 1 end
            end
            return numAccount, numCharacter
        end,
        CreateMacro = function(name, icon, body, perChar)
            assert(type(perChar) == "boolean")
            assert(#name <= 16, "macro name too long: " .. name)
            assert(#body <= 255, "macro body too long")
            created = created + 1
            macros[#macros + 1] = { name = name, body = body, icon = icon, perChar = perChar }
        end,
        EditMacro = function(i, _, icon, body)
            edited = edited + 1
            if icon then macros[i].icon = icon end
            if body then macros[i].body = body end
        end,
        DeleteMacro = function(i) deleted = deleted + 1; table.remove(macros, i) end,
        InCombatLockdown = function() return combat end,
        CreateFrame = function(_, name) return Frame(name) end,
        hooksecurefunc = function(tbl, key, fn)
            local orig = tbl[key]
            tbl[key] = function(...) orig(...); fn(...) end
        end,
    }
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env._G = { NaowhForever = ns, SLASH_SAY1 = "/say", SLASH_CAST1 = "/cast", SLASH_SCRIPT1 = "/run",
        SLASH_TARGET_MARKER1 = "/tm", EMOTE1_CMD1 = "/wave" }
    setmetatable(env, { __index = _G })
    local chunk
    if setfenv then
        chunk = assert(loadstring(source)); setfenv(chunk, env)
    else
        chunk = assert(load(source, "Macros", "t", env))
    end
    chunk()

    local t = { ns = ns }
    function t.Fire(event)
        for _, fr in ipairs(frames) do
            if fr.events[event] then fr.handler(fr, event) end
        end
    end
    function t.FoodBar()
        for _, fr in ipairs(frames) do
            if fr.name == "NaowhForeverFoodBar" then return fr end
        end
    end
    function t.Set(k, v) S.Set(k, v) end
    function t.Body(name) local i = Find(name); return i > 0 and macros[i].body or nil end
    function t.Macro(name) local i = Find(name); return i > 0 and macros[i] or nil end
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
    Check("profile macro is a character macro", t.Macro("Example").perChar, true)
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
    Check("managed macro stays a General macro", t.Macro("NF Trinket 1").perChar, false)
    t.Combat(true)
    t.ns.RemoveManagedMacro("trinket1")
    Check("remove in combat keeps macro", t.Body("NF Trinket 1") ~= nil, true)
    t.Combat(false)
    t.ns.RemoveManagedMacro("trinket1")
    Check("right-click removes macro", t.Body("NF Trinket 1"), nil)
end

-- Shared profile macros that run Lua ask before they are created.
do
    local t = Fixture({})
    t.Fire("PLAYER_ENTERING_WORLD")
    local accept
    t.ns.Confirm = function(_, onYes) accept = onYes end
    t.ns.PickupProfileMacro({ name = "Sneaky", body = "#showtooltip\n/run print(1)" })
    Check("script macro waits for confirmation", t.Body("Sneaky"), nil)
    accept()
    Check("confirmed script macro created", t.Body("Sneaky") ~= nil, true)
    accept = nil
    t.ns.PickupProfileMacro({ name = "Plain", body = "/cast Frostbolt" })
    Check("plain macro needs no confirmation", accept == nil and t.Body("Plain") ~= nil, true)
end

-- Class macros go to the character tab, so its limit is the one checked.
do
    local t = Fixture({ maxChar = 1 })
    t.Fire("PLAYER_ENTERING_WORLD")
    t.ns.PickupProfileMacro({ name = "One", body = "/say one" })
    t.ns.PickupProfileMacro({ name = "Two", body = "/say two" })
    Check("character limit respected", t.Body("Two"), nil)
    Check("character limit named", t.printed[#t.printed]:find("Character macros are full", 1, true) ~= nil, true)
end

-- A full General tab warning once must not silence a full Character tab.
do
    local t = Fixture({ settings = { trinket1 = true }, max = 0, maxChar = 0 })
    t.Fire("PLAYER_ENTERING_WORLD")
    t.ns.PickupProfileMacro({ name = "One", body = "/say one" })
    Check("each tab warns", #t.printed, 2)
end

-- Command checks warn about what would fail when pressed, and leave script lines alone.
do
    local t = Fixture({})
    t.Fire("PLAYER_ENTERING_WORLD")
    local function Problems(body) return #t.ns.MacroProblems(body) end
    Check("known commands pass", Problems("#showtooltip\n/cast [@mouseover,help][] Heal\n/tm [@focus] 8"), 0)
    Check("emotes and channels pass", Problems("/wave\n/2 LFG"), 0)
    Check("unknown command flagged", Problems("/castt Frostbolt"), 1)
    Check("case does not matter", Problems("/CAST Frostbolt"), 0)
    Check("non-command line flagged", Problems("cast Frostbolt"), 1)
    Check("unbalanced bracket flagged", Problems("/cast [@mouseover Heal"), 1)
    Check("script brackets ignored", Problems("/run local t = {}; t[1] = 2 print(t[1]"), 0)
    t.ns.PickupProfileMacro({ name = "Typo", body = "/castt Frostbolt" })
    Check("typo macro still created", t.Body("Typo"), "/castt Frostbolt")
    Check("typo macro warns", t.printed[#t.printed]:find("Typo may not work", 1, true) ~= nil, true)
end

-- Food & Drink bar: built only once switched on, best food and drink, updates after combat.
do
    local t = Fixture({ bags = { 1179, 8766, 5349, 4599 } })
    t.Fire("PLAYER_ENTERING_WORLD")
    Check("food bar not built while off", t.FoodBar(), nil)
    t.Set("foodBar", true)
    local bar = t.FoodBar()
    local food, drink = bar.buttons[1], bar.buttons[2]
    Check("food bar shown", bar.shown, true)
    Check("conjured food first", food.attrs.item1, "item:5349")
    Check("highest level drink", drink.attrs.item1, "item:8766")
    Check("food button uses an item", food.attrs.type1, "item")
    Check("drink icon", drink.icon.texture, "icon8766")
    Check("food count", food.count.text, 1)

    t.Combat(true)
    t.Bags({ 4599, 4599 })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("no change in combat", food.attrs.item1, "item:5349")
    t.Combat(false)
    t.Fire("PLAYER_REGEN_ENABLED")
    Check("food after combat", food.attrs.item1, "item:4599")
    Check("count after combat", food.count.text, 2)
    Check("no drink: button does nothing", drink.attrs.type1, nil)
    Check("no drink: icon greyed", drink.icon.desaturated, true)

    t.Set("foodBar", false)
    Check("food bar hidden when off", bar.shown, false)
    t.Bags({ 1179 })
    t.Fire("BAG_UPDATE_DELAYED")
    Check("bag changes ignored while off", food.attrs.item1, "item:4599")
end

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("test-macros: all passed")
