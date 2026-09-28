-------------------------------------------------------------------------------
--  NaowhForever_Macros.lua -- the Macros module: macros the addon
--  writes and keeps pointed at the best item or spell you have, rewritten out of combat
--  as bags and spells change.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local STATUS = UI.STATUS

local S = UI.ModuleSettings("macros", {
    enabled = true, classMacros = {},
    health = false, healthOrder = "stone",
    mana = false, food = false, bandage = false,
    trinket1 = false, trinket2 = false,
    focus = false, focusMark = false, focusMarker = 8, focusAnnounce = false,
})
-- Authored definitions travel with shared packs; presentation settings stay in this module.
local GetSetting, SetSetting = S.Get, S.Set
function S.Get(key)
    if key == "classMacros" and ns.DB then
        local data = ns.DB().utilityReminders
        return data and data.classMacros or {}
    end
    return GetSetting(key)
end
function S.Set(key, value)
    if key == "classMacros" and ns.DB then
        local db = ns.DB()
        db.utilityReminders = db.utilityReminders or {}
        db.utilityReminders.classMacros = value
    else
        SetSetting(key, value)
    end
end

ns.MacroSettings = S

local HEALTH_ORDER_VALUES = { stone = "Healthstone First", potion = "Potion First" }
local HEALTH_ORDER_ORDER = { "stone", "potion" }

local MARKER_VALUES = { [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull" }
local MARKER_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }

local function MacroIcon(key, text, tooltip)
    return { type = "iconbutton", text = text,
        tooltip = tooltip .. " Right-click to remove the macro.",
        icon = ({ health = 134829, mana = 134855, food = 133971, bandage = 133682,
            trinket1 = 134400, trinket2 = 134400, focus = 132212 })[key],
        active = function() return S.Get(key) == true end,
        onClick = function() ns.PickupManagedMacro(key) end,
        onRightClick = function() ns.RemoveManagedMacro(key) end }
end

function ns.BuildClassMacrosPage(parent, y)
    local W = UI.Widgets
    local _, h = W:Note(parent, "Class macros are supplied by your profile. Click or drag an icon to put its macro on your action bar.", y)
    y = y - h
    local _, class = UnitClass("player")
    local entries = (S.Get("classMacros") or {})[class] or {}
    if #entries == 0 then
        _, h = W:Note(parent, "No class macros configured for this class.", y)
        return y - h
    end
    for _, entry in ipairs(entries) do
        _, h = W:DualRow(parent, y,
            { type = "iconbutton", text = entry.name or "Class Macro", icon = entry.icon,
                tooltip = type(entry.body) == "string" and entry.body or nil,
                onClick = function() ns.PickupProfileMacro(entry) end },
            { type = "label", text = "Click or drag to action bar" }); y = y - h
    end
    return y
end

function ns.BuildMacroConsumablesPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Click or drag an icon to create a General macro and place it on your action bar. "
        .. "It keeps itself current as your bags change, updating after combat. Existing character "
        .. "macros stay in place so their action bar slots are preserved.", y); y = y - h

    _, h = W:SectionHeader(parent, "CONSUMABLE MACROS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        MacroIcon("health", "Health Macro",
            "Uses the best healthstone or healing potion in your bags."),
        S.Dropdown("healthOrder", "Health Priority", HEALTH_ORDER_VALUES, HEALTH_ORDER_ORDER,
            nil, "health")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        MacroIcon("mana", "Mana Potion Macro", "Uses the best mana potion in your bags."),
        MacroIcon("food", "Food & Drink Macro",
            "Eats or drinks the best food and water in your bags, conjured first.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        MacroIcon("bandage", "Bandage Macro",
            "Bandages yourself with the best bandage in your bags."),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "TRINKETS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        MacroIcon("trinket1", "Trinket 1 Macro", "Uses your top trinket slot."),
        MacroIcon("trinket2", "Trinket 2 Macro", "Uses your bottom trinket slot.")
    ); y = y - h

    return y
end

