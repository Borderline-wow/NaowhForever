-- MinimapPins.lua: pins on the minimap for spots on a world map, kept in place while you move (Parts.MinimapLayer).
local ns = _G.NaowhForever
local Parts = ns.Shared.Parts

local INTERVAL = 0.05
local NEAR_FACTOR = 2
local REFRESH_YARDS = 40
local MOVE_EVENTS = { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "MINIMAP_UPDATE_ZOOM" }
local ROTATE_CVAR = "rotateMinimap"
local SQUARE = "SQUARE"

local Layer = {}
Layer.__index = Layer

local function Fit(self, mapID)
    local cont, o = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
    local _, u = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
    local _, v = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
    if not (o and u and v) then return false end
    self.cont, self.ox, self.oy = cont, o:GetXY()
    local ux, uy = u:GetXY()
    local vx, vy = v:GetXY()
    self.ux, self.uy, self.vx, self.vy = ux - self.ox, uy - self.oy, vx - self.ox, vy - self.oy
    self.det = self.ux * self.vy - self.uy * self.vx
    self.width, self.height = C_Map.GetMapWorldSize(mapID)
    return self.det ~= 0
end

local function Inside(dx, dy, radius, square)
    if square then return math.abs(dx) <= radius and math.abs(dy) <= radius end
    return dx * dx + dy * dy <= radius * radius
end

local function HideFrom(self, first)
    for i = first, #self.pins do
        local pin = self.pins[i]
        pin:Hide()
        pin.spot = nil
    end
end

local function Here(self)
    local wx, wy, _, cont = UnitPosition("player")
    if not wx or cont ~= self.cont then return end
    local rx, ry = wx - self.ox, wy - self.oy
    return (rx * self.vy - ry * self.vx) / self.det, (self.ux * ry - self.uy * rx) / self.det, wx, wy
end

local function Gather(self, px, py, radius)
    local near, reach, xy = self.near, radius * NEAR_FACTOR, self.opts.xy
    wipe(near)
    for i = 1, self.count do
        local x, y = xy(self.spots, i)
        local dx, dy = (x - px) * self.width, (py - y) * self.height
        if dx * dx + dy * dy <= reach * reach then near[#near + 1] = i end
    end
end

function Layer:Place()
    local px, py, wx, wy = Here(self)
    if not px then return HideFrom(self, 1) end
    local radius = C_Minimap.GetViewRadius()
    if not self.at or radius ~= self.radius
        or (wx - self.at[1]) ^ 2 + (wy - self.at[2]) ^ 2 > REFRESH_YARDS * REFRESH_YARDS then
        self.at, self.radius = { wx, wy }, radius
        Gather(self, px, py, radius)
    end
    local facing = C_CVar.GetCVarBool(ROTATE_CVAR) and GetPlayerFacing() or 0
    local sin, cos = math.sin(facing), math.cos(facing)
    local square = GetMinimapShape and GetMinimapShape() == SQUARE
    local scaleX, scaleY = Minimap:GetWidth() / 2 / radius, Minimap:GetHeight() / 2 / radius
    local xy, opts, n = self.opts.xy, self.opts, 0
    for _, i in ipairs(self.near) do
        if n >= opts.max then break end
        local x, y = xy(self.spots, i)
        local dx, dy = (x - px) * self.width, (py - y) * self.height
        dx, dy = dx * cos + dy * sin, dy * cos - dx * sin
        if Inside(dx, dy, radius, square) then
            n = n + 1
            local pin = self.pins[n] or opts.new(n)
            self.pins[n] = pin
            if pin.spot ~= i then
                pin.spot = i
                opts.paint(pin, self.spots, i)
            end
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", dx * scaleX, dy * scaleY)
            pin:Show()
        end
    end
    HideFrom(self, n + 1)
end

local function Tick(frame, elapsed)
    frame.since = frame.since + elapsed
    if frame.since < INTERVAL then return end
    frame.since = 0
    frame.layer:Place()
end

local function Live(self)
    local live = self.count > 0 and (self.moving or C_CVar.GetCVarBool(ROTATE_CVAR))
    self.frame:SetScript("OnUpdate", live and Tick or nil)
end

local function OnEvent(frame, event)
    local self = frame.layer
    if event ~= "MINIMAP_UPDATE_ZOOM" then self.moving = event == "PLAYER_STARTED_MOVING" end
    self:Place()
    Live(self)
end

function Parts.MinimapLayer(opts)
    local self = setmetatable({ opts = opts, pins = {}, near = {}, count = 0 }, Layer)
    self.frame = CreateFrame("Frame")
    self.frame.layer, self.frame.since = self, 0
    self.frame:SetScript("OnEvent", OnEvent)
    return self
end

function Layer:Set(mapID, spots, count)
    self.spots, self.count, self.at = spots, 0, nil
    if mapID and spots and count > 0 and Fit(self, mapID) then self.count = count end
    for _, pin in ipairs(self.pins) do pin.spot = nil end
    for _, event in ipairs(MOVE_EVENTS) do
        if self.count > 0 then self.frame:RegisterEvent(event) else self.frame:UnregisterEvent(event) end
    end
    if self.count > 0 then
        self.moving = IsPlayerMoving()
        self:Place()
    else
        HideFrom(self, 1)
    end
    Live(self)
end

function Layer:Repaint()
    for _, pin in ipairs(self.pins) do pin.spot = nil end
    if self.count > 0 then self:Place() end
end
