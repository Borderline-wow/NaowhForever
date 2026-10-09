-------------------------------------------------------------------------------
--  NaowhForever_AuraBuffs.lua -- the AuraBuffs module: buff and consumable
--  reminders, the campfire, low health, and the debuff sounds the AuraBuffs window
--  hands to the existing debuff alert editor. Its settings page is AuraBuffs > Settings.
--
--  In combat the client refuses addons the player's auras outright
--  (GetAuraDataByIndex errors, GetPlayerAuraBySpellID returns nil with the buff up), so a
--  buff-based reminder has to freeze for the fight or it reads every buff as missing.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local S = UI.ModuleSettings("auraBuffs", {
    enabled = true, consumableEntries = {},
    campBuffTextSize = 16, campBuffSide = "right", campShowMissing = true,
    food = true, elixirs = true, flasks = true,
    consumablesWhere = "instance", consumablesMinutes = 2,
    onlyIfCarried = true, hideResting = true,
    scrolls = true, scrollsSkipActive = false,
    raidBuffs = false, raidBuffsOwn = true,
    raidBuffPicks = { intellect = true, stamina = true, spirit = true, wild = true, blessing = false },
    iconSize = 36, buffsFont = "", buffsFontSize = 14, buffsOutline = "OUTLINE",
    buffsPos = { point = "TOP", relPoint = "TOP", x = 0, y = -232 },

    campfire = true, campTimer = true, campBuffs = true,
    campSound = true, campSoundKey = "none", campIconSize = 110, campNearbyAlert = true,
    campShowUnder = true, campShowUnderMinutes = 2, campNearbyMinutes = 2, campStyle = "round",
    campAlertScale = 1.4, campAlertFade = true,
    campAlertFont = "", campAlertOutline = "", campAlertBackground = "none",
    campSimpleWidth = 360, campSimpleHeight = 26, campSimpleTextSize = 12, campBonusIcons = false,
    campHiddenBonuses = {}, campFont = "", campOutline = "", campBarOutline = "NONE",
    campPos = { point = "CENTER", relPoint = "BOTTOMRIGHT", x = -223, y = 61 },

    lowHealth = true, lowHealthBelow = 35, lowHealthItem = "auto",
    lowHealthIconSize = 48, lowHealthGlow = true,
    lowHealthFont = "", lowHealthFontSize = 16, lowHealthOutline = "OUTLINE",
    lowHealthSound = true, lowHealthSoundKey = "none",
    lowHealthPos = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 249 },
    campBuffMode = false, windowAlpha = 1,
})
-- Authored definitions travel with shared packs; presentation settings stay in this module.
local GetSetting, SetSetting = S.Get, S.Set
function S.Get(key)
    if key == "consumableEntries" and ns.DB then
        local data = ns.DB().utilityReminders
        return data and data.consumables or {}
    end
    return GetSetting(key)
end
function S.Set(key, value)
    if key == "consumableEntries" and ns.DB then
        local db = ns.DB()
        db.utilityReminders = db.utilityReminders or {}
        db.utilityReminders.consumables = value
    else
        SetSetting(key, value)
    end
end

ns.AuraBuffSettings = S

local CATEGORY_NAMES = { food = "Food", flask = "Flask", scroll = "Scroll",
    battle = "Battle Elixir", guardian = "Guardian Elixir" }
local CATEGORY_ORDER = { "food", "flask", "scroll", "battle", "guardian" }
local LIST_PREFIX = "NFCONSUMABLES1:"
local MAX_ENTRIES = 500   -- a pack holding more is refused on import

