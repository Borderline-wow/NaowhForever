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

--- A waypoint on the map, and the arrow on it where the game has one.
---@param title string what the pin is for, as the chat line names it
---@param map number uiMapID
---@param x number percent, as the data files write it
---@param y number percent
---@param note? string what the pin points at, after the title (" (entrance)")
---@return boolean placed false where the map takes no waypoints
function ns.PlaceWaypoint(title, map, x, y, note)
    if TomTom and TomTom.AddWaypoint and PlaceTomTom(title, map, x, y, note) then return true end
    if not C_Map.CanSetUserWaypointOnMap(map) then
        ns.Print("That map does not take waypoints.")
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    ns.Print("Waypoint for " .. ns.WaypointText(title, map, x, y, note))
    return true
end
