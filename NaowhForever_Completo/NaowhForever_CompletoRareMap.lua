-------------------------------------------------------------------------------
--  NaowhForever_CompletoRareMap.lua -- rares on the world map: one star for each rare you have
--  not killed, the game's rare star, where it is most likely to be (the spot Wowhead saw it
--  at most, or the middle of the way it patrols); with Show Killed Rares a grey one for those
--  you have. Hover a star for the rare's tooltip (what it is, whether you killed it, its
--  drops): its other spawn spots show as smaller stars and its way, if it patrols, as a trail
--  of small ones, until you move off it; every other rare's star fades meanwhile. Click a star
--  for a waypoint, as every pin of ours. Right-click it to keep its spots and way shown and
--  the others faded (focus it) after you move off; right-click it again, or another star, to
--  let go. Built like the quest giver pins (NaowhForever_CompletoMap.lua).
--
--  Off until Rare Pins is switched on: then a data provider on the world map, redrawn when a
--  rare is killed or ticked off while the map is open.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.CompletoSettings
local R = ns.Completo.Rares
local St = ns.Shared.Style

local TEMPLATE = "NaowhForeverRarePinTemplate"
-- The game's rare star; the skull raid mark where the client has no such atlas.
local STAR_ATLAS = "VignetteKill"
local SKULL_FILE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local KILLED_ALPHA = 0.7
-- What a hovered star shows, against the star: its other spawn spots ("spot") and the dots
-- along its way ("dot"); size and alpha of each.
local KINDS = { spot = { 0.7, 0.9 }, dot = { 0.45, 0.8 } }
local LIT_SCALE = 1.3                      -- the hovered rare's star
local FADED_ALPHA = 0.2                    -- every other rare's, while one is hovered

local function On()
    return S.Get("enabled") and S.Get("rarePins")
end

local function SoftBlue(r, g, b)
    local c = ns.ThemeTint("accentSoft", nil)
    if c then return c.r, c.g, c.b end
    return r, g, b
end

-------------------------------------------------------------------------------
--  Pins
-------------------------------------------------------------------------------
-- A global so the XML template can name it.
NaowhForeverRarePinMixin = CreateFromMixins(MapCanvasPinMixin)

function NaowhForeverRarePinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

-- The map calls this on every acquired pin, and its SetPassThroughButtons is protected: from
-- our refresh it is blocked in combat. These pins want their clicks, so there is nothing to
-- pass through.
function NaowhForeverRarePinMixin:CheckMouseButtonPassthrough() end

-- Not smaller on the small map than on the full-screen one.
NaowhForeverRarePinMixin.ApplyCurrentScale = ns.Completo.ScalePin

