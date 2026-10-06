-------------------------------------------------------------------------------
--  NaowhForever_TownMap.lua -- the QoL town map: service NPCs from NaowhForever_TownData.lua,
--  mailboxes and spirit healers from their own files, pinned on the world map for your faction.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local TEMPLATE = "NaowhForeverTownPinTemplate"
-- The light blue of the hint lines: the shade each one always was (r, g, b), or the theme's
-- lighter Accent once the theme has changed the Accent. Returns r, g, b, so where it is not
-- the last argument its values are put in locals first.
local function SoftBlue(r, g, b)
    local c = ns.ThemeTint("accentSoft", nil)
    if c then return c.r, c.g, c.b end
    return r, g, b
end
local LINK_TEMPLATE = "NaowhForeverZoneLinkPinTemplate"
local TRAVEL_ATLAS = "vehicle-templeofkotmogu-cyanball"
local EXIT_ATLAS = "house-reward-green-arrow-up"
local CAPITALS = ns.TownCapitals

-- Category -> the setting that shows it, its icon and the label in the tooltip.
local CATEGORIES = {
    spirit     = { "townSpiritHealers", "Interface\\Icons\\Spell_Holy_GuardianSpirit", "Spirit Healer" },
    class      = { "townClass", nil, "Class Trainer" },
    profession = { "townProfession", "Interface\\Icons\\INV_Misc_Book_09", "Trainer" },
    flight     = { "townFlight", "Interface\\Icons\\Ability_Mount_Gryphon_01", "Flight Master" },
    inn        = { "townInn", "Interface\\Icons\\INV_Misc_Rune_01", "Innkeeper" },
    bank       = { "townBank", "Interface\\Icons\\INV_Misc_Bag_10", "Banker" },
    auction    = { "townBank", "Interface\\Icons\\INV_Misc_Coin_01", "Auctioneer" },
    stable     = { "townStable", "Interface\\Icons\\Ability_Hunter_BeastTaming", "Stable Master" },
    repair     = { "townRepair", "Interface\\Icons\\Trade_BlackSmithing", "Repairs" },
    reagents   = { "townSupplies", "Interface\\Icons\\INV_Misc_Dust_01", "Reagents" },
    ammo       = { "townSupplies", "Interface\\Icons\\INV_Ammo_Arrow_01", "Ammunition" },
    food       = { "townSupplies", "Interface\\Icons\\INV_Misc_Food_14", "Food & Drink" },
    trade      = { "townVendors", "Interface\\Icons\\INV_Fabric_Linen_01", "Trade Goods" },
    vendor     = { "townVendors", "Interface\\Icons\\INV_Misc_Bag_07", "Vendor" },
    mail       = { "townMail", "Interface\\Icons\\INV_Letter_15", "Send and collect mail" },
}

local function On()
    return S.Get("enabled") and S.Get("townMap")
end

-------------------------------------------------------------------------------
--  Pins
-------------------------------------------------------------------------------
-- A global so the XML template can name it.
NaowhForeverTownPinMixin = CreateFromMixins(MapCanvasPinMixin)

function NaowhForeverTownPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

-- The map calls this on every acquired pin, and its SetPassThroughButtons is protected: from
-- our refresh it is blocked in combat. These pins take no clicks, so clicks reach the map anyway.
function NaowhForeverTownPinMixin:CheckMouseButtonPassthrough() end

-- npc: { x, y, category, name, title, class token, factions }
function NaowhForeverTownPinMixin:OnAcquired(npc)
    self.npc = npc
    local size = S.Get("townPinSize")
    self:SetSize(size, size)
    local icon = CATEGORIES[npc[3]][2] or ("Interface\\Icons\\ClassIcon_" .. npc[6]:lower():gsub("^%l", string.upper))
    self.Icon:SetTexture(icon)
    self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self:SetPosition(npc[1] / 100, npc[2] / 100)
end

function NaowhForeverTownPinMixin:OnMouseEnter()
    local npc = self.npc
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(npc[4], 1, 1, 1)
    local title = npc[5] ~= "" and npc[5] or CATEGORIES[npc[3]][3]
    GameTooltip:AddLine(title, SoftBlue(0.3, 0.71, 0.96))
    GameTooltip:Show()
end

function NaowhForeverTownPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

-- Separate clickable pins keep ordinary vendor/trainer pins click-through.
NaowhForeverZoneLinkPinMixin = CreateFromMixins(MapCanvasPinMixin)
function NaowhForeverZoneLinkPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end
function NaowhForeverZoneLinkPinMixin:CheckMouseButtonPassthrough() end
function NaowhForeverZoneLinkPinMixin:OnAcquired(link)
    self.link = link
    self:SetSize(S.Get("townPinSize"), S.Get("townPinSize"))
    self.Icon:SetAtlas(link.atlasName)
    self.Icon:SetRotation(link.rotation or 0)
    self:SetPosition(link.position:GetXY())
