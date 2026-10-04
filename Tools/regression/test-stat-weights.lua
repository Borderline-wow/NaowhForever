-- Stat Weights: each spec's weights with your changes kept apart from the defaults, sharing
-- them as a line, how much stronger an item makes you over what you wear (rings against the
-- weaker one, a two-hander against both hands), the tooltip line (installed only once the
-- module is on), and its window.
local Load = dofile("Tools/regression/load_files.lua")
local TocFiles = dofile("Tools/regression/toc_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end
local NOTHING = function() end

-- Items by ID: where they go and their stats.
local ITEMS = {
    [1] = { "INVTYPE_HAND", { ITEM_MOD_AGILITY_SHORT = 10 } },
    [2] = { "INVTYPE_HAND", { ITEM_MOD_ATTACK_POWER_SHORT = 10 } },
    [3] = { "INVTYPE_FINGER", { ITEM_MOD_AGILITY_SHORT = 5 } },
    [4] = { "INVTYPE_FINGER", { ITEM_MOD_AGILITY_SHORT = 8 } },
    [5] = { "INVTYPE_FINGER", { ITEM_MOD_AGILITY_SHORT = 2 } },
    [6] = { "INVTYPE_2HWEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } },
    [7] = { "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } },
    [8] = { "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 } },
    [9] = { "INVTYPE_HAND", { ITEM_MOD_STAMINA_SHORT = 1 } },
}

-- A secret number: any arithmetic or comparison on it fails, as in the game.
local SECRET = {}

local function Fixture(class)
    local state = { worn = {}, account = {}, printed = {}, postCalls = {}, watchers = {} }
    local ns = { Shared = {}, QoLSettings = {} }
    local db, listeners = {}, {}
    ns.UI = {
        ModuleSettings = function(_, defaults)
            return {
                Get = function(k) if db[k] == nil then return defaults[k] end return db[k] end,
                Set = function(k, v)
                    db[k] = v
                    for i = 1, #listeners do listeners[i](k, v) end
                end,
                OnChange = function(fn) listeners[#listeners + 1] = fn end,
                Toggle = function(k, text) return { type = "toggle", key = k, text = text } end,
            }
        end,
        RefreshPage = NOTHING,
        STATUS = { untested = "" },
    }
    ns.AccountSettings = function() return state.account end
    ns.Color = function(_, text) return text end
    ns.Print = function(text) state.printed[#state.printed + 1] = text end
    ns.Apply = NOTHING
    local env = setmetatable({
        _G = { NaowhForever = ns },
        UnitClass = function() return class, class end,
        -- While state.secret, your stats come back secret, as the game hands them out then.
        UnitStat = function() if state.secret then return SECRET, SECRET end return 50, 50 end,
        UnitAttackSpeed = function()
            if state.secret then return SECRET, SECRET end
            return state.speed or 2, state.offSpeed
        end,
        C_Secrets = { ShouldUnitStatsBeSecret = function() return state.secret == true end },
        -- A frame that keeps its events and its handler, for the talent watcher.
        CreateFrame = function()
            local f = { events = {} }
            function f.RegisterEvent(self, event) self.events[event] = true end
            function f.SetScript(self, _, fn) self.onEvent = fn end
            state.watchers[#state.watchers + 1] = f
            return f
        end,
        -- Forever's talents: one trait tree, its three groups the classic trees, points spent
        -- in each (state.spent, by tree).
        C_ClassTalents = { GetActiveConfigID = function() return state.spent and 7 end },
        C_Traits = {
            GetConfigInfo = function() return { treeIDs = { 70 } } end,
            GetGroupDisplayInfoByTreeID = function()
                return { { groupID = 101 }, { groupID = 102 }, { groupID = 103 } }
            end,
            GetGroupCurrencyInfo = function()
                local infos = {}
                for i, spent in ipairs(state.spent) do
                    infos[i] = { traitNodeGroupID = 100 + i, currencyInfos = { { spent = spent } } }
                end
                return infos
            end,
        },
        issecretvalue = function() return false end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        CreateAtlasMarkup = function() return "^" end,
        ITEM_QUALITY_COLORS = { [3] = { hex = "|cff0070dd" } },
        Enum = { TooltipDataType = { Item = 0 } },
        TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) state.postCalls[#state.postCalls + 1] = fn end },
        hooksecurefunc = function(t, key, fn)
            local original = t[key]
            t[key] = function(...) original(...); fn(...) end
        end,
        GetInventoryItemLink = function(_, slot) return state.worn[slot] and "item:" .. state.worn[slot] end,
        GetInventoryItemID = function(_, slot) return state.worn[slot] end,
        C_Item = {
            -- Every item armour (class 4, subclass 2); none needs a level.
            GetItemInfoInstant = function(id) return id, "", "", ITEMS[id] and ITEMS[id][1], 0, 4, 2 end,
            GetItemInfo = function() return "name", "link", 3, 10, 0 end,
            GetItemStats = function(link)
                local item = ITEMS[tonumber(link:match("item:(%d+)"))]
                return item and item[2]
            end,
            IsItemDataCachedByID = function() return true end,
            GetItemNameByID = function(id) return "Item " .. id end,
            GetItemIconByID = function() return 134400 end,
            GetItemQualityByID = function() return 3 end,
            GetItemCount = function() return 0 end,
        },
    }, { __index = _G })
    local files = { "Shared/Shared.lua", "Shared/Data/Forever.lua", "Shared/Style.lua", "Shared/Items.lua",
        "Shared/Parts.lua" }
    for _, path in ipairs(TocFiles("^StatWeights/.*%.lua$")) do files[#files + 1] = path end
    Load(files, env)
    return ns, state, env
end

-------------------------------------------------------------------------------
--  The defaults
-------------------------------------------------------------------------------
do
    local ns = Fixture("ROGUE")
    local SW = ns.StatWeights
    local known = {}
    for _, stat in ipairs(SW.STATS) do known[stat[1]] = true end
    local classes = {}
    for _, spec in ipairs(ns.StatWeightDefaults) do
        classes[spec.class] = (classes[spec.class] or 0) + 1
        check("a spec has a name and weights: " .. spec.key, type(spec.name) == "string" and next(spec.weights))
        for stat in pairs(spec.weights) do check("its weights are stats the editor shows: " .. stat, known[stat]) end
    end
    for _, class in ipairs({ "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }) do
        check("every class has its specs: " .. class, (classes[class] or 0) >= 3)
    end
    -- Every spec the BiS List ranks has weights.
    local bis = { QoLSettings = {} }
    Load({ "BiS/Data/BiS.lua" }, setmetatable({ _G = { NaowhForever = bis } }, { __index = _G }))
    for _, spec in ipairs(bis.BiSData.specs) do
        check("the BiS List's spec has weights: " .. spec.key, SW.Spec(spec.key) ~= nil)
    end
    check("a rogue's specs are a rogue's", #SW.ClassSpecs() == 3 and SW.ClassSpecs()[1].class == "ROGUE")
    check("with no talents nor pick, the first is yours", SW.ActiveSpec() == "assassination-rogue")
    ns.StatWeightSettings.Set("spec", "combat-rogue")
    check("the one picked on the page is", SW.ActiveSpec() == "combat-rogue")
    ns.StatWeightSettings.Set("spec", "fire-mage")
    check("never another class's", SW.ActiveSpec() == "assassination-rogue")
end

-------------------------------------------------------------------------------
--  Automatic: your talents say your spec
-------------------------------------------------------------------------------
do
    local ns, state = Fixture("ROGUE")
    local SW = ns.StatWeights
    state.spent = { 3, 8, 0 }
    check("the tree with the most points is your spec", SW.ActiveSpec() == "combat-rogue")
    state.spent = { 0, 2, 9 }
    check("read once until your talents change", SW.ActiveSpec() == "combat-rogue")
    local watcher = state.watchers[1]
    check("watching the game's talent change", watcher and watcher.events.TRAIT_CONFIG_UPDATED)
    watcher.onEvent()
    check("then read again", SW.ActiveSpec() == "subtlety-rogue")
    ns.StatWeightSettings.Set("spec", "assassination-rogue")
    check("a spec picked by hand wins", SW.ActiveSpec() == "assassination-rogue")
    ns.StatWeightSettings.Set("spec", nil)
    state.spent = { 0, 0, 0 }
    watcher.onEvent()
    check("no points yet: the first", SW.ActiveSpec() == "assassination-rogue")
end

-------------------------------------------------------------------------------
--  Your changes
-------------------------------------------------------------------------------
do
    local ns, state = Fixture("ROGUE")
    local SW = ns.StatWeights
    local key = "combat-rogue"
    local heard = 0
    SW.OnChange(function() heard = heard + 1 end)
    check("the defaults to start", SW.For(key).agi == 1 and not SW.Changed(key, "agi"))
    SW.Set(key, "agi", 1.5)
    check("a change counts", SW.For(key).agi == 1.5 and SW.Changed(key, "agi") and heard == 1)
    check("and is kept for the account, only it", state.account.statWeights[key].agi == 1.5
        and next(state.account.statWeights[key], "agi") == nil)
    SW.Set(key, "agi", 1)
    check("back to the default, nothing is kept", state.account.statWeights[key] == nil and SW.For(key).agi == 1)
    SW.Set(key, "fire", 2)
    SW.Set(key, "nonsense", 2)
    check("a stat it has none of can be given one; one that is no stat cannot",
        SW.For(key).fire == 2 and SW.For(key).nonsense == nil)
    SW.Reset(key)
    check("Reset puts the defaults back", SW.For(key).fire == nil and state.account.statWeights[key] == nil)

    -- Sharing a spec's weights as a line.
    check("with no changes, the line is the spec alone", SW.Export(key) == "NFSW1:combat-rogue:")
    SW.Set(key, "agi", 1.25)
    SW.Set(key, "spi", 0.5)
    local line = SW.Export(key)
    check("Export writes only your changes", line == "NFSW1:combat-rogue:agi=1.25,spi=0.5")
    SW.Reset(key)
    SW.Set(key, "fire", 3)
    local ok = SW.Import(line, "arcane-mage")
    check("Import puts Naowh's back, then the line's changes on top", ok and SW.For(key).agi == 1.25
        and SW.For(key).spi == 0.5 and SW.For(key).str == 0.5 and SW.For(key).fire == nil)
    -- A simulator's export: its stats for the spec on the page, the rest to 0.
    ok = SW.Import('( Pawn: v1: "Combat WoWSims Weights": Class=Rogue,Agility=2.100,Ap=1.000,'
        .. 'HitRating=13.200,MeleeDps=3.000,RangedDps=9.000,SpellPen=1.000 )', key)
    local weights = SW.For(key)
    check("a WoWSims export: its stats", ok and weights.agi == 2.1 and weights.ap == 1 and weights.hit == 13.2
        and weights.dps == 3)
    check("what it does not name goes to 0, what we have no stat for is left out", weights.str == 0
        and weights.crit == 0 and weights.sta == 0)
    check("another class's export is refused", not SW.Import('( Pawn: v1: "x": Class=Mage, Intellect=1 )', key))
    check("one with no stat we read is refused", not SW.Import('( Pawn: v1: "x": SpellPen=1 )', key))
    check("a line that is not ours is refused", not SW.Import("hello") and not SW.Import("NFSW1:nobody:agi=1")
        and not SW.Import("NFSW1:combat-rogue:agi=x"))
end

-------------------------------------------------------------------------------
--  How much stronger an item makes you
-------------------------------------------------------------------------------
do
    local ns, state = Fixture("ROGUE")
    local SW = ns.StatWeights
    local weights = SW.For("combat-rogue")
    state.worn = { [10] = 2, [11] = 4, [12] = 5, [16] = 7, [17] = 8 }
    -- Your five stats at 50 each: 0.5 Strength, 1 Agility, 0.15 Stamina; then the 10 Attack
    -- Power on your gloves (0.5) and your weapons' damage per second (7, the off hand's half).
    local power = SW.Power(weights)
    check("your stats' worth: yours, then what you wear adds", math.abs(power - (25 + 50 + 7.5 + 5 + 140 + 52.5)) < 1e-6)
    local gloves = SW.Gain(1, 10, weights, power)
    check("10 Agility over 10 Attack Power", math.abs(gloves - 100 * 5 / power) < 1e-6)
    check("a ring over the weaker one you wear", SW.Gain(3, 12, weights, power) > 0 and SW.Gain(3, 11, weights, power) < 0)
    local twoHand = SW.Gain(6, 16, weights, power, 17)
    check("a two-hander against both hands", math.abs(twoHand - 100 * (280 - 140 - 52.5) / power) < 1e-6)
    state.speed, state.offSpeed = 2, 1.5
    check("an enchant's point of weapon damage: a point of dps over the weapon's speed",
        SW.SwingDamage(weights, 16) == 7 / 2 and SW.SwingDamage(weights, 17) == 7 * 0.5 / 1.5)
    state.worn[10] = nil
    check("over nothing worn, its whole worth", math.abs(SW.Gain(1, 10, weights, SW.Power(weights)) - 100 * 10 / SW.Power(weights)) < 1e-6)
    -- Stats the game keeps secret (reported on Forever, every item hovered): no worth, no gain,
    -- no error.
    state.secret = true
    check("secret stats: no worth", SW.Power(weights) == nil)
    check("secret stats: no gain", SW.Gain(1, 10, weights, SW.Power(weights)) == nil)
    check("secret stats: a swing at the usual speed", SW.SwingDamage(weights, 16) == 7 / 2.6)
    state.secret = false
end

-------------------------------------------------------------------------------
--  The tooltip line
-------------------------------------------------------------------------------
do
    local ns, state = Fixture("ROGUE")
    local S = ns.StatWeightSettings
    ns.Apply()
    check("off, no hook on tooltips", #state.postCalls == 0)
    S.Set("enabled", true)
    check("on, its hook goes in", #state.postCalls == 1)
    ns.Apply()
    S.Set("enabled", true)
    check("once", #state.postCalls == 1)
    local OnItem = state.postCalls[1]
    local function Lines(id)
        local tip = { lines = {} }
        function tip.AddLine(self, text) self.lines[#self.lines + 1] = text end
        function tip.IsForbidden() return false end
        function tip.GetItem() return "x", "item:" .. id end
        OnItem(tip, { id = id })
        return tip.lines
    end
    state.worn = { [10] = 2, [11] = 4, [12] = 5 }
    local lines = Lines(1)
    check("an upgrade: one line, the arrow, how much, then the spec", #lines == 1
        and lines[1]:find("^|A:bags%-greenarrow") and lines[1]:find("+6% upgrade|r", 1, true)
        and lines[1]:find("Assassination", 1, true))
    check("nothing on what is worse", #Lines(9) == 0)
    check("nor on what you wear", #Lines(2) == 0)
    lines = Lines(3)
    check("a ring is weighed against the weaker you wear", lines[1] and lines[1]:find("+", 1, true))
    check("not gear, no line", #Lines(999) == 0)
    -- A comparison tooltip (what you wear, beside the item's) has no GetItem on Forever.
    local shopping = { lines = {} }
    function shopping.AddLine(self, text) self.lines[#self.lines + 1] = text end
    function shopping.IsForbidden() return false end
    OnItem(shopping, { id = 1 })
    check("a comparison tooltip, which has no GetItem: no error, weighed by its ID", #shopping.lines == 1)
    -- The BiS List's class rules: what your class does not wear is no upgrade.
    local asked
    ns.ClassCanUse = function(class, item) asked = class .. " " .. item[1] .. " " .. item[2]; return false end
    check("nor on gear your class does not wear, by the BiS List's rules", #Lines(1) == 0
        and asked == "ROGUE 4 2")
    ITEMS[1][1] = "INVTYPE_CLOAK"
    Lines(1)
    check("a cloak asked as anyone's, not as cloth", asked == "ROGUE 4 0")
    ITEMS[1][1] = "INVTYPE_HAND"
    ns.ClassCanUse = nil
    S.Set("enabled", false)
    check("the module off, no line", #Lines(1) == 0)
end

-------------------------------------------------------------------------------
--  The window: your class's specs, then on the left only the stats the spec uses, a bar and a
--  number each, points and percents apart, a stat at 0 drops off and Add a stat brings it back;
--  on the right your best upgrades by these weights; Import, Export and Reset on its title bar
-------------------------------------------------------------------------------
do
    local ns, state, env = Fixture("ROGUE")
    local SW = ns.StatWeights
    -- Frames that keep what is set on them; any other method does nothing.
    local made = {}
    local METHODS = {
        SetScript = function(f, k, fn) f.scripts[k] = fn end,
        SetText = function(f, text) f.text = text end,
        GetText = function(f) return f.text end,
        Show = function(f) f.shown = true end,
        Hide = function(f) f.shown = false end,
        SetShown = function(f, on) f.shown = on and true or false end,
        IsShown = function(f) return f.shown end,
        SetWidth = function(f, w) f.width = w end,
        GetWidth = function(f) return f.width or 0 end,
        SetHeight = function(f, h) f.height = h end,
        SetAlpha = function(f, a) f.alpha = a end,
        EnableMouse = function(f, on) f.mouse = on end,
        GetStringWidth = function() return 40 end,
        ClearFocus = function(f) if f.scripts.OnEditFocusLost then f.scripts.OnEditFocusLost(f) end end,
        SetFocus = function(f) f.focused = true end,
        GetParent = function(f) return f.parent end,
    }
    local Frame
    METHODS.CreateTexture = function(f) return Frame(f) end
    function Frame(parent)
        -- A method (capitalised) it does not keep does nothing; a field it was not given is nil.
        local f = setmetatable({ scripts = {}, shown = true, parent = parent }, { __index = function(_, k)
            return METHODS[k] or (k:find("^%u") and NOTHING or nil)
        end })
        made[#made + 1] = f
        return f
    end
    local timers = {}
    env.CreateFrame = function(_, _, parent) return Frame(parent) end
    env.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    local function Flush()
        local run = timers
        timers = {}
        for _, fn in ipairs(run) do fn() end
    end
    env.GameTooltip_Hide = NOTHING
    env.IsModifiedClick = function() return state.modified end
    env.HandleModifiedItemClick = function(link) state.linked = link end
    local menu
    env.MenuUtil = { CreateContextMenu = function(_, fill)
        menu = {}
        fill(nil, { CreateTitle = NOTHING, CreateButton = function(_, text, fn) menu[#menu + 1] = { text = text, fn = fn } end })
    end }
    ns.Font = function(parent) return Frame(parent) end
    ns.Solid = function(parent) return Frame(parent) end
    ns.Border = function() return { SetColor = NOTHING } end
    ns.THEME = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    ns.UIScale = function() return 1 end
    ns.L = function(text) return text end
    local qol = { bisWindowAlpha = 0.8 }
    ns.QoLSettings = { Get = function(k) return qol[k] end, Set = function(k, v) qol[k] = v end, OnChange = NOTHING }
    ns.UI.SlimScroll = function(parent) return Frame(parent) end
    local Parts = ns.Shared.Parts
    local bar = {}
    Parts.Window = function()
        local window = Frame()
        window.backdrop = { Card = NOTHING, Paint = function(_, alpha) state.painted = alpha end }
        return window
    end
    Parts.TitleBar = function(window) return Frame(window) end
    Parts.Opacity = function(window) return Frame(window), { _refreshValue = NOTHING } end
    Parts.BarButton = function(parent, _, tip, _, onClick)
        local button = Frame(parent)
        button.onClick = onClick
        bar[tip] = button
        return button
    end
    Parts.FooterBrand = NOTHING
    Parts.FooterNote = function(window) local note = Frame(window); note.text = Frame(note); return note end
    Parts.Tabs = function(parent, _, items, onPick)
        local tabs = Frame(parent)
        tabs.items, tabs.onPick = items, onPick
        return tabs
    end
    Parts.FitTabs = NOTHING
    Parts.PaintTabs = function(tabs, shown) tabs.picked = shown end
    Parts.Link = function(parent, onClick) local link = Frame(parent); link.onClick = onClick; return link end
    Parts.SetLink = function(link, text) link.text = text end
    Parts.IconButton = function(parent, onClick)
        local button = Frame(parent)
        button.onClick, button.icon = onClick, Frame(button)
        return button
    end
    Parts.ItemIcon = function(parent) local icon = Frame(parent); icon.texture = Frame(icon); return icon end
    Parts.MarkForever = NOTHING
    Parts.Tip = function() return true end
    -- The window's file again, against these frames (it reads them when it builds).
    Load({ "StatWeights/UI/Window.lua" }, env)
    ns.OpenStatWeightsWindow()
    local window
    for _, f in ipairs(made) do
        if rawget(f, "backdrop") then window = f end
    end
    check("it opens at the BiS List's opacity", window and window.shown and state.painted == 0.8)
    check("a switch with your class's specs, on yours", #window.specs.items == 3 and window.specs.picked == SW.ActiveSpec()
        and window.specs.items[1].label == "Assassination")
    local weights = window.weights
    local function Shown(group)
        local names, i = {}, 0
        for _, row in ipairs(weights.rows) do
            if row.shown and (group == 1) == not ({ hit = 1, crit = 1, haste = 1, dps = 1, dmg = 1 })[row.stat] then
                i = i + 1
                names[i] = row.name.text
            end
        end
        return table.concat(names, ",")
    end
    check("points: only the stats Assassination uses", Shown(1) == "Strength,Agility,Stamina,Attack Power,Armor")
    check("percents and weapon dps apart; an enchant's weapon damage is worked out", Shown(2) == "Weapon DPS,Hit %,Crit %,Haste %")
    check("each list under its title", weights.groups[1].text == "PER POINT" and weights.groups[2].text == "PER 1% OR WEAPON DPS")
    check("the footer says whose weights", window.note.text.text == "Default weights  \194\183  3 Oct 2026"
        and window.reset.alpha == 0.35 and window.reset.mouse == false)
    check("what the tooltip line looks like", window.sample.text:find("Assassination", 1, true)
        and window.sample.text:find("+9% upgrade", 1, true))
    check("without a BiS list, how to see your best upgrades", window.upgrades.note.shown
        and window.upgrades.note.text:find("BiS List", 1, true))
    check("as tall as what it shows, not a screenful of nothing", window.height and window.height < 760
        and window.height >= 440)
    local function Row(stat)
        for _, row in ipairs(weights.rows) do
            if row.shown and row.stat == stat then return row end
        end
    end
    local agility = Row("agi")
    check("the bar is longest for what counts most", agility.bar.width > Row("str").bar.width)
    check("no mark on a default", not agility.dot.shown and not agility.reset.shown)
    agility.box.text = "1,5"
    agility.box:ClearFocus()
    Flush()
    agility = Row("agi")
    check("typing a number sets it (a comma counts as the point)", SW.For("assassination-rogue").agi == 1.5)
    check("the window shows it changed", window.note.text.text:find("1 changed", 1, true) and window.reset.alpha == 1
        and agility.dot.shown and agility.reset.shown)
    agility.reset.onClick(agility.reset)
    Flush()
    check("its own reset puts it back", SW.For("assassination-rogue").agi ~= 1.5 and not Row("agi").dot.shown)
    agility = Row("agi")
    agility.box.text = "1.5"
    agility.box:ClearFocus()
    Flush()
    local stamina = Row("sta")
    stamina.box.text = "0"
    stamina.box:ClearFocus()
    Flush()
    check("0 takes it off the list", not Shown(1):find("Stamina", 1, true))
    agility = Row("agi")
    agility.box.text = "lots"
    agility.box:ClearFocus()
    check("what is no number is put back", agility.box.text == "1.5" and SW.For("assassination-rogue").agi == 1.5)
    weights.add.onClick(weights.add)
    local intellect
    for _, item in ipairs(menu) do
        if item.text == "Intellect" then intellect = item end
    end
    check("Add a stat lists the stats not on it", weights.add.shown and intellect ~= nil)
    intellect.fn()
    local row = Row("int")
    check("Add a stat puts it on at 0, its box ready, no made-up weight", row and row.box.text == "0" and row.box.focused
        and SW.For("assassination-rogue").int == nil)
    row.box:ClearFocus()
    Flush()
    check("left at 0, it drops off again", not Shown(1):find("Intellect", 1, true))
    window.specs.onPick("combat-rogue")
    check("another spec's weights a click away", window.specs.picked == "combat-rogue"
        and window.sample.text:find("Combat", 1, true) and window.note.text.text:find("^Default"))
    window.specs.onPick("assassination-rogue")
    -- With a BiS list: its best upgrades by these weights, and the sample line on the best.
    ns.BiS = { On = function() return true end, Lists = {
        List = function() return { slots = { [10] = 1, [11] = 4 } } end,
        CurrentSpec = function() return { key = "assassination-rogue" } end,
    } }
    state.worn = { [10] = 2, [11] = 4 }
    window.specs.onPick("assassination-rogue")
    local first = window.upgrades.rows[1]
    check("your best upgrade, its slot, by how much", first and first.shown and first.name.text:find("Item 1", 1, true)
        and first.slot.text == "Hands" and first.gain.text:find("^%+%d+%%") and not window.upgrades.note.shown)
    check("not what you wear", not (window.upgrades.rows[2] and window.upgrades.rows[2].shown))
    check("the sample line on it", window.sample.text:find(first.gain.text:match("%+%d+%%"), 1, true))
    state.modified = true
    first.scripts.OnClick(first)
    check("a shift-click links it, as items do elsewhere", state.linked == "link")
    -- Import, Export and Reset on the title bar, said plainly.
    local prompt, copied, confirmed
    ns.PromptText = function(title, _, _, onAccept) prompt = { title = title, accept = onAccept } end
    ns.ShowCopyLine = function(_, text) copied = text end
    ns.Confirm = function(_, yes) confirmed = yes end
    bar["Import weights"].onClick()
    check("Import says what it takes, and where WoWSims has it", prompt and prompt.title:find("WoWSims EP export", 1, true))
    prompt.accept('( Pawn: v1: "Sim": Class=Rogue, Agility=2, Ap=1 )')
    check("and takes a WoWSims export for the spec shown", SW.For("assassination-rogue").agi == 2
        and SW.For("assassination-rogue").str == 0)
    bar["Export these weights"].onClick()
    check("Export copies your weights as a line", copied and copied:find("^NFSW1:assassination%-rogue:"))
    bar["Reset to Default"].onClick()
    confirmed()
    Flush()
    check("Reset asks, then puts them all back", SW.For("assassination-rogue").agi ~= 2
        and window.note.text.text:find("^Default"))
end

print(("test-stat-weights: %d checks passed"):format(checks))
