-------------------------------------------------------------------------------
--  NaowhForever_DiscoveryMap.lua -- library book pins on the world map: every book still to
--  find on the zone map open, and your librarian (or mage trainer) while you carry books for
--  them. Click a pin for a waypoint. Built like the town map's pins.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.DiscoverySettings
local L = ns.Library

local TEMPLATE = "NaowhForeverLibraryPinTemplate"
-- The light blue of the hint lines: the shade each one always was (r, g, b), or the theme's
-- lighter Accent once the theme has changed the Accent. Returns r, g, b, so where it is not
-- the last argument its values are put in locals first.
local function SoftBlue(r, g, b)
    local c = ns.ThemeTint("accentSoft", nil)
    if c then return c.r, c.g, c.b end
    return r, g, b
end
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_11"
local TURN_IN_ICON = "Interface\\Icons\\INV_Misc_Book_07"

local function On()
    return S.Get("enabled") and S.Get("mapPins")
end

-------------------------------------------------------------------------------
--  Pins
-------------------------------------------------------------------------------
-- A global so the XML template can name it.
NaowhForeverLibraryPinMixin = CreateFromMixins(MapCanvasPinMixin)

function NaowhForeverLibraryPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

-- The map calls this on every acquired pin, and its SetPassThroughButtons is protected: from
-- our refresh it is blocked in combat. These pins want their clicks, so there is nothing to
-- pass through.
function NaowhForeverLibraryPinMixin:CheckMouseButtonPassthrough() end

-- entry: { book, spot } for a book, or { npc, count } for where to hand books in.
function NaowhForeverLibraryPinMixin:OnAcquired(entry)
    self.entry = entry
    self:SetSize(S.Get("mapPinSize"), S.Get("mapPinSize"))
    local icon = entry.book and (C_Item.GetItemIconByID(entry.book.item) or BOOK_ICON) or TURN_IN_ICON
    self.Icon:SetTexture(icon)
    self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if entry.book then
        self:SetPosition(entry.spot[2] / 100, entry.spot[3] / 100)
    else
        self:SetPosition(entry.npc.x / 100, entry.npc.y / 100)
    end
end

function NaowhForeverLibraryPinMixin:OnMouseEnter()
    local entry = self.entry
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if entry.book then
        local book, spot = entry.book, entry.spot
        GameTooltip:SetText(book.name, 1, 1, 1)
        GameTooltip:AddLine(L.Where(spot), 0.61, 0.64, 0.69)
        if spot[5] then GameTooltip:AddLine(spot[5], 1, 1, 1, true) end
        local npc = L.TurnIn(book)
        local hr, hg, hb = SoftBlue(0.3, 0.71, 0.96)
        GameTooltip:AddLine("Hand in to " .. npc.name .. ", " .. npc.place, hr, hg, hb, true)
    else
        local npc = entry.npc
        GameTooltip:SetText(npc.name, 1, 1, 1)
        GameTooltip:AddLine(entry.count == 1 and "Takes the book you carry."
            or ("Takes the %d books you carry."):format(entry.count), 1, 0.82, 0)
    end
    GameTooltip:AddLine("Click for a waypoint.", SoftBlue(0.3, 0.71, 0.96))
    GameTooltip:Show()
end

function NaowhForeverLibraryPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function NaowhForeverLibraryPinMixin:OnClick(button)
    if button ~= "LeftButton" then return end
    local entry = self.entry
    if entry.book then
        local spot = entry.spot
        ns.PlaceWaypoint(entry.book.name, spot[1], spot[2], spot[3], spot[4] and (" (" .. spot[4] .. ")"),
            C_Item.GetItemIconByID(entry.book.item))
    else
        ns.PlaceWaypoint(entry.npc.name, entry.npc.map, entry.npc.x, entry.npc.y)
    end
end

-------------------------------------------------------------------------------
--  The map's data provider
-------------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function provider:RefreshAllData()
    self:RemoveAllData()
    if not On() then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    for _, item in ipairs(L.OnMap(mapID)) do
        map:AcquirePin(TEMPLATE, { book = item[1], spot = item[2] })
    end
    local counts = {}
    for _, book in ipairs(ns.LibraryBooks) do
        if L.ForMe(book) and L.Carried(book) then
            local kind = book.turnIn or "librarian"
            counts[kind] = (counts[kind] or 0) + 1
        end
    end
    if not S.Get("mapTurnIn") then return end
    for kind, n in pairs(counts) do
        local npc = ns.LibraryTurnIns[kind][L.Side()]
        if npc.map == mapID then map:AcquirePin(TEMPLATE, { npc = npc, count = n }) end
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local added, events

local function Redraw()
    if added and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

local function Apply()
    if On() then
        if not added then
            WorldMapFrame:AddDataProvider(provider)
            added = true
        end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", Redraw)
        end
        -- Looting a book takes its pin away; handing one in takes the librarian's.
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("QUEST_TURNED_IN")
    elseif events then
        events:UnregisterAllEvents()
    end
    Redraw()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "mapPins" or key == "mapPinSize" or key == "mapTurnIn" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
