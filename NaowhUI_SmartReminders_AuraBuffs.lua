-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_AuraBuffs.lua -- the AuraBuffs module: buff and consumable
--  reminders, the campfire, low health, and the debuff sounds the Poison & Dispel tab
--  hands to the existing debuff alert editor.
--
--  In combat the client refuses addons the player's auras outright
--  (GetAuraDataByIndex errors, GetPlayerAuraBySpellID returns nil with the buff up), so a
--  buff-based reminder has to freeze for the fight or it reads every buff as missing.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local UI = ns.UI
local STATUS = UI.STATUS

local S = UI.ModuleSettings("auraBuffs", {
    enabled = true,
    food = true, elixirs = true, flasks = true,
    consumablesWhere = "instance", consumablesMinutes = 2,
    onlyIfCarried = true, hideResting = true,
    scrolls = true, scrollsSkipActive = true,
    raidBuffs = false, raidBuffsOwn = true,
    iconSize = 36,

    campfire = true, campTimer = true, campBuffs = true,
    campSound = true, campSoundKey = "none", campIconSize = 56, campNearbyAlert = true,

    lowHealth = true, lowHealthBelow = 35, lowHealthItem = "auto",
    lowHealthIconSize = 48, lowHealthGlow = true,
    lowHealthSound = true, lowHealthSoundKey = "none",
})
ns.AuraBuffSettings = S

local WHERE_VALUES = { always = "Everywhere", instance = "Dungeons & Raids", raid = "Raids Only" }
local WHERE_ORDER = { "always", "instance", "raid" }

local ITEM_VALUES = { auto = "Best in Bags", stone = "Healthstone", potion = "Healing Potion" }
local ITEM_ORDER = { "auto", "stone", "potion" }

function ns.BuildAuraBuffsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE .. " Buff reminders pause during combat: the game "
        .. "hides your buffs from addons until the fight ends, and they pick up again after.",
        y); y = y - h

    _, h = W:SectionHeader(parent, "FOOD, ELIXIRS & FLASKS" .. STATUS.limited, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("food", "Food Buff", "Reminds you to eat when your Well Fed buff is missing."),
        S.Toggle("flasks", "Flasks")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("elixirs", "Elixirs",
            "Battle and guardian elixirs are tracked separately, so one of each counts."),
        S.Dropdown("consumablesWhere", "Show In", WHERE_VALUES, WHERE_ORDER)
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("consumablesMinutes", "Warn With Minutes Left", 0, 10, 1,
            "Shows the reminder this long before a buff runs out. 0 waits until it is gone."),
        S.Toggle("onlyIfCarried", "Only If I Carry One",
            "Skips the reminder when nothing in your bags would fix it.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideResting", "Hide While Resting"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "SCROLLS" .. STATUS.limited, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("scrolls", "Scroll Reminder",
            "A scroll you loot, Scroll of Spirit for example, joins your buff reminders "
            .. "until you read it."),
        S.Toggle("scrollsSkipActive", "Skip If That Buff Is Up",
            "Stays quiet while you already have a buff of the same type.", "scrolls")
    ); y = y - h

    _, h = W:SectionHeader(parent, "RAID BUFFS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("raidBuffs", "Raid Buff Reminders",
            "Missing class buffs in your group, out of combat."),
        S.Toggle("raidBuffsOwn", "Only Buffs I Can Cast", nil, "raidBuffs")
    ); y = y - h

    _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("iconSize", "Icon Size", 20, 64, 1, "Move the icons in Unlock Mode."),
        { type = "label", text = "" }
    ); y = y - h

    return y
end

function ns.BuildCampfirePage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    local _, names, order = ns.SoundChoices()
    names.none = "None"
    table.insert(order, 1, "none")

    _, h = W:SectionHeader(parent, "CAMPFIRE" .. STATUS.limited, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campfire", "Campfire Reminder",
            "A round camp icon while Camp Benefits is up, and a reminder when it is not."),
        S.Toggle("campTimer", "Show Camp Timer",
            "A countdown in the icon, and a ring around it that drains as the camp runs down: "
            .. "green above 30 minutes, yellow above 5, red under 5.", "campfire")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("campBuffs", "Show Active Camp Buffs",
            "The camp buffs you have running, listed under the icon: Camp Chair, Fish Bowl, "
            .. "Tent and the rest.", "campfire"),
        S.Slider("campIconSize", "Icon Size", 24, 80, 1, nil, "campfire")
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

    return y
end

function ns.BuildLowHealthPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

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
