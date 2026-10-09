-- SettingsPage.lua: the Macros settings page (Macros/Settings), declared as cards.
local ns = _G.NaowhForever

local M = ns.Macros
local S = M.Settings
local Smart = M.Smart
local Settings = ns.Shared.Settings
local Group = Settings.Group

local OPACITY_RANGE, PERCENT_SCALE = ns.Shared.Style.OPACITY_RANGE, ns.Shared.Style.PERCENT_SCALE
local ORDER_KEPT, ORDER_HEALTH, ORDER_FOCUS, ORDER_WINDOW = 5, 20, 30, 40
local MACROS_OFF = "Turn on Macros"
local TEXT_KEPT = "%d of %d kept current"
local TEXT_ANNOUNCES_MARKS = "Announces and marks your focus"
local TEXT_ANNOUNCES = "Announces your focus"
local TEXT_MARKS = "Marks your focus"
local TEXT_JUST_FOCUS = "Just sets your focus"

local HEALTH_ORDER_VALUES = { stone = "Healthstone First", potion = "Potion First" }
local HEALTH_ORDER_ORDER = { "stone", "potion" }
local MARKER_VALUES = { [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull" }
local MARKER_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }

local On = Smart.On

local function MarkOn() return On() and S.Get("focusMark") == true end

local function HealthSummary(store)
    return HEALTH_ORDER_VALUES[store.Get("healthOrder")] or ""
end

local function FocusSummary(store)
    local announce, mark = store.Get("focusAnnounce"), store.Get("focusMark")
    if announce and mark then return TEXT_ANNOUNCES_MARKS end
    if announce then return TEXT_ANNOUNCES end
    if mark then return TEXT_MARKS end
    return TEXT_JUST_FOCUS
end

local function KeptSummary(store)
    return TEXT_KEPT:format(Smart.KeptCount(store), #Smart.list)
end

local page = Settings.Page("Macros/Settings", S)

page:Window({
    text = "Open Naowh's Forge",
    open = function() ns.OpenMacroWindow() end,
    headline = Smart.Headline,
    detail = Smart.Detail,
})

page:Card({
    id = "kept", name = "Kept Current", order = ORDER_KEPT,
    help = "The macros the addon writes and keeps up to date for you, out of combat. Switch one on here, "
        .. "or take it to your bars from Smart Macros in Naowh's Forge.",
    summary = KeptSummary,
    rows = {
        { key = "health", label = "NF Health", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best healthstone or healing potion." },
        { key = "mana", label = "NF Mana", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best mana potion." },
        { key = "food", label = "NF Food", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best food and drink, conjured first." },
        { key = "bandage", label = "NF Bandage", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best bandage, on yourself." },
        { key = "trinket1", label = "NF Trinket 1", toggle = true, needs = On, why = MACROS_OFF,
          help = "Uses your top trinket." },
        { key = "trinket2", label = "NF Trinket 2", toggle = true, needs = On, why = MACROS_OFF,
          help = "Uses your bottom trinket." },
        { key = "focus", label = "NF Focus", toggle = true, needs = On, why = MACROS_OFF,
          help = "Focuses your mouseover, or your target." },
        { key = "acceptPopup", label = "NF Accept", toggle = true, needs = On, why = MACROS_OFF,
          help = "Accepts the popup on screen: a summons, a resurrection, a group invite." },
    },
})

page:Card({
    id = "health", name = "Health Macro", order = ORDER_HEALTH,
    help = "NF Health uses the best healthstone or healing potion in your bags. Switch it on in Kept Current.",
    summary = HealthSummary,
    rows = {
        { key = "healthOrder", label = "Health Priority", choice = { HEALTH_ORDER_VALUES, HEALTH_ORDER_ORDER },
          needs = On, why = MACROS_OFF,
          help = "Which the macro uses first when you carry both: a healthstone or a healing potion." },
    },
})

page:Card({
    id = "focus", name = "Focus Macro", order = ORDER_FOCUS,
    help = "NF Focus focuses your mouseover, or your target. Switch it on in Kept Current.",
    summary = FocusSummary,
    rows = {
        Group("Announce"),
        { key = "focusAnnounce", label = "Announce Focus", toggle = true, needs = On, why = MACROS_OFF,
          help = "Tells your group what you focused." },
        Group("Marker"),
        { key = "focusMark", label = "Mark Focus", toggle = true, needs = On, why = MACROS_OFF,
          help = "Puts a raid marker on your focus. Pressing the macro again on the same focus clears the marker." },
        { key = "focusMarker", label = "Focus Marker", choice = { MARKER_VALUES, MARKER_ORDER }, needs = MarkOn,
          why = "Needs Mark Focus", help = "The raid marker Mark Focus puts on your focus." },
    },
})

page:Card({
    id = "window", name = "Window", order = ORDER_WINDOW,
    help = "Naowh's Forge, Macros' own window: your macros, the ones kept current, and Naowh's library.",
    search = "import export macro strings shorten to library save right-click right click icon star favorite",
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = OPACITY_RANGE,
          unit = "%", scale = PERCENT_SCALE, help = "How solid the window is, in percent. Also on its title bar." },
    },
})
