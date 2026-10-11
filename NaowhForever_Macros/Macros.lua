-- Macros.lua: the Macros module's settings, its pack's class macros, the macro icons, the module table (ns.Macros) and the macros the Consumable Bar can carry.
local ns = _G.NaowhForever

local F = ns.FEATURES.macros

local S = ns.UI.ModuleSettings("macros", {
    enabled = F.enabled, classMacros = {},
    health = F.health, healthOrder = "potion", healthstone = F.healthstone, healthPotion = F.healthPotion,
    mana = F.mana, food = F.food, foodOnly = false, drink = F.drink, bandage = F.bandage,
    healthExtra = "", healthstoneExtra = "", healthPotionExtra = "", manaExtra = "", foodExtra = "",
    drinkExtra = "", bandageExtra = "",
    trinket1 = F.trinket1, trinket2 = F.trinket2,
    focus = F.focus, focusMark = true, focusMarker = 8, focusAnnounce = true,
    acceptPopup = F.acceptPopup, windowAlpha = 1,
})

local CLASS_MACROS = "classMacros"

ns.ConsumableMacros = {
    health = { label = "Health", name = "NF Health", icon = 134829 },
    healthstone = { label = "Healthstone", name = "NF Healthstone", icon = 135230 },
    healthPotion = { label = "Health Potion", name = "NF Health Potion", icon = 134830 },
    mana = { label = "Mana Potion", name = "NF Mana", icon = 134855 },
    food = { label = "Food", name = "NF Food", icon = 133971 },
    drink = { label = "Drink", name = "NF Drink", icon = 132794 },
    bandage = { label = "Bandage", name = "NF Bandage", icon = 133682 },
}

local GetSetting, SetSetting = S.Get, S.Set

local function PackMacros()
    local data = ns.DB().utilityReminders
    return data and data.classMacros or {}
end

local function SetPackMacros(value)
    local db = ns.DB()
    db.utilityReminders = db.utilityReminders or {}
    db.utilityReminders.classMacros = value
end

function S.Get(key)
    if key == CLASS_MACROS and ns.DB then return PackMacros() end
    return GetSetting(key)
end

function S.Set(key, value)
    if key == CLASS_MACROS and ns.DB then
        SetPackMacros(value)
    else
        SetSetting(key, value)
    end
end

ns.MacroSettings = S

local M = { Settings = S }
ns.Macros = M

function M.Redraw() end

local function EntryIcon(entry)
    local picked = ns.AccountSettings().macroIcons
    return picked and picked[entry.name] or entry.icon
end

ns.MacroEntryIcon = EntryIcon
