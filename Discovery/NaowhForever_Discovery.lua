-------------------------------------------------------------------------------
--  NaowhForever_Discovery.lua -- the Discovery module: the library books you can still
--  find, how many you have handed in toward the Friend of the Library rewards, and who takes
--  them for your faction. Books and turn-ins come from NaowhForever_DiscoveryData.lua.
--
--  Off by default, every feature too. The tracker, map pin and nearby files register nothing
--  but a login check until their feature is switched on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

local S = UI.ModuleSettings("discovery", {
    enabled = false,
    tracker = false, trackerAlways = false, mapPins = false,
    nearbySound = false, nearbyRange = 40,
})
ns.DiscoverySettings = S

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local IN_BAGS = "|cffffd100In bags|r"
local IN_BANK = "|cffffd100In bank|r"
local MISSING = "|cfff87171Missing|r"
local STRIPE = { r = 0, g = 0, b = 0 }
local STRIPE_ALPHA = 0.35

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

function Library.ZoneName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("map " .. mapID)
end

function Library.Where(spot)
    local coords = ("(%.1f, %.1f)"):format(spot[2], spot[3])
    return spot[4] and (spot[4] .. " " .. coords) or coords
end

-------------------------------------------------------------------------------
--  Books page
-------------------------------------------------------------------------------
-- Zones in the order their first book appears in the data, so the list reads by set.
local function ZonesInOrder()
    local order, seen = {}, {}
    for _, book in ipairs(ns.LibraryBooks) do
        for _, spot in ipairs(book.spots) do
            if not seen[spot[1]] then
                seen[spot[1]] = true
                order[#order + 1] = spot[1]
            end
        end
    end
    return order
end

local function Status(book)
    if Library.Done(book) then return ns.Color("muted", "Finished") end
    local stored = Library.Stored(book)
    if stored == "bags" then return IN_BAGS end
    if stored == "bank" then return IN_BANK end
    return MISSING
end

local BUTTON_W, STATUS_W = 90, 80
local function Row(parent, y, text, sub, status, onWaypoint, stripe)
    local x = UI.CONTENT_PAD + 20
    local full = (parent:GetWidth() or 0) > 0 and parent:GetWidth() or 960
    if onWaypoint then
        local btn = UI.KeepButton(parent, "bookWaypoint", "Waypoint", 80, 20, onWaypoint)
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -x, y - 2)
    end
    local st = UI.KeepFont(parent, "bookStatus", 13, nil)
    st:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(x + BUTTON_W), y - 4)
    st:SetJustifyH("RIGHT")
    st:SetWordWrap(false)
    st:SetText(status)
    local statusW = math.max(STATUS_W, math.ceil(st:GetStringWidth()))
    local fs = UI.KeepFont(parent, "book", 13, nil)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
    fs:SetWidth(full - x * 2 - BUTTON_W - statusW - 10)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    local h = math.ceil(fs:GetStringHeight()) + 4
    local s = UI.KeepFont(parent, "bookSub", 11, nil, T.muted)
    s:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 14, -2)
    s:SetWidth(full - x * 2 - BUTTON_W - 14)
    s:SetJustifyH("LEFT")
    s:SetWordWrap(true)
    s:SetText(sub)
    h = h + math.ceil(s:GetStringHeight()) + 2
    if stripe then
        local band = UI.Keep(parent, "bookStripe", function(p)
            return ns.Solid(p, "BACKGROUND", STRIPE, STRIPE_ALPHA)
        end)
        band:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 6, y)
        band:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(x - 6), y)
        band:SetHeight(h + 6)
    end
    return h + 6
end

local function ProgressNote(parent, y)
    local done, total = Library.Progress()
    local goal = Library.NextGoal()
    local librarian = ns.LibraryTurnIns.librarian[Library.Side()]
    local status = goal and ("%d of %d handed in toward %s (%d)."):format(done, total, goal.name, goal.books)
        or ("%d of %d handed in; both rewards earned."):format(done, total)
    local _, h = UI.Widgets:Note(parent, "Library books hidden around Azeroth. Hand them to "
        .. librarian.name .. " (" .. librarian.place .. ") for Friend of the Library at 10 and "
        .. "Greater Friend of the Library at 20. " .. status, y)
    return y - h
end

function ns.BuildDiscoverySettingsPage(parent, y)
    local W = UI.Widgets
    local _, h
    y = ProgressNote(parent, y)

    _, h = W:SectionHeader(parent, "TRACKER" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("tracker", "Show Tracker",
            "Pops up when you enter a zone with books you still need, with a waypoint for each "
            .. "and your progress toward the next reward, and stays while you are in that zone. "
            .. "The X closes it until you enter another. Move it in Unlock Mode.", "enabled"),
        S.Toggle("trackerAlways", "Always Show",
            "Keep the tracker up in every zone, with a dropdown of the zones where you still have "
            .. "books to find. Entering one selects it. The X on the tracker switches this off.",
            "tracker")
    ); y = y - h

    _, h = W:SectionHeader(parent, "MAP PINS" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mapPins", "Show on World Map",
            "Pins every book you still need on its zone's map, and your librarian while you "
            .. "carry books. Hover a pin for the exact spot; click it for a waypoint.", "enabled")
    ); y = y - h

    _, h = W:SectionHeader(parent, "NEARBY ALERT" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("nearbySound", "Sound When Nearby",
            "Plays the map ping and names the book in chat when you come within range of one you "
            .. "still need. Once per book, until you walk away and come back.", "enabled"),
        S.Slider("nearbyRange", "Range (yards)", 10, 100, 5, nil, "nearbySound")
    ); y = y - h
    return y
end

function ns.BuildDiscoveryBooksPage(parent, y)
    local W = UI.Widgets
    local _, h
    y = ProgressNote(parent, y)

    local zones = ZonesInOrder()
    for i = 1, #zones do
        local mapID, items = zones[i], {}
        for _, book in ipairs(ns.LibraryBooks) do
            if Library.ForMe(book) then
                for _, spot in ipairs(book.spots) do
                    if spot[1] == mapID then items[#items + 1] = { book, spot } end
                end
            end
        end
        if #items > 0 then
            _, h = W:SectionHeader(parent, Library.ZoneName(mapID):upper(), y); y = y - h
            for n, item in ipairs(items) do
                local book, spot = item[1], item[2]
                local npc = Library.TurnIn(book)
                local sub = Library.Where(spot) .. "  -  Hand in to " .. npc.name
                y = y - Row(parent, y, Library.Title(book), sub, Status(book),
                    function() ns.PlaceWaypoint(book.name, spot[1], spot[2], spot[3]) end,
                    n % 2 == 1)
            end
        end
    end

    local unplaced = {}
    for _, book in ipairs(ns.LibraryBooks) do
        if book.unplaced and Library.ForMe(book) then unplaced[#unplaced + 1] = book end
    end
    if #unplaced > 0 then
        _, h = W:SectionHeader(parent, "NOT FOUND YET", y); y = y - h
        for n, book in ipairs(unplaced) do
            y = y - Row(parent, y, Library.Title(book), "Nobody has found this one on Forever yet.",
                Status(book), nil, n % 2 == 1)
        end
    end
    return y
end
