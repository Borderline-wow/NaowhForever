-------------------------------------------------------------------------------
--  Quartermasters.lua -- where each faction's quartermaster stands, for the pin on its
--  page (ns.Journal.Reputation.Quartermaster): learned the first time you open a vendor who
--  sells its rewards, from where you stand beside them, and kept account-wide; else entered
--  by hand in Tools/journal_factions.json. The PvP rank's vendor the same way, one per side
--  (Rep.RankVendor). It listens for vendors only while the Journal is on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings
local Rep = J.Reputation

local sellers   -- item ID -> the faction whose reward it is, made the first time a vendor opens
local rankIndexed = false   -- the rank's rewards are in it (none between seasons: tried again)
local listener

local function Spots(create)
    local account = ns.AccountSettings()
    local spots = account.journalQuartermasters
    if type(spots) ~= "table" then
        if not create then return nil end
        spots = {}
        account.journalQuartermasters = spots
    end
    return spots
end

-- A learned spot, in percent as waypoints take it. Spots learned before were kept as the
-- map's 0 to 1: those are put in percent once, here (a real spot that close to the map's
-- corner on both axes is not one a vendor stands at).
local function Learned(spot)
    if type(spot) ~= "table" or not (spot.map and spot.x and spot.y) then return nil end
    if spot.x <= 1 and spot.y <= 1 then spot.x, spot.y = spot.x * 100, spot.y * 100 end
    return spot
end

---@return { name?: string, map: number, x: number, y: number }? spot where its quartermaster stands, in percent
function Rep.Quartermaster(faction)
    local spots = Spots()
    return spots and Learned(spots[faction.key]) or faction.quartermaster
end

-- The rank's vendor's key: Alliance and Horde buy from their own, and the spots are the
-- account's.
local function RankKey()
    return J.RANK.key .. "-" .. (UnitFactionGroup("player") or "")
end

-- Learned only: Wowhead Forever has no map position for the rank vendors, so the pin shows
-- once you have opened yours.
---@return { name?: string, map: number, x: number, y: number }? spot where your side's PvP rank vendor stands
function Rep.RankVendor()
    local spots = Spots()
    return spots and Learned(spots[RankKey()]) or nil
end

local function Sellers()
    if not sellers then
        sellers = {}
        for _, tab in ipairs({ "reputation", "pvp" }) do
            for _, faction in ipairs(J.Factions(tab)) do
                for _, tier in ipairs(faction.tiers) do
                    for _, id in ipairs(tier.items) do sellers[id] = faction end
                end
            end
        end
    end
    -- The rank's rewards that are items, as the game lists them for each rank this season.
    local info = not rankIndexed and Rep.Rank()
    if info then
        rankIndexed = true
        for rank = 1, info.maxLevel or 0 do
            for _, reward in ipairs(Rep.RankRewards(rank) or {}) do
                if reward.itemID then sellers[reward.itemID] = J.RANK end
            end
        end
    end
    return sellers
end

-- A vendor opened: when it sells a faction's rewards, where you stand is where its
-- quartermaster stands. Outside an instance only (the map has no position inside one).
local function MerchantShown()
    local index, faction = Sellers(), nil
    for i = 1, GetMerchantNumItems() do
        faction = index[GetMerchantItemID(i) or 0]
        if faction then break end
    end
    if not faction then return end
    local map = C_Map.GetBestMapForUnit("player")
    local position = map and C_Map.GetPlayerMapPosition(map, "player")
    if not position then return end
    local x, y = position:GetXY()   -- the map's 0 to 1: kept in percent, as waypoints take it
    local name = UnitName("npc")
    if name and issecretvalue(name) then name = nil end
    Spots(true)[faction.rank and RankKey() or faction.key] = { name = name, map = map, x = x * 100, y = y * 100 }
end

local function Sync()
    local on = S.Get("enabled")
    if not (on or listener) then return end
    if not listener then
        listener = CreateFrame("Frame")
        listener:SetScript("OnEvent", MerchantShown)
    end
    if on then listener:RegisterEvent("MERCHANT_SHOW") else listener:UnregisterAllEvents() end
end

S.OnChange(function(key)
    if key == "enabled" then Sync() end
end)
hooksecurefunc(ns, "Apply", Sync)
