-- Quartermasters.lua: where each faction's quartermaster and the PvP rank's vendor stand, learned at the vendor.
local ns = _G.NaowhForever

local J = ns.Journal
local S = J.Settings
local Rep = J.Reputation
local PERCENT = J.C.PERCENT

local SPOTS_KEY = "journalQuartermasters"
local MAP_FRACTION = 1
local SIDE_JOIN = "-"

local EMPTY = {}
local sellers
local rankIndexed = false
local listener

local function Spots(create)
    local account = ns.AccountSettings()
    local spots = account[SPOTS_KEY]
    if type(spots) == "table" then return spots end
    if not create then return nil end
    spots = {}
    account[SPOTS_KEY] = spots
    return spots
end

local function Learned(spot)
    if type(spot) ~= "table" or not (spot.map and spot.x and spot.y) then return nil end
    if spot.x <= MAP_FRACTION and spot.y <= MAP_FRACTION then spot.x, spot.y = spot.x * PERCENT, spot.y * PERCENT end
    return spot
end

local function RankKey()
    return J.RANK.key .. SIDE_JOIN .. (UnitFactionGroup("player") or "")
end

local function IndexRewards()
    sellers = {}
    for _, tab in ipairs(J.TABS) do
        for _, faction in ipairs(J.Factions(tab)) do
            for _, tier in ipairs(faction.tiers) do
                for _, id in ipairs(tier.items) do sellers[id] = faction end
            end
        end
    end
end

local function IndexRank(info)
    rankIndexed = true
    for rank = 1, info.maxLevel or 0 do
        for _, reward in ipairs(Rep.RankRewards(rank) or EMPTY) do
            if reward.itemID then sellers[reward.itemID] = J.RANK end
        end
    end
end

local function Sellers()
    if not sellers then IndexRewards() end
    local info = not rankIndexed and Rep.Rank()
    if info then IndexRank(info) end
    return sellers
end

local function SoldHere()
    local index = Sellers()
    for i = 1, GetMerchantNumItems() do
        local faction = index[GetMerchantItemID(i) or 0]
        if faction then return faction end
    end
end

local function MerchantShown()
    local faction = SoldHere()
    if not faction then return end
    local map = C_Map.GetBestMapForUnit("player")
    local position = map and C_Map.GetPlayerMapPosition(map, "player")
    if not position then return end
    local x, y = position:GetXY()
    local name = UnitName("npc")
    if name and issecretvalue(name) then name = nil end
    Spots(true)[faction.rank and RankKey() or faction.key] = { name = name, map = map, x = x * PERCENT, y = y * PERCENT }
end

function Rep.Quartermaster(faction)
    local spots = Spots()
    return spots and Learned(spots[faction.key]) or faction.quartermaster
end

function Rep.RankVendor()
    local spots = Spots()
    return spots and Learned(spots[RankKey()]) or nil
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

local function OnSettingChanged(key)
    if key == "enabled" then Sync() end
end

S.OnChange(OnSettingChanged)
hooksecurefunc(ns, "Apply", Sync)