-- How it looks: as drawn, or while a rare is hovered (lit: this pin's rare; else faded).
local function Look(pin, lit, faded)
    local kind = KINDS[pin.kind]
    local size = S.Get("rarePinSize") * (kind and kind[1] or 1)
    if lit and not kind then size = size * LIT_SCALE end
    pin:SetSize(size, size)
    local alpha = kind and kind[2] or 1
    if pin.killed then alpha = alpha * KILLED_ALPHA end
    if lit and not kind then alpha = 1 elseif faded then alpha = FADED_ALPHA end
    pin.Icon:SetAlpha(alpha)
end

-- spot: { npc, x, y (percent), kind: nil for a rare's star, "spot" or "dot" for what its
-- hover shows }.
function NaowhForeverRarePinMixin:OnAcquired(spot)
    self.npc, self.spotX, self.spotY, self.kind = spot.npc, spot.x, spot.y, spot.kind
    self.killed = R.Killed(spot.npc)
    -- The star a level above what its hover shows, so nothing covers it.
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI", spot.kind and 0 or 1)
    -- Those take no mouse: the pointer stays on the star they belong to.
    self:EnableMouse(not spot.kind)
    local icon = self.Icon
    if not icon:SetAtlas(STAR_ATLAS) then icon:SetTexture(SKULL_FILE) end
    icon:SetDesaturated(self.killed)
    Look(self)
    self:SetPosition(spot.x / 100, spot.y / 100)
    if self.ApplyCurrentScale then self:ApplyCurrentScale() end
end

local provider
local focused       -- the rare clicked: shown as when hovered, until clicked again
local shown = {}    -- the pins a hovered star shows, until the pointer leaves it
local spot = {}     -- handed to each pin; OnAcquired copies what it needs

-- The points from the first'th on ({ x, y, ... }), as pins of that kind; kept in into.
local function Place(map, npc, points, first, kind, into)
    for i = first * 2 - 1, points and #points or 0, 2 do
        spot.npc, spot.x, spot.y, spot.kind = npc, points[i], points[i + 1], kind
        local pin = map:AcquirePin(TEMPLATE, spot)
        if into then into[#into + 1] = pin end
    end
end

-- A rare's other spawn spots and its way, while its star is hovered; nil takes them away.
local function ShowMore(npc)
    local map = provider and provider:GetMap()
    if not map then return end
    for i = #shown, 1, -1 do
        map:RemovePin(shown[i])
        shown[i] = nil
    end
    if not npc then return end
    Place(map, npc, R.Trail(npc), 1, "dot", shown)
    Place(map, npc, R.Spots(npc), 2, "spot", shown)
end

-- npc: the rare hovered, its pins lit and the rest faded; nil puts every pin back.
local function Highlight(npc)
    local map = provider and provider:GetMap()
    if not map then return end
    for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
        Look(pin, npc ~= nil and pin.npc == npc, npc ~= nil and pin.npc ~= npc)
    end
end

-- The rare's tooltip while its star is hovered: what it is, whether you killed it, where else
-- it is, its loot.
local function ShowTip(pin)
    local npc, m = pin.npc, T.muted
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(R.Name(npc), 1, 1, 1)
    local low, high = R.Levels(npc)
    local level = low <= 0 and "??" or low == high and tostring(low) or ("%d-%d"):format(low, high)
    GameTooltip:AddLine(("%s, level %s"):format(R.Elite(npc) and "Rare elite" or "Rare", level), 1, 0.82, 0)
    local record = R.Record(npc)
    if record then
        local have = St.HAVE_RGB
        GameTooltip:AddLine(record.n > 1 and ("Killed %d times"):format(record.n) or "Killed", have.r, have.g, have.b)
    else
        GameTooltip:AddLine("Not killed yet", 1, 1, 1)
    end
    local others = R.SpotCount(npc) - 1
    if R.Trail(npc) then
        GameTooltip:AddLine("Patrols: the small stars are its way", m.r, m.g, m.b)
    end
    if others > 0 then
        GameTooltip:AddLine(("Spawns at %d more spots, shown smaller"):format(others), m.r, m.g, m.b)
    end
    R.AddLoot(GameTooltip, npc)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(pin.npc == focused and "Click for a waypoint, right-click to let go."
        or "Click for a waypoint, right-click to keep its spots shown.", SoftBlue(0.3, 0.71, 0.96))
    GameTooltip:Show()
end

local Rest

function NaowhForeverRarePinMixin:OnMouseEnter()
    ShowTip(self)
    ShowMore(self.npc)
    Highlight(self.npc)
end

-- Back to the focused rare, if one is: its spots and way shown, the others faded; else every
-- rare as drawn.
function Rest()
    ShowMore(focused)
    Highlight(focused)
end

function NaowhForeverRarePinMixin:OnMouseLeave()
    GameTooltip:Hide()
    Rest()
end

-- Click: a waypoint to this star; right-click: focus the rare, or let go of the one focused.
function NaowhForeverRarePinMixin:OnClick(button)
    if button == "LeftButton" then
        ns.PlaceWaypoint(R.Name(self.npc), R.Map(self.npc), self.spotX, self.spotY)
    elseif button == "RightButton" then
        focused = focused ~= self.npc and self.npc or nil
        if focused then
            -- Still under the pointer: as hovered, its tooltip saying what a right-click does now.
            self:OnMouseEnter()
        else
            -- Let go of: every star back at once, not only once the pointer moves off; the
            -- tooltip stays while it is still over the star.
            Rest()
            ShowTip(self)
        end
    end
end

-------------------------------------------------------------------------------
--  The map's data provider
-------------------------------------------------------------------------------
provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
    wipe(shown)
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

-- One star per rare: its first spot, where it was seen most (R.Spots's order).
function provider:RefreshAllData()
    self:RemoveAllData()
    if not On() then return end
    local map = self:GetMap()
    local killedToo = S.Get("rarePinsKilled")
    local still = false
    for _, npc in ipairs(R.OnMap(map:GetMapID())) do
        if killedToo or not R.Killed(npc) then
            local spots = R.Spots(npc)
            spot.npc, spot.x, spot.y, spot.kind = npc, spots[1], spots[2], nil
            map:AcquirePin(TEMPLATE, spot)
            if npc == focused then still = true end
        end
    end
    -- The focused rare stays so while it is on the map shown; another map lets go of it.
    if not still then focused = nil end
    Rest()
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local added

local function Redraw()
    if added and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

local function Apply()
    if On() and not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    Redraw()
end

-- A rare killed or ticked off: its star goes, or turns grey.
R.OnChange(function()
    if On() then Redraw() end
end)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "rarePins" or key == "rarePinsKilled" or key == "rarePinSize" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local OFF = "Turn on Completo"
local function Enabled() return S.Get("enabled") == true end

Settings.Page("Completo/Rares", S):Card({
    id = "rarePins", name = "Map Pins", order = 30, switch = "rarePins",
    help = "A star on the world map for every rare you have not killed, where it is most likely to be. "
        .. "Hover one for the rare and its drops, its other spawn spots and, if it patrols, its way; "
        .. "click it for a waypoint, right-click it to keep its spots and way shown.",
    summary = function(store)
        return store.Get("rarePinsKilled") and "Every rare, the ones you killed in grey"
            or "The rares you have not killed"
    end,
    rows = {
        { key = "rarePinsKilled", label = "Show Killed Rares", toggle = true, needs = Enabled, why = OFF,
          help = "Also a grey star on the map for the rares you have killed." },
        { key = "rarePinSize", label = "Pin Size", slider = { 12, 32, 1 }, needs = Enabled, why = OFF,
          help = "How big the stars are on the map." },
    },
})