-- Entries are profile data, never executable code. Buff IDs are only needed when the buff is
-- not the item's own: food counts any Well Fed, other items their use spell.
function ns.ParseConsumableEntry(category, text)
    if not CATEGORY_NAMES[category] or type(text) ~= "string" then return end
    local ids = {}
    for token in text:gmatch("[^,%s]+") do
        if not token:match("^%d+$") then return end
        local id = tonumber(token)
        if id < 1 or id > 2147483647 then return end
        ids[#ids + 1] = id
    end
    if #ids == 0 then return end
    local itemID = table.remove(ids, 1)
    return { category = category, itemID = itemID, auras = ids[1] and ids or nil }
end

local function EditEntry(category, index)
    local entries = S.Get("consumableEntries") or {}
    local existing = index and entries[index]
    local initial = existing and existing.itemID .. (existing.auras and ", " .. table.concat(existing.auras, ", ") or "") or ""
    ns.PromptText("Item ID, then buff spell ID(s) if not the item's own", initial, 240, function(text)
        local entry = ns.ParseConsumableEntry(category, text)
        if not entry then ns.Print("Enter an item ID, then any buff spell IDs, separated by commas.") return end
        local copy = {}
        for i, value in ipairs(S.Get("consumableEntries") or {}) do copy[i] = value end
        copy[index or #copy + 1] = entry
        S.Set("consumableEntries", copy)
        UI:RefreshPage(true)
    end)
end

-- One line, since the paste box is one line: food=13931,2680;battle=13454/17539
function ns.ConsumableListString(entries)
    local byCategory = {}
    for _, entry in ipairs(entries) do
        local ids = byCategory[entry.category] or {}
        byCategory[entry.category] = ids
        ids[#ids + 1] = entry.auras and entry.itemID .. "/" .. table.concat(entry.auras, "/") or tostring(entry.itemID)
    end
    local groups = {}
    for _, category in ipairs(CATEGORY_ORDER) do
        if byCategory[category] then
            groups[#groups + 1] = category .. "=" .. table.concat(byCategory[category], ",")
        end
    end
    return LIST_PREFIX .. table.concat(groups, ";")
end

-- A list string, or a profile string whose consumables are taken and nothing else.
function ns.ParseConsumableList(text)
    text = text:gsub("%s", "")
    local entries = {}
    if text:sub(1, #LIST_PREFIX) == LIST_PREFIX then
        for group in text:sub(#LIST_PREFIX + 1):gmatch("[^;]+") do
            local category, ids = group:match("^(%a+)=(.+)$")
            if not category then return end
            for item in ids:gmatch("[^,]+") do
                local entry = ns.ParseConsumableEntry(category, (item:gsub("/", ",")))
                if not entry then return end
                entries[#entries + 1] = entry
            end
        end
    else
        local payload = ns.DecodeProfile(text)
        local sr = payload and payload.parts.smartReminders
        local list = sr and type(sr.utilityReminders) == "table" and sr.utilityReminders.consumables
        for _, entry in ipairs(type(list) == "table" and list or {}) do entries[#entries + 1] = entry end
    end
    if #entries > 0 then return entries end
end

local function ImportList()
    ns.PromptText("Paste a consumables list or a profile string", "", 0, function(text)
        local incoming = ns.ParseConsumableList(text)
        if not incoming then ns.Print("That string holds no consumables list.") return end
        local entries, have = {}, {}
        for i, entry in ipairs(S.Get("consumableEntries") or {}) do
            entries[i] = entry
            have[entry.category .. ":" .. entry.itemID] = true
        end
        local added = 0
        for _, entry in ipairs(incoming) do
            local key = entry.category .. ":" .. entry.itemID
            if not have[key] and #entries < MAX_ENTRIES then
                have[key] = true
                entries[#entries + 1] = entry
                added = added + 1
            end
        end
        S.Set("consumableEntries", entries)
        ns.Print(("Added %d consumables; %d were already listed or past the %d limit."):format(
            added, #incoming - added, MAX_ENTRIES))
        UI:RefreshPage(true)
    end)
end

local function ExportList()
    local entries = S.Get("consumableEntries") or {}
    if #entries == 0 then ns.Print("There are no consumables to export yet.") return end
    ns.ShowCopyBox("Consumables list", ns.ConsumableListString(entries))
end

function ns.BuildAuraBuffConsumables(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Add an item ID, or import a list. Food counts any Well Fed "
        .. "buff and other items their own buff; add buff spell IDs only for an item that gives another. "
        .. "Nothing is added automatically. Hover a reminder to choose a configured item from your bags. "
        .. "Reminders pause in combat; item menus work outside combat. When and where they show is on "
        .. "AuraBuffs > Settings.", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Import a list or a profile's consumables", buttonText = "Import",
            onClick = ImportList },
        { type = "button", text = "Copy this profile's list", buttonText = "Export", onClick = ExportList })
    y = y - h
    for _, category in ipairs(CATEGORY_ORDER) do
        _, h = W:SectionHeader(parent, CATEGORY_NAMES[category]:upper(), y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "button", text = "Add " .. CATEGORY_NAMES[category], buttonText = "Add",
                onClick = function() EditEntry(category) end },
            { type = "label", text = "Item ID, buff spell IDs optional" }); y = y - h
        for index, entry in ipairs(S.Get("consumableEntries") or {}) do
            if entry.category == category then
                local name = C_Item.GetItemNameByID(entry.itemID) or ("Item " .. entry.itemID)
                local buffs = entry.auras and "Buffs: " .. table.concat(entry.auras, ", ")
                    or category == "food" and "Buff: any Well Fed" or "Buff: the item's own"
                _, h = W:DualRow(parent, y,
                    { type = "button", text = name, buttonText = "Edit",
                        onClick = function() EditEntry(category, index) end },
                    { type = "button", text = buffs, buttonText = "Remove",
                        onClick = function()
                            local copy = {}
                            for i, value in ipairs(S.Get("consumableEntries") or {}) do
                                if i ~= index then copy[#copy + 1] = value end
                            end
                            S.Set("consumableEntries", copy)
                            UI:RefreshPage(true)
                        end }); y = y - h
            end
        end
    end
    return y
end

-- The debuff alert editor already registers these with C_UnitAuras.AddAuraSound, which the
-- game plays itself mid-combat whatever the addon can read. Sound only: nothing can be
-- drawn off an aura the addon cannot see.
function ns.BuildPoisonDispelPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "A sound when a poison, disease or curse lands on you, even in "
        .. "combat. Add each debuff by its aura spell ID. Sound only, no on-screen glow. "
        .. "Dwarves can pick the Stoneform voice, which only speaks while Stoneform is "
        .. "ready.", y); y = y - h
    -- The debuff sounds run in Smart Reminders.
    if not ns.BuildDebuffsPage then
        _, h = W:Note(parent, "Turn on Smart Reminders under Settings > Modules to add debuff sounds.", y)
        return y - h
    end
    return ns.BuildDebuffsPage(parent, y)
end

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local function DebuffSounds()
    local I = ns.Integrations
    local rules = I and I.Rules and I.Rules(false)
    local n = 0
    for _, rule in pairs(rules or {}) do
        if type(rule) == "table" and rule.trigger and rule.trigger.type == "auraSound" then n = n + 1 end
    end
    return n
end

local function Headline()
    if not S.Get("enabled") then return "AuraBuffs is off" end
    local n = #(S.Get("consumableEntries") or {})
    if n == 0 then return "No consumables to watch yet" end
    return ("%d %s to watch"):format(n, n == 1 and "consumable" or "consumables")
end

local function Detail()
    local n = DebuffSounds()
    if n == 0 then return "Add the consumables to watch, and debuffs that play a sound, in the AuraBuffs window." end
    return ("%d %s play a sound. Edit both lists in the AuraBuffs window."):format(n,
        n == 1 and "debuff" or "debuffs")
end

local function WindowSummary(store)
    return ("%d%% opacity"):format(math.floor((store.Get("windowAlpha") or 1) * 100 + 0.5))
end

local page = Settings.Page("AuraBuffs/Settings", S)

page:Window({
    text = "Open AuraBuffs",
    open = function() ns.OpenAuraBuffsWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "window", name = "Window", order = 50,
    help = "The AuraBuffs window: the consumables to watch and the debuffs that play a sound.",
    summary = WindowSummary,
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 }, unit = "%",
          scale = 0.01, help = "How solid the window is, in percent. Also on its title bar." },
    },
})
