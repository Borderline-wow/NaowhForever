-------------------------------------------------------------------------------
--  NaowhForever_FavoriteRecipes.lua -- what to do with the recipes you have starred but not
--  learned yet (the star is in Naowh's profession window). Two settings:
--
--  Train Favorites: at a profession trainer who teaches any of them that you can learn now, a
--  small window beside the trainer's lists them with their cost: Learn one, or Learn All.
--  Search Favorites AH: at the auction house, a window beside it lists the patterns, plans
--  and manuals of your favourites for your professions, the ones listed at your last Scan
--  Prices first with their price. Buy finds the cheapest listing and asks, as the auction
--  house's own buyout does, before Accept buys it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local T = ns.THEME

local BLACK = { r = 0, g = 0, b = 0 }
local WIDTH, ROW_H, TOP, MAX_ROWS = 420, 26, 36, 8
local FOOTER_H = 36

local function OnTrainer()
    return S.Get("enabled") and S.Get("trainFavorites")
end

local function OnAH()
    return S.Get("enabled") and S.Get("searchFavoritesAH")
end

local function Favorites()
    return ns.ProfFavorites and ns.ProfFavorites.Store() or {}
end

-- As the Recipe Finder tells: the recipe's info while its profession is loaded, else the
-- spellbook.
local function Known(spell)
    local info = C_TradeSkillUI.GetRecipeInfo(spell)
    if info and info.learned then return true end
    return (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spell)) or false
end

-- "1g 20s", "35s", "8c": plain text, leaving out the coins that are zero.
local function Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then
        if s > 0 then
            if c > 0 then return ("%dg %ds %dc"):format(g, s, c) end
            return ("%dg %ds"):format(g, s)
        end
        if c > 0 then return ("%dg %dc"):format(g, c) end
        return ("%dg"):format(g)
    end
    if s > 0 then
        if c > 0 then return ("%ds %dc"):format(s, c) end
        return ("%ds"):format(s)
    end
    return ("%dc"):format(c)
end

-------------------------------------------------------------------------------
--  The small window both use
-------------------------------------------------------------------------------
local function Panel(title)
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetSize(WIDTH, 80)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    ns.Solid(p, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(p, BLACK)
    p.title = ns.Font(p, 13, nil, T.accent)
    p.title:SetPoint("TOPLEFT", 10, -11)
    p.title:SetText(title)
    p.close = ns.Button(p, "X", 20, 20, function() p.dismissed = true; p:Hide() end)
    p.close:SetPoint("TOPRIGHT", -7, -7)
    p.note = ns.Font(p, 11, nil, T.muted)
    p.note:SetPoint("BOTTOMLEFT", 10, 12)
    p.note:SetJustifyH("LEFT")
    p.rows = {}
    -- The shopping list sits under the patterns window, and moves as it shows and hides.
    p:HookScript("OnShow", function() if ns.ShoppingListPlace then ns.ShoppingListPlace() end end)
    p:HookScript("OnHide", function() if ns.ShoppingListPlace then ns.ShoppingListPlace() end end)
    p:Hide()
    return p
end

-- A line: the icon, the name, a note on the right (a cost, a price) and a button after it.
local function Row(p, i, label, onClick)
    local row = p.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, p)
    row:SetSize(WIDTH - 20, ROW_H - 2)
    row:SetPoint("TOPLEFT", 10, -TOP - (i - 1) * ROW_H)
    row:EnableMouse(true)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.button = ns.Button(row, label, 64, 20, function() onClick(row) end)
    row.button:SetPoint("RIGHT")
    row.note = ns.Font(row, 12, nil, T.muted)
    row.note:SetPoint("RIGHT", row.button, "LEFT", -8, 0)
    row.note:SetJustifyH("RIGHT")
    row.name = ns.Font(row, 12, nil)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item then
            GameTooltip:SetItemByID(self.item)
        elseif self.spell then
            GameTooltip:SetSpellByID(self.spell)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    p.rows[i] = row
    return row
end

-- Shows the first rows, hides the rest, and sizes the window to them.
local function Fit(p, shown, footer)
    for i = shown + 1, #p.rows do p.rows[i]:Hide() end
    p:SetHeight(TOP + shown * ROW_H + (footer and FOOTER_H or 14))
end

-------------------------------------------------------------------------------
--  At a trainer
-------------------------------------------------------------------------------
local trainer
local trainerOpen   -- between TRAINER_SHOW and TRAINER_CLOSED

