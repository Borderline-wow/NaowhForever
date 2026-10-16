-- Run with Lua 5.1 from the repository root: the journey on the minimap. A world offset lands where the minimap
-- puts it, turned by your facing when it rotates; and the dots drawn run along the walk to the first point and
-- each leg after it, one on the first corner, none beyond the circle; a ride in its mode's colour, as on the world map.
local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end
local function Near(a, b) return math.abs(a - b) < 1e-6 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local drawn = {}
local frame
local points = { { c = 0, x = 50, y = 0, walk = true }, { c = 0, x = 500, y = 0, walk = false, mode = "fly" }, { c = 1, x = 0, y = 0 } }
local listeners = {}
local settings = { minimapRoute = true }
local here = { c = 0, x = 0, y = 0 }

local ns = { THEME = { accent = { r = 0, g = 0.5, b = 1 } }, Shared = { Style = { ROUND = "round" } } }
ns.Journeys = {
    On = function() return true end,
    Settings = { Get = function(key) return settings[key] end, OnChange = function() end },
    Guide = { OnChange = function(fn) listeners[#listeners + 1] = fn end, Points = function() return points end,
        Current = function() return nil end },
    World = { Player = function() return here end },
}
local env = setmetatable({
    NaowhForever = ns,
    hooksecurefunc = function() end,
    CreateFromMixins = function() return {} end,
    MapCanvasDataProviderMixin = {},
    MapCanvasPinMixin = {},
    WorldMapFrame = { AddDataProvider = function() end, IsShown = function() return false end },
    Minimap = { GetWidth = function() return 200 end, GetFrameLevel = function() return 1 end },
    C_Minimap = { GetViewRadius = function() return 100 end },
    GetCVar = function() return "0" end,
    GetPlayerFacing = function() return 0 end,
    CreateFrame = function()
        frame = { scripts = {} }
        frame.SetAllPoints = function() end
        frame.SetFrameLevel = function() end
        frame.SetScript = function(f, k, fn) f.scripts[k] = fn end
        frame.CreateTexture = function()
            local dot = { shown = false }
            dot.SetTexture = function() end
            dot.ClearAllPoints = function() end
            dot.SetPoint = function(d, _, _, _, x, y) d.x, d.y = x, y end
            dot.SetSize = function(d, w) d.size = w end
            dot.SetVertexColor = function(d, r, g, b) d.r, d.g, d.b = r, g, b end
            dot.Show = function(d) d.shown = true end
            dot.Hide = function(d) d.shown = false end
            drawn[#drawn + 1] = dot
            return dot
        end
        return frame
    end,
}, { __index = _G })
env._G = env
for _, path in ipairs({ "NaowhForever_Utilities/Journeys/UI/MapRoute.lua", "NaowhForever_Utilities/Journeys/UI/MinimapRoute.lua" }) do
    local chunk = assert(loadstring(Read(path), path))
    setfenv(chunk, env)
    chunk()
end
local M = ns.Journeys.MinimapMath

local x, y = M.Project(100, 0, 0, 0.5)
Check(Near(x, 0) and Near(y, 50), "north is up, half a pixel a yard")
x, y = M.Project(0, 100, 0, 0.5)
Check(Near(x, -50) and Near(y, 0), "west is left")
x, y = M.Project(0, 100, math.pi / 2, 0.5)
Check(Near(x, 0) and Near(y, 50), "facing west, west is up")
x, y = M.Project(100, 0, math.pi, 0.5)
Check(Near(x, 0) and Near(y, -50), "facing south, north is down")

Check(frame and frame.scripts.OnUpdate, "a journey with points updates the minimap")
frame.scripts.OnUpdate(frame, 0.1)
local shown, corner, farthest = {}, false, 0
local fly, accent = ns.Journeys.RouteTint.fly, ns.THEME.accent
for _, dot in ipairs(drawn) do
    if dot.shown then
        shown[#shown + 1] = dot
        Check(Near(dot.x, 0), "every dot is on the route, due north")
        if Near(dot.y, 50) then corner = dot.size == 5 end
        farthest = math.max(farthest, dot.y)
        if dot.y > 50 then
            Check(dot.r == fly[1] and dot.g == fly[2] and dot.b == fly[3], "a flight's dots are in the flight colour")
        else
            Check(dot.r == accent.r and dot.g == accent.g and dot.b == accent.b, "a walk's dots are in the accent")
        end
    end
end
Check(#shown == 11, "six on the walk to the first point, five on the leg until the circle: " .. #shown)
Check(corner, "a walk dot sits on the first corner")
Check(farthest > 90 and farthest <= 97, "none past the circle: " .. farthest)

points = nil
for _, fn in ipairs(listeners) do fn() end
Check(frame.scripts.OnUpdate == nil, "no journey, no update")
for _, dot in ipairs(drawn) do Check(not dot.shown, "and no dot is left") end

print(("journeys minimap: %d checks passed"):format(checks))
