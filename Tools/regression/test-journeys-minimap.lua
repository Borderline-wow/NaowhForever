-- Run with Lua 5.1 from the repository root: the journey on the minimap. A world offset lands where the minimap
-- puts it, turned by your facing when it rotates; a segment is cut to the minimap's circle; and the lines drawn
-- are the walk to the first point and each leg after it, those beyond the circle cut short.
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
local points = { { c = 0, x = 50, y = 0, walk = true }, { c = 0, x = 500, y = 0, walk = false }, { c = 1, x = 0, y = 0 } }
local changed
local settings = { minimapRoute = true }
local here = { c = 0, x = 0, y = 0 }

local ns = { THEME = { accent = { r = 0, g = 0.5, b = 1 } } }
ns.Journeys = {
    On = function() return true end,
    Settings = { Get = function(key) return settings[key] end, OnChange = function() end },
    Guide = { OnChange = function(fn) changed = fn end, Points = function() return points end },
    World = { Player = function() return here end },
}
local env = setmetatable({
    NaowhForever = ns,
    hooksecurefunc = function() end,
    Minimap = { GetWidth = function() return 200 end, GetFrameLevel = function() return 1 end },
    C_Minimap = { GetViewRadius = function() return 100 end },
    GetCVar = function() return "0" end,
    GetPlayerFacing = function() return 0 end,
    CreateFrame = function()
        frame = { scripts = {} }
        frame.SetAllPoints = function() end
        frame.SetFrameLevel = function() end
        frame.SetScript = function(f, k, fn) f.scripts[k] = fn end
        frame.CreateLine = function()
            local line = { shown = false }
            line.SetStartPoint = function(l, _, _, x, y) l.ax, l.ay = x, y end
            line.SetEndPoint = function(l, _, _, x, y) l.bx, l.by = x, y end
            line.SetThickness = function() end
            line.SetColorTexture = function() end
            line.Show = function(l) l.shown = true end
            line.Hide = function(l) l.shown = false end
            drawn[#drawn + 1] = line
            return line
        end
        return frame
    end,
}, { __index = _G })
env._G = env
local chunk = assert(loadstring(Read("NaowhForever_Journeys/UI/MinimapRoute.lua"), "MinimapRoute.lua"))
setfenv(chunk, env)
chunk()
local M = ns.Journeys.MinimapMath

local x, y = M.Project(100, 0, 0, 0.5)
Check(Near(x, 0) and Near(y, 50), "north is up, half a pixel a yard")
x, y = M.Project(0, 100, 0, 0.5)
Check(Near(x, -50) and Near(y, 0), "west is left")
x, y = M.Project(0, 100, math.pi / 2, 0.5)
Check(Near(x, 0) and Near(y, 50), "facing west, west is up")
x, y = M.Project(100, 0, math.pi, 0.5)
Check(Near(x, 0) and Near(y, -50), "facing south, north is down")

local ax, ay, bx, by = M.Clip(-10, 0, 10, 5, 20)
Check(ax == -10 and ay == 0 and bx == 10 and by == 5, "a segment inside is kept whole")
Check(M.Clip(30, 30, 40, 40, 20) == nil, "a segment outside is dropped")
ax, ay, bx, by = M.Clip(-10, 0, 30, 0, 20)
Check(Near(ax, -10) and Near(bx, 20) and Near(ay, 0) and Near(by, 0), "a segment leaving the circle is cut at its edge")
local ex, _, fx = M.Clip(-30, 0, 30, 0, 20)
Check(Near(ex, -20) and Near(fx, 20), "a segment across it is cut at both")
Check(M.Clip(-30, 20, 30, 20, 20) == nil and M.Clip(5, 5, 5, 5, 20) == nil, "a tangent and a point are nothing")

Check(frame and frame.scripts.OnUpdate, "a journey with points updates the minimap")
frame.scripts.OnUpdate(frame, 0.1)
local shown = {}
for _, line in ipairs(drawn) do if line.shown then shown[#shown + 1] = line end end
Check(#shown == 2, "the walk to the first point and the leg after it: " .. #shown)
Check(Near(shown[1].ax, 0) and Near(shown[1].ay, 0) and Near(shown[1].by, 50), "the first runs from you to it")
Check(Near(shown[2].ay, 50) and shown[2].by < 100 and shown[2].by > 90, "the second is cut short at the circle: " .. shown[2].by)

points = nil
changed()
Check(frame.scripts.OnUpdate == nil, "no journey, no update")
for _, line in ipairs(drawn) do Check(not line.shown, "and no line is left") end

print(("journeys minimap: %d checks passed"):format(checks))
