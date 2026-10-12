-- MinimapRoute.lua: the journey drawn on the minimap, the walk you are on and the legs after it, clipped to its circle.
local ns = _G.NaowhForever

local sqrt, sin, cos = math.sqrt, math.sin, math.cos

local T = ns.THEME
local Jy = ns.Journeys
local S = Jy.Settings
local Guide = Jy.Guide
local World = Jy.World

local WALK_WIDTH, LEG_WIDTH = 3, 2
local WALK_ALPHA, LEG_ALPHA = 0.95, 0.6
local UPDATE_EVERY = 0.05
local EDGE = 0.97
local ROTATE_CVAR = "rotateMinimap"
local ROTATING = "1"

local overlay
local lines = {}
local points
local sinceUpdate = 0

local Math = {}
Jy.MinimapMath = Math

local function On()
    return Jy.On() and S.Get("minimapRoute")
end

-- A world offset (yards north, yards west) as minimap pixels, the minimap turned by facing when it rotates.
function Math.Project(north, west, facing, pixelsPerYard)
    local east = -west
    local x = east * cos(facing) + north * sin(facing)
    local y = -east * sin(facing) + north * cos(facing)
    return x * pixelsPerYard, y * pixelsPerYard
end

-- The part of the segment a to b inside the circle of radius r about the origin: ax, ay, bx, by or nil.
function Math.Clip(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local a = dx * dx + dy * dy
    if a == 0 then return nil end
    local b = 2 * (ax * dx + ay * dy)
    local c = ax * ax + ay * ay - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return nil end
    local root = sqrt(disc)
    local from = math.max(0, (-b - root) / (2 * a))
    local to = math.min(1, (-b + root) / (2 * a))
    if from >= to then return nil end
    return ax + dx * from, ay + dy * from, ax + dx * to, ay + dy * to
end

local function Line(i)
    local line = lines[i]
    if not line then
        line = overlay:CreateLine(nil, "OVERLAY")
        lines[i] = line
    end
    return line
end

local function Hide(from)
    for i = from, #lines do lines[i]:Hide() end
end

local function Draw(here)
    local radius = C_Minimap.GetViewRadius()
    if not radius or radius <= 0 then return Hide(1) end
    local half = Minimap:GetWidth() / 2
    local reach = half * EDGE
    local facing = GetCVar(ROTATE_CVAR) == ROTATING and GetPlayerFacing() or 0
    local n, prev = 0, { 0, 0 }
    for _, p in ipairs(points) do
        if p.c ~= here.c then
            prev = nil
        else
            local x, y = Math.Project(p.x - here.x, p.y - here.y, facing, half / radius)
            local ax, ay, bx, by
            if prev then ax, ay, bx, by = Math.Clip(prev[1], prev[2], x, y, reach) end
            if ax then
                n = n + 1
                local line = Line(n)
                local color = T.accent
                line:SetStartPoint("CENTER", overlay, ax, ay)
                line:SetEndPoint("CENTER", overlay, bx, by)
                line:SetThickness(p.walk and WALK_WIDTH or LEG_WIDTH)
                line:SetColorTexture(color.r, color.g, color.b, p.walk and WALK_ALPHA or LEG_ALPHA)
                line:Show()
            end
            prev = { x, y }
        end
    end
    Hide(n + 1)
end

local function Update(_, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate < UPDATE_EVERY then return end
    sinceUpdate = 0
    local here = World.Player()
    if here and points then Draw(here) else Hide(1) end
end

local function Refresh()
    points = On() and Guide.Points() or nil
    if not points then
        if overlay then
            overlay:SetScript("OnUpdate", nil)
            Hide(1)
        end
        return
    end
    if not overlay then
        overlay = CreateFrame("Frame", nil, Minimap)
        overlay:SetAllPoints()
        overlay:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    end
    sinceUpdate = UPDATE_EVERY
    overlay:SetScript("OnUpdate", Update)
end

Guide.OnChange(Refresh)
S.OnChange(Refresh)
hooksecurefunc(ns, "Apply", Refresh)
Refresh()
