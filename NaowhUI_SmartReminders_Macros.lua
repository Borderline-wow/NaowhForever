-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Macros.lua -- the Macros module: character macros the addon
--  writes and keeps pointed at the best item or spell you have, rewritten out of combat
--  as bags and spells change.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local UI = ns.UI
local STATUS = UI.STATUS

local S = UI.ModuleSettings("macros", {
    enabled = true,
    health = false, healthOrder = "stone",
    mana = false, food = false, bandage = false,
    trinket1 = false, trinket2 = false,
    focus = false, focusMark = false, focusMarker = 8, focusAnnounce = false,
})
ns.MacroSettings = S

local HEALTH_ORDER_VALUES = { stone = "Healthstone First", potion = "Potion First" }
local HEALTH_ORDER_ORDER = { "stone", "potion" }

local MARKER_VALUES = { [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull" }
local MARKER_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }

function ns.BuildMacroConsumablesPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE .. " Each macro appears in your character macros "
        .. "once switched on. Put it on a bar once and it keeps itself current.", y); y = y - h

    _, h = W:SectionHeader(parent, "CONSUMABLE MACROS" .. STATUS.ready, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("health", "Health Macro",
            "Uses the best healthstone or healing potion in your bags."),
        S.Dropdown("healthOrder", "Health Priority", HEALTH_ORDER_VALUES, HEALTH_ORDER_ORDER,
            nil, "health")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mana", "Mana Potion Macro", "Uses the best mana potion in your bags."),
        S.Toggle("food", "Food & Drink Macro",
            "Eats or drinks the best food and water in your bags, conjured first.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bandage", "Bandage Macro",
            "Bandages yourself with the best bandage in your bags."),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "TRINKETS" .. STATUS.ready, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("trinket1", "Trinket 1 Macro", "Uses your top trinket slot."),
        S.Toggle("trinket2", "Trinket 2 Macro", "Uses your bottom trinket slot.")
    ); y = y - h

    return y
end

function ns.BuildMacroFocusPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "SET FOCUS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focus", "Set Focus Macro", "Focuses your mouseover, or your target."),
        S.Toggle("focusAnnounce", "Announce Focus", "Tells your group what you focused.", "focus")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusMark", "Mark Focus", "Puts a raid marker on your focus.", "focus"),
        S.Dropdown("focusMarker", "Focus Marker", MARKER_VALUES, MARKER_ORDER, nil, "focus")
    ); y = y - h

    _, h = W:SectionHeader(parent, "CLASS MACROS" .. STATUS.untested, y); y = y - h
    _, h = W:Note(parent, "Focus and cursor casts for your class, like interrupting your "
        .. "focus or dropping a ground effect at the cursor. These come once each class's "
        .. "Forever spells are mapped, since Forever's spell IDs differ from retail's.", y)
    y = y - h

    return y
end
