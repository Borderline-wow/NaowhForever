-------------------------------------------------------------------------------
--  Places.lua -- the world's zones by name (ns.Shared.Places): a zone's map, and showing a map
--  on the world map. Read from the game's map tables the first time one is asked for.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Places = {}
ns.Shared.Places = Places

local zones   -- zone name -> its map ID

local function Load()
    zones = {}
    local map = C_Map.GetBestMapForUnit("player") or C_Map.GetFallbackWorldMapID()
    local info = map and C_Map.GetMapInfo(map)
    while info and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if not info then return end
    for _, zone in ipairs(C_Map.GetMapChildrenInfo(info.mapID, Enum.UIMapType.Zone, true) or {}) do
        zones[zone.name] = zones[zone.name] or zone.mapID
    end
end

---@return number? mapID the zone with this name
function Places.Zone(name)
    if not zones then Load() end
    return zones[name]
end

-- The world map opened on the map; out of combat only, where addon code may open it.
---@param map number? uiMapID
---@return boolean shown
function Places.ShowMap(map)
    if not map or InCombatLockdown() then return false end
    C_Map.OpenWorldMap(map)
    return true
end
