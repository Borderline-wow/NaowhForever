-------------------------------------------------------------------------------
--  NaowhForever_Discovery.lua -- the Discovery module: the library books you can still
--  find, how many you have handed in toward the Friend of the Library rewards, and who takes
--  them for your faction (NaowhForever_DiscoveryData.lua); and the Cozy Sleeping Bag's hidden
--  quest chain, step by step (NaowhForever_SleepingBagData.lua). Its settings are two tabs,
--  Library Books and Sleeping Bag.
--
--  Off by default, every feature too. The tracker, map pin and nearby files register nothing
--  but a login check until their feature is switched on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local S = UI.ModuleSettings("discovery", {
    enabled = false,
    tracker = false, trackerAlways = false, trackerScale = 1, mapPins = false, mapPinSize = 18, mapTurnIn = true,
    nearbySound = false, nearbyRange = 40, nearbyPing = true, nearbyChat = true, openMap = true, windowAlpha = 1,
    -- Each window's own opacity: the Discovery window (windowAlpha), the Library Books tracker,
    -- the Sleeping Bag tracker.
    trackerAlpha = 1,
    bagTracker = false, bagTrackerScale = 1, bagTrackerAlpha = 1, bagMapPins = false, bagMapPinSize = 20,
})
ns.DiscoverySettings = S

-- The windows' opacity was one setting (windowAlpha) before each had its own: a player who set
-- it keeps it on the trackers until they set theirs. Once: a tracker's own, once set, is kept.
local function SplitOpacity()
    local was = S.Raw("windowAlpha")
    if was == nil then return end
    for _, key in ipairs({ "trackerAlpha", "bagTrackerAlpha" }) do
        if S.Raw(key) == nil then S.Set(key, was) end
    end
end
hooksecurefunc(ns, "Apply", SplitOpacity)

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"

local Library = {}
ns.Library = Library

function Library.Side()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

-- A book this character can take: its faction's or either, and one Forever has.
function Library.ForMe(book)
    return not book.missing and (book.side == "B" or book.side == Library.Side())
end

function Library.Done(book)
    return C_QuestLog.IsQuestFlaggedCompleted(book.quest)
end

-- The bank count is the client's copy from the last time the bank was open.
function Library.Stored(book)
    if Library.Done(book) then return nil end
    if C_Item.GetItemCount(book.item) > 0 then return "bags" end
    if C_Item.GetItemCount(book.item, true) > 0 then return "bank" end
end

function Library.Carried(book)
    return Library.Stored(book) ~= nil
end

function Library.Title(book)
    if Library.Done(book) then return CHECK .. " " .. ns.Color("muted", book.name) end
    local c = GetQuestDifficultyColor(book.tier)
    return ("|cff%02x%02x%02x(%d)|r %s"):format(c.r * 255, c.g * 255, c.b * 255, book.tier, book.name)
end

-- The zone you stand in. Caves and buildings have maps of their own under the zone; the
-- books are placed on the zone's, so walk up to it.
function Library.PlayerZone()
    local id = C_Map.GetBestMapForUnit("player")
    local info = id and C_Map.GetMapInfo(id)
    while info and info.mapType and info.mapType > Enum.UIMapType.Zone
        and info.parentMapID and info.parentMapID ~= 0 do
        id = info.parentMapID
        info = C_Map.GetMapInfo(id)
    end
    return id
end

function Library.TurnIn(book)
    return ns.LibraryTurnIns[book.turnIn or "librarian"][Library.Side()]
end

-- Books handed to the librarian, which are the ones the reward quests count, and how many
-- this character could hand in at all.
function Library.Progress()
    local done, total = 0, 0
    for _, book in ipairs(ns.LibraryBooks) do
        if book.turnIn == "librarian" and Library.ForMe(book) then
            total = total + 1
            if Library.Done(book) then done = done + 1 end
        end
    end
    return done, total
end

function Library.NextGoal()
    for _, goal in ipairs(ns.LibraryGoals) do
        if not C_QuestLog.IsQuestFlaggedCompleted(goal.quest) then return goal end
    end
end

-- Where a reward quest stands for you: "claimed" (handed in), "ready" (enough books and the
-- level it needs), "level" (enough books, your level too low) or "ahead".
function Library.GoalState(goal, done)
    if C_QuestLog.IsQuestFlaggedCompleted(goal.quest) then return "claimed" end
    if done < goal.books then return "ahead" end
    if goal.level and UnitLevel("player") < goal.level then return "level" end
    return "ready"
end

local function State(book)
    if Library.Done(book) then return "done" end
    if Library.Carried(book) then return "carried" end
    return "find"
end