-- A trainer service's name, whether it can be learned ("available", "unavailable", "used" or
-- "header") and its icon. Forever returns these in another order than Blizzard's documented
-- one (its third value is the icon's file ID, seen in game 2026-09-30), so the kind is
-- whichever value is one of those words and the icon the first number.
local KINDS = { available = true, unavailable = true, used = true, header = true }
local function ServiceInfo(i)
    local values = { GetTrainerServiceInfo(i) }
    local kind, icon
    for k = 2, #values do
        local v = values[k]
        if not kind and type(v) == "string" and KINDS[v] then kind = v end
        if not icon and type(v) == "number" and v > 1000 then icon = v end
    end
    return values[1], kind, icon
end
ns.TrainerServiceInfo = ServiceInfo

-- The trainer's services that are favourites you can learn now. Matched by name, as the
-- service list has no spell IDs (as the Recipe Finder's trainer scan does).
local function TrainerOffers()
    if not (IsTradeskillTrainer and IsTradeskillTrainer()) then return {} end
    local byName = {}
    for spell, on in pairs(Favorites()) do
        if on and not Known(spell) then
            local name = C_Spell.GetSpellName(spell)
            if name then byName[name] = spell end
        end
    end
    local out = {}
    for i = 1, GetNumTrainerServices() do
        local name, kind, icon = ServiceInfo(i)
        -- No kind given at all: learnable when its skill requirement is met (you do not know
        -- it yet, or it would not be a favourite here).
        if not kind and name and byName[name] then
            local _, _, met = GetTrainerServiceSkillReq(i)
            kind = met ~= false and "available" or "unavailable"
        end
        if name and kind == "available" and byName[name] then
            out[#out + 1] = { index = i, name = name, spell = byName[name],
                cost = GetTrainerServiceCost(i) or 0,
                icon = icon or (GetTrainerServiceIcon and GetTrainerServiceIcon(i))
                    or C_Spell.GetSpellTexture(byName[name]) }
        end
    end
    return out
end

local RenderTrainer, Learn

local function LearnClick(row) Learn({ row.offer }) end

-- Learns the offers you can pay for, from Learn's click. Last index first: buying a service
-- can renumber the ones after it, and one whose index now names another service (a click
-- before the list was drawn again) is skipped.
function Learn(offers)
    local money = GetMoney()
    table.sort(offers, function(a, b) return a.index > b.index end)
    for _, o in ipairs(offers) do
        if o.cost <= money and ServiceInfo(o.index) == o.name then
            BuyTrainerService(o.index)
            money = money - o.cost
        end
    end
end

local function BuildTrainer()
    trainer = Panel("Train Favorites")
    trainer.all = ns.AccentBorder(ns.Button(trainer, "Learn All", 140, 22, function() Learn(trainer.offers) end))
    trainer.all:SetPoint("BOTTOMRIGHT", -10, 8)
end

RenderTrainer = function()
    local frame = _G.ClassTrainerFrame
    if not (OnTrainer() and (trainerOpen or frame and frame:IsShown())) then return trainer and trainer:Hide() end
    local offers = TrainerOffers()
    if #offers == 0 then return trainer and trainer:Hide() end
    if not trainer then BuildTrainer() end
    if trainer.dismissed then return end
    trainer.offers = offers
    local total = 0
    for i, o in ipairs(offers) do
        total = total + o.cost
        if i <= MAX_ROWS then
            local row = Row(trainer, i, "Learn", LearnClick)
            row.offer, row.item, row.spell = o, nil, o.spell
            row.icon:SetTexture(o.icon)
            row.name:SetText(o.name)
            row.note:SetText(Money(o.cost))
            row.note:SetTextColor(GetMoney() < o.cost and 1 or T.muted.r, GetMoney() < o.cost and 0.3 or T.muted.g,
                GetMoney() < o.cost and 0.3 or T.muted.b)
            row:Show()
        end
    end
    Fit(trainer, math.min(#offers, MAX_ROWS), true)
    ns.SetButtonText(trainer.all, ("Learn All (%s)"):format(Money(total)))
    trainer.all:SetEnabled(GetMoney() >= total)
    trainer.all:SetAlpha(GetMoney() >= total and 1 or 0.45)
    trainer.note:SetText(#offers > MAX_ROWS and ("+%d more"):format(#offers - MAX_ROWS) or "")
    trainer:ClearAllPoints()
    if frame and frame:IsShown() then
        trainer:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
    else
        trainer:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    trainer:Show()
end

-------------------------------------------------------------------------------
--  At the auction house
-------------------------------------------------------------------------------
local market

-- Patterns bought here, per character: itemID -> when. A bought one waits in the mailbox,
-- where the game cannot be asked, so it stays off the list for as long as auction mail keeps
-- (30 days) unless it turns up in the bags or bank, or is learned, first.
local BOUGHT_KEEP = 30 * 86400

local function Bought()
    local account = ns.AccountSettings()
    if type(account.profBoughtPatterns) ~= "table" then account.profBoughtPatterns = {} end
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    account.profBoughtPatterns[key] = account.profBoughtPatterns[key] or {}
    return account.profBoughtPatterns[key]
end

-- One you already have, carried, banked or bought and still in the mail.
local function Owned(item)
    if (C_Item.GetItemCount(item, true, false, true) or 0) > 0 then return true end
    local at = Bought()[item]
    if at and time() - at < BOUGHT_KEEP then return true end
    if at then Bought()[item] = nil end
    return false
end

local mine, patterns, patternPool, NONE = {}, {}, {}, {}

local function Mine(index)
    local line = index and select(7, GetProfessionInfo(index))
    if line then mine[line] = true end
end

local function PricedFirst(a, b)
    if (a.price ~= nil) ~= (b.price ~= nil) then return a.price ~= nil end
    if a.price and b.price and a.price ~= b.price then return a.price < b.price end
    return a.r.spell < b.r.spell
end

-- The patterns, plans and manuals of your favourites that you have not learned or got yet,
-- for the professions you have: priced ones (listed at the last scan) first, cheapest first.
local function Patterns()
    wipe(mine)
    local p1, p2, p3, p4, p5 = GetProfessions()
    Mine(p1)
    Mine(p2)
    Mine(p3)
    Mine(p4)
    Mine(p5)
    local favorites, n = Favorites(), 0
    for line, data in pairs(ns.RecipeData or NONE) do
        if mine[line] then
            for _, r in ipairs(data.recipes) do
                if r.recipe and favorites[r.spell] and not Known(r.spell) and not Owned(r.recipe) then
                    n = n + 1
                    local e = patternPool[n] or {}
                    patternPool[n] = e
                    e.r, e.item, e.price = r, r.recipe, ns.AuctionPrice and ns.AuctionPrice(r.recipe)
                    patterns[n] = e
                end
            end
        end
    end
    for i = n + 1, #patterns do patterns[i] = nil end
    table.sort(patterns, PricedFirst)
    return patterns
end

-- Types the name into the auction house's search on its Buy tab and runs it.
local function Search(name)
    local ah = _G.AuctionHouseFrame
    if not (name and ah and ah:IsShown() and ah.SearchBar) then return end
    if ah.SetDisplayMode and _G.AuctionHouseFrameDisplayMode then
        pcall(ah.SetDisplayMode, ah, _G.AuctionHouseFrameDisplayMode.Buy)
    end
    ah.SearchBar:SetSearchText(name)
    ah.SearchBar:StartSearch()
end

-- Buy: the cheapest listing of a pattern, bought only once Accept is clicked, as the auction
-- house's own buyout asks. Buy's click searches (patterns are single listings, so the
-- answer is ITEM_SEARCH_RESULTS_UPDATED); the states RenderConfirm shows:
--   searching -> ready (Accept) -> placing -> bought, or none, noanswer and failed (Try
--   Again), byamount (Search), unconfirmed
local SEARCH_TIMEOUT, BUY_TIMEOUT = 5, 15
local buy   -- { item, name, key, state, auctionID, price, gen }
local bids = {}   -- auctionID -> itemID, for every bid Accept placed and not yet answered
local RenderConfirm

local function StartBuy(item, name)
    local gen = (buy and buy.gen or 0) + 1
    local key = C_AuctionHouse.MakeItemKey(item)
    buy = { item = item, name = name, key = key, state = "searching", gen = gen }
    C_AuctionHouse.SendSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
        false)
    C_Timer.After(SEARCH_TIMEOUT, function()
        if buy and buy.gen == gen and buy.state == "searching" then
            buy.state = "noanswer"
            RenderConfirm()
        end
    end)
    RenderConfirm()
end

-- What each pattern costs now, from searches while the auction house is open: itemID ->
-- the cheapest buyout, or false for none listed. Emptied when the auction house closes.
local live = {}
local waiting = {}

-- The cheapest listing with a buyout that is not your own, from the last search for `key`.
local function Cheapest(key)
    local best
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) or 0 do
        local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
        if r and (r.buyoutAmount or 0) > 0 and not r.containsOwnerItem and not r.containsAccountItem
            and (not best or r.buyoutAmount < best.buyoutAmount) then
            best = r
        end
    end
    live[key.itemID] = best and best.buyoutAmount or false
    return best
end

local function ReadResults()
    local best = Cheapest(buy.key)
    if best then
        buy.state, buy.auctionID, buy.price = "ready", best.auctionID, best.buyoutAmount
    else
        buy.state = "none"
    end
    RenderConfirm()
end

-- The live prices are looked up one pattern at a time when the window first shows, each
-- search answered (or given up after LOOKUP_TIMEOUT) before the next, so the auction house's
-- limit on searches is never hit. Buy takes precedence; the list waits for it.
local LOOKUP_TIMEOUT, LOOKUP_GAP = 3, 0.3
local lookup, lookups, looked = nil, {}, {}
local lookupWait    -- the LOOKUP_GAP after an answer, before the next search
local RenderMarket

local function BuyClick(row) StartBuy(row.item, row.searchName) end

local function NextLookup()
    if lookup or lookupWait or (buy and (buy.state == "searching" or buy.state == "placing")) then return end
    local item = table.remove(lookups, 1)
    if not item then return end
    local key = C_AuctionHouse.MakeItemKey(item)
    local gen = (looked.gen or 0) + 1
    looked.gen = gen
    lookup = { item = item, key = key }
    C_AuctionHouse.SendSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
        false)
    C_Timer.After(LOOKUP_TIMEOUT, function()
        if lookup and looked.gen == gen then
            lookup = nil
            NextLookup()
        end
    end)
end

local function LookupDone()
    Cheapest(lookup.key)
    lookup, lookupWait = nil, true
    RenderMarket()
    C_Timer.After(LOOKUP_GAP, function()
        lookupWait = nil
        NextLookup()
    end)
end

-- Accept, in its click as the game requires: the only thing here that spends gold.
local function Accept()
    if not buy then return end
    if buy.state == "noanswer" or buy.state == "failed" then return StartBuy(buy.item, buy.name) end
    if buy.state == "byamount" then return Search(buy.name) end
    if buy.state ~= "ready" or GetMoney() < buy.price then return end
    C_AuctionHouse.PlaceBid(buy.auctionID, buy.price)
    bids[buy.auctionID] = buy.item
    buy.state = "placing"
    local placed = buy
    C_Timer.After(BUY_TIMEOUT, function()
        if buy == placed and buy.state == "placing" then
            buy.state = "unconfirmed"
            RenderConfirm()
        end
    end)
    RenderConfirm()
end

-- AUCTION_HOUSE_PURCHASE_COMPLETED for a listing Accept bid on, whatever the box shows now.
local function Purchased(auctionID)
    local item = bids[auctionID]
    bids[auctionID] = nil
    -- On its way by mail: off the list, one is all it takes to learn.
    Bought()[item] = time()
    -- That listing is gone: the row looks its price up again.
    live[item], looked[item] = nil, nil
    if buy and buy.auctionID == auctionID then
        buy.state = "bought"
        RenderConfirm()
    end
    C_Timer.After(1, function() if RenderMarket then RenderMarket() end end)
end

-- Under the list, as the auction house's own "Buyout auction for:" box.
local function BuildConfirm()
    local c = CreateFrame("Frame", nil, market)
    c:SetSize(WIDTH, 78)
    c:SetPoint("TOPLEFT", market, "BOTTOMLEFT", 0, -6)
    c:EnableMouse(true)
    ns.Solid(c, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(c, BLACK)
    c.line1 = ns.Font(c, 12, nil)
    c.line1:SetPoint("TOP", 0, -10)
    c.line1:SetWidth(WIDTH - 20)
    c.line2 = ns.Font(c, 12, nil)
    c.line2:SetPoint("TOP", c.line1, "BOTTOM", 0, -4)
    c.line2:SetWidth(WIDTH - 20)
    c.accept = ns.Button(c, "Accept", 120, 22, Accept)
    c.accept:SetPoint("BOTTOMRIGHT", c, "BOTTOM", -4, 8)
    c.cancel = ns.Button(c, "Cancel", 120, 22, function()
        buy = nil
        c:Hide()
    end)
    c.cancel:SetPoint("BOTTOMLEFT", c, "BOTTOM", 4, 8)
    market.confirm = c
    c:HookScript("OnShow", function() if ns.ShoppingListPlace then ns.ShoppingListPlace() end end)
    c:HookScript("OnHide", function() if ns.ShoppingListPlace then ns.ShoppingListPlace() end end)
end

-- For the shopping list: the patterns window and its buyout box, to sit under them.
function ns.FavoritePatternsFrames()
    return market, market and market.confirm
end

RenderConfirm = function()
    if not market then return end
    if not market.confirm then BuildConfirm() end
    local c = market.confirm
    if not buy then return c:Hide() end
    local name, muted = buy.name or "the pattern", "|cff" .. ("%02x%02x%02x"):format(T.muted.r * 255,
        T.muted.g * 255, T.muted.b * 255)
    local line1, line2, accept, enabled, cancel = "", "", "Accept", false, "Cancel"
    if buy.state == "searching" then
        line1, line2 = "Looking for the cheapest", name
    elseif buy.state == "ready" then
        local short = GetMoney() < buy.price
        line1 = "Buyout auction for:"
        line2 = ("%s  %s%s|r"):format(name, short and "|cffff4d4d" or "|cffffffff", Money(buy.price))
        enabled = not short
        if short then line1 = "|cffff4d4dYou do not have enough gold.|r" end
    elseif buy.state == "none" then
        line1, line2, cancel = "None with a buyout listed right now.", muted .. name .. "|r", "Close"
    elseif buy.state == "noanswer" then
        line1, line2, accept, enabled = "No answer from the auction house.",
            muted .. "Searches are limited to a few a second.|r", "Try Again", true
    elseif buy.state == "byamount" then
        line1, line2, accept, enabled = "Sold by amount, not as single listings.",
            muted .. "Search shows it on the Buy tab.|r", "Search", true
    elseif buy.state == "placing" then
        line1, line2 = "Buying", name
    elseif buy.state == "failed" then
        line1, line2, accept, enabled = "The purchase failed.",
            muted .. "Someone may have bought it first.|r", "Try Again", true
    elseif buy.state == "unconfirmed" then
        line1, line2, cancel = "No answer to the purchase yet.",
            muted .. "Check your mailbox before buying it again.|r", "Close"
    elseif buy.state == "bought" then
        line1, line2, cancel = "Bought " .. name .. ".", muted .. "It is on its way to your mailbox.|r", "Close"
    end
    c.line1:SetText(line1)
    c.line2:SetText(line2)
    ns.SetButtonText(c.accept, accept)
    local alone = buy.state == "none" or buy.state == "bought" or buy.state == "unconfirmed"
    c.accept:SetShown(not alone)
    -- Cancel beside Accept, or centred on its own as Close.
    c.cancel:ClearAllPoints()
    if alone then
        c.cancel:SetPoint("BOTTOM", c, "BOTTOM", 0, 8)
    else
        c.cancel:SetPoint("BOTTOMLEFT", c, "BOTTOM", 4, 8)
    end
    c.accept:SetEnabled(enabled)
    c.accept:SetAlpha(enabled and 1 or 0.45)
    ns.SetButtonText(c.cancel, cancel)
    c:Show()
end

RenderMarket = function()
    local ah = _G.AuctionHouseFrame
    if not (OnAH() and ah and ah:IsShown()) then return market and market:Hide() end
    local list = Patterns()
    if #list == 0 then return market and market:Hide() end
    if not market then market = Panel("Favorite Patterns") end
    if market.dismissed then return end
    local scanned = ns.AuctionScanTime and ns.AuctionScanTime()
    for i = 1, math.min(#list, MAX_ROWS) do
        local e = list[i]
        local row = Row(market, i, "Buy", BuyClick)
        local name = C_Item.GetItemNameByID(e.item)
        if not name then
            waiting[e.item] = true
            C_Item.RequestLoadItemDataByID(e.item)
        end
        row.item, row.spell, row.searchName = e.item, nil, name
        row.icon:SetTexture(C_Item.GetItemIconByID(e.item))
        row.name:SetText(name or C_Spell.GetSpellName(e.r.spell) or "?")
        -- The price now once looked up; until then the last scan's, marked as such.
        local now = live[e.item]
        if now ~= nil then
            row.note:SetText(now and Money(now) or "none listed")
        else
            row.note:SetText(e.price and ("scan " .. Money(e.price)) or scanned and "not listed" or "no scan yet")
            if not looked[e.item] then
                looked[e.item] = true
                lookups[#lookups + 1] = e.item
            end
        end
        if now then
            row.note:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
        else
            row.note:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
        end
        row.button:SetEnabled(name ~= nil)
        row.button:SetAlpha(name and 1 or 0.45)
        row:Show()
    end
    Fit(market, math.min(#list, MAX_ROWS), #list > MAX_ROWS)
    market.note:SetText(#list > MAX_ROWS and ("+%d more"):format(#list - MAX_ROWS) or "")
    market:ClearAllPoints()
    market:SetPoint("TOPLEFT", ah, "TOPRIGHT", 8, 0)
    market:Show()
    NextLookup()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local pending = false
local function Flush()
    pending = false
    RenderTrainer()
    RenderMarket()
end

local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0.2, Flush)
end

-- A trainer's services can arrive a moment after the trainer opens, with no event to say so,
-- so opening looks again a few times.
local OPEN_TRIES = { 0.2, 0.6, 1.5 }
local function TrainerOpened()
    trainerOpen = true
    if trainer then trainer.dismissed = nil end
    for _, delay in ipairs(OPEN_TRIES) do
        C_Timer.After(delay, function()
            if not (trainer and trainer:IsShown()) then RenderTrainer() end
        end)
    end
end

-- Blizzard's trainer window, once its addon has loaded: it opening or closing is followed as
-- well as the trainer events, in case those come before its list is filled.
local hookedTrainer
local function HookTrainerFrame()
    local frame = _G.ClassTrainerFrame
    if hookedTrainer or not frame then return end
    hookedTrainer = true
    frame:HookScript("OnShow", function() if OnTrainer() then TrainerOpened() end end)
    frame:HookScript("OnHide", function() if trainer then trainer:Hide() end end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name, loaded)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_TrainerUI" then HookTrainerFrame() end
        return
    elseif event == "TRAINER_SHOW" then
        HookTrainerFrame()
        TrainerOpened()
        return
    elseif event == "TRAINER_CLOSED" then
        trainerOpen = false
        if trainer then trainer:Hide() end
        return
    elseif event == "AUCTION_HOUSE_SHOW" then
        if market then market.dismissed = nil end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        buy, lookup = nil, nil
        wipe(live)
        wipe(lookups)
        wipe(looked)
        wipe(waiting)
        if market then market:Hide() end
        return
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local item = type(name) == "table" and name.itemID
        if buy and buy.state == "searching" and item == buy.item then
            ReadResults()
            RenderMarket()
        end
        if lookup and item == lookup.item then LookupDone() end
        return
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if buy and buy.state == "searching" and name == buy.item then
            buy.state = "byamount"
            RenderConfirm()
        end
        if lookup and name == lookup.item then
            lookup = nil
            C_Timer.After(LOOKUP_GAP, NextLookup)
        end
        return
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        if bids[name] then Purchased(name) end
        return
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        if buy and buy.state == "placing" then
            buy.state = "failed"
            RenderConfirm()
        end
        return
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if not waiting[name] then return end
        waiting[name] = nil
        if not (loaded and market and market:IsShown()) then return end
    end
    Queue()
end)

local function Apply()
    events:UnregisterAllEvents()
    if trainer and not OnTrainer() then trainer:Hide() end
    if market and not OnAH() then market:Hide() end
    if not (OnTrainer() or OnAH()) then return end
    for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "AUCTION_HOUSE_SHOW",
        "AUCTION_HOUSE_CLOSED", "PLAYER_MONEY", "ITEM_DATA_LOAD_RESULT", "ADDON_LOADED",
        "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
        "AUCTION_HOUSE_SHOW_ERROR" }) do
        pcall(events.RegisterEvent, events, event)
    end
    HookTrainerFrame()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "trainFavorites" or key == "searchFavoritesAH" then
        Apply()
        Queue()
    end
end)
hooksecurefunc(ns, "Apply", Apply)

-- A star set or cleared at a trainer or the auction house shows at once: the profession
-- window's star goes through ns.ProfFavorites.Toggle.
if ns.ProfFavorites then
    hooksecurefunc(ns.ProfFavorites, "Toggle", function()
        if OnTrainer() or OnAH() then Queue() end
    end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
