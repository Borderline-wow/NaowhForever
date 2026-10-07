-------------------------------------------------------------------------------
--  UI/SettingsPage.lua -- the BiS List's settings page (BiS List/Settings in the options
--  window): a card that says where your list stands and opens the BiS List, then the list's
--  marks, Drop Alert with its live preview (UI/AlertPreview.lua), your lists and the window.
--  Stat Weights, the Character Panel and the Naowh Score add their own cards to this page.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local S = B.Settings
local L, R, A = B.Lists, B.Rankings, B.Actions

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local St = B.Style
local PLACE_DOT = St.PLACE_DOT
local BIS_OFF = "Turn on the BiS List"
local NEEDS_LOOKS = { "bis", "bisToast" }

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

local ALERT_FOR = { { bis = "Your BiS only", top2 = "Your top two", all = "Every pick" }, { "bis", "top2", "all" } }
local STARS = { { icon = "On the icon, left", iconRight = "On the icon, right", name = "Before the name",
    none = "Hidden" }, { "icon", "iconRight", "name", "none" } }
local BORDERS = { { none = "None", black = "Black", quality = "The item's quality",
    rank = "Your rank's colour (BiS orange)" }, { "none", "black", "quality", "rank" } }

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

-- A sound plays as you pick it, the game's own as well as the addon's.
local function SoundRow(key, label, help)
    return { key = key, label = label, choice = Sounds, needs = "bis", why = BIS_OFF, help = help,
        get = function() return S.Get(key) end,
        set = function(v)
            S.Set(key, v)
            B.Alerts.Play(v)
        end }
end

local function ListGet() return select(3, ns.BisListChoices()) end