end
-- A zeppelin tower's pin has a second destination on right click, a zone exit a waypoint to
-- the road.
function NaowhForeverZoneLinkPinMixin:OnClick(button)
    local link = self.link
    if button == "RightButton" and link.rightUiMapID then
        self:GetMap():SetMapID(link.rightUiMapID)
    elseif button == "RightButton" and link.exitX then
        ns.PlaceWaypoint("Road to " .. link.name, self:GetMap():GetMapID(), link.exitX, link.exitY)
    elseif button == "LeftButton" then
        self:GetMap():SetMapID(link.linkedUiMapID)
    end
end
function NaowhForeverZoneLinkPinMixin:OnMouseEnter()
    local link = self.link
    local r, g, b = SoftBlue(0.3, 0.71, 0.96)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(link.name)
    if link.rightUiMapID then
        GameTooltip:AddLine(link.rightName, 1, 1, 1)
        GameTooltip:AddLine("Left-click: " .. C_Map.GetMapInfo(link.linkedUiMapID).name, r, g, b)
        GameTooltip:AddLine("Right-click: " .. C_Map.GetMapInfo(link.rightUiMapID).name, r, g, b)
    elseif link.linkedUiMapID ~= self:GetMap():GetMapID() then
        GameTooltip:AddLine("Click to open this zone", r, g, b)
    end
    if link.exitX then GameTooltip:AddLine("Right-click for a waypoint to this road", r, g, b) end
    GameTooltip:Show()
end
function NaowhForeverZoneLinkPinMixin:OnMouseLeave() GameTooltip:Hide() end

-------------------------------------------------------------------------------
--  The map's data provider
-------------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    self:GetMap():RemoveAllPinsByTemplate(LINK_TEMPLATE)
end

function provider:RefreshAllData()
    self:RemoveAllData()
    if not On() then return end
    local mapID = self:GetMap():GetMapID()
    local list = (not S.Get("townCapitalsOnly") or CAPITALS[mapID]) and ns.TownNPCs[mapID] or {}
    -- Forever has no map links of its own (GetMapLinksForMap returns nothing).
    if S.Get("townZoneLinks") then
        for _, exit in ipairs(ns.ZoneExits[mapID] or {}) do
            self:GetMap():AcquirePin(LINK_TEMPLATE, { name = C_Map.GetMapInfo(exit[4]).name,
                atlasName = EXIT_ATLAS, position = CreateVector2D(exit[1] / 100, exit[2] / 100),
                rotation = exit[3], linkedUiMapID = exit[4], exitX = exit[1], exitY = exit[2] })
        end
    end
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local _, class = UnitClass("player")
    if S.Get("townTravel") then
        for _, dock in ipairs(ns.TownTravel[mapID] or {}) do
            if dock[3]:find(faction, 1, true) then
                self:GetMap():AcquirePin(LINK_TEMPLATE, { name = dock[4], atlasName = TRAVEL_ATLAS,
                    position = CreateVector2D(dock[1] / 100, dock[2] / 100), linkedUiMapID = dock[5],
                    rightName = dock[6], rightUiMapID = dock[7] })
            end
        end
    end
    for _, npc in ipairs(list or {}) do
        local cat = CATEGORIES[npc[3]]
        if npc[7]:find(faction, 1, true) and S.Get(cat[1])
            and (npc[3] ~= "class" or npc[6] == class) then
            self:GetMap():AcquirePin(TEMPLATE, npc)
        end
    end
    -- Not held to the capitals: that keeps vendors and trainers off questing maps, and a
    -- mailbox out in the world is what you look for there.
    if S.Get("townMail") then
        for _, mailbox in ipairs(ns.TownMailboxes[mapID] or {}) do
            self:GetMap():AcquirePin(TEMPLATE, mailbox)
        end
    end
    if S.Get("townSpiritHealers") then
        for _, healer in ipairs(ns.TownSpiritHealers[mapID] or {}) do
            self:GetMap():AcquirePin(TEMPLATE, healer)
        end
    end
end

-------------------------------------------------------------------------------
--  Minimap: the mailboxes and spirit healers of the zone you are in
-------------------------------------------------------------------------------
-- The game says when you start and stop moving but not where you are, so the pins are placed
-- several times a second while you move (or always, with a rotating minimap, for turning).
local MINI_SIZE = 12
local MINI_INTERVAL = 0.05
local MINI_EVENTS = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD" }
local miniPins, miniSpots = {}, {}
local miniMap, miniWidth, miniHeight   -- the zone shown and its size in yards
-- The zone's map in world coordinates: its continent, top left corner and the steps for one
-- whole map across and down. UnitPosition makes no table each tick, GetPlayerMapPosition does.
local miniCont, miniOX, miniOY, miniUX, miniUY, miniVX, miniVY, miniDet
local mini = CreateFrame("Frame")
local moving, elapsed = false, 0

