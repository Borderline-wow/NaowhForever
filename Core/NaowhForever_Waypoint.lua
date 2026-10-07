-------------------------------------------------------------------------------
--  NaowhForever_Waypoint.lua -- ns.PlaceWaypoint: a waypoint on the map for any module
--  (the Dungeon Journal's quests and entrances, Discovery's books, Professions' trainers).
--  With TomTom loaded, its waypoint and arrow instead of the game's. ns.WaypointText and
--  ns.WaypointLink: the same spot as a line and a map pin link for chat.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

-- Only the last TomTom waypoint this set is kept, so clicking pin after pin does not pile
-- up arrows.
local tomtomWaypoint

--- Whether a waypoint can go on the map: TomTom's wherever it is loaded, else where the game
--- takes one.
---@param map number uiMapID
---@return boolean
function ns.CanPlaceWaypoint(map)
    return (TomTom and TomTom.AddWaypoint) ~= nil or C_Map.CanSetUserWaypointOnMap(map)
end

--- The spot as a line: "Smart Drinks (quest giver): Durotar 62.5, 37.6".
---@param title string what the pin is for
---@param map number uiMapID
---@param x number percent
---@param y number percent
---@param note? string what it points at, after the title
---@return string
function ns.WaypointText(title, map, x, y, note)
    local info = C_Map.GetMapInfo(map)
    return ("%s%s: %s %.1f, %.1f"):format(title, note or "", info and info.name or "", x, y)
end

local function PlaceTomTom(title, map, x, y, note)
    if tomtomWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomWaypoint) end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, map, x / 100, y / 100, {
        title = title .. (note or ""), from = "Naowh Forever", persistent = false, crazy = true,
        silent = true,
    })
    if not ok then return false end
    tomtomWaypoint = uid
    ns.Print("TomTom waypoint for " .. ns.WaypointText(title, map, x, y, note))
    return true
end

--- A map pin link for chat at the spot, as the game's own Share Pin makes: clicked, it puts
--- the pin on the reader's map. The game only makes one for your own pin, so yours is set
--- there for the moment it takes and put back as it was.
---@param map number uiMapID
---@param x number percent
---@param y number percent
---@return string? link nil where the map takes no pin
function ns.WaypointLink(map, x, y)
    if not C_Map.CanSetUserWaypointOnMap(map) then return nil end
    local previous = C_Map.GetUserWaypoint()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    local link = C_Map.GetUserWaypointHyperlink()
    if previous then C_Map.SetUserWaypoint(previous) else C_Map.ClearUserWaypoint() end
    return link
end

--- Seconds a reached waypoint shows before a route moves on; the Waypoint Pin's arrival holds
--- as long.
ns.WAYPOINT_HOLD = 4

local route   -- { title, stops = { { title, map, x, y, note, icon }, ... }, at }
local arrivals = 0
local watch = CreateFrame("Frame")

local function SetGameWaypoint(title, map, x, y, note, icon)
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    ns.placedWaypoint = { title = title, note = note, icon = icon, map = map, x = x, y = y }
end

local function EndRoute()
    route = nil
    watch:UnregisterAllEvents()
end

--- A waypoint on the map, and the arrow on it where the game has one. With the Waypoint Pin on,
--- always the game's, which the pin follows, rather than TomTom's. Ends a route.
---@param title string what the pin is for, as the chat line names it
---@param map number uiMapID
---@param x number percent, as the data files write it
---@param y number percent
---@param note? string what the pin points at, after the title (" (entrance)")
---@param icon? number|string a texture for the Waypoint Pin's card and navigator
---@return boolean placed false where the map takes no waypoints
function ns.PlaceWaypoint(title, map, x, y, note, icon)
    EndRoute()
    local pin = ns.WaypointPinOn and ns.WaypointPinOn()
    if not pin and TomTom and TomTom.AddWaypoint and PlaceTomTom(title, map, x, y, note) then return true end
    if not C_Map.CanSetUserWaypointOnMap(map) then
        ns.Print("That map does not take waypoints.")
        return false
    end
    SetGameWaypoint(title, map, x, y, note, icon)
    ns.Print("Waypoint for " .. ns.WaypointText(title, map, x, y, note))
    return true
end

-------------------------------------------------------------------------------
--  Routes: stops in order, the next one placed WAYPOINT_HOLD after the game says the last
--  was reached. Always the game's waypoint, since TomTom's never reports arriving. Placing any
--  other waypoint, or clearing it, ends the route.
-------------------------------------------------------------------------------
local function OnStop(point)
    local stop = route.stops[route.at]
    return point ~= nil and point.uiMapID == stop[2] and math.abs(point.position.x * 100 - stop[3]) < 0.05
        and math.abs(point.position.y * 100 - stop[4]) < 0.05
end

local function PlaceStop()
    local stop = route.stops[route.at]
    if not C_Map.CanSetUserWaypointOnMap(stop[2]) then
        ns.Print("That map does not take waypoints.")
        EndRoute()
        return false
    end
    SetGameWaypoint(stop[1], stop[2], stop[3], stop[4], stop[5], stop[6])
    ns.Print(("%s, stop %d of %d: %s"):format(route.title, route.at, #route.stops,
        ns.WaypointText(stop[1], stop[2], stop[3], stop[4], stop[5])))
    return true
end

watch:SetScript("OnEvent", function(_, event, isWaypoint)
    if event == "USER_WAYPOINT_UPDATED" then
        if not OnStop(C_Map.GetUserWaypoint()) then EndRoute() end
    -- isWaypoint: a stop the game routes you through on the way, not the spot itself.
    elseif not isWaypoint and OnStop(C_Map.GetUserWaypoint()) then
        arrivals = arrivals + 1
        local this = arrivals
        C_Timer.After(ns.WAYPOINT_HOLD, function()
            if this ~= arrivals or not route then return end
            if route.at == #route.stops then EndRoute() return end
            route.at = route.at + 1
            PlaceStop()
        end)
    end
end)

--- A route through the stops in order, the first placed now. One stop is a plain waypoint.
---@param title string what the route is ("Training run")
---@param stops table[] { title, map, x, y, note?, icon? } each, as ns.PlaceWaypoint takes them
---@return boolean placed
function ns.PlaceWaypointRoute(title, stops)
    if #stops < 2 then
        local stop = stops[1]
        return stop ~= nil and ns.PlaceWaypoint(stop[1], stop[2], stop[3], stop[4], stop[5], stop[6])
    end
    EndRoute()
    route = { title = title, stops = stops, at = 1 }
    watch:RegisterEvent("USER_WAYPOINT_UPDATED")
    watch:RegisterEvent("NAVIGATION_DESTINATION_REACHED")
    return PlaceStop()
end

--- The route being followed: its title, the stop it is on, how many there are, and the next
--- stop's title (nil on the last). Nothing without a route.
function ns.WaypointRoute()
    if not route then return end
    local nextStop = route.stops[route.at + 1]
    return route.title, route.at, #route.stops, nextStop and nextStop[1]
end
