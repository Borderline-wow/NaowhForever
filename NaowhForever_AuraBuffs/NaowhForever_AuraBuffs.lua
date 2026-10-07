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
    campBuffTextSize = 16, campBuffSide = "below", campShowMissing = true,
    food = true, elixirs = true, flasks = true,
    consumablesWhere = "instance", consumablesMinutes = 2,
    onlyIfCarried = true, hideResting = true,
    scrolls = true, scrollsSkipActive = true,
    raidBuffs = false, raidBuffsOwn = true,
    iconSize = 36,

    campfire = true, campTimer = true, campBuffs = true,
    campSound = true, campSoundKey = "none", campIconSize = 64, campNearbyAlert = true,
    campShowUnder = false, campShowUnderMinutes = 10, campNearbyMinutes = 2, campStyle = "round",
    campAlertScale = 1.4, campAlertFade = true,
    campAlertFont = "", campAlertOutline = "", campAlertBackground = "none",
    campSimpleWidth = 360, campSimpleHeight = 26, campSimpleTextSize = 12, campBonusIcons = false,
    campHiddenBonuses = {},

    lowHealth = true, lowHealthBelow = 35, lowHealthItem = "auto",
    lowHealthIconSize = 48, lowHealthGlow = true,
    lowHealthSound = true, lowHealthSoundKey = "none",
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

-- Entries are profile data, never executable code. Require explicit item and aura IDs.
function ns.ParseConsumableEntry(category, text)
    if not CATEGORY_NAMES[category] or type(text) ~= "string" then return end
    local ids = {}
    for token in text:gmatch("[^,%s]+") do
        if not token:match("^%d+$") then return end
        local id = tonumber(token)
        if id < 1 or id > 2147483647 then return end
        ids[#ids + 1] = id
    end
    if #ids < 2 then return end
    local entry = { category = category, itemID = table.remove(ids, 1), auras = ids }
    return entry
end

local function EditEntry(category, index)
    local entries = S.Get("consumableEntries") or {}
    local existing = index and entries[index]
    local initial = existing and (existing.itemID .. ", " .. table.concat(existing.auras, ", ")) or ""
    ns.PromptText("Item ID, then buff spell ID(s), separated by commas", initial, 240, function(text)
        local entry = ns.ParseConsumableEntry(category, text)
        if not entry then ns.Print("Enter an item ID followed by at least one buff spell ID.") return end
        local copy = {}
        for i, value in ipairs(S.Get("consumableEntries") or {}) do copy[i] = value end
        copy[index or #copy + 1] = entry
        S.Set("consumableEntries", copy)
        UI:RefreshPage(true)
    end)
end

function ns.BuildAuraBuffConsumables(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Add an item ID and its buff spell ID(s), or import a profile with reminders. "
        .. "Nothing is added automatically. Hover a reminder to choose a configured item from your bags. "
        .. "Reminders pause in combat; item menus work outside combat. When and where they show is on "
        .. "AuraBuffs > Settings.", y); y = y - h
    for _, category in ipairs(CATEGORY_ORDER) do
        _, h = W:SectionHeader(parent, CATEGORY_NAMES[category]:upper(), y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "button", text = "Add " .. CATEGORY_NAMES[category], buttonText = "Add",
                onClick = function() EditEntry(category) end },
            { type = "label", text = "Item ID + buff spell IDs" }); y = y - h
        for index, entry in ipairs(S.Get("consumableEntries") or {}) do
            if entry.category == category then
                local name = C_Item.GetItemNameByID(entry.itemID) or ("Item " .. entry.itemID)
                _, h = W:DualRow(parent, y,
                    { type = "button", text = name, buttonText = "Edit",
                        onClick = function() EditEntry(category, index) end },
                    { type = "button", text = "Buffs: " .. table.concat(entry.auras, ", "), buttonText = "Remove",
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
