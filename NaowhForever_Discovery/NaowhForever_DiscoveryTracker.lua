-------------------------------------------------------------------------------
--  NaowhForever_DiscoveryTracker.lua -- the library book tracker: in a zone with books you
--  still need, a small window lists them with a waypoint for each. It pops up on entering
--  such a zone; Always Show keeps it up in every zone. Built on the shared tracker window
--  (Parts.TrackerPanel, as the Dungeon Quest Tracker): the progress bar and the zone dropdown
--  under the title, a row per book (a waypoint pin in front, a tick in its place once a book
--  is handed in) and a cog for its settings in the bottom right.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.DiscoverySettings
local L = ns.Library
local T = ns.THEME
local Parts = ns.Shared.Parts
local St = ns.Shared.Style

-- The light blue of the hint lines: the shade each one always was (r, g, b), or the theme's
-- lighter Accent once the theme has changed the Accent. Returns r, g, b, so where it is not
-- the last argument its values are put in locals first.
local function SoftBlue(r, g, b)
    local c = ns.ThemeTint("accentSoft", nil)
    if c then return c.r, c.g, c.b end
    return r, g, b
end
local READY = { r = 0x19 / 255, g = 1, b = 0x19 / 255 }
local SETTINGS_PAGE = "Discovery/Library Books"
local TURN_INS = { "librarian", "trainer" }
local STORES = { "bags", "bank" }

local panel, zoneEvents, shownEvents
local dismissedZone   -- the zone the X closed it in, until you leave
local pickedZone      -- the zone the dropdown is listing, while it shows
local zoneNames, zoneOrder = {}, {}
local entries, pool, count = {}, {}, 0
local carried = {}
local toFind, doneHere, hereList = {}, {}, {}

local function On()
    return S.Get("enabled") and S.Get("tracker")
end

