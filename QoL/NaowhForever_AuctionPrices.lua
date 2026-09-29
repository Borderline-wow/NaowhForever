-------------------------------------------------------------------------------
--  NaowhForever_AuctionPrices.lua -- auction house prices from a full scan: a Scan Prices
--  button on the auction house, the lowest buyout per item kept for each realm and faction,
--  and that price on item tooltips and as a loot feed price source.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local SCAN_COOLDOWN = 900   -- Blizzard allows one full scan every 15 minutes
local CHUNK = 1000          -- listings read per frame, so a large auction house does not stall
local TIMEOUT = 60
local TAG = "|cff0091edNaowh AH|r"

local button, scanning, scanGen = nil, nil, 0

-- One price table per auction house: prices differ between realms and factions. Read on
-- every item tooltip, so the key is worked out once.
local houseKey
local function House(create)
    local account = ns.AccountSettings()
    account.ahPrices = account.ahPrices or {}
    houseKey = houseKey or GetRealmName() .. "-" .. (UnitFactionGroup("player") or "")
    if create and not account.ahPrices[houseKey] then account.ahPrices[houseKey] = { prices = {} } end
    return account.ahPrices[houseKey]
end

-- The lowest buyout for one of the item at the last scan, and when that scan ran.
function ns.AuctionPrice(itemID)
    local house = House()
    if house and itemID then return house.prices[itemID], house.time end
end

local function Age(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

function ns.AuctionScanSummary()
    local house = House()
    if not (house and house.time) then return "No scan yet for this realm and faction." end
    local count = 0
    for _ in pairs(house.prices) do count = count + 1 end
    return ("Last scan %s ago: %s items priced."):format(Age(time() - house.time), BreakUpLargeNumbers(count))
end

local function Label(text)
    if button then button.label:SetText(text) end
end

local events = CreateFrame("Frame")

local function Stop(message)
    scanning = nil
    scanGen = scanGen + 1
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    Label("Scan Prices")
    if message then ns.Print(TAG .. ": " .. message) end
end

-- The listings arrive all at once and are read a chunk per frame. Each keeps its buyout for
-- one of the item; listings without a buyout (bid only) are skipped.
local function Read()
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local total = C_AuctionHouse.GetNumReplicateItems()
    if total == 0 then return Stop("The auction house returned no listings. Try again in a moment.") end
    local prices, index, gen = {}, 0, scanGen
    local function Step()
        if gen ~= scanGen then return end
        local last = math.min(index + CHUNK, total) - 1
        for i = index, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
                C_AuctionHouse.GetReplicateItemInfo(i)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local each = math.floor(buyout / count)
                if not prices[itemID] or each < prices[itemID] then prices[itemID] = each end
            end
        end
        index = last + 1
        if index < total then
            Label(("Scanning %d%%"):format(math.floor(index * 100 / total)))
            C_Timer.After(0, Step)
            return
        end
        local house = House(true)
        house.prices, house.time = prices, time()
        Stop()
        ns.Print(TAG .. ": " .. ns.AuctionScanSummary())
    end
    Step()
end

local function Scan()
    if scanning then return end
    local house = House()
    local wait = house and house.time and SCAN_COOLDOWN - (time() - house.time)
    if wait and wait > 0 then
        ns.Print(("%s: Blizzard allows one full scan every 15 minutes. Next scan in %dm."):format(
            TAG, math.ceil(wait / 60)))
        return
    end
    scanning = true
    scanGen = scanGen + 1
    local gen = scanGen
    Label("Scanning...")
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    C_AuctionHouse.ReplicateItems()
    C_Timer.After(TIMEOUT, function()
        if gen == scanGen and scanning then
            Stop("no answer from the auction house. A full scan can only run once every 15 minutes.")
        end
    end)
end

local function ShowButton()
    local frame = _G.AuctionHouseFrame
    if not frame then return end
    if not button then
        button = ns.Button(frame, "Scan Prices", 120, 24, Scan)
        local tab = frame.AuctionsTab
        if tab then
            button:SetPoint("LEFT", tab, "RIGHT", 8, 0)
        else
            button:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -8, -4)
        end
        ns.Tooltip(button, "Scan Prices", function()
            return "Reads every listing on the auction house and keeps the lowest buyout for "
                .. "each item, shown on item tooltips. Blizzard allows one full scan every 15 "
                .. "minutes.\n\n" .. ns.AuctionScanSummary()
        end)
    end
    button:SetShown(S.Get("ahPrices"))
end

events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ShowButton()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if scanning then Stop("scan stopped: the auction house closed.") end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        Read()
    end
end)
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")

hooksecurefunc(S, "Set", function(key)
    if key == "ahPrices" and button then button:SetShown(S.Get("ahPrices")) end
end)

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not S.Get("ahTooltip") then return end
    local id = data and data.id
    if not id or (issecretvalue and issecretvalue(id)) then return end
    local price, when = ns.AuctionPrice(id)
    if not price then return end
    tooltip:AddDoubleLine(TAG, C_CurrencyInfo.GetCoinTextureString(price, 12)
        .. " |cff808080each, " .. Age(time() - when) .. " ago|r", 1, 1, 1, 1, 1, 1)
end)
