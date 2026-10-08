-------------------------------------------------------------------------------
--  NaowhForever_CompletoMap.lua -- quest givers on the world map (and the mobs whose drop
--  begins a quest, where they spawn): a yellow ! at each one with a quest you can pick up
--  that still gives experience, a blue one where all of them are repeatable, and with Low
--  Level Quests a grey ! at those with only quests that no longer give experience. Hover for
--  the quests, click for a waypoint.
--  Built like Discovery's book pins.
--
--  Off until Map Pins is switched on: then a data provider on the world map, and quest events
--  redraw it while the map is open.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.CompletoSettings
local Q = ns.Completo.Quests

local TEMPLATE = "NaowhForeverQuestGiverPinTemplate"
-- The game's own quest marks; the gossip window's ! where the atlas is missing.
local BANG_ATLAS, GREY_ATLAS = "QuestNormal", "TrivialQuests"
local BANG_FILE = "Interface\\GossipFrame\\AvailableQuestIcon"
local REPEAT_ATLAS = "QuestDaily"
local GREY_RGB = { r = 0.62, g = 0.62, b = 0.62 }
local REPEAT_RGB = { r = 0.35, g = 0.7, b = 1 }
-- The light blue of the hint lines, or the theme's lighter Accent once the theme changed it.
local function SoftBlue(r, g, b)
    local c = ns.ThemeTint("accentSoft", nil)
    if c then return c.r, c.g, c.b end
    return r, g, b
end

local function On()
    return S.Get("enabled") and S.Get("mapPins")
end

-------------------------------------------------------------------------------
--  Pins
-------------------------------------------------------------------------------
-- A global so the XML template can name it.
NaowhForeverQuestGiverPinMixin = CreateFromMixins(MapCanvasPinMixin)

function NaowhForeverQuestGiverPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

-- The map calls this on every acquired pin, and its SetPassThroughButtons is protected: from
-- our refresh it is blocked in combat. These pins want their clicks, so there is nothing to
-- pass through.
function NaowhForeverQuestGiverPinMixin:CheckMouseButtonPassthrough() end

-- A yellow !, or a grey one: the game's grey mark where it has one, else the yellow greyed.
-- A blue ! for a giver with only repeatable quests: the game's own where it has one, else the
-- yellow tinted blue.
local function SetMark(icon, grey, repeatable)
    icon:SetVertexColor(1, 1, 1)
    icon:SetDesaturated(false)
    if grey and icon:SetAtlas(GREY_ATLAS) then return end
    if not grey and repeatable and icon:SetAtlas(REPEAT_ATLAS) then return end
    if not icon:SetAtlas(BANG_ATLAS) then icon:SetTexture(BANG_FILE) end
    if grey or repeatable then
        local c = grey and GREY_RGB or REPEAT_RGB
        icon:SetDesaturated(true)
        icon:SetVertexColor(c.r, c.g, c.b)
    end
end

-- giver: { x, y, quests, grey, repeatable } from Q.Givers. Copied: Q.Givers reuses its tables.
function NaowhForeverQuestGiverPinMixin:OnAcquired(giver)
    self.quests = self.quests or {}
    wipe(self.quests)
    for i, id in ipairs(giver.quests) do self.quests[i] = id end
    self.grey = giver.grey
    local size = S.Get("mapPinSize")
    self:SetSize(size, size)
    SetMark(self.Icon, giver.grey, giver.repeatable)
    self:SetPosition(giver.x / 100, giver.y / 100)
end

function NaowhForeverQuestGiverPinMixin:OnMouseEnter()
    local first = self.quests[1]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Q.Giver(first) or "Quest giver", 1, 1, 1)
    -- A mob whose drop begins a quest: the item, its name once the game has it, else the quest's.
    local item = Q.Item(first)
    if item then
        local name = C_Item.GetItemNameByID(item) or Q.Name(first)
        GameTooltip:AddLine(("Drops %s, which begins:"):format(name), 1, 0.82, 0)
    end
    for _, id in ipairs(self.quests) do
        local c = Q.Trivial(id) and GREY_RGB or GetQuestDifficultyColor(Q.Level(id))
        local level = ("Level %d"):format(Q.Level(id))
        if Q.Repeatable(id) then level = "Repeatable, " .. level end
        GameTooltip:AddDoubleLine(Q.Name(id), level, c.r, c.g, c.b, c.r, c.g, c.b)
    end
    GameTooltip:AddLine("Click for a waypoint.", SoftBlue(0.3, 0.71, 0.96))
    GameTooltip:Show()
end

function NaowhForeverQuestGiverPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function NaowhForeverQuestGiverPinMixin:OnClick(button)
    if button ~= "LeftButton" then return end
    local first = self.quests[1]
    local map, x, y = Q.Spot(first)
    if map then ns.PlaceWaypoint(Q.Giver(first) or Q.Name(first), map, x, y) end
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
    Q.Refresh()
    for _, giver in ipairs(Q.Givers(map:GetMapID(), S.Get("mapGrey"), S.Get("mapChainsOnly"))) do
        map:AcquirePin(TEMPLATE, giver)
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local added, events

local function Redraw()
    if added and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

-- Picking a quest up, handing one in or dropping it changes which givers have one for you;
-- a level up turns some grey and lets others be picked up.
local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }

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
        for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
    elseif events then
        events:UnregisterAllEvents()
    end
    Redraw()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "mapPins" or key == "mapGrey" or key == "mapChainsOnly"
        or key == "mapPinSize" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
