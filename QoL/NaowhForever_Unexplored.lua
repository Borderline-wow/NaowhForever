-------------------------------------------------------------------------------
--  NaowhForever_Unexplored.lua -- the world map's unexplored areas drawn greyed out instead
--  of left blank, from NaowhForever_MapOverlays.lua.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local TEMPLATE = "NaowhForeverUnexploredPinTemplate"
local TILE = 256   -- the overlays' tile size, see Tools/build_map_overlays.py
local GREY = 0.6   -- vertex colour over the desaturated art

local function On()
    return S.Get("enabled") and S.Get("mapUnexplored")
end

-- A tile's drawn size and its texture file's size, along one side: the last tile of a row or
-- column holds what is left, in a file rounded up to a power of two.
local function Span(index, count, size)
    if index < count then return TILE, TILE end
    local pixels = size % TILE
    if pixels == 0 then pixels = TILE end
    local file = 16
    while file < pixels do file = file * 2 end
    return pixels, file
end

-------------------------------------------------------------------------------
--  The pin: one for the whole map, holding every unexplored area's tiles
-------------------------------------------------------------------------------
-- A global so the XML template can name it.
NaowhForeverUnexploredPinMixin = CreateFromMixins(MapCanvasPinMixin)

function NaowhForeverUnexploredPinMixin:OnLoad()
    self:SetIgnoreGlobalPinScale(true)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_EXPLORATION")
    self.textures = CreateTexturePool(self, "ARTWORK", 0)
end

-- Its SetPassThroughButtons is protected in combat, and this pin takes no clicks.
function NaowhForeverUnexploredPinMixin:CheckMouseButtonPassthrough() end

function NaowhForeverUnexploredPinMixin:Refresh()
    self.textures:ReleaseAll()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local overlays = On() and ns.MapOverlays[mapID]
    if not overlays then return end
    self:SetSize(map:DenormalizeHorizontalSize(1), map:DenormalizeVerticalSize(1))
    self:SetAlpha(S.Get("mapUnexploredAlpha") * map:GetGlobalAlpha())

    local explored = {}
    for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
        explored[info.textureWidth .. ":" .. info.textureHeight .. ":" .. info.offsetX .. ":" .. info.offsetY] = true
    end
    for _, area in ipairs(overlays) do
        local width, height, x, y = area[1], area[2], area[3], area[4]
        if not explored[width .. ":" .. height .. ":" .. x .. ":" .. y] then
            local wide, tall = math.ceil(width / TILE), math.ceil(height / TILE)
            for row = 1, tall do
                local rowPixels, rowFile = Span(row, tall, height)
                for col = 1, wide do
                    local colPixels, colFile = Span(col, wide, width)
                    local tex = self.textures:Acquire()
                    tex:SetSize(colPixels, rowPixels)
                    tex:SetTexCoord(0, colPixels / colFile, 0, rowPixels / rowFile)
                    tex:SetPoint("TOPLEFT", x + TILE * (col - 1), -(y + TILE * (row - 1)))
                    tex:SetTexture(area[4 + (row - 1) * wide + col], nil, nil, "TRILINEAR")
                    tex:SetDesaturated(true)
                    tex:SetVertexColor(GREY, GREY, GREY)
                    tex:Show()
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  The map's data provider
-------------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() provider.pin:Refresh() end)

function provider:OnAdded(map)
    MapCanvasDataProviderMixin.OnAdded(self, map)
    self.pin = map:AcquirePin(TEMPLATE)
    self.pin:SetPosition(0.5, 0.5)
end

function provider:OnShow()
    if On() then events:RegisterEvent("MAP_EXPLORATION_UPDATED") end
end

function provider:OnHide()
    events:UnregisterEvent("MAP_EXPLORATION_UPDATED")
end

function provider:RemoveAllData()
    self.pin.textures:ReleaseAll()
end

function provider:RefreshAllData()
    self.pin:Refresh()
end

function provider:OnGlobalAlphaChanged()
    self.pin:SetAlpha(S.Get("mapUnexploredAlpha") * self:GetMap():GetGlobalAlpha())
end

local added
local function Apply()
    if not added then
        if not On() then return end
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then
        if On() then
            events:RegisterEvent("MAP_EXPLORATION_UPDATED")
        else
            events:UnregisterEvent("MAP_EXPLORATION_UPDATED")
        end
        provider:RefreshAllData()
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^mapUnexplored") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

ns.Shared.Settings.Page("QoL/Interface", S):Card({
    id = "mapUnexplored", name = "Unexplored Areas", order = 45, switch = "mapUnexplored",
    help = "Shows the parts of the world map you have not explored yet, greyed out.",
    summary = function(store)
        return ("%d%% opacity"):format(math.floor(store.Get("mapUnexploredAlpha") * 100 + 0.5))
    end,
    rows = {
        { key = "mapUnexploredAlpha", label = "Opacity", slider = { 10, 100, 5 }, unit = "%", scale = 0.01 },
    },
})
