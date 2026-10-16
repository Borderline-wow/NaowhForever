-- ConsumableBar.lua: the Consumable Bar's module table (ns.ConsumableBar), its entries, their settings and its change listeners.
local ns = _G.NaowhForever

local S = ns.QoLSettings

local ITEM_FALLBACK = ns.L("Item %d")
local BUTTON_ITEM = "NaowhForeverConsumableBarItem%s"
local BUTTON_NAMED = "NaowhForeverConsumableBar%s"
local BIND_CLICK = "CLICK %s:LeftButton"
local MACRO_PREFIX = "macro:"
local MACRO_PATTERN = "^macro:(%a+)$"
local MACRO_NAME = "%s (%s)"
local MACROS_ADDON = "NaowhForever_Macros"
local ITEM_IN_BODY = "item:(%d+)"
local FOOD, DRINK = "smart:food", "smart:drink"
local MANA_MACRO, DRINK_MACRO = "macro:mana", "macro:drink"

local NEEDS_MANA = { [DRINK] = true, [MANA_MACRO] = true, [DRINK_MACRO] = true }
local OLD_ADDON = "NaowhForever_ConsumableBar"
local OLD_COPY = C_AddOns.DoesAddOnExist(OLD_ADDON) and C_AddOns.GetAddOnEnableState(OLD_ADDON) > 0

local SMART = {
    [FOOD] = { label = ns.L("Best Food"), button = "SmartFood", icon = ns.NO_FOOD.icon, empty = ns.NO_FOOD.text,
        binding = "food" },
    [DRINK] = { label = ns.L("Best Drink"), button = "SmartDrink", icon = ns.NO_DRINK.icon, empty = ns.NO_DRINK.text,
        binding = "drink" },
}

local NO_FLAGS = {}
local NO_ITEMS = {}
local listeners = {}
local best = {}
local shownFor, shownMacros, shown

local CB = {}
ns.ConsumableBar = CB
CB.S = S
CB.PREFIX = "consumableBar"
CB.PAGE = "Consumable Bar/Settings"
CB.CARD = "Consumable Bar/Settings:bar"
CB.FOOD, CB.DRINK = FOOD, DRINK
CB.OLD_COPY = OLD_COPY

function CB.On()
    return S.Get("consumableBar") == true and not OLD_COPY
end

function CB.Has(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function CB.Secret(v)
    return issecretvalue and issecretvalue(v)
end

function CB.SavedItems()
    local items = S.Get("consumableBarItems")
    return type(items) == "table" and items or NO_ITEMS
end

function CB.NeedsMana(entry)
    return NEEDS_MANA[entry] == true
end

local function Hidden(entry)
    if NEEDS_MANA[entry] and not ns.UsesMana() then return true end
    return type(entry) == "string" and entry:find(MACRO_PATTERN) ~= nil and not CB.MacroInfo(entry)
end

local function AnyHidden(items)
    for _, entry in ipairs(items) do
        if Hidden(entry) then return true end
    end
    return false
end

function CB.MacrosOn()
    return ns.ModuleOn(MACROS_ADDON)
end

function CB.Items()
    local items, macros = CB.SavedItems(), CB.MacrosOn()
    if shownFor == items and shownMacros == macros then return shown end
    if not AnyHidden(items) then return items end
    shownFor, shownMacros, shown = items, macros, {}
    for _, entry in ipairs(items) do
        if not Hidden(entry) then shown[#shown + 1] = entry end
    end
    return shown
end

function CB.Flags(entry)
    local all = S.Get("consumableBarItemFlags")
    return type(all) == "table" and all[entry] or NO_FLAGS
end

function CB.ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or ITEM_FALLBACK:format(itemID)
end

function CB.ItemSpell(itemID)
    local _, spellID = C_Item.GetItemSpell(itemID)
    if not spellID then C_Item.RequestLoadItemDataByID(itemID) end
    return spellID
end

function CB.MacroKey(entry)
    local key = type(entry) == "string" and entry:match(MACRO_PATTERN)
    return key and ns.ConsumableMacros and ns.ConsumableMacros[key] and CB.MacrosOn() and key
end

function CB.MacroInfo(entry)
    local key = CB.MacroKey(entry)
    local macros = ns.ConsumableMacros
    return key and macros and macros[key]
end

function CB.MacroEntry(key)
    return MACRO_PREFIX .. key
end

function CB.Smart(entry)
    return SMART[entry]
end

function CB.RefreshSmart()
    best[FOOD], best[DRINK] = ns.BestFoodAndDrink()
    local point = ns.FoodBarPoint
    if point then point(best[FOOD], best[DRINK]) end
end

function CB.Resolve(entry)
    if type(entry) == "number" then return entry end
    if SMART[entry] then return best[entry] end
    local info = CB.MacroInfo(entry)
    local body = info and GetMacroBody(info.name)
    return body and tonumber(body:match(ITEM_IN_BODY))
end

function CB.EntryName(entry)
    local info = CB.MacroInfo(entry)
    if info then return MACRO_NAME:format(info.label, info.name) end
    local smart = SMART[entry]
    if smart then return smart.label end
    if type(entry) ~= "number" then return entry end
    return CB.ItemName(entry)
end

function CB.EntryIcon(entry)
    local item = CB.Resolve(entry)
    if item then return C_Item.GetItemIconByID(item) or CB.C.EMPTY_ICON end
    local info = CB.MacroInfo(entry) or SMART[entry]
    return info and info.icon or CB.C.EMPTY_ICON
end

function CB.EmptyTip(entry)
    local smart = SMART[entry]
    if smart then return smart.empty end
    local info = CB.MacroInfo(entry)
    return info and CB.EntryName(entry)
end

function CB.ButtonName(entry)
    local key = CB.MacroKey(entry)
    if key then return BUTTON_NAMED:format((key:gsub("^%l", string.upper))) end
    local smart = SMART[entry]
    if smart and not ns.FoodBarBindings then return ns.FOOD_BUTTONS[smart.binding] end
    if smart then return BUTTON_NAMED:format(smart.button) end
    return BUTTON_ITEM:format(tostring(entry))
end

function CB.BindAction(entry)
    local smart = SMART[entry]
    local shared = ns.FoodBarBindings
    if smart and shared then return shared[smart.binding] end
    return BIND_CLICK:format(CB.ButtonName(entry))
end

function CB.HasMacro(key)
    return CB.Has(CB.SavedItems(), MACRO_PREFIX .. key)
end

function ns.ConsumableBarUsesMacro(key)
    return CB.On() and CB.HasMacro(key) and CB.MacrosOn() or false
end

function CB.HasFoodButtons()
    local saved = CB.SavedItems()
    return CB.Has(saved, FOOD) or (ns.UsesMana() and CB.Has(saved, DRINK))
end

function ns.ConsumableBarUsesFood()
    return CB.On() and CB.HasFoodButtons() or false
end

function CB.OnChange(fn)
    listeners[#listeners + 1] = fn
end

function CB.Changed()
    for _, fn in ipairs(listeners) do fn() end
end