local function BarTooltip(bar)
    local done, total = L.Progress()
    GameTooltip:SetOwner(bar, "ANCHOR_LEFT")
    GameTooltip:SetText("Library Books")
    GameTooltip:AddLine(("%d of %d books handed in"):format(done, total), 1, 1, 1)
    for _, goal in ipairs(ns.LibraryGoals) do
        local state, r, g, b
        local now = L.GoalState(goal, done)
        if now == "claimed" then
            state, r, g, b = "Claimed", 0.61, 0.64, 0.69
        elseif now == "ready" then
            state, r, g, b = "Ready to hand in", READY.r, READY.g, READY.b
        elseif now == "level" then
            state, r, g, b = ("At level %d"):format(goal.level), 1, 0.82, 0
        else
            state, r, g, b = ("%d to go"):format(goal.books - done), 1, 1, 1
        end
        GameTooltip:AddLine(" ")
        local sr, sg, sb = SoftBlue(0.3, 0.71, 0.96)
        GameTooltip:AddDoubleLine(("%s (%d)"):format(goal.name, goal.books), state, sr, sg, sb, r, g, b)
        local names = {}
        for _, reward in ipairs(goal.rewards) do
            names[#names + 1] = C_Item.GetItemNameByID(reward[1]) or reward[2]
        end
        GameTooltip:AddLine(table.concat(names, " or "), 0.61, 0.64, 0.69, true)
    end
    local librarian = ns.LibraryTurnIns.librarian[L.Side()]
    GameTooltip:AddLine(" ")
    local hr, hg, hb = SoftBlue(0.3, 0.7, 0.95)
    GameTooltip:AddLine("Hand in to " .. librarian.name .. ", " .. librarian.place, hr, hg, hb, true)
    local bags, bank = 0, 0
    for _, book in ipairs(ns.LibraryBooks) do
        local stored = L.ForMe(book) and L.Stored(book)
        if stored == "bags" then bags = bags + 1 elseif stored == "bank" then bank = bank + 1 end
    end
    if bags > 0 then GameTooltip:AddLine(bags .. " waiting in your bags", 1, 0.82, 0) end
    if bank > 0 then GameTooltip:AddLine(bank .. " waiting in your bank", 1, 0.82, 0) end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function Opacity()
    return S.Get("trackerAlpha") or 1
end

local function LoadPosition()
    local pos = S.Get("trackerPos")
    if type(pos) == "table" then return pos.point, pos.relPoint, pos.x, pos.y end
end

local function SavePosition(point, relPoint, x, y)
    S.Set("trackerPos", { point = point, relPoint = relPoint, x = x, y = y })
end

local function Mover(frame, onMoved)
    return ns.UI.AttachMover(frame, "Library Books", onMoved, "Discovery/Library Books")
end

-- The X closes it until you change zone, and switches Always Show off, so switching that
-- back on is how to bring it back.
local function Close()
    dismissedZone = L.PlayerZone()
    panel:Hide()
    if S.Get("trackerAlways") then
        S.Set("trackerAlways", false)
        ns.UI:RefreshPage(true)
    end
end

local function OpenBooks()
    ns.OpenDiscoveryWindow("books")
end

local function PickedZone()
    return pickedZone
end

local function PickZone(id)
    S.Set("trackerZone", id)
end

local function BuildPanel()
    panel = Parts.TrackerPanel("LIBRARY BOOKS", {
        onTitle = OpenBooks, titleTip = "Library Books", titleHint = "Click to open the Books page.",
        onClose = Close,
        bar = true,
        picker = { values = zoneNames, order = zoneOrder, get = PickedZone, set = PickZone },
        settings = { page = SETTINGS_PAGE, card = "tracker", tip = "Library Books settings",
            hint = "Opens the Library Books tracker's settings." },
        opacity = Opacity,
        load = LoadPosition, save = SavePosition, place = { "RIGHT", "RIGHT", -260, -120 },
        mover = Mover,
    })
    panel:SetScale(S.Get("trackerScale"))
    panel.bar:EnableMouse(true)
    panel.bar:SetScript("OnEnter", BarTooltip)
    panel.bar:SetScript("OnLeave", GameTooltip_Hide)
    panel.picker:Hide()
    panel:Place()
    panel:Paint()
    panel:Hide()
end

-------------------------------------------------------------------------------
--  What it lists
-------------------------------------------------------------------------------
-- Books looted and not handed in, counted per person who takes them and where they are
-- kept: carried["librarian/bags"] and so on.
local function CarriedByTurnIn()
    wipe(carried)
    for _, book in ipairs(ns.LibraryBooks) do
        local stored = L.ForMe(book) and L.Stored(book)
        if stored then
            local key = (book.turnIn or "librarian") .. "/" .. stored
            carried[key] = (carried[key] or 0) + 1
        end
    end
    return carried
end

local function RenderBar()
    local bar = panel.bar
    local done, total = L.Progress()
    local goal = L.NextGoal()
    local accent = T.accent
    if goal then
        local ready = L.GoalState(goal, done) == "ready"
        bar:SetMinMaxValues(0, goal.books)
        bar:SetValue(math.min(done, goal.books))
        local c = ready and READY or accent
        bar:SetStatusBarColor(c.r, c.g, c.b, 0.85)
        bar.text:SetText(ready and (goal.name .. " ready to hand in")
            or ("%d / %d  %s"):format(done, goal.books, goal.name))
    else
        bar:SetMinMaxValues(0, math.max(total, 1))
        bar:SetValue(done)
        bar:SetStatusBarColor(READY.r, READY.g, READY.b, 0.85)
        bar.text:SetText(("%d / %d books handed in"):format(done, total))
    end
end

-- Every zone with a book still to find, in the data's order (by set), with how many:
-- { uiMapID, count } pairs. keep, the zone picked in the dropdown, stays in the list at 0
-- once its last book is looted, so the pick does not jump to another zone under you.
local zonesLeft, zonePool, zoneAt = {}, {}, {}

local function ZonesLeft(keep)
    wipe(zoneAt)
    local zones = 0
    for _, book in ipairs(ns.LibraryBooks) do
        local find = L.ToFind(book)
        for _, spot in ipairs(book.spots) do
            local id = spot[1]
            local zone = zoneAt[id]
            if not zone then
                zones = zones + 1
                zone = zonePool[zones] or {}
                zonePool[zones] = zone
                zone[1], zone[2] = id, 0
                zoneAt[id] = zone
            end
            if find then zone[2] = zone[2] + 1 end
        end
    end
    local n = 0
    for i = 1, zones do
        local zone = zonePool[i]
        if zone[2] > 0 or zone[1] == keep then
            n = n + 1
            zonesLeft[n] = zone
        end
    end
    for i = n + 1, #zonesLeft do zonesLeft[i] = nil end
    return zonesLeft
end

-- Points the dropdown at the zones left and returns the one to list: the saved pick, which
-- ZonesLeft keeps even once it runs out, else the first.
local function Pick(left)
    local saved = S.Get("trackerZone")
    wipe(zoneNames)
    wipe(zoneOrder)
    pickedZone = nil
    for i, z in ipairs(left) do
        zoneNames[z[1]] = L.ZoneName(z[1]) .. "  " .. ns.Color("muted", "(" .. z[2] .. ")")
        zoneOrder[i] = z[1]
        if z[1] == saved then pickedZone = saved end
    end
    pickedZone = pickedZone or left[1][1]
    panel.picker._refreshLabel()
    return pickedZone
end

local function Add(text, color)
    count = count + 1
    local entry = pool[count]
    if entry then wipe(entry) else entry = {}; pool[count] = entry end
    entry.text, entry.color = text, color
    entries[count] = entry
    return entry
end

local function NpcWaypoint(entry)
    L.WaypointNpc(entry.npc)
end

local function BookWaypoint(entry)
    L.WaypointBook(entry.book, entry.spot)
end

local function BookTip(row)
    local book, spot = row.entry.book, row.entry.spot
    GameTooltip:SetText(book.name)
    local c = GetQuestDifficultyColor(book.tier)
    GameTooltip:AddLine(("Level %d"):format(book.tier), c.r, c.g, c.b)
    if spot[5] then GameTooltip:AddLine(spot[5], 1, 1, 1, true) end
    local npc = L.TurnIn(book)
    local hr, hg, hb = SoftBlue(0.3, 0.7, 0.95)
    GameTooltip:AddLine("Hand in to " .. npc.name .. ", " .. npc.place, hr, hg, hb, true)
end

-- zone is where you stand; left, when given, is the zones for the dropdown, and the list is
-- the picked zone's instead of yours.
local function Render(zone, left)
    local listZone = left and Pick(left) or zone
    panel.picker:SetShown(left ~= nil)
    count = 0
    CarriedByTurnIn()
    for _, kind in ipairs(TURN_INS) do
        for _, place in ipairs(STORES) do
            local n = carried[kind .. "/" .. place]
            if n then
                local npc = ns.LibraryTurnIns[kind][L.Side()]
                local books = n == 1 and "1 book" or (n .. " books")
                local entry = Add(books .. " in your " .. place, St.CARRIED_RGB)
                entry.sub = "Hand in to " .. npc.name .. ", " .. npc.place
                entry.npc, entry.waypoint = npc, NpcWaypoint
            end
        end
    end
    L.OnMap(listZone, toFind)
    if #toFind == 0 then Add("No more books in this area.", T.muted) end
    for _, item in ipairs(toFind) do
        local book, spot = item[1], item[2]
        local sub = L.Where(spot)
        if book.turnIn == "trainer" then sub = sub .. ", mage trainer" end
        local entry = Add(book.name)
        entry.sub, entry.book, entry.spot = sub, book, spot
        entry.waypoint, entry.tip = BookWaypoint, BookTip
    end
    for _, item in ipairs(L.DoneOnMap(listZone, doneHere)) do
        Add(item[1].name, T.muted).done = true
    end
    for i = count + 1, #entries do entries[i] = nil end
    panel.title:SetText("LIBRARY BOOKS  " .. ns.Color("muted", L.ZoneName(zone)))
    RenderBar()
    panel:Fit(panel:SetRows(entries))
end

-------------------------------------------------------------------------------
--  When it shows
-------------------------------------------------------------------------------
local shownZone   -- the zone it popped up in; it stays up there until you leave or close it
local lastZone    -- the zone of the last redraw, so entering a zone selects it once

local function Hide()
    shownZone = nil
    if shownEvents then shownEvents:UnregisterAllEvents() end
    if panel then panel:Hide() end
end

-- Without Always Show it pops up on entering a zone with books to find and stays for as
-- long as you are in that zone, even once they are looted. With it, it shows in every zone
-- with the dropdown, until the X or the toggle switches it off. Entering a zone with books
-- selects it; a zone picked from the dropdown after that sticks until you enter another.
local function Refresh()
    if not On() then return Hide() end
    local zone = L.PlayerZone()
    if zone ~= dismissedZone then dismissedZone = nil end
    local here = zone and #L.OnMap(zone, hereList) > 0
    local always = S.Get("trackerAlways")
    local entered = zone ~= lastZone
    lastZone = zone
    if always and here and entered and S.Get("trackerZone") ~= zone then
        S.Set("trackerZone", zone)   -- redraws through the Set hook
        return
    end
    local left = zone and always and ZonesLeft(S.Get("trackerZone")) or nil
    if left and #left == 0 then left = nil end
    local stay = panel and panel:IsShown() and shownZone == zone
    local show = zone and not dismissedZone and (always or here or stay)
    if not show then return Hide() end
    if not panel then BuildPanel() end
    Render(zone, left)
    panel:Show()
    shownZone = zone
    -- Looting a book fills your bags; handing one in completes its quest.
    shownEvents:RegisterEvent("BAG_UPDATE_DELAYED")
    shownEvents:RegisterEvent("QUEST_TURNED_IN")
end

-- Loot and turn-ins can fire several events at once; gather them into one redraw.
local redrawQueued

local function QueuedRefresh()
    redrawQueued = false
    Refresh()
end

local function QueueRefresh()
    if redrawQueued then return end
    redrawQueued = true
    C_Timer.After(0.2, QueuedRefresh)
end

local function Apply()
    if On() then
        if not zoneEvents then
            zoneEvents = CreateFrame("Frame")
            zoneEvents:SetScript("OnEvent", QueueRefresh)
            shownEvents = CreateFrame("Frame")
            shownEvents:SetScript("OnEvent", QueueRefresh)
        end
        zoneEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    elseif zoneEvents then
        zoneEvents:UnregisterAllEvents()
    end
    Refresh()
end

local OWN_KEYS = { enabled = true, tracker = true, trackerAlways = true, trackerZone = true }

hooksecurefunc(S, "Set", function(key, value)
    if key == "trackerScale" and panel then panel:SetScale(value) end
    if key == "trackerAlpha" and panel then panel:Paint() end
    if not OWN_KEYS[key] then return end
    -- Switching Always Show back on brings the tracker back here, whatever the X closed.
    -- Switching it off closes it, unless the zone you are in has books to find.
    if key == "trackerAlways" then
        -- Switching it on selects the zone you are in, as entering it would.
        if value then dismissedZone, lastZone = nil, nil else shownZone = nil end
    end
    Apply()
end)
hooksecurefunc(ns, "Apply", Apply)

-- Unlock Mode shows it wherever you are, on your zone or the first zone with books for you.
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if not On() then return end
    if not panel then BuildPanel() end
    local zone = L.PlayerZone()
    if not zone or #L.OnMap(zone, hereList) == 0 then
        zone = L.Side() == "H" and 1413 or 1436
    end
    Render(zone)
    panel.mover:Show()
    panel:Show()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if panel then
        panel.mover:Hide()
        Refresh()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
