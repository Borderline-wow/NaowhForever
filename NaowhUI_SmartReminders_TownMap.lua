-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_TownMap.lua -- the QoL town map: trainers, vendors, innkeepers,
--  flight masters, bankers and more pinned on the world map for your faction, so nobody has
--  to ask a guard for directions. Positions come from NaowhUI_SmartReminders_TownData.lua.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.QoLSettings

local TEMPLATE = "NaowhForeverTownPinTemplate"

-- Category -> the setting that shows it, its icon and the label in the tooltip.
local CATEGORIES = {
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
    GameTooltip:AddLine(title, 0.3, 0.71, 0.96)
    GameTooltip:Show()
end

function NaowhForeverTownPinMixin:OnMouseLeave()
    GameTooltip:Hide()
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
    local list = On() and ns.TownNPCs[self:GetMap():GetMapID()]
    if not list then return end
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local _, class = UnitClass("player")
    for _, npc in ipairs(list) do
        local cat = CATEGORIES[npc[3]]
        if npc[7]:find(faction, 1, true) and S.Get(cat[1])
            and (npc[3] ~= "class" or npc[6] == class) then
            self:GetMap():AcquirePin(TEMPLATE, npc)
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
