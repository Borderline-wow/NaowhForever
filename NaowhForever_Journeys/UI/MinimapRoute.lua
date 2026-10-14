-- MinimapRoute.lua: the journey drawn on the minimap as dots, the walk you are on and the legs after it, inside its circle.
local ns = _G.NaowhForever

local sin, cos = math.sin, math.cos

local T = ns.THEME
local Jy = ns.Journeys
local S = Jy.Settings
local Guide = Jy.Guide
local World = Jy.World
local TINT = Jy.RouteTint

local DOT = ns.Shared.Style.ROUND
local FILTER = "TRILINEAR"
local WALK_SIZE, LEG_SIZE = 5, 4
local WALK_GAP, LEG_GAP = 10, 9
local WALK_ALPHA, LEG_ALPHA = 0.95, 0.6
local UPDATE_EVERY = 0.05
local EDGE = 0.97
local ROTATE_CVAR = "rotateMinimap"
local ROTATING = "1"

local overlay
local dots = {}
local points
local sinceUpdate = 0
local count, size, alpha, limit = 0, 0, 0, 0
local tint

local Math = {}
Jy.MinimapMath = Math

local function On()
    return Jy.On() and S.Get("minimapRoute")
end

function Math.Project(north, west, facing, pixelsPerYard)
    local east = -west
    local x = east * cos(facing) + north * sin(facing)
    local y = -east * sin(facing) + north * cos(facing)
    return x * pixelsPerYard, y * pixelsPerYard
end

local function Place(x, y)
    if x * x + y * y > limit then return end
    count = count + 1
    local dot = dots[count]
    if not dot then
        dot = overlay:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(DOT, nil, nil, FILTER)
        dots[count] = dot
    end
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", overlay, "CENTER", x, y)
    dot:SetSize(size, size)
    if tint then
        dot:SetVertexColor(tint[1], tint[2], tint[3], alpha)
    else
        dot:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, alpha)
    end
    dot:Show()
end

local function Hide(from)
    for i = from, #dots do dots[i]:Hide() end
end

local function Draw(here)
    local radius = C_Minimap.GetViewRadius()
    if not radius or radius <= 0 then return Hide(1) end
    local half = Minimap:GetWidth() / 2
    limit = (half * EDGE) ^ 2
    local facing = GetCVar(ROTATE_CVAR) == ROTATING and GetPlayerFacing() or 0
    local px, py, carry = 0, 0, nil
    count = 0
    for _, p in ipairs(points) do
        if p.c ~= here.c then
            px, carry = nil, nil
        else
            local x, y = Math.Project(p.x - here.x, p.y - here.y, facing, half / radius)
            if px then
                size, alpha = p.walk and WALK_SIZE or LEG_SIZE, p.walk and WALK_ALPHA or LEG_ALPHA
                tint = not p.walk and TINT[p.mode] or nil
                carry = Jy.RouteDots(px, py, x, y, p.walk and WALK_GAP or LEG_GAP, carry, Place)
            end
            px, py = x, y
        end
    end
    Hide(count + 1)
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
