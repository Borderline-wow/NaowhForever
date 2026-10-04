-------------------------------------------------------------------------------
--  UI/SettingsPage.lua -- the BiS List's page in the options window: a card that says where
--  your list stands and opens the BiS List, its switch, Drop Alert with its studio (how the
--  alert looks, UI/AlertPreview.lua), then your lists, the key and the window. Page builder
--  only, resolved by the options window at open time.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local S = B.Settings
local L, R, A = B.Lists, B.Rankings, B.Actions

local St = B.Style
local PLACE_DOT = St.PLACE_DOT
local STUDIO_GAP = 8            -- the Drop Alert row to the studio under it

local function Headline()
    local list, spec = L.List(), L.CurrentSpec()
    return ("Your list: %s%s"):format(ns.Color("accentSoft", (list.name:gsub("||", "|"))),
        spec and ns.Color("muted", PLACE_DOT .. spec.name) or "")
end

local function Detail()
    local list = L.List()
    local have, total = R.Had(list)
    if total == 0 then return "Nothing picked yet: open it and pick each slot's BiS, or import a list." end
    local place = R.RunNext(list)[1]
    return ("You have %d of your %d BiS.%s"):format(have, total,
        place and (" Run next: %s, for %d."):format(place.name, place.bis) or "")
end

-- What a row needs on: the module, and Drop Alert too for what Drop Alert does.
local NEEDS_BIS = { "bis" }
local NEEDS_ALERT = { "bis", "bisLootAlert" }
local DROPDOWN_W = 200          -- the sounds, lists and specs: room for "Raid Warning (game)"
local ALERT_FOR_W = 160
local OPACITY_BOX_W = 52        -- room for "100%"

local function OpacityGet()
    return math.floor((S.Get("bisWindowAlpha") or 1) * 100 + 0.5)
end

local function OpacitySet(value)
    S.Set("bisWindowAlpha", value / 100)
end

local OPACITY_ROW = {
    type = "slider", text = "Window Opacity", min = St.OPACITY_MIN, max = 100, step = 5,
    boxWidth = OPACITY_BOX_W,
    tooltip = "How solid the BiS List's window is, in percent. Also on its title bar.",
    getValue = OpacityGet, setValue = OpacitySet,
}

local KEY_ROW = {
    type = "label", text = "Key Binding",
    tooltip = "Press this key to open the BiS List, and again to close it.",
}

local LIST_ROW = {
    type = "dropdown", text = "Your List", width = DROPDOWN_W,
    tooltip = "Lists are shared by every character of your class. Each character keeps using the one picked here.",
    getValue = function() return select(3, ns.BisListChoices()) end,
    setValue = ns.SelectBisList,
}

local MANAGE_ROW = {
    type = "buttons", text = "Manage Lists",
    buttons = {
        { text = "New", onClick = A.New, tooltip = "Start an empty list for your class." },
        { text = "Rename", onClick = A.Rename, tooltip = "Rename the list in use." },
        { text = "Import", onClick = A.Import, tooltip = "Paste a list someone shared." },
        { text = "Export", onClick = A.Export, tooltip = "Copy the list in use to share it." },
        { text = "Delete", onClick = A.Delete, tooltip = "Delete the list in use. Asks first." },
    },
}

