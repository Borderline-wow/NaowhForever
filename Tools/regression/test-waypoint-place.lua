-- Run with Lua 5.1 from the repository root: ns.PlaceWaypoint. With TomTom loaded its waypoint
-- is used, unless the Waypoint Pin is on, which follows the game's own; either way the spot's
-- title, note and icon are kept for the pin.
local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local tomtom, set, tracked, printed = {}, {}, 0, {}
local pinOn = false
local ns = {
    Print = function(msg) printed[#printed + 1] = msg end,
    WaypointPinOn = function() return pinOn end,
}
local env = setmetatable({
    NaowhForever = ns,
    TomTom = {
        AddWaypoint = function(_, map, x, y, opts)
            tomtom[#tomtom + 1] = { map = map, x = x, y = y, title = opts.title }
            return #tomtom
        end,
        RemoveWaypoint = function() end,
    },
    C_Map = {
        CanSetUserWaypointOnMap = function() return true end,
        SetUserWaypoint = function(point) set[#set + 1] = point end,
        GetMapInfo = function() return { name = "Orgrimmar" } end,
    },
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function() tracked = tracked + 1 end },
    UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end },
}, { __index = _G })
env._G = env
local f = assert(io.open("Core/NaowhForever_Waypoint.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local chunk = assert(loadstring(source, "Core/NaowhForever_Waypoint.lua"))
setfenv(chunk, env)
chunk()

Check(ns.PlaceWaypoint("Hanashi", 1454, 81.5, 19.6, " (Weapon Master)", 132), "placed")
Check(#tomtom == 1 and #set == 0 and tomtom[1].title == "Hanashi (Weapon Master)", "pin off: TomTom's waypoint")

pinOn = true
Check(ns.PlaceWaypoint("Hanashi", 1454, 81.5, 19.6, " (Weapon Master)", 132), "placed again")
Check(#tomtom == 1 and #set == 1 and set[1].map == 1454 and tracked == 1, "pin on: the game's, tracked, not TomTom's")
local placed = ns.placedWaypoint
Check(placed.title == "Hanashi" and placed.note == " (Weapon Master)" and placed.icon == 132
    and placed.map == 1454 and placed.x == 81.5 and placed.y == 19.6, "the title, note and icon kept for the pin")

env.TomTom = nil
pinOn = false
ns.PlaceWaypoint("Rwag", 1411, 41.3, 68.0)
Check(#set == 2 and ns.placedWaypoint.icon == nil and ns.placedWaypoint.note == nil, "no TomTom: the game's, without extras")

print(("test-waypoint-place: %d checks passed"):format(checks))
