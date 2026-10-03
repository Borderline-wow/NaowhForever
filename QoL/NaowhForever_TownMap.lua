-------------------------------------------------------------------------------
--  NaowhForever_TownMap.lua -- the QoL town map: service NPCs from NaowhForever_TownData.lua,
--  and mailboxes from NaowhForever_TownMailboxes.lua, pinned on the world map for your faction.
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
local CAPITALS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true, [2482] = true, [2521] = true }

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
    self:SetPosition(link.position:GetXY())
end
function NaowhForeverZoneLinkPinMixin:OnClick(button)
    if button == "LeftButton" and self.link then self:GetMap():SetMapID(self.link.linkedUiMapID) end
end
function NaowhForeverZoneLinkPinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.link.name)
    GameTooltip:AddLine("Click to open this zone", SoftBlue(0.3, 0.71, 0.96))
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
    if S.Get("townSpiritHealers") and C_DeathInfo and C_DeathInfo.GetGraveyardsForMap then
        for _, grave in ipairs(C_DeathInfo.GetGraveyardsForMap(mapID) or {}) do
            local x, y = grave.position:GetXY()
            self:GetMap():AcquirePin(TEMPLATE, { x * 100, y * 100, "spirit", grave.name, "Spirit Healer", nil, "AH" })
        end
    end
    if S.Get("townZoneLinks") and C_Map.GetMapLinksForMap then
        for _, link in ipairs(C_Map.GetMapLinksForMap(mapID) or {}) do
            self:GetMap():AcquirePin(LINK_TEMPLATE, link)
        end
    end
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local _, class = UnitClass("player")
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
end

local added
local function Apply()
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then provider:RefreshAllData() end
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