function ns.BuildMacroFocusPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:SectionHeader(parent, "SET FOCUS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        MacroIcon("focus", "Set Focus Macro", "Focuses your mouseover, or your target."),
        S.Toggle("focusAnnounce", "Announce Focus", "Tells your group what you focused.", "focus")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusMark", "Mark Focus", "Puts a raid marker on your focus. Pressing the "
            .. "macro again on the same focus clears the marker.", "focus"),
        S.Dropdown("focusMarker", "Focus Marker", MARKER_VALUES, MARKER_ORDER, nil, "focus")
    ); y = y - h

    return y
end

-------------------------------------------------------------------------------
--  Runtime
-------------------------------------------------------------------------------
-- Classic-era item IDs, best first.
local MANA_POTIONS = { 13444, 13443, 6149, 3827, 3385, 2455 }
local BANDAGES = { 14530, 14529, 8545, 8544, 6451, 6450, 3531, 3530, 2581, 1251 }
local CONJURED = {
    [8079] = true, [8078] = true, [8077] = true, [3772] = true, [2136] = true, [2288] = true,
    [5350] = true, [22895] = true, [8076] = true, [8075] = true, [1487] = true, [1114] = true,
    [1113] = true, [5349] = true,
}
local FOOD_SPELL, DRINK_SPELL = 433, 430
local ICON = 134400     -- question mark, so #showtooltip shows the item

local MACROS = {
    { key = "health", name = "NF Health" },
    { key = "mana", name = "NF Mana" },
    { key = "food", name = "NF Food" },
    { key = "bandage", name = "NF Bandage" },
    { key = "trinket1", name = "NF Trinket 1" },
    { key = "trinket2", name = "NF Trinket 2" },
    { key = "focus", name = "NF Focus" },
}

local ready, pending, warnedFull
local toDelete = {}

local function FirstCarried(list)
    for _, id in ipairs(list) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

-- Best food and best drink in the bags: conjured first, then the highest required level.
local function BestFoodAndDrink()
    local foodName, drinkName = C_Spell.GetSpellName(FOOD_SPELL), C_Spell.GetSpellName(DRINK_SPELL)
    local best, score = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            local spell = id and C_Item.GetItemSpell(id)
            local kind = (spell == foodName and "food") or (spell == drinkName and "drink")
            if kind then
                local s = (CONJURED[id] and 1000 or 0) + (select(5, C_Item.GetItemInfo(id)) or 0)
                if not score[kind] or s > score[kind] then best[kind], score[kind] = id, s end
            end
        end
    end
    return best.food, best.drink
end

