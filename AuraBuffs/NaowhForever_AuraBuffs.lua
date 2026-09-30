-------------------------------------------------------------------------------
--  NaowhForever_AuraBuffs.lua -- the AuraBuffs module: buff and consumable
--  reminders, the campfire, low health, and the debuff sounds the Poison & Dispel tab
--  hands to the existing debuff alert editor.
--
--  In combat the client refuses addons the player's auras outright
--  (GetAuraDataByIndex errors, GetPlayerAuraBySpellID returns nil with the buff up), so a
--  buff-based reminder has to freeze for the fight or it reads every buff as missing.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local STATUS = UI.STATUS

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
    campShowUnder = false, campShowUnderMinutes = 10,

    lowHealth = true, lowHealthBelow = 35, lowHealthItem = "auto",
    lowHealthIconSize = 48, lowHealthGlow = true,
    lowHealthSound = true, lowHealthSoundKey = "none",
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

local WHERE_VALUES = { always = "Everywhere", instance = "Dungeons & Raids", raid = "Raids Only" }
local WHERE_ORDER = { "always", "instance", "raid" }

local ITEM_VALUES = { auto = "Best in Bags", stone = "Healthstone", potion = "Healing Potion" }
local ITEM_ORDER = { "auto", "stone", "potion" }

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

function ns.BuildAuraBuffsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Add an item ID and its buff spell ID(s), or import a profile with reminders. "
        .. "Nothing is added automatically. Hover a reminder to choose a configured item from your bags. "
        .. "Reminders pause in combat; item menus work outside combat.", y); y = y - h
    _, h = W:SectionHeader(parent, "RAID BUFFS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("raidBuffs", "Raid Buff Reminders",
            "Missing class buffs in your group, out of combat, with how many are missing "
            .. "them. A camp buff standing in for one, the Incense Candle for Arcane Intellect "
            .. "for example, is not seen, so it still counts as missing."),
        S.Toggle("raidBuffsOwn", "Only Buffs I Can Cast",
            "Off: every buff a class in your group can cast.", "raidBuffs")
    ); y = y - h

    _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("iconSize", "Icon Size", 20, 64, 1, "Move the icons in Unlock Mode."),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "CONSUMABLES", y); y = y - h
    for _, category in ipairs(CATEGORY_ORDER) do
        _, h = W:Feature(parent, y, { type = "label", text = CATEGORY_NAMES[category] }); y = y - h
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
    _, h = W:Feature(parent, y, { type = "label", text = "Reminder Settings" }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("consumablesWhere", "Show In", WHERE_VALUES, WHERE_ORDER),
        S.Slider("consumablesMinutes", "Warn With Minutes Left", 0, 10, 1)); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("onlyIfCarried", "Only If I Carry One"),
        S.Toggle("hideResting", "Hide While Resting")); y = y - h

    return y
end

function ns.BuildCampfirePage(parent, y)
    local W = UI.Widgets
    local _, h

    local _, names, order = ns.SoundChoices()
    names.none = "None"
    table.insert(order, 1, "none")

    _, h = W:SectionHeader(parent, "CAMPFIRE" .. STATUS.limited, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campfire", "Campfire Reminder",
            "A round camp icon while Camp Benefits is up, a one minute countdown while you sit "
            .. "at a campfire, and a reminder when the camp is gone."),
        S.Toggle("campTimer", "Show Camp Timer",
            "A countdown in the icon, and a ring around it that drains as the camp runs down: "
            .. "green above 30 minutes, yellow above 5, red under 5.", "campfire")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campBuffs", "Show Active Camp Buffs",
            "The active effects reported in your Camp Benefits tooltip.", "campfire"),
        S.Slider("campIconSize", "Icon Size", 24, 110, 1, nil, "campfire")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campShowUnder", "Show Only When Low",
            "Keeps the icon hidden while Camp Benefits has more time left than Minutes, and "
            .. "shows it once the camp drops under that. The sitting countdown and the Refresh "
            .. "Camp reminder still show.", "campfire"),
        S.Slider("campShowUnderMinutes", "Minutes", 1, 59, 1, nil, "campShowUnder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campSound", "Play a Sound to Refresh",
            "Plays when it is time to refresh the camp.", "campfire"),
        S.Dropdown("campSoundKey", "Sound", names, order, nil, "campSound")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campNearbyAlert", "Camp Nearby Alert",
            "\"Camp Nearby\" in the middle of the screen when a campfire is in range and your "
            .. "camp needs refreshing: no Camp Benefits, or less than 2 minutes left. Move it in "
            .. "Unlock Mode.", "campfire"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        S.Slider("campBuffTextSize", "Buff Text Size", 8, 28, 1),
        S.Dropdown("campBuffSide", "Buff Text Position",
            { below = "Below", above = "Above", left = "Left", right = "Right" },
            { "below", "above", "left", "right" })
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campShowMissing", "Show Refresh Reminder"),
        { type = "label", text = "" }
    ); y = y - h
    return y
end

function ns.BuildLowHealthPage(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "LOW HEALTH" .. STATUS.ready, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lowHealth", "Low Health Reminder",
            "Shows a healing item's icon the moment your health drops below the threshold, "
            .. "in combat too: the game shows and hides it itself."),
        S.Slider("lowHealthBelow", "Show Below (%)", 10, 90, 1, nil, "lowHealth")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("lowHealthItem", "Item", ITEM_VALUES, ITEM_ORDER, nil, "lowHealth"),
        S.Slider("lowHealthIconSize", "Icon Size", 24, 96, 1, nil, "lowHealth")
    ); y = y - h
    local _, names, order = ns.SoundChoices()
    names.none = "None"
    table.insert(order, 1, "none")
    _, h = W:DualRow(parent, y,
        S.Toggle("lowHealthGlow", "Glow", nil, "lowHealth"),
        S.Toggle("lowHealthSound", "Play a Sound",
            "Plays once each time your health drops below the threshold. If the game hides "
            .. "your health from addons mid-fight, it only plays out of combat.", "lowHealth")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("lowHealthSoundKey", "Sound", names, order, nil, "lowHealthSound"),
        { type = "label", text = "" }
    ); y = y - h

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
    return ns.BuildDebuffsPage(parent, y)
end