local function Spots(mapID, state)
    local out = {}
    if not mapID then return out end
    for _, book in ipairs(ns.LibraryBooks) do
        if Library.ForMe(book) and State(book) == state then
            for _, spot in ipairs(book.spots) do
                if spot[1] == mapID then out[#out + 1] = { book, spot } end
            end
        end
    end
    return out
end

function Library.OnMap(mapID) return Spots(mapID, "find") end
function Library.DoneOnMap(mapID) return Spots(mapID, "done") end

function Library.Waypoint(title, map, x, y, note)
    if ns.PlaceWaypoint(title, map, x, y, note) and S.Get("openMap") then ns.Shared.Places.ShowMap(map) end
end

function Library.WaypointBook(book, spot)
    Library.Waypoint(book.name, spot[1], spot[2], spot[3], spot[4] and (" (" .. spot[4] .. ")"))
end

function Library.WaypointNpc(npc)
    Library.Waypoint(npc.name, npc.map, npc.x, npc.y)
end

function Library.ZoneName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("map " .. mapID)
end

function Library.Where(spot)
    local coords = ("(%.1f, %.1f)"):format(spot[2], spot[3])
    return spot[4] and (spot[4] .. " " .. coords) or coords
end

-------------------------------------------------------------------------------
--  The Cozy Sleeping Bag's chain
-------------------------------------------------------------------------------
local Bag = {}
ns.SleepingBagChain = Bag
local names, subs, nowSubs = {}, {}, {}

-- Your faction's steps, in order.
function Bag.Steps()
    return ns.SleepingBag.steps[Library.Side()]
end

-- A step is done once the quest it hands in is; the first, once the quest it starts is in your
-- log or handed in.
function Bag.StepDone(step)
    if step.started then
        return C_QuestLog.IsQuestFlaggedCompleted(step.started) or C_QuestLog.IsOnQuest(step.started)
    end
    return C_QuestLog.IsQuestFlaggedCompleted(step.done)
end

-- The step to do now, and its place in the chain; nil once you have the bag.
function Bag.Current()
    for i, step in ipairs(Bag.Steps()) do
        if not Bag.StepDone(step) then return step, i end
    end
end

function Bag.Level()
    return UnitLevel("player") >= ns.SleepingBag.level
end

function Bag.Where(step)
    return ("%s, %s (%.1f, %.1f)"):format(Library.ZoneName(step.map), step.place, step.x, step.y)
end

function Bag.Name(step)
    local name = names[step]
    if name then return name end
    name = step.object
    for _, other in ipairs(Bag.Steps()) do
        if other ~= step and other.object == step.object and other.map ~= step.map then
            name = ("%s (%s)"):format(step.object, Library.ZoneName(step.map))
            break
        end
    end
    names[step] = name
    return name
end

function Bag.Sub(step, now)
    local cache = now and step.tip and nowSubs or subs
    local sub = cache[step]
    if sub then return sub end
    sub = ("%s, %s"):format(Library.ZoneName(step.map), step.place)
    if cache == nowSubs then sub = sub .. "\n" .. step.tip end
    cache[step] = sub
    return sub
end

function Bag.Waypoint(step)
    Library.Waypoint(step.object, step.map, step.x, step.y, " (" .. step.place .. ")")
end

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local DISCOVERY_OFF = "Turn on Discovery"

local function On() return S.Get("enabled") == true end

local function Headline()
    local done, total = Library.Progress()
    return ("%d of %d books handed in"):format(done, total)
end

local function Detail()
    local goal = Library.NextGoal()
    local librarian = ns.LibraryTurnIns.librarian[Library.Side()]
    if not goal then return "Every reward earned. " .. librarian.name .. " thanks you." end
    return ("Next: %s at %d. Hand them to %s."):format(goal.name, goal.books, librarian.name)
end

local function TrackerSummary(store)
    return store.Get("trackerAlways") and "In every zone" or "In zones with books to find"
end

local function NearbySummary(store)
    return ("Within %d yards"):format(store.Get("nearbyRange"))
end

local function MapSummary(store)
    return store.Get("mapTurnIn") and "Books and who takes them" or "Books only"
end

local function WaypointSummary(store)
    return store.Get("openMap") and "Pins it and opens the map" or "Pins it only"
end

-------------------------------------------------------------------------------
--  Library Books
-------------------------------------------------------------------------------
local page = Settings.Page("Discovery/Library Books", S)

page:Window({
    text = "Open Library Books",
    open = function() ns.OpenDiscoveryWindow("books") end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "tracker", name = "Tracker", order = 10, switch = "tracker",
    help = "Pops up when you enter a zone with books you still need, with a waypoint for each and your "
        .. "progress toward the next reward, and stays while you are in that zone. The X closes it until "
        .. "you enter another. Move it with Move Elements.",
    summary = TrackerSummary,
    rows = {
        { key = "trackerAlways", label = "Always Show", toggle = true, needs = On, why = DISCOVERY_OFF,
          help = "Keep the tracker up in every zone, with a dropdown of the zones where you still have books "
              .. "to find. Entering one selects it. The X on the tracker switches this off." },
        { key = "trackerScale", label = "Scale", slider = { 50, 150, 5 }, unit = "%", scale = 0.01, needs = On,
          why = DISCOVERY_OFF, help = "How big the tracker is." },
        { key = "trackerAlpha", label = "Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 }, unit = "%",
          scale = 0.01, needs = On, why = DISCOVERY_OFF, help = "How solid the tracker is, in percent." },
    },
})

page:Card({
    id = "mapPins", name = "Map Pins", order = 20, switch = "mapPins",
    help = "Pins every book you still need on its zone's map, and your librarian while you carry books. "
        .. "Hover a pin for the exact spot; click it for a waypoint.",
    summary = MapSummary,
    rows = {
        { key = "mapTurnIn", label = "Hand-In Pin", toggle = true, needs = On, why = DISCOVERY_OFF,
          help = "While you carry books, a pin on who takes them: your librarian, or the mage trainer." },
        { key = "mapPinSize", label = "Pin Size", slider = { 12, 32, 1 }, needs = On, why = DISCOVERY_OFF,
          help = "How big the pins are on the map." },
    },
})

page:Card({
    id = "nearby", name = "Nearby Alert", order = 30, switch = "nearbySound",
    help = "Plays the map ping and names the book in chat when you come within range of one you still need. "
        .. "Once per book, until you walk away and come back.",
    summary = NearbySummary,
    rows = {
        { key = "nearbyRange", label = "Range", slider = { 10, 100, 5 }, unit = " yd", needs = On,
          why = DISCOVERY_OFF, help = "How close a book has to be before it pings." },
        { key = "nearbyPing", label = "Ping Sound", toggle = true, needs = On, why = DISCOVERY_OFF,
          help = "Plays the map ping when a book is near." },
        { key = "nearbyChat", label = "Chat Line", toggle = true, needs = On, why = DISCOVERY_OFF,
          help = "Names the book in chat, with how far it is and where." },
    },
})

page:Card({
    id = "waypoints", name = "Waypoints", order = 35,
    help = "What a waypoint from the Discovery window or the tracker does.",
    summary = WaypointSummary,
    rows = {
        { key = "openMap", label = "Open the Map", toggle = true,
          help = "Also opens the world map on the waypoint, so you see where it is. Out of combat only." },
    },
})

page:Card({
    id = "window", name = "Window", order = 90,
    help = "Discovery's own window, with every book and where to find it.",
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 },
          unit = "%", scale = 0.01, help = "How solid the window is, in percent. Also on its title bar." },
    },
})

