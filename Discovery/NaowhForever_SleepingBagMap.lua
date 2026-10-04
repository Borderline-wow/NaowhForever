-------------------------------------------------------------------------------
--  NaowhForever_SleepingBagMap.lua -- the Cozy Sleeping Bag's steps on the world map: a pin with
--  the bag's icon and the step's number on every step still to do, on the zone map open; the
--  step to do now in full, the ones after it faded. Two steps at one spot (the Messenger Bag
--  and the satchel under it) share a pin: the first not done. Click a pin for a waypoint. Built
--  like the library book pins (NaowhForever_DiscoveryMap.lua). Off by default.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.DiscoverySettings
local Bag = ns.SleepingBagChain
local T = ns.THEME
local St = ns.Shared.Style

local TEMPLATE = "NaowhForeverSleepingBagPinTemplate"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Bag_07"
local LATER_ALPHA = 0.6        -- a step after the one to do now
local BADGE = 12               -- the step's number, on a dark disc at the pin's corner

local function On()
    return S.Get("enabled") and S.Get("bagMapPins")
end

-------------------------------------------------------------------------------
--  Pins
-------------------------------------------------------------------------------
-- A global so the XML template can name it.
NaowhForeverSleepingBagPinMixin = CreateFromMixins(MapCanvasPinMixin)

function NaowhForeverSleepingBagPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    local badge = CreateFrame("Frame", nil, self)
    badge:SetSize(BADGE, BADGE)
    badge:SetPoint("CENTER", self, "BOTTOMRIGHT", -2, 2)
    badge:SetFrameLevel(self:GetFrameLevel() + 2)
    badge.disc = badge:CreateTexture(nil, "ARTWORK")
    badge.disc:SetAllPoints()
    badge.disc:SetTexture(St.ROUND, "CLAMP", "CLAMP", "TRILINEAR")
    badge.disc:SetVertexColor(0, 0, 0, 0.9)
    badge.text = ns.Font(badge, 9, nil, T.fg)
    badge.text:SetPoint("CENTER", 0, 0)
    self.badge = badge
end

-- Its SetPassThroughButtons is protected; these pins want their clicks (as the library's).
function NaowhForeverSleepingBagPinMixin:CheckMouseButtonPassthrough() end

-- entry: { step, number, now }.
function NaowhForeverSleepingBagPinMixin:OnAcquired(entry)
    self.entry = entry
    local size = S.Get("bagMapPinSize")
    self:SetSize(size, size)
    self.Icon:SetTexture(C_Item.GetItemIconByID(ns.SleepingBag.item) or FALLBACK_ICON)
    self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.badge.text:SetText(entry.number)
    self:SetAlpha(entry.now and 1 or LATER_ALPHA)
    self:SetPosition(entry.step.x / 100, entry.step.y / 100)
end

function NaowhForeverSleepingBagPinMixin:OnMouseEnter()
    local entry, step = self.entry, self.entry.step
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(("Sleeping Bag, step %d"):format(entry.number), 1, 1, 1)
    GameTooltip:AddLine(Bag.Name(step), 1, 0.82, 0)
    GameTooltip:AddLine(Bag.Where(step), T.muted.r, T.muted.g, T.muted.b, true)
    if step.tip then GameTooltip:AddLine(step.tip, 1, 1, 1, true) end
    if not entry.now then GameTooltip:AddLine("A later step.", T.muted.r, T.muted.g, T.muted.b) end
    GameTooltip:AddLine("Click for a waypoint.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

function NaowhForeverSleepingBagPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function NaowhForeverSleepingBagPinMixin:OnClick(button)
    if button == "LeftButton" then Bag.Waypoint(self.entry.step) end
end

-------------------------------------------------------------------------------
--  The map's data provider
-------------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

local function SameSpot(a, b)
    return a and b and a.map == b.map and a.x == b.x and a.y == b.y
end

function provider:RefreshAllData()
    self:RemoveAllData()
    if not On() then return end
    local _, at = Bag.Current()
    if not at then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local steps = Bag.Steps()
    for i = at, #steps do
        local step = steps[i]
        -- A step at the spot of the one before it (still to do) waits for that one.
        if step.map == mapID and not (i > at and SameSpot(step, steps[i - 1])) then
            map:AcquirePin(TEMPLATE, { step = step, number = i, now = i == at })
        end
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local added, events

local function Redraw()
    if added and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

local function OnEvent(frame, event)
    if event ~= "QUEST_LOG_UPDATE" then
        frame:RegisterEvent("QUEST_LOG_UPDATE")
        return
    end
    frame:UnregisterEvent("QUEST_LOG_UPDATE")
    Redraw()
end

local function Apply()
    if On() then
        if not added then
            WorldMapFrame:AddDataProvider(provider)
            added = true
        end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        -- A step taken or handed in moves the pins on.
        events:RegisterEvent("QUEST_ACCEPTED")
        events:RegisterEvent("QUEST_TURNED_IN")
    elseif events then
        events:UnregisterAllEvents()
    end
    Redraw()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "bagMapPins" or key == "bagMapPinSize" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