local function SpecRow()
    local values, order = {}, {}
    for _, spec in ipairs(R.ClassSpecs()) do
        values[spec.key] = spec.name
        order[#order + 1] = spec.key
    end
    if not order[1] then return { type = "label", text = "" } end
    return { type = "dropdown", text = "Rankings For", values = values, order = order, width = DROPDOWN_W,
        tooltip = "Whose ranking the picker shows. Each spec keeps its own picks on a list.",
        getValue = function() local spec = L.CurrentSpec(); return spec and spec.key end,
        setValue = ns.SetBisSpec }
end

local ALERT_FOR = { values = { bis = "Your BiS only", top2 = "Your top two", all = "Every pick" },
    order = { "bis", "top2", "all" } }

-- The addon's sounds, with the game's two Drop Alert has always used first.
local function Sounds()
    local _, names, order = ns.SoundChoices()
    local values, keys = {}, {}
    for key, name in pairs(B.Alerts.GAME_SOUND_NAMES) do values[key] = name end
    keys[1], keys[2] = "game:raidwarning", "game:epicloot"
    for _, key in ipairs(order) do
        values[key] = names[key]
        keys[#keys + 1] = key
    end
    return values, keys
end

-- A sound to pick: it plays as you pick it, and its play button plays it again (the game's
-- sounds as well as the addon's, through Drop Alert's own player).
local function SoundRow(key, text, tooltip, values, order)
    return S.SoundDropdown(key, text, values, order, tooltip, NEEDS_ALERT, B.Alerts.Play)
end

-- Drop Alert: its switch and which picks, its studio, then chat, the roll frame and sounds.
local function DropAlert(parent, y)
    local W = ns.UI.Widgets
    local _, h
    _, h = W:SectionHeader(parent, "DROP ALERT", y); y = y - h
    local alertFor = S.Dropdown("bisAlertFor", "Alert For", ALERT_FOR.values, ALERT_FOR.order,
        "Which of your picks alert: your BiS only, your top two, or every pick on your list.", NEEDS_ALERT)
    alertFor.width = ALERT_FOR_W
    _, h = W:DualRow(parent, y,
        S.Toggle("bisLootAlert", "Drop Alert", "When an item on your list is up for a roll or in the loot "
            .. "window, and again when it is yours.", NEEDS_BIS),
        alertFor)
    y = y - h
    y = y - STUDIO_GAP - B.BuildAlertStudio(parent, y - STUDIO_GAP)
    _, h = W:DualRow(parent, y,
        S.Toggle("bisAlertChat", "Chat Line", "A line in chat with the item's link.", NEEDS_ALERT),
        S.Toggle("bisAlertBadge", "Roll Frame Badge", "Your star and rank on the game's roll frame.", NEEDS_ALERT))
    y = y - h
    local sounds, soundOrder = Sounds()
    _, h = W:DualRow(parent, y,
        SoundRow("bisDropSound", "Drop Sound", "When it is up for a roll or drops.", sounds,
            soundOrder),
        SoundRow("bisYoursSound", "It's Yours Sound", "When it is yours.", sounds, soundOrder))
    y = y - h
    return y
end

function ns.BuildQoLBiSSettingsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h, row
    y = ns.Shared.Parts.SettingsCard(parent, y, "bisCard", "Open BiS List", ns.OpenBisWindow, Headline(), Detail())

    _, h = W:SectionHeader(parent, "BIS LIST" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bis", "BiS List", "Tracks your list and marks the items on it."),
        S.Toggle("bisTooltip", "Show on Tooltips", "Your list's rank on the items in it.", NEEDS_BIS)); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bisBagMarks", "Bag Marks", "The marks your BiS List's slots have, on the items in your "
            .. "bags: each item's level, your BiS's star, Forever's mark on what is new in Forever, and "
            .. "the green arrow on gear better than what you wear by your stat weights. "
            .. "In the game's bags or EllesmereUI's, where ours stand in for its item level.", NEEDS_BIS)); y = y - h
    y = DropAlert(parent, y)

    _, h = W:SectionHeader(parent, "LISTS AND WINDOW", y); y = y - h
    LIST_ROW.values, LIST_ROW.order = ns.BisListChoices()
    _, h = W:DualRow(parent, y, LIST_ROW, SpecRow()); y = y - h
    _, h = W:DualRow(parent, y, MANAGE_ROW); y = y - h
    OPACITY_ROW.format = UI.FormatPercent
    row, h = W:DualRow(parent, y, KEY_ROW, OPACITY_ROW); y = y - h
    if row then   -- nil while the settings search scans this page
        UI.KeyField(row._leftRegion, "NAOWHFOREVER_BIS", "Open BiS List")
    end
    return y
end
