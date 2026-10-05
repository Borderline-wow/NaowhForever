-- Run with Lua 5.1 from the repository root: the Naowh character panel's slots, loaded from the
-- files Shared.xml and CharacterPanel.xml load, against stubs of the game's slot buttons. Checks
-- that it is off and hooks nothing by default; on, the game's art fades and each slot shows its
-- edge, item level, Forever's mark and your BiS's star, and no upgrade arrow; your score and your
-- spec's stats (their yardstick, worth bars, row height and hover cards); Slot Marks alone puts
-- the marks on the game's own panel as it looks; it stands down while
-- EllesmereUI styles the panel; your supporter badge shows only when you have one, never a grey
-- one or a pitch; off again, the game's art comes back; and neither a slot's update
-- nor a repaint of the stats makes garbage.
local Load = dofile("Tools/regression/load_files.lua")
local TocFiles = dofile("Tools/regression/toc_files.lua")
local Measure = dofile("Tools/regression/measure.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

-------------------------------------------------------------------------------
--  Stubs: a frame keeps its scripts, size, text, alpha and shown state; every other method is
--  one shared do-nothing function, so the stubs make no garbage of their own.
-------------------------------------------------------------------------------
local NOTHING = function() end
local Frame
local made = 0
local METHODS = {
    SetScript = function(f, script, fn) f.scripts[script] = fn end,
    HookScript = function(f, script, fn) f.hooks[script] = fn end,
    GetParent = function(f) return rawget(f, "parent") end,
    SetText = function(f, text) f.text = text end,
    -- A secret (see UnitStat below) formats as its value, as the game shows one.
    SetFormattedText = function(f, format, ...)
        local args = { ... }
        for i = 1, select("#", ...) do
            if type(args[i]) == "table" then args[i] = args[i].value end
        end
        f.text = format:format(unpack(args))
    end,
    Show = function(f) f.shown = true end,
    Hide = function(f) f.shown = false end,
    SetShown = function(f, shown) f.shown = shown and true or false end,
    IsShown = function(f) return rawget(f, "shown") ~= false end,
    IsVisible = function(f) return rawget(f, "shown") ~= false end,
    SetAlpha = function(f, alpha) f.alpha = alpha end,
    SetDesaturated = function(f, on) f.desaturated = on end,
    SetWidth = function(f, w) f.w = w end,
    SetHeight = function(f, h) f.h = h end,
    SetTexCoord = function(f, l) f.crop = l end,
    GetFrameLevel = function() return 1 end,
    GetStringWidth = function() return 40 end,
    GetText = function(f) return rawget(f, "text") end,
    GetWidth = function(f) return rawget(f, "w") or 300 end,
    GetHeight = function(f) return rawget(f, "h") or 37 end,
    SetPoint = function(f, point, relative) f.points = f.points or {}; f.points[point] = relative end,
    ClearAllPoints = function(f) f.points = {} end,
    GetEffectiveScale = function() return 1 end,
    CreateTexture = function(f) return Frame(f) end,
    CreateFontString = function(f) return Frame(f) end,
}
local META = { __index = function(_, key)
    if METHODS[key] then return METHODS[key] end
    if type(key) == "string" and key:find("^%u") then return NOTHING end
end }
function Frame(parent)
    made = made + 1
    return setmetatable({ scripts = {}, hooks = {}, parent = parent }, META)
end

local WHITE = { r = 1, g = 1, b = 1 }
local state = { worn = {}, links = {}, values = {}, listeners = {}, ellesmere = nil, gains = 0 }
local hooks = {}

-- The game's slot buttons, as Blizzard makes them: an icon, a quality border, a frame texture
-- and a border frame.
local function SlotButton()
    local button = Frame()
    button.icon, button.IconBorder, button.BorderFrame, button.normal = Frame(button), Frame(button),
        Frame(button), Frame(button)
    button.GetNormalTexture = function(self) return self.normal end
    return button
end

local NAMES = { [0] = "Ammo", "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard" }
local buttons = {}
for i, name in pairs(NAMES) do buttons[i] = SlotButton(); buttons["Character" .. name .. "Slot"] = buttons[i] end

local function Texture(parent) local x = Frame(parent); return x end
local character = Frame()
character.NineSlice, character.PortraitContainer = Frame(character), Frame(character)
character.LeftPaneHost, character.RightPaneHost = Frame(character), Frame(character)
local leftArt, rightArt, divider = Texture(), Texture(), Frame()
character.LeftPaneHost.GetRegions = function() return leftArt end
character.RightPaneHost.GetRegions = function() return rightArt end
character.RightPaneHost.GetChildren = function(self) return divider, unpack(self.children or {}) end
local close = Frame(character)
local closeArt = Texture(close)
close.GetNormalTexture = function() return closeArt end
character.CloseButton = close
character.RightPaneToggleButton = Frame(character)
local statsList = Frame(character)
statsList.ScrollBox, statsList.ScrollBar = Frame(statsList), Frame(statsList)
statsList.SetPoint = function(self, point, relative, _, _, y)
    self.points = self.points or {}
    self.points[point] = relative
    if point == "TOPLEFT" then self.drop = -(y or 0) end
    if point == "BOTTOMRIGHT" then self.lift = y or 0 end
end
local title, levelText = Frame(), Frame()
for _, text in ipairs({ title, levelText }) do
    text.GetFontObject = function() return "GameFontNormal" end
    text.SetFontObject = function(self, object) self.object = object end
    text.SetFont = function(self, path, size) self.size = size; self.object = nil end
end

local S = {
    Get = function(key) return state.values[key] end,
    Set = function(key, value)
        state.values[key] = value
        for _, fn in ipairs(state.listeners) do fn(key, value) end
    end,
    OnChange = function(fn) state.listeners[#state.listeners + 1] = fn end,
}
-- The QoL defaults this module adds, and the QoL switch on.
-- Slot Marks is on by default; off here, to start from nothing (its own checks turn it on).
state.values = { enabled = true, characterPanel = false, characterPanelSlotMarks = false, characterPanelLevels = true,
    characterPanelMarks = true, characterPanelEnchants = true, characterPanelScore = true,
    characterPanelBadge = true, characterPanelStats = "spec" }

-- Your list: the head's BiS is 101 (you wear it), the chest's 202 (you wear 200 there).
local LIST = { slots = { [1] = 101, [5] = 202 }, extra = {} }
local RANK = { [101] = 1 }
local enchantTodo = { [5] = true }
-- Your spec and its weights, the same tables each time, so a repaint's garbage is the module's.
local ASSASSINATION = { name = "Assassination Rogue" }
local WEIGHTS = { agi = 1, hit = 10, str = 0.5, int = 0 }
local STATS = { 44, 80 }   -- your Strength and Agility

local ns = {
    THEME = setmetatable({}, { __index = function() return WHITE end }),
    Color = function(_, text) return tostring(text) end,
    Font = function(parent) return Frame(parent) end,
    Solid = function(parent) return Frame(parent) end,
    Border = function()
        local border = { SetColor = function(self, r, g, b) self.r, self.g, self.b = r, g, b end }
        return border
    end,
    Hairline = function(region) return region end,
    UIFontPath = function() return "font" end,
    PixelInset = function(region) return region end,
    UI = { Keep = NOTHING },
    QoLSettings = S,
    Apply = NOTHING,
    IsBisItem = function(id) return RANK[id] end,
    BADGE_TIERS = {
        legendary = { title = "Legendary Patron", about = "Supports Naowh.", large = "legendaryArt",
            chat = "legendaryChat", markup = "|TlegendaryChat:0|t",
            color = { r = 1, g = 0.5, b = 0 } },
        developer = { title = "Developer", about = "Builds Naowh Forever.", large = "developerArt",
            color = { r = 0, g = 0.57, b = 0.93 } },
    },
    BadgeOf = function(guid)
        local entry = state.badges and state.badges[guid]
        if not entry then return nil end
        return state.badgeTiers[type(entry) == "table" and entry.tier or entry], entry
    end,
    BadgeSince = function() return nil end,
    StatWeights = {
        OnChange = NOTHING,
        STATS = { { "agi", "Agility" }, { "str", "Strength" }, { "hit", "Hit %" }, { "int", "Intellect" },
            { "sta", "Stamina" }, { "armor", "Armor" }, { "shit", "Spell Hit %" } },
        ActiveSpec = function() return "assassination-rogue" end,
        Spec = function(key) return key == "assassination-rogue" and ASSASSINATION or nil end,
        For = function() return WEIGHTS end,
    },
    -- The score: its own test is test-naowh-score's; here what the corner asks of it.
    NaowhScore = {
        Unit = function() return 8.3 end,
        Colored = function(score) return "|cff1eff00" .. score .. "|r" end,
        Best = function() return 58.8 end,
        Grade = function(score) return score / 58.8 end,
        RAMP = { { 0, 0.6, 0.6, 0.6 }, { 1, 1, 0.5, 0 } },
        Text = tostring,
    },
    ConfirmReload = function() state.reloads = (state.reloads or 0) + 1 end,
}
ns.BiS = {
    On = function() return true end,
    OnListChange = NOTHING,
    Lists = { List = function() return LIST end },
    Gains = { Read = function(_, out) out.now, out.bis = 8.3, 16.3; return out end },
    Upgrades = { Gain = function() state.gains = state.gains + 1; return 9 end },
    View = {
        EnchantBadge = function(parent) return Frame(parent) end,
        PaintEnchantBadge = function(badge, slot) badge:SetShown(enchantTodo[slot] == true) end,
    },
}

-- The tooltip keeps its lines, so a row's hover card can be read.
local tooltip = Frame()
tooltip.SetText = function(self, text) self.lines = { text } end
tooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
tooltip.NumLines = function(self) return #self.lines end

local env = setmetatable({
    NaowhForever = ns,
    CreateFrame = function(_, _, parent)
        local f = Frame(parent)
        if parent then
            local children = rawget(parent, "children") or {}
            parent.children = children
            children[#children + 1] = f
        end
        return f
    end,
    hooksecurefunc = function(a, b, c)
        if type(a) == "string" then hooks[a] = b else
            local original = a[b]
            a[b] = function(...) original(...); c(...) end
        end
    end,
    C_Item = {
        GetItemNameByID = function(id) return "item " .. id end,
        GetItemQualityByID = function(id) return id and 4 or nil end,
        GetDetailedItemLevelInfo = function(link) return state.links[link] end,
        IsEquippedItem = function(id)
            for _, worn in pairs(state.worn) do if worn == id then return true end end
            return false
        end,
        GetItemCount = function() return 0 end,
        GetItemInfoInstant = NOTHING,
        IsItemDataCachedByID = function() return true end,
    },
    GetInventoryItemID = function(_, slot) return state.worn[slot] end,
    UnitLevel = function() return 20 end,
    UnitGUID = function() return "Player-1-ME" end,
    UnitClass = function() return "Rogue", "ROGUE" end,
    UnitName = function() return "Die Man" end,
    RAID_CLASS_COLORS = { ROGUE = { colorStr = "fffff468" }, WARRIOR = { colorStr = "ffc79c6e" } },
    GetInventoryItemLink = function(_, slot) return state.worn[slot] and ("link" .. slot) end,
    ITEM_QUALITY_COLORS = { [4] = { hex = "|cffa335ee", r = 0.64, g = 0.21, b = 0.93 } },
    GameTooltip = tooltip,
    GameTooltip_Hide = NOTHING,
    UIParent = Frame(),
    Menu = { GetManager = function() return { IsAnyMenuOpen = function() return false end } end },
    EllesmereUI = nil,
    CharacterFrame = character,
    CharacterFrameTitleText = title,
    CharacterLevelText = levelText,
    CharacterStatsPaneScrollBox = statsList,
    CharacterFrameRightPaneHostStoneBg = "stoneArt",
    UnitArmor = function()
        if state.statsSecret then return { value = 250 }, { value = 250 } end
        return 250, 250
    end,
    GetCombatRatingBonus = function() if state.statsSecret then return { value = 0 } end return 0 end,
    -- While state.statsSecret, the game keeps your stats secret: a value that fails any arithmetic
    -- or comparison, which only the calls that take a secret can show.
    UnitStat = function(_, index)
        if state.statsSecret then return { value = 0 }, { value = STATS[index] or 0 } end
        return 0, STATS[index] or 0
    end,
    C_Secrets = { ShouldUnitStatsBeSecret = function() return state.statsSecret == true end },
    C_StringUtil = { FloorToNearestString = function(n)
        return tostring(math.floor(type(n) == "table" and n.value or n))
    end },
    GetHitModifier = function() return 3 end,
    GetSpellHitModifier = function() return 2 end,
    CR_HIT_SPELL = 8,
    CR_HIT_MELEE = 6,
    -- What a spec weighing many stats reads (its totals' own numbers do not matter here).
    UnitAttackPower = function() return 100, 0, 0 end,
    GetSpellBonusDamage = function() return 0 end,
    GetCritChance = function() return 5 end,
    GetSpellCritChance = function() return 2 end,
    GetMeleeHaste = function() return 0 end,
    UnitDamage = function() return 20, 30 end,
    UnitAttackSpeed = function() return 2 end,
    GetManaRegen = function() return 1 end,
    GameFontNormal = "GameFontNormal",
    CreateColor = function() return { SetRGBA = NOTHING } end,
}, { __index = function(_, key)
    if buttons[key] then return buttons[key] end
    return _G[key]
end })
env._G = env
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local files = TocFiles("^Shared/.*%.lua$")
for _, path in ipairs(TocFiles("^CharacterPanel/.*%.lua$")) do files[#files + 1] = path end
check("the TOC loads the module's files", files[#files] == "CharacterPanel/SettingsPage.lua")
Load(files, env)
local CP = ns.CharacterPanel
ns.Shared.ForeverNew.items[101] = true   -- the head's item is new in Forever

-------------------------------------------------------------------------------
--  Off by default: nothing hooked, nothing made.
-------------------------------------------------------------------------------
local before = made
ns.Apply()
check("off by default: the game's slot update not hooked, nothing made", hooks.PaperDollItemSlotButton_Update == nil
    and made == before and not CP.On())

-------------------------------------------------------------------------------
--  On: the game's art faded, ours over each slot.
-------------------------------------------------------------------------------
state.worn = { [1] = 101, [5] = 200, [16] = 300 }
state.links = { link1 = 30, link5 = 25, link16 = 1 }
S.Set("characterPanel", true)
local head, chest, weapon, shirt = buttons[1], buttons[5], buttons[16], buttons[4]
check("on: the game's slot update hooked; its slots' tooltips left alone", hooks.PaperDollItemSlotButton_Update ~= nil
    and head.hooks.OnEnter == nil)
check("the game's art faded, never hidden", head.normal.alpha == 0 and head.IconBorder.alpha == 0
    and head.BorderFrame.alpha == 0 and head.normal.shown ~= false)
check("the icon cropped as the BiS List's", head.icon.crop == 0.08)
check("the frame: its border, portrait, panes' art, divider and close button's look faded",
    character.NineSlice.alpha == 0 and character.PortraitContainer.alpha == 0 and leftArt.alpha == 0
    and rightArt.alpha == 0 and divider.alpha == 0 and closeArt.alpha == 0)
check("its title and level in our font", title.size == 12 and levelText.size == 14)
local badge = CP.badge
check("your Naowh Score big under your level, shown", badge and badge.parent == character
    and badge.shown ~= false and badge.points.TOP == levelText)
badge.scripts.OnShow(badge)
check("painted with your score, in its grade's colour, as the panel opens", badge.value.text == "|cff1eff008.3|r")
check("only the score: its bar's legend the best it is graded against", badge.best.text == "Best 58.8"
    and badge.rest.shown ~= false)

-- Grade Against Both (the default): your level's goal as a gold tick on the bar, with no label
-- (the tooltip names it), while it is short of the best in the game; with Best in the Game, no tick.
do
    local Score = ns.NaowhScore
    local best = Score.Best
    Score.Best = function(level) return level and 24.4 or 58.8 end
    S.Set("naowhScoreCompare", "both")
    check("Both: your level's goal ticked on the bar", badge.goal.shown == true
        and badge.goal.points.CENTER == badge.bar)
    check("no label for it, only the best's", badge.goalLabel == nil and badge.best.text == "Best 58.8")
    S.Set("naowhScoreCompare", "max")
    check("Best in the Game: no goal on the bar", badge.goal.shown == false)
    Score.Best = best
    S.Set("naowhScoreCompare", nil)
end

-- Ours: the frame the module made on the game's button.
local function Ours(button) return button.children and button.children[1] end
local Update = hooks.PaperDollItemSlotButton_Update
for _, button in ipairs(buttons) do Update(button) end
local h, c, w, s = Ours(head), Ours(chest), Ours(weapon), Ours(shirt)
check("ours over every slot, each knowing its slot", h and h.slot == 1 and c.slot == 5 and s.slot == 4)
check("an empty ammo slot (the game says item 0) is empty, its level not asked for",
    Ours(buttons[0]).marks.level.text == "" and Ours(buttons[0]).marks.forever.shown == false)
check("each slot's edge in its item's quality colour; an empty one black", h.edge.r == 0.64 and s.edge.r == 0)
check("its item level in the corner; none for an empty slot or a level 1 item", h.marks.level.text == 30
    and c.marks.level.text == 25 and w.marks.level.text == "" and s.marks.level.text == "")
check("Forever's mark on an item new in Forever, only there", h.marks.forever.shown == true and c.marks.forever.shown == false)
check("your BiS's star on it, nothing on what is not on your list", h.marks.rank.text ~= "" and c.marks.rank.text == "")
check("where your BiS is something you do not wear: no arrow, nothing on the slot", c.up == nil
    and c.marks.rank.text == "" and state.gains == 0)
check("the enchant dot where a better enchant waits", c.wand.shown == true and h.wand.shown == false)
Update(chest)

-- Settings: each part on its own.
S.Set("characterPanelLevels", false)
check("Item Level off: no levels", h.marks.level.text == "" and c.marks.level.text == "")
S.Set("characterPanelLevels", true)
S.Set("characterPanelMarks", false)
check("BiS Marks off: no star, no mark", h.marks.rank.text == "" and h.marks.forever.shown == false)
S.Set("characterPanelMarks", true)
S.Set("characterPanelEnchants", false)
check("Enchant Dots off: no dot", c.wand.shown == false)
S.Set("characterPanelEnchants", true)
S.Set("characterPanelScore", false)
check("Naowh Score off: no score in the corner", badge.shown == false)

-- Your supporter badge, in the left pane's top corner: only ever a badge of your own. A player
-- without one sees nothing there, and nothing asks them for one.
state.badgeTiers = ns.BADGE_TIERS
local opened = 0
ns.MakeModal = function() opened = opened + 1; return Frame(), Frame() end
S.Set("characterPanelBadge", true)
check("no badge: nothing in the corner, nothing made", CP.supportBadge == nil)
state.badges = { ["Player-1-ME"] = { tier = "developer", title = "Lead Developer" } }
S.Set("characterPanelBadge", true)
local support = CP.supportBadge
check("your supporter badge in the left pane's corner", support and support.parent == character.LeftPaneHost
    and support.shown ~= false)
support.scripts.OnShow(support)
check("yours: in its colour, with your own title", support.title.text == "Lead Developer"
    and support.line.text == "Naowh Forever Team" and support.emblem.desaturated ~= true)
check("a click on it opens nothing", support.scripts.OnClick == nil and opened == 0)
S.Set("characterPanelBadge", false)
check("Supporter Badge off: no badge", support.shown == false)
S.Set("characterPanelBadge", true)
check("and back on", support.shown == true)
state.badges = nil
character.LeftPaneHost.hooks.OnShow(character.LeftPaneHost)
check("once you have none, it goes as the panel opens", support.shown == false)
support.scripts.OnShow(support)
check("and a repaint without a badge hides it, never a grey one", support.shown == false and opened == 0)
state.badges = { ["Player-1-ME"] = "developer" }
character.LeftPaneHost.hooks.OnShow(character.LeftPaneHost)
check("a badge of your own shows again, looked at as the panel opens", support.shown == true)
state.badges = nil
character.LeftPaneHost.hooks.OnShow(character.LeftPaneHost)

-- No preview setting, grey badge or pitch is left in the panel's files.
for _, path in ipairs({ "CharacterPanel/Badge.lua", "CharacterPanel/SettingsPage.lua", "QoL/NaowhForever_QoL.lua" }) do
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a")
    f:close()
    for _, word in ipairs({ "characterPanelBadgeAsk", "Badge Preview", "Learn more", "MakeModal", "Patreon" }) do
        check(path .. " has no " .. word, not source:find(word, 1, true))
    end
end

-- The stats: your spec's first (the default), the game's list under it; the switch at the
-- pane's bottom.
local switch, spec
for _, child in ipairs(character.children or {}) do
    if rawget(child, "buttons") then switch = child elseif rawget(child, "rows") then spec = child end
end
-- The switch keeps its picked side in .shown (the shared tabs' own field), so its showing is
-- read through its own SetShown here.
switch.SetShown = function(self, on) self.visible = on and true or false end
spec.h = 300   -- the room down to the switch
statsList.hooks.OnShow(statsList)
check("your spec's stats first: ours over the game's list, the game's faded", switch and spec
    and switch.visible == true and switch.shown == "spec" and spec.shown == true and statsList.alpha == 0)
check("the switch's first side says which spec", switch.buttons[1].text.text == "Assassination"
    and switch.buttons[2].text.text == "All Stats")
check("the restyle's fade of the right pane's frames leaves ours be", switch.alpha ~= 0 and spec.alpha ~= 0)
-- The score is off here: the list starts where the game had it, and ends over the switch at
-- the pane's bottom (26 + 2 * 6).
check("the switch at the pane's bottom, the game's list ending over it", switch.points.BOTTOM == character.RightPaneHost
    and statsList.points.TOPLEFT == "stoneArt" and statsList.drop == 0 and statsList.lift == 38)
local rows = spec.rows
check("the stats in order: primary, then the ratings, then Stamina and Armor, each with your total",
    rows[1].name.text == "Agility" and rows[1].total.text == "80"
    and rows[2].name.text == "Strength" and rows[3].name.text == "Hit %" and rows[3].total.text == "3.0%"
    and rows[4].name.text == "Stamina" and rows[5].name.text == "Armor")
check("headed by the spec and the yardstick its weights are measured in", spec.title.text == "BEST FOR ASSASSINATION"
    and spec.head.text == "VS AGI")
-- Weights agi 1, str 0.5, hit 10: bars by the square root of their share of the heaviest, 50 wide.
check("each worth a bar, by the square root of its share of the heaviest", rows[3].bar.w == 50
    and rows[1].bar.w == 16 and rows[2].bar.w == 11 and rows[1].bar.shown ~= false)
check("Stamina and Armor shown whatever your spec weighs them, without a bar", rows[4].bar.shown == false
    and rows[5].track.shown == false and rows[5].total.text == "250")
local weightsOpened
ns.OpenStatWeightsWindow = function() weightsOpened = true end
spec.weights.scripts.OnClick(spec.weights)
check("on the title's line, the scales: a click to the stat weights, to change them",
    spec.weights.tip == "Stat Weights" and weightsOpened)
check("not what it does not weigh", rows[6].shown == false)
-- 300 tall, less the title and headings (48) and the bottom gap (4): 5 rows would get 49 each,
-- held to the roomy 30.
check("the rows share out the room, up to a roomy height", rows[1].h == 30 and rows[5].h == 30)
rows[3].scripts.OnEnter(rows[3])
check("a row's hover card: its worth in the yardstick, what it does, your total", tooltip.lines[1] == "Hit %"
    and tooltip.lines[2] == "1% Hit is worth 10 Agility to Assassination."
    and tooltip.lines[3] == "Chance not to miss: worth the most until you stop missing."
    and tooltip.lines[4] == "You: 3.0%")
rows[1].scripts.OnEnter(rows[1])
check("the yardstick's says so", tooltip.lines[2] == "Agility is the yardstick: every other stat is weighed against it.")
rows[4].scripts.OnEnter(rows[4])
check("one the spec does not weigh says so", tooltip.lines[2] == "Assassination does not count it.")
-- Repainted as your stats change, with no garbage.
spec.IsVisible = function() return true end
Measure(check)("your spec's stats repainted", 1, function() spec.scripts.OnEvent(spec) end)
-- Reported on Forever: your stats go secret under the game's addon restrictions.
state.statsSecret = true
spec.scripts.OnEvent(spec, "UNIT_STATS", "player")
check("secret stats: shown through the calls that take a secret", rows[1].total.text == "80"
    and rows[5].total.text == "250")
check("one we would have to add up ourselves, a dash", rows[3].name.text == "Hit %" and rows[3].total.text == "-")
for i = 1, 6 do
    env["GameTooltipTextLeft" .. i] = { SetFormattedText = function(_, format, value)
        tooltip.lines[i] = format:format(value)
    end }
end
rows[1].scripts.OnEnter(rows[1])
check("and its hover card's total, written the same way", tooltip.lines[#tooltip.lines] == "You: 80")
state.statsSecret = false
spec.scripts.OnEvent(spec, "ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
check("and back when the restriction lifts", rows[1].total.text == "80")
-- A spec weighing many stats: 14 rows still fit (17 each), the rest of the rows hidden.
local For = ns.StatWeights.For
ns.StatWeights.For = function()
    return { agi = 1, str = 0.5, int = 0.2, spi = 0.1, ap = 0.5, spell = 0.3, crit = 14, scrit = 2, hit = 10,
        haste = 8, dps = 7, mp5 = 0.4, sta = 0.15, armor = 0.01 }
end
statsList.hooks.OnShow(statsList)
check("many stats: every row fits above the switch", rows[14].shown ~= false and rows[15].shown == false
    and 14 * rows[1].h <= 300 - 52)
-- A caster: its spell hit, the game's spell hit (rating and talents) as its total.
ns.StatWeights.For = function() return { spell = 1, int = 0.3, shit = 14, sta = 0.05, armor = 0.005 } end
statsList.hooks.OnShow(statsList)
check("a caster's spell hit, its own total, after its power", rows[3].name.text == "Spell Hit %"
    and rows[3].total.text == "2.0%")
ns.StatWeights.For = For
statsList.hooks.OnShow(statsList)
statsList.shown = false
statsList.hooks.OnHide(statsList)
check("the game's titles or gear sets in its place: the switch and ours go", switch.visible == false
    and spec.shown == false)
statsList.shown = true
statsList.hooks.OnShow(statsList)
S.Set("characterPanelStats", "all")
check("All Stats again: the game's list back", spec.shown == false and statsList.alpha == 1)
S.Set("characterPanelScore", true)
statsList.hooks.OnShow(statsList)
-- With the score: the list down by what it needs beyond the room the game leaves
-- (10 under your level, the card 46 + 6 + 4 + 10 + 2, less 20).
check("score on: the game's list down under your score", statsList.drop == 58)

-- A slot's update makes no garbage.
Measure(check)("every slot updated", 1, function()
    for i = 1, #buttons do Update(buttons[i]) end
end)

-------------------------------------------------------------------------------
--  EllesmereUI styling the panel: this stands down, and the game's art is back for it.
-------------------------------------------------------------------------------
env.EllesmereUI = { GetBlizzWindowStyle = function(key) return key == "charsheet" and "eui" or "off" end }
S.Set("characterPanel", true)
check("EllesmereUI styles the panel: Naowh's stands down", not CP.On() and head.normal.alpha == 1
    and h.shown == false)
local paints = h.marks.level.text
state.links.link1 = 31
Update(head)
check("and the game's updates paint nothing of ours", h.marks.level.text == paints)
env.EllesmereUI = { GetBlizzWindowStyle = function() return "off" end }
S.Set("characterPanel", true)
check("its sheet at Blizz Default: Naowh's is on again", CP.On() and head.normal.alpha == 0 and h.shown == true)

-------------------------------------------------------------------------------
--  Off again: the game's art back, ours hidden, the icon whole.
-------------------------------------------------------------------------------
S.Set("characterPanel", false)
check("off: the game's list back where the game had it", statsList.drop == 0 and statsList.lift == 0)
check("off: the game's art back and ours hidden", head.normal.alpha == 1 and head.IconBorder.alpha == 1
    and head.icon.crop == 0 and h.shown == false)
check("the frame's art back, its title and level in the game's font again", character.NineSlice.alpha == 1
    and leftArt.alpha == 1 and closeArt.alpha == 1 and title.object == "GameFontNormal"
    and levelText.object == "GameFontNormal")
Update(head)
check("and the game's updates paint nothing of ours", h.shown == false)

-------------------------------------------------------------------------------
--  Slot Marks alone: the game's own panel as it looks (no EllesmereUI, ours off), with the
--  marks on its slots.
-------------------------------------------------------------------------------
S.Set("characterPanelSlotMarks", true)
check("Slot Marks: the game's art and whole icon kept, our edge hidden", not CP.On()
    and head.normal.alpha == 1 and head.IconBorder.alpha == 1 and head.icon.crop == 0 and h.look.shown == false)
check("and the marks on its slots: level, star, Forever's mark, enchant dot", h.shown == true
    and h.marks.level.text == 31 and h.marks.rank.text ~= "" and h.marks.forever.shown == true
    and c.wand.shown == true)
Update(head)
check("the game's slot update paints them, leaving its icon whole", h.shown == true and head.icon.crop == 0)
S.Set("characterPanel", true)
check("with the Naowh Character Panel too: its look, the marks the same", head.normal.alpha == 0
    and h.look.shown == true and h.marks.level.text == 31)
S.Set("characterPanel", false)
S.Set("characterPanelSlotMarks", false)
check("both off: ours hidden", h.shown == false and head.normal.alpha == 1)

-------------------------------------------------------------------------------
--  The switch swaps EllesmereUI's character panel for ours, and back: its own switch, after a
--  reload; back on only if ours turned it off.
-------------------------------------------------------------------------------
local db = {}
env.EllesmereUIDB = db
env.EllesmereUI = { GetBlizzWindowStyle = function() return db.themedCharacterSheet == false and "off" or "eui" end }
state.reloads = 0
S.Set("characterPanel", true)
check("on: EllesmereUI's character panel off, a reload offered, ours on", db.themedCharacterSheet == false
    and state.reloads == 1 and CP.On())
S.Set("characterPanel", false)
check("off: EllesmereUI's back on, a reload offered", db.themedCharacterSheet == true and state.reloads == 2
    and not CP.On())
db.themedCharacterSheet = false   -- turned off in EllesmereUI's own options
S.Set("characterPanel", true)
S.Set("characterPanel", false)
check("EllesmereUI's turned off by you: ours on and off leaves it off, no reload asked",
    db.themedCharacterSheet == false and state.reloads == 2)
env.EllesmereUIDB, env.EllesmereUI = nil, nil
S.Set("characterPanel", true)
S.Set("characterPanel", false)
check("without EllesmereUI: nothing to swap, no reload asked", state.reloads == 2)

print(("test-character-panel: %d checks passed"):format(checks))
