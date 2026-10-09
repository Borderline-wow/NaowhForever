-- Macros.lua: the Macros module's settings, its pack's class macros, the macro icons and the module table (ns.Macros).
local ns = _G.NaowhForever

local F = ns.FEATURES.macros

local S = ns.UI.ModuleSettings("macros", {
    enabled = F.enabled, classMacros = {},
    health = F.health, healthOrder = "potion",
    mana = F.mana, food = F.food, bandage = F.bandage,
    trinket1 = F.trinket1, trinket2 = F.trinket2,
    focus = F.focus, focusMark = true, focusMarker = 8, focusAnnounce = true,
    acceptPopup = F.acceptPopup, windowAlpha = 1,
})

local CLASS_MACROS = "classMacros"

local GetSetting, SetSetting = S.Get, S.Set
local icons

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

local function MacroIcons()
    if icons then return icons end
    local all = {}
    GetLooseMacroIcons(all)
    GetLooseMacroItemIcons(all)
    GetMacroIcons(all)
    GetMacroItemIcons(all)
    icons = {}
    for _, icon in ipairs(all) do
        local id = tonumber(icon)
        if id then icons[#icons + 1] = id end
    end
    return icons
end

ns.MacroIconList = MacroIcons

local function IconChoices()
    local account = ns.AccountSettings()
    account.macroIcons = account.macroIcons or {}
    return account.macroIcons
end

local function EntryIcon(entry)
    return IconChoices()[entry.name] or entry.icon
end

ns.MacroEntryIcon = EntryIcon