local function SpecChoices()
    local values, order = {}, {}
    for _, spec in ipairs(R.ClassSpecs()) do
        values[spec.key] = spec.name
        order[#order + 1] = spec.key
    end
    return values, order
end

local function SpecGet()
    local spec = L.CurrentSpec()
    return spec and spec.key
end

local function MarksSummary(store)
    local tips, bags = store.Get("bisTooltip"), store.Get("bisBagMarks")
    if tips and bags then return "On tooltips and in your bags" end
    if tips then return "On tooltips" end
    if bags then return "In your bags" end
    return "Only in its window"
end

local function AlertSummary(store)
    local which = ALERT_FOR[1][store.Get("bisAlertFor")] or ALERT_FOR[1].all
    return which .. (store.Get("bisToast") and ", on screen" or "") .. (store.Get("bisAlertChat") and ", in chat" or "")
end

local function ListsSummary()
    local list = L.List()
    return list and (list.name:gsub("||", "|")) or ""
end

local function WindowSummary(store)
    return ("%d%% opacity"):format(math.floor((store.Get("bisWindowAlpha") or 1) * 100 + 0.5))
end

local page = Settings.Page("BiS List/Settings", S)

page:Window({
    text = "Open BiS List",
    open = function() ns.OpenBisWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "marks", name = "BiS List", order = 10,
    help = "Your list's marks on items out in the game.",
    summary = MarksSummary,
    rows = {
        { key = "bisTooltip", label = "Show on Tooltips", toggle = true, needs = "bis", why = BIS_OFF,
          help = "Your list's rank on the items in it." },
        { key = "bisBagMarks", label = "Bag Marks", toggle = true, needs = "bis", why = BIS_OFF,
          help = "Your BiS List's slot marks on the items in your bags: item level, your BiS's star, Forever's "
              .. "mark and the green arrow on an upgrade. In the game's bags or EllesmereUI's." },
        { key = "bisBagLevels", label = "Item Level in Bags", toggle = true, needs = "bisBagMarks",
          why = "Turn on Bag Marks", help = "Each gear item's level in the corner of its bag slot." },
    },
})

page:Card({
    id = "dropAlert", name = "Drop Alert", order = 20, switch = "bisLootAlert",
    help = "When an item on your list is up for a roll or in the loot window, and again when it is yours. "
        .. "Move the on-screen alert with Move Elements.",
    summary = AlertSummary,
    studio = B.AlertStudio,
    rows = {
        { key = "bisAlertFor", label = "Alert For", choice = ALERT_FOR, needs = "bis", why = BIS_OFF,
          help = "Which of your picks alert: your BiS only, your top two, or every pick on your list." },
        { key = "bisAlertChat", label = "Chat Line", toggle = true, needs = "bis", why = BIS_OFF,
          help = "A line in chat with the item's link." },
        { key = "bisAlertBadge", label = "Roll Frame Badge", toggle = true, needs = "bis", why = BIS_OFF,
          help = "Your star and rank on the game's roll frame." },
        SoundRow("bisDropSound", "Drop Sound", "When it is up for a roll or drops."),
        SoundRow("bisYoursSound", "It's Yours Sound", "When it is yours."),
        { label = "Play Test", button = function() A.TestAlert() end, buttonText = "Play Test", needs = "bis",
          why = BIS_OFF,
          help = "Plays Drop Alert with your list's first BiS, as you set it: up for a roll, dropped, then yours." },
        Settings.Group("On-Screen Alert"),
        { key = "bisToast", label = "On-Screen Alert", toggle = true, needs = "bis", why = BIS_OFF,
          help = "The item, your star and what happened, on screen for a while." },
        { key = "bisToastScale", label = "Size", slider = { 60, 160, 5 }, unit = "%", scale = 0.01,
          needs = NEEDS_LOOKS, help = "How big the on-screen alert is." },
        { key = "bisToastTime", label = "Stays For", slider = { 2, 15, 1 }, unit = "s", needs = NEEDS_LOOKS,
          help = "Seconds before it fades." },
        { key = "bisToastAlpha", label = "Background", slider = { 0, 100, 5 }, unit = "%", scale = 0.01,
          needs = NEEDS_LOOKS, help = "How solid its background is." },
        { key = "bisToastGlow", label = "Glow", toggle = true, needs = NEEDS_LOOKS,
          help = "A soft glow round it in your rank's colour." },
        { key = "bisToastStar", label = "Star", choice = STARS, needs = NEEDS_LOOKS,
          help = "Where your star sits: on the icon's corner, before the name, or hidden." },
        { key = "bisToastBorder", label = "Border", choice = BORDERS, needs = NEEDS_LOOKS,
          help = "Its edge: none, black, the item's quality, or your rank's colour." },
        Settings.Look("bisToast", { text = true, size = { 10, 20, 1 }, needs = NEEDS_LOOKS }),
        Settings.Group("Line Under the Name"),
        { key = "bisToastEvent", label = "What Happened", toggle = true, needs = NEEDS_LOOKS,
          help = "Up for a roll, dropped, or yours." },
        { key = "bisToastRank", label = "Your Rank", toggle = true, needs = NEEDS_LOOKS,
          help = "Your BiS, your second pick, and so on." },
        { key = "bisToastSlot", label = "The Slot", toggle = true, needs = NEEDS_LOOKS,
          help = "The slot it is for." },
        { key = "bisToastSource", label = "Where It Drops", toggle = true, needs = NEEDS_LOOKS,
          help = "The boss or place it comes from." },
        { key = "bisToastGain", label = "How Much Stronger", toggle = true, needs = NEEDS_LOOKS,
          help = "How much stronger it makes you by your stat weights, as +%." },
    },
})

page:Card({
    id = "lists", name = "Lists", order = 30,
    help = "Lists are shared by every character of your class; each character keeps using the one picked "
        .. "here. New, Rename, Import, Export and Delete are in the BiS List's window.",
    summary = ListsSummary,
    rows = {
        { label = "Your List", choice = ns.BisListChoices, get = ListGet, set = ns.SelectBisList,
          help = "The list this character uses." },
        { label = "Rankings For", choice = SpecChoices, get = SpecGet, set = ns.SetBisSpec,
          help = "Whose ranking the picker shows. Each spec keeps its own picks on a list." },
        { label = "Key Binding", binding = "NAOWHFOREVER_BIS",
          help = "Press this key to open the BiS List, and again to close it." },
    },
})

page:Card({
    id = "window", name = "Window", order = 80,
    help = "The BiS List's own window, and its Stat Weights window.",
    summary = WindowSummary,
    rows = {
        { key = "bisWindowAlpha", label = "Window Opacity", slider = { St.OPACITY_MIN, 100, 5 }, unit = "%",
          scale = 0.01, help = "How solid the BiS List's windows are, in percent. Also on their title bars." },
    },
})

-- A list picked, renamed or made in the window: the page names it.
B.OnListChange(function()
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end)