-------------------------------------------------------------------------------
--  Sleeping Bag
-------------------------------------------------------------------------------
local function BagSummary()
    local _, at = Bag.Current()
    if not at then return "You have the Cozy Sleeping Bag" end
    return ("Step %d of %d"):format(at, #Bag.Steps())
end

local function BagHeadline()
    local _, at = Bag.Current()
    local n = #Bag.Steps()
    if not at then return "You have the Cozy Sleeping Bag" end
    return ("Sleeping Bag: step %d of %d"):format(at, n)
end

local function BagDetail()
    local step = Bag.Current()
    if not step then return "Rest in it for a bonus to experience." end
    if not Bag.Level() then return ("It starts at level %d."):format(ns.SleepingBag.level) end
    return ("Next: %s, %s."):format(step.object, Library.ZoneName(step.map))
end

local bags = Settings.Page("Discovery/Sleeping Bag", S)

bags:Window({
    text = "Open Sleeping Bag",
    open = function() ns.OpenDiscoveryWindow("bag") end,
    headline = BagHeadline,
    detail = BagDetail,
})

bags:Card({
    id = "bagtracker", name = "Tracker", order = 10, switch = "bagTracker",
    help = "Shows each Sleeping Bag step, with how to reach the next one and a waypoint.",
    summary = BagSummary,
    rows = {
        { key = "bagTrackerScale", label = "Scale", slider = { 50, 150, 5 }, unit = "%", scale = 0.01, needs = On,
          why = DISCOVERY_OFF, help = "How big the tracker is." },
        { key = "bagTrackerAlpha", label = "Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 }, unit = "%",
          scale = 0.01, needs = On, why = DISCOVERY_OFF, help = "How solid the tracker is, in percent." },
    },
})

bags:Card({
    id = "bagmappins", name = "Map Pins", order = 20, switch = "bagMapPins",
    help = "Shows the Sleeping Bag steps still to do on your map; click one for a waypoint.",
    rows = {
        { key = "bagMapPinSize", label = "Pin Size", slider = { 12, 32, 1 }, needs = On, why = DISCOVERY_OFF,
          help = "How big the pins are on the map." },
    },
})