local function UseLines(...)
    local lines = { "#showtooltip" }
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then lines[#lines + 1] = line end
    end
    if #lines == 1 then return end
    return table.concat(lines, "\n")
end

local function ItemLine(id, prefix)
    return id and ("/use " .. (prefix or "") .. "item:" .. id)
end

-- The macro body for each key, or nil to leave an existing macro as it is (nothing carried).
local BODIES = {
    health = function()
        local stone, potion = FirstCarried(ns.HEALTHSTONES), FirstCarried(ns.HEALING_POTIONS)
        if S.Get("healthOrder") == "potion" then return UseLines(ItemLine(potion or stone)) end
        return UseLines(ItemLine(stone or potion))
    end,
    mana = function() return UseLines(ItemLine(FirstCarried(MANA_POTIONS))) end,
    food = function()
        local food, drink = BestFoodAndDrink()
        return UseLines(ItemLine(food), ItemLine(drink))
    end,
    bandage = function() return UseLines(ItemLine(FirstCarried(BANDAGES), "[@player] ")) end,
    trinket1 = function() return "#showtooltip 13\n/use 13" end,
    trinket2 = function() return "#showtooltip 14\n/use 14" end,
    focus = function()
        local body = "/focus [@mouseover,exists,nodead][]"
        if S.Get("focusMark") then body = body .. "\n/tm [@focus] " .. S.Get("focusMarker") end
        -- Chat commands take no conditionals, so the channel is chosen here and the macro
        -- is rewritten on roster changes.
        local channel = (IsInRaid() and "/ra") or (IsInGroup() and "/p")
        if S.Get("focusAnnounce") and channel then
            body = body .. "\n" .. channel .. " Focus: %f"
        end
        return body
    end,
}

local function Write(m, body)
    local index = GetMacroIndexByName(m.name)
    if index > 0 then
        if GetMacroBody(index) ~= body then EditMacro(index, m.name, ICON, body) end
        return
    end
    local accountCount = GetNumMacros()
    if accountCount >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
        if not warnedFull then
            warnedFull = true
            ns.Print("General macros are full, so " .. m.name
                .. " could not be made. Delete one and it will be added.")
        end
        return
    end
    CreateMacro(m.name, m.icon or ICON, body, false)
end

local function Update()
    if not ready then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local on = S.Get("enabled")
    for _, m in ipairs(MACROS) do
        if on and S.Get(m.key) then
            toDelete[m.name] = nil
            local body = BODIES[m.key]()
            if body then Write(m, body) end
        elseif toDelete[m.name] then
            toDelete[m.name] = nil
            local index = GetMacroIndexByName(m.name)
            if index > 0 then DeleteMacro(index) end
        end
    end
end

function ns.PickupManagedMacro(key)
    if InCombatLockdown() then ns.Print("Move macros outside combat.") return end
    if not ready or not S.Get("enabled") then ns.Print("Enable Macros first.") return end
    S.Set(key, true)
    if UI.RefreshPage then UI:RefreshPage(true) end
    Update()
    for _, macro in ipairs(MACROS) do
        if macro.key == key then
            local index = GetMacroIndexByName(macro.name)
            if index > 0 then PickupMacro(index)
            else ns.Print("Carry a matching item and make room in General macros first.") end
            return
        end
    end
end

function ns.RemoveManagedMacro(key)
    if InCombatLockdown() then ns.Print("Remove macros outside combat.") return end
    if not S.Get(key) then return end
    S.Set(key, false)
    if UI.RefreshPage then UI:RefreshPage(true) end
end

local SCRIPT_COMMANDS = { ["/run"] = true, ["/script"] = true, ["/dump"] = true }

function ns.PickupProfileMacro(entry)
    if InCombatLockdown() or not ready or not S.Get("enabled") then return end
    if type(entry.name) ~= "string" or #entry.name < 1 or #entry.name > 16
        or type(entry.body) ~= "string" or #entry.body < 1 or #entry.body > 255 then
        ns.Print("A profile macro needs a name (1-16 characters) and body (1-255 characters).")
        return
    end
    local index = GetMacroIndexByName(entry.name)
    if index > 0 and GetMacroBody(index) ~= entry.body then
        ns.Print("A different macro already uses that name; rename it before adding the profile macro.")
        return
    end
    local function Place()
        if InCombatLockdown() then return end
        Write(entry, entry.body)
        local placed = GetMacroIndexByName(entry.name)
        if placed > 0 then PickupMacro(placed) end
    end
    -- Profile macros come from shared packs, so script lines need the player's say-so.
    if index == 0 then
        for line in entry.body:gmatch("[^\n]+") do
            local command = line:match("^%s*(/%a+)")
            if command and SCRIPT_COMMANDS[command:lower()] then
                ns.Confirm(entry.name .. " runs a script from a shared profile. Hover its icon to "
                    .. "read it first. Create it?", Place)
                return
            end
        end
    end
    Place()
end

-- Only switching a macro or the module off deletes it. A profile or spec switch that turns
-- one off leaves it alone, since deleting a macro also empties its action bar slot.
local function SettingChanged(key, value)
    if value == false then
        for _, m in ipairs(MACROS) do
            if key == "enabled" or key == m.key then toDelete[m.name] = true end
        end
    end
    Update()
end

-- Nothing is written before the first PLAYER_ENTERING_WORLD, when the character's macros
-- are loaded; GetMacroIndexByName misses them earlier and every macro would be made twice.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        ready = true
    elseif event == "PLAYER_REGEN_ENABLED" and not pending then
        return
    elseif event == "GROUP_ROSTER_UPDATE" and not (S.Get("focus") and S.Get("focusAnnounce")) then
        return
    end
    Update()
end)
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
-- Fires when a macro is deleted, so a macro that did not fit is made once there is room.
events:RegisterEvent("UPDATE_MACROS")

hooksecurefunc(S, "Set", SettingChanged)
hooksecurefunc(ns, "Apply", Update)