local function MiniOn()
    return On() and S.Get("townMinimap")
end

local function MiniFit(map)
    local cont, o = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0, 0))
    local _, u = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(1, 0))
    local _, v = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0, 1))
    if not (o and u and v) then return false end
    miniCont, miniOX, miniOY = cont, o:GetXY()
    local ux, uy = u:GetXY()
    local vx, vy = v:GetXY()
    miniUX, miniUY, miniVX, miniVY = ux - miniOX, uy - miniOY, vx - miniOX, vy - miniOY
    miniDet = miniUX * miniVY - miniUY * miniVX
    return miniDet ~= 0
end

local function MiniPlace()
    local wx, wy, _, cont = UnitPosition("player")
    if not wx or cont ~= miniCont then
        for _, pin in ipairs(miniPins) do pin:Hide() end
        return
    end
    local rx, ry = wx - miniOX, wy - miniOY
    local px = (rx * miniVY - ry * miniVX) / miniDet
    local py = (miniUX * ry - miniUY * rx) / miniDet
    local radius = C_Minimap.GetViewRadius()
    local facing = C_CVar.GetCVarBool("rotateMinimap") and GetPlayerFacing() or 0
    local sin, cos = math.sin(facing), math.cos(facing)
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local scaleX, scaleY = Minimap:GetWidth() / 2 / radius, Minimap:GetHeight() / 2 / radius
    for i, spot in ipairs(miniSpots) do
        local dx = (spot[1] / 100 - px) * miniWidth
        local dy = (py - spot[2] / 100) * miniHeight
        dx, dy = dx * cos + dy * sin, dy * cos - dx * sin
        local inside
        if square then
            inside = math.abs(dx) <= radius and math.abs(dy) <= radius
        else
            inside = dx * dx + dy * dy <= radius * radius
        end
        local pin = miniPins[i]
        pin:SetPoint("CENTER", Minimap, "CENTER", dx * scaleX, dy * scaleY)
        pin:SetShown(inside)
    end
end

local function MiniTick(_, delta)
    elapsed = elapsed + delta
    if elapsed < MINI_INTERVAL then return end
    elapsed = 0
    MiniPlace()
end

local function MiniUpdate()
    local live = #miniSpots > 0 and (moving or C_CVar.GetCVarBool("rotateMinimap"))
    mini:SetScript("OnUpdate", live and MiniTick or nil)
end

