-- Run with Lua 5.1 from the repository root: the world map's unexplored areas. The overlay data
-- has a tile for every 256px of each area on every zone, and the pin draws the areas the game
-- does not report as explored, tile by tile in the art's pixels (the last row and column cut
-- from a power-of-two file), greyed out, and nothing while the setting is off.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local ns = {}
local chunk = assert(loadstring(Read("QoL/NaowhForever_MapOverlays.lua")))
setfenv(chunk, { _G = { NaowhForever = ns } })
chunk()

local maps, areas = 0, 0
for map, list in pairs(ns.MapOverlays) do
    maps = maps + 1
    for _, area in ipairs(list) do
        local tiles = math.ceil(area[1] / 256) * math.ceil(area[2] / 256)
        Check(#area == 4 + tiles, "a tile for every 256px: " .. map)
        areas = areas + 1
    end
end
Check(maps >= 40 and areas >= 500, ("every zone (%d maps, %d areas)"):format(maps, areas))
Check(#ns.MapOverlays[1413] == 25, "the Barrens has its 25 areas")
Check(ns.MapOverlays[1454] == nil, "a capital has none")

-- The pin, against stubs.
local settings = { enabled = true, mapUnexplored = false, mapUnexploredAlpha = 0.6 }
local S = { Get = function(key) return settings[key] end, Set = function() end }
local card
ns.QoLSettings = S
ns.Shared = { Settings = { Page = function() return { Card = function(_, c) card = c end } end } }
ns.Apply = function() end
ns.MapOverlays = { [1] = { { 300, 100, 10, 20, 11, 12 }, { 64, 64, 500, 400, 13 } } }

local explored = {}
local textures = {}
local function NewTexture()
    local t = { shown = false }
    function t:SetSize(w, h) self.w, self.h = w, h end
    function t:SetTexCoord(l, r, top, b) self.coords = { l, r, top, b } end
    function t:SetPoint(_, x, y) self.x, self.y = x, y end
    function t:SetTexture(file) self.file = file end
    function t:SetDesaturated(d) self.desaturated = d end
    function t:SetVertexColor(r) self.grey = r end
    function t:Show() self.shown = true end
    return t
end
local pool = {
    ReleaseAll = function() for i = #textures, 1, -1 do textures[i] = nil end end,
    Acquire = function() local t = NewTexture(); textures[#textures + 1] = t; return t end,
}
local map = {
    GetMapID = function() return 1 end,
    DenormalizeHorizontalSize = function() return 1002 end,
    DenormalizeVerticalSize = function() return 668 end,
    GetGlobalAlpha = function() return 1 end,
}
local function Mixin(...)
    local t = {}
    for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do t[k] = v end end
    return t
end
local env = setmetatable({
    _G = { NaowhForever = ns },
    CreateFromMixins = Mixin,
    MapCanvasPinMixin = {}, MapCanvasDataProviderMixin = { OnAdded = function() end },
    CreateTexturePool = function() return pool end,
    C_MapExplorationInfo = { GetExploredMapTextures = function() return explored end },
    CreateFrame = function()
        return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end }
    end,
    hooksecurefunc = function() end,
    WorldMapFrame = { IsShown = function() return false end },
}, { __index = _G })
chunk = assert(loadstring(Read("QoL/NaowhForever_Unexplored.lua")))
setfenv(chunk, env)
chunk()

local pin = Mixin(env.NaowhForeverUnexploredPinMixin, {
    SetIgnoreGlobalPinScale = function() end, UseFrameLevelType = function() end,
    GetMap = function() return map end,
    SetSize = function(self, w, h) self.w, self.h = w, h end,
    SetAlpha = function(self, a) self.alpha = a end,
})
pin:OnLoad()

pin:Refresh()
Check(#textures == 0, "nothing drawn while off")

settings.mapUnexplored = true
pin:Refresh()
Check(#textures == 3, "both areas drawn, the wide one in two tiles")
Check(pin.w == 1002 and pin.h == 668 and pin.alpha == 0.6, "the pin covers the map at the chosen opacity")
local first, second = textures[1], textures[2]
Check(first.file == 11 and first.w == 256 and first.h == 100 and first.x == 10 and first.y == -20,
    "the first tile at the area's offset")
Check(first.coords[2] == 1 and first.coords[4] == 100 / 128, "a full-width tile, cut to 100 of a 128px file")
Check(second.file == 12 and second.w == 44 and second.x == 266 and second.coords[2] == 44 / 64,
    "the last column holds what is left, from a 64px file")
Check(first.desaturated and first.grey < 1 and first.shown, "greyed out")

explored = { { textureWidth = 300, textureHeight = 100, offsetX = 10, offsetY = 20 } }
pin:Refresh()
Check(#textures == 1 and textures[1].file == 13, "an explored area is left to the game")

Check(card and card.switch == "mapUnexplored", "the card switches the setting")
Check(Read("QoL/NaowhForever_QoL.lua"):find("mapUnexplored = false", 1, true), "Unexplored Areas starts off")

print(("test-map-unexplored: %d checks passed"):format(checks))