local function MiniRefresh()
    wipe(miniSpots)
    miniMap = MiniOn() and C_Map.GetBestMapForUnit("player")
    if miniMap and MiniFit(miniMap) then
        if S.Get("townMail") then
            for _, mailbox in ipairs(ns.TownMailboxes[miniMap] or {}) do miniSpots[#miniSpots + 1] = mailbox end
        end
        if S.Get("townSpiritHealers") then
            for _, healer in ipairs(ns.TownSpiritHealers[miniMap] or {}) do miniSpots[#miniSpots + 1] = healer end
        end
        miniWidth, miniHeight = C_Map.GetMapWorldSize(miniMap)
    end
    for i = #miniSpots + 1, #miniPins do miniPins[i]:Hide() end
    for i, spot in ipairs(miniSpots) do
        local pin = miniPins[i]
        if not pin then
            pin = CreateFrame("Frame", nil, Minimap, TEMPLATE)
            pin:SetSize(MINI_SIZE, MINI_SIZE)
            pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            pin:SetScript("OnEnter", pin.OnMouseEnter)
            pin:SetScript("OnLeave", pin.OnMouseLeave)
            miniPins[i] = pin
        end
        pin.npc = spot
        pin.Icon:SetTexture(CATEGORIES[spot[3]][2])
    end
    if #miniSpots > 0 then
        mini:RegisterEvent("PLAYER_STARTED_MOVING")
        mini:RegisterEvent("PLAYER_STOPPED_MOVING")
        mini:RegisterEvent("MINIMAP_UPDATE_ZOOM")
        moving = IsPlayerMoving()
        MiniPlace()
    else
        mini:UnregisterEvent("PLAYER_STARTED_MOVING")
        mini:UnregisterEvent("PLAYER_STOPPED_MOVING")
        mini:UnregisterEvent("MINIMAP_UPDATE_ZOOM")
    end
    MiniUpdate()
end

mini:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
        moving = event == "PLAYER_STARTED_MOVING"
        MiniPlace()
        MiniUpdate()
    elseif event == "MINIMAP_UPDATE_ZOOM" then
        MiniPlace()
    else
        MiniRefresh()
    end
end)

local function MiniApply()
    for _, event in ipairs(MINI_EVENTS) do
        if MiniOn() then mini:RegisterEvent(event) else mini:UnregisterEvent(event) end
    end
    MiniRefresh()
end

local added
local function Apply()
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then provider:RefreshAllData() end
    MiniApply()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^town") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-------------------------------------------------------------------------------
--  Audit: /naowh townaudit
-------------------------------------------------------------------------------
-- The data comes from Classic Era, so it is checked against Forever by standing at each NPC:
-- opening their window records where you are, next to where the data puts them, in the
-- account store (townAudit[mapID][name] = { x, y }).
local AUDIT_EVENTS = { "GOSSIP_SHOW", "MERCHANT_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED",
    "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW", "PET_STABLE_SHOW" }
local audit = CreateFrame("Frame")
local auditing = false

audit:SetScript("OnEvent", function()
    local name = UnitName("npc")
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not (name and pos) then return end
    local x, y = pos:GetXY()
    x, y = math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
    local log = ns.AccountSettings()
    log.townAudit = log.townAudit or {}
    log.townAudit[map] = log.townAudit[map] or {}
    log.townAudit[map][name] = { x, y }
    for _, npc in ipairs(ns.TownNPCs[map] or {}) do
        if npc[4] == name then
            ns.Print(("%s: you %.1f, %.1f / data %.1f, %.1f, %.1f apart"):format(name, x, y,
                npc[1], npc[2], math.sqrt((x - npc[1]) ^ 2 + (y - npc[2]) ^ 2)))
            return
        end
    end
    ns.Print(("%s: you %.1f, %.1f on map %d, not in the data"):format(name, x, y, map))
end)

function ns.TownAudit()
    auditing = not auditing
    for _, event in ipairs(AUDIT_EVENTS) do
        if auditing then audit:RegisterEvent(event) else audit:UnregisterEvent(event) end
    end
    local count = 0
    for _, names in pairs(ns.AccountSettings().townAudit or {}) do
        for _ in pairs(names) do count = count + 1 end
    end
    ns.Print(("Town audit %s. %d NPCs recorded so far."):format(auditing and "on: open an "
        .. "NPC's window while standing next to them" or "off", count))
end

local Group = ns.Shared.Settings.Group
local TOWN_SHOW = { "townSpiritHealers", "townZoneLinks", "townTravel", "townClass", "townProfession", "townFlight",
    "townInn", "townBank", "townRepair", "townSupplies", "townStable", "townVendors", "townMail" }

local function TownSummary(store)
    local shown = 0
    for i = 1, #TOWN_SHOW do
        if store.Get(TOWN_SHOW[i]) then shown = shown + 1 end
    end
    return ("%d of %d shown%s"):format(shown, #TOWN_SHOW,
        store.Get("townCapitalsOnly") and ", town pins in capitals only" or "")
end

ns.Shared.Settings.Page("QoL/Interface", S):Card({
    id = "townMap", name = "Town Map Pins", order = 40, switch = "townMap",
    help = "Trainers, vendors, innkeepers, flight masters and more pinned on the world map for "
        .. "your faction, with their name and title on hover. No more asking a guard.",
    summary = TownSummary,
    rows = {
        { key = "townPinSize", label = "Pin Size", slider = { 10, 28, 1 } },
        { key = "townCapitalsOnly", label = "Town Pins Only in Capitals", toggle = true,
          help = "Keeps vendors and trainers off questing maps." },
        { key = "townMinimap", label = "Mailboxes & Spirit Healers on Minimap", toggle = true,
          help = "Pins the ones near you on the minimap too." },
        Group("Show"),
        { key = "townSpiritHealers", label = "Spirit Healers", toggle = true,
          help = "Every graveyard's spirit healer, in towns and out in the world." },
        { key = "townZoneLinks", label = "Clickable Zone Exits", toggle = true,
          help = "Click an exit to open the adjoining zone map." },
        { key = "townTravel", label = "Boats & Zeppelins", toggle = true,
          help = "Every dock and zeppelin tower; click one to open where it goes." },
        { key = "townClass", label = "Class Trainers", toggle = true, help = "Your class's trainers only." },
        { key = "townProfession", label = "Profession Trainers", toggle = true },
        { key = "townFlight", label = "Flight Masters", toggle = true },
        { key = "townInn", label = "Innkeepers", toggle = true },
        { key = "townBank", label = "Bank & Auction House", toggle = true },
        { key = "townRepair", label = "Repairs", toggle = true },
        { key = "townSupplies", label = "Reagents, Ammo & Food", toggle = true },
        { key = "townStable", label = "Stable Masters", toggle = true },
        { key = "townVendors", label = "Other Vendors", toggle = true,
          help = "Trade goods and every other merchant." },
        { key = "townMail", label = "Mailboxes", toggle = true,
          help = "Every mailbox, in towns and out in the world." },
    },
})
