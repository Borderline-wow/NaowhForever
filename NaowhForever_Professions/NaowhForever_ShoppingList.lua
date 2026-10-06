-------------------------------------------------------------------------------
--  NaowhForever_ShoppingList.lua -- Shopping List: the materials for crafts you mean to make,
--  gathered anywhere and bought together at the auction house.
--
--  In the profession window, "- [n] + Add to List" under a recipe's reagents puts the
--  materials Buy on AH would buy (every checked reagent vendors do not sell) for n crafts on
--  the list, per character. At the auction house the list shows beside it, under Favorite
--  Patterns when that is open. Nothing is bought without a check and a confirm:
--    Check Prices  each material is searched, the cheapest listings added up for the amount,
--                  and the ones well above your last scan, or short on supply, turn red;
--    Buy All       each material in turn asks the auction house for its final price, shown
--                  in red when it has moved well above the check, and Confirm pays it.
--  Starting a purchase is protected: only a click may (ADDON_ACTION_BLOCKED when tried on its
--  own, confirmed in game 2026-09-30), so each material after the first takes one click on Buy
--  Next. Bought materials leave the list.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local T = ns.THEME

local BLACK = { r = 0, g = 0, b = 0 }
local RED = "|cffff4d4d"
local WIDTH, ROW_H, TOP, MAX_ROWS = 420, 24, 36, 10
local OVERPRICED = 1.25       -- a live price this far above the last scan is warned about
local DRIFT = 1.10            -- a final price this far above the check is warned about
local SEARCH_TIMEOUT, BUY_TIMEOUT, GAP = 5, 15, 0.3
local ADD_ROW_W = 22 + 2 + 40 + 2 + 22 + 12 + 90

local function On()
    return S.Get("enabled") and S.Get("shoppingList")
end

local function Hex(c)
    return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
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

local waiting = {}
local function ItemName(item)
    local name = C_Item.GetItemNameByID(item)
    if not name then
        waiting[item] = true
        C_Item.RequestLoadItemDataByID(item)
    end
    return name
end

-------------------------------------------------------------------------------
--  The list
-------------------------------------------------------------------------------
-- Per character: recipeID -> { name, count (crafts), need = { itemID -> per craft },
-- got = { itemID -> already bought, when less than all of it was } }.
local function List()
    local account = ns.AccountSettings()
    if type(account.profShopping) ~= "table" then account.profShopping = {} end
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    account.profShopping[key] = account.profShopping[key] or {}
    return account.profShopping[key]
end

local totals, materialList, materialPool = {}, {}, {}
local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.item < b.item
end

-- Every material on the list with its total amount, by name.
local function Materials()
    wipe(totals)
    for _, craft in pairs(List()) do
        for item, per in pairs(craft.need) do
            totals[item] = (totals[item] or 0) + per * craft.count - (craft.got and craft.got[item] or 0)
        end
    end
    local n = 0
    for item, qty in pairs(totals) do
        n = n + 1
        local m = materialPool[n] or {}
        materialPool[n] = m
        m.item, m.qty, m.name = item, qty, ItemName(item) or ""
        materialList[n] = m
    end
    for i = n + 1, #materialList do materialList[i] = nil end
    table.sort(materialList, ByName)
    return materialList
end

-- A material taken off every craft; a craft with nothing left goes too.
local function Drop(item)
    local list = List()
    for recipeID, craft in pairs(list) do
        craft.need[item] = nil
        if craft.got then craft.got[item] = nil end
        if next(craft.need) == nil then list[recipeID] = nil end
    end
end

local function HasNeeds(recipeID)
    local api = ns.ProfWindowAPI
    local owned = api.Owned()
    local ok, reagents = pcall(api.Reagents, recipeID)
    if not ok then return false end
    for _, r in ipairs(reagents) do
        if not owned[r.itemID] and not api.IsVendorItem(r.itemID) then return true end
    end
    return false
end

-- What Add to List would add for a recipe: its checked reagents vendors do not sell.
local function Needs(recipeID)
    local api = ns.ProfWindowAPI
    local out, owned = {}, api.Owned()
    local ok, reagents = pcall(api.Reagents, recipeID)
    for _, r in ipairs(ok and reagents or {}) do
        if not owned[r.itemID] and not api.IsVendorItem(r.itemID) then out[r.itemID] = r.need end
    end
    return out
end

local Render

local function Add(info, crafts)
    local need = Needs(info.recipeID)
    if next(need) == nil then return end
    local list = List()
    local craft = list[info.recipeID]
    if craft then
        craft.count = craft.count + crafts
        craft.icon = craft.icon or info.icon
        for item, per in pairs(need) do craft.need[item] = per end
    else
        list[info.recipeID] = { name = info.name, icon = info.icon, count = crafts, need = need }
    end
    local parts = {}
    for item, per in pairs(need) do
        parts[#parts + 1] = ("%dx %s"):format(per * crafts, ItemName(item) or ("item " .. item))
    end
    ns.Print(("Shopping list: %s for %d %s (%s)."):format(info.name, crafts,
        crafts == 1 and "craft" or "crafts", table.concat(parts, ", ")))
    if Render then Render() end
end

-------------------------------------------------------------------------------
--  The list in the profession window's right column
-------------------------------------------------------------------------------
-- While the list is on, your own professions get a right column, where another player's show
-- their order: the crafts on the list (each with X), every material with an estimate from
-- the last scan, and Clear. Add to List fills it at once, so it is plain what it did.
local SIDE_W, SIDE_ROW_H, SIDE_CRAFTS, SIDE_MATERIALS = 260, 20, 6, 12
local side
local crafts, craftPool = {}, {}
local function ByCraftName(a, b) return (a.craft.name or "") < (b.craft.name or "") end

-- The profession window widens for the column (its Activate asks).
function ns.ShoppingListWide()
    return On() and true or false
end

local function SideRow(pool, i, withIcon)
    local row = pool[i]
    if row then return row end
    row = CreateFrame("Frame", nil, side)
    row:SetSize(SIDE_W - 16, SIDE_ROW_H - 2)
    row:EnableMouse(true)
    if withIcon then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(SIDE_ROW_H - 4, SIDE_ROW_H - 4)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    row.note = ns.Font(row, 11, nil, T.muted)
    row.note:SetJustifyH("RIGHT")
    row.name = ns.Font(row, 12, nil)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", withIcon and row.icon or row, withIcon and "RIGHT" or "LEFT", withIcon and 6 or 0, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row:SetScript("OnEnter", function(self)
        if not (self.item or self.spell) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item then
            GameTooltip:SetItemByID(self.item)
        elseif not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, self.spell) then
            GameTooltip:SetSpellByID(self.spell)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    pool[i] = row
    return row
end

local function BuildSide(win)
    -- A child of the middle column, so it hides with it on the overview.
    side = CreateFrame("Frame", nil, win.mid)
    side:SetPoint("TOPLEFT", win.mid, "TOPRIGHT", 8, 0)
    side:SetPoint("BOTTOMLEFT", win.mid, "BOTTOMRIGHT", 8, 0)
    side:SetWidth(SIDE_W)
    ns.Solid(side, "BACKGROUND", T.panel, 0.6):SetAllPoints()
    side.title = ns.Font(side, 14, nil, T.accent)
    side.title:SetPoint("TOPLEFT", 10, -10)
    side.title:SetText("Shopping List")
    side.hint = ns.Font(side, 12, nil, T.muted)
    side.hint:SetPoint("TOPLEFT", 10, -36)
    side.hint:SetWidth(SIDE_W - 20)
    side.hint:SetJustifyH("LEFT")
    side.hint:SetWordWrap(true)
    side.hint:SetSpacing(2)
    side.hint:SetText("Choose a recipe, set how many crafts and click Add to List: its materials "
        .. "land here. At the auction house the list shows beside it, to check the prices and "
        .. "buy it all.")
    side.craftsHead = ns.Font(side, 12, nil, { r = 1, g = 0.82, b = 0 })
    side.craftsHead:SetText("Crafts")
    side.materialsHead = ns.Font(side, 12, nil, { r = 1, g = 0.82, b = 0 })
    side.materialsHead:SetText("Materials")
    side.crafts, side.materials = {}, {}
    side.total = ns.Font(side, 12, nil)
    side.total:SetPoint("BOTTOMLEFT", 10, 16)
    side.total:SetPoint("RIGHT", -100, 0)
    side.total:SetJustifyH("LEFT")
    side.total:SetWordWrap(true)
    side.clear = ns.Button(side, "Clear", 80, 24, function()
        wipe(List())
        if Render then Render() end
    end)
    side.clear:SetPoint("BOTTOMRIGHT", -10, 10)
    ns.Tooltip(side.clear, "Clear", "Empties the shopping list.")
    side:Hide()
end

local function SideRender()
    if not side then return end
    local api = ns.ProfWindowAPI
    if not On() or (api and api.Linked()) then return side:Hide() end
    local list, materials = List(), Materials()
    local n = 0
    for recipeID, craft in pairs(list) do
        n = n + 1
        local e = craftPool[n] or {}
        craftPool[n] = e
        e.id, e.craft = recipeID, craft
        crafts[n] = e
    end
    for i = n + 1, #crafts do crafts[i] = nil end
    table.sort(crafts, ByCraftName)
    side.hint:SetShown(#crafts == 0)
    side.craftsHead:SetShown(#crafts > 0)
    side.materialsHead:SetShown(#materials > 0)
    local y = -36
    if #crafts > 0 then
        side.craftsHead:ClearAllPoints()
        side.craftsHead:SetPoint("TOPLEFT", 10, y)
        y = y - 18
    end
    for i = 1, math.max(#crafts, #side.crafts) do
        local e = crafts[i]
        local row = (e or side.crafts[i]) and SideRow(side.crafts, i, true)
        if row and e and i <= SIDE_CRAFTS then
            if not row.remove then
                row.remove = ns.Button(row, "X", 16, 16, function()
                    if row.recipeID then
                        List()[row.recipeID] = nil
                        if Render then Render() end
                    end
                end)
                row.remove:SetPoint("RIGHT")
                ns.Tooltip(row.remove, "Remove", "Takes this craft and its materials off the list.")
                row.note:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
            end
            row.recipeID, row.spell = e.id, e.id
            -- Crafts added before the icon was kept read it from the recipe.
            row.icon:SetTexture(e.craft.icon or C_Spell.GetSpellTexture(e.id))
            row.name:SetText(("%dx %s"):format(e.craft.count, e.craft.name or "?"))
            row.note:SetText("")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, y)
            row:Show()
            y = y - SIDE_ROW_H
        elseif row then
            row:Hide()
        end
    end
    if #materials > 0 then
        y = y - 8
        side.materialsHead:ClearAllPoints()
        side.materialsHead:SetPoint("TOPLEFT", 10, y)
        y = y - 18
    end
    local est, missing = 0, 0
    for i = 1, math.max(#materials, #side.materials) do
        local m = materials[i]
        local row = (m or side.materials[i]) and SideRow(side.materials, i, true)
        if m then
            local scan = ns.AuctionPrice and ns.AuctionPrice(m.item)
            if scan then est = est + scan * m.qty else missing = missing + 1 end
            if i <= SIDE_MATERIALS then
                if not row.note:GetPoint() then row.note:SetPoint("RIGHT") end
                row.item = m.item
                row.icon:SetTexture(C_Item.GetItemIconByID(m.item))
                row.name:SetText(("%dx %s"):format(m.qty, ItemName(m.item) or ("item " .. m.item)))
                row.note:SetText(scan and ("~" .. Money(scan * m.qty)) or "no price")
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 8, y)
                row:Show()
                y = y - SIDE_ROW_H
            else
                row:Hide()
            end
        elseif row then
            row:Hide()
        end
    end
    side.total:SetText(#materials > 0 and ("About %s at your last scan%s"):format(Money(est),
        missing > 0 and (", %d unpriced"):format(missing) or "") or "")
    side.clear:SetShown(#crafts > 0)
    side:Show()
end

-------------------------------------------------------------------------------
--  Add to List, in the profession window's recipe pane
-------------------------------------------------------------------------------
local addRow, addRecipe

local function Crafts()
    return math.max(1, tonumber(addRow and addRow.qty:GetText() or "") or 1)
end

-- Called once the profession window is built, with the window.
function ns.ShoppingListAttach(win)
    BuildSide(win)
    local d = win.detail
    local row = CreateFrame("Frame", nil, d)
    row:SetSize(ADD_ROW_W, 24)
    row:Hide()
    addRow = row
    row.add = ns.Button(row, "Add to List", 90, 24, function()
        local info = ns.ProfWindowAPI.SelectedInfo()
        if info then Add(info, Crafts()) end
    end)
    row.add:SetPoint("RIGHT")
    ns.Tooltip(row.add, "Add to Shopping List", "Puts the materials for that many crafts on your "
        .. "shopping list: every checked reagent that vendors do not sell, whatever is in your "
        .. "bags. Uncheck a reagent to leave it out. At the auction house the list shows beside "
        .. "it, to check the prices and buy it all.")
    local qty = ns.NewEditBox(row)
    qty:SetSize(40, 24)
    qty:SetNumeric(true)
    qty:SetMaxLetters(3)
    qty:SetJustifyH("CENTER")
    qty:SetText("1")
    qty:SetScript("OnEscapePressed", qty.ClearFocus)
    qty:SetScript("OnEnterPressed", qty.ClearFocus)
    row.qty = qty
    local plus = ns.Button(row, "+", 22, 24, function()
        qty:SetText(tostring(math.min(999, Crafts() + 1)))
    end)
    plus:SetPoint("RIGHT", row.add, "LEFT", -12, 0)
    qty:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = ns.Button(row, "-", 22, 24, function()
        qty:SetText(tostring(math.max(1, Crafts() - 1)))
    end)
    minus:SetPoint("RIGHT", qty, "LEFT", -2, 0)
    ns.Tooltip(qty, "Crafts", "How many crafts Add to List adds the materials for.")
end

-- Called on every draw of the recipe pane: the chosen recipe and its last reagent row, or nil
-- to hide the row. Under Buy on AH's row when that shows, else under the reagents.
function ns.ShoppingListRender(info, last)
    if not info then SideRender() end
    if not addRow then return end
    if not (On() and info and last) or not HasNeeds(info.recipeID) then return addRow:Hide() end
    if info.recipeID ~= addRecipe then
        addRecipe = info.recipeID
        addRow.qty:SetText("1")
    end
    local buyRow = addRow:GetParent().buyRow
    addRow:ClearAllPoints()
    if buyRow and buyRow:IsShown() then
        addRow:SetPoint("TOPRIGHT", buyRow, "BOTTOMRIGHT", 0, -4)
    else
        addRow:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 4, -4)
    end
    addRow:Show()
end

-------------------------------------------------------------------------------
--  At the auction house: checking and buying
-------------------------------------------------------------------------------
-- A run through the list, one material at a time:
--   checking (each searched) -> checked -> quoting -> quoted -> buying -> ready (the next) ... done
-- with noanswer, single, noquote, unavailable, failed and unconfirmed on the way.
local run
local panel

local function AuctionHouseOpen()
    local ah = _G.AuctionHouseFrame
    return ah and ah:IsShown()
end

local function Current()
    return run and run.items[run.index]
end

local ScheduleCheck

-- The next material to check, or the check is done.
local function CheckNext()
    run.index = run.index + 1
    local e = Current()
    if not e then
        run.state, run.index = "checked", 0
        return Render()
    end
    -- A search sent while the auction house is busy is dropped: wait until it is ready.
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        run.index = run.index - 1
        run.checkWaiting = true
        C_Timer.After(0.5, function()
            if run and run.checkWaiting and run.state == "checking" then
                run.checkWaiting = nil
                CheckNext()
            end
        end)
        return
    end
    run.checkWaiting = nil
    run.gen = run.gen + 1
    local gen = run.gen
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(e.item),
        { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, true)
    C_Timer.After(SEARCH_TIMEOUT, function()
        if run and run.gen == gen and run.state == "checking" then
            e.noanswer = (e.noanswer or 0) + 1
            -- Once more before giving the material up.
            if e.noanswer < 2 then run.index = run.index - 1 end
            ScheduleCheck()
        end
    end)
    Render()
end

-- The next check after GAP. A new one replaces any still waiting, and ends the current
-- material's timeout: a late or repeated answer moves the check on once, not twice.
function ScheduleCheck()
    run.gen = run.gen + 1
    local gen = run.gen
    C_Timer.After(GAP, function()
        if run and run.gen == gen and run.state == "checking" then CheckNext() end
    end)
end

local function StartCheck()
    local items = {}
    for _, m in ipairs(Materials()) do items[#items + 1] = { item = m.item, qty = m.qty } end
    if #items == 0 then return end
    run = { state = "checking", items = items, index = 0, gen = 0, bought = 0 }
    CheckNext()
end

-- A material's listings came back: the cheapest added up to its amount, leaving out your own.
local function ReadListings(e)
    local have, total = 0, 0
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(e.item) or 0 do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(e.item, i)
        if r then
            local n = math.min((r.quantity or 0) - (r.numOwnerItems or 0), e.qty - have)
            if n > 0 then have, total = have + n, total + n * r.unitPrice end
            if have >= e.qty then break end
        end
    end
    if have < e.qty and not C_AuctionHouse.HasFullCommoditySearchResults(e.item) then
        -- More listings than the first page: this event comes again with them.
        C_AuctionHouse.RequestMoreCommoditySearchResults(e.item)
        return
    end
    e.found, e.cost = have, total
    local scan = ns.AuctionPrice and ns.AuctionPrice(e.item)
    e.warn = have > 0 and scan and (total / have) > scan * OVERPRICED or false
    e.short = have < e.qty
    -- Buy what is there when the amount is not.
    e.buy = have
    ScheduleCheck()
end

-- The total now of everything that can be bought.
local function CheckedTotal()
    local total, count = 0, 0
    for _, e in ipairs(run.items) do
        if (e.buy or 0) > 0 then total, count = total + e.cost, count + 1 end
    end
    return total, count
end

-- Moves to the next material there is something to buy of, or to done.
local function NextBuy()
    repeat
        run.index = run.index + 1
    until not Current() or (Current().buy or 0) > 0
    run.state = Current() and "ready" or "done"
    Render()
end

-- From a click (Buy All, Buy Next, Try Again): ask the auction house for the current
-- material's final price. Only a click may start a purchase.
local function Quote()
    local e = Current()
    if not e then return end
    run.state = "quoting"
    run.gen = run.gen + 1
    local gen = run.gen
    C_AuctionHouse.StartCommoditiesPurchase(e.item, e.buy)
    C_Timer.After(SEARCH_TIMEOUT, function()
        if run and run.gen == gen and run.state == "quoting" then
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            run.state = "noquote"
            Render()
        end
    end)
    Render()
end

-- The only thing here that spends gold, from Confirm's click.
local function Confirm()
    local e = Current()
    if not (e and run.state == "quoted") or GetMoney() < run.total then return end
    run.state = "buying"
    run.gen = run.gen + 1
    local gen = run.gen
    C_AuctionHouse.ConfirmCommoditiesPurchase(e.item, e.buy)
    C_Timer.After(BUY_TIMEOUT, function()
        if run and run.gen == gen and run.state == "buying" then
            run.state = "unconfirmed"
            Render()
        end
    end)
    Render()
end

local function CancelRun()
    if run and (run.state == "quoting" or run.state == "quoted") then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    end
    run = nil
    Render()
end

local function Skip()
    if run and (run.state == "quoting" or run.state == "quoted") then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    end
    NextBuy()
end

-- The one button that moves the run on: check, buy, confirm, or try again.
local function Primary()
    local state = run and run.state
    if not run then return StartCheck() end
    if state == "checked" then
        -- Buy All: the first material's price at once, in this click. Each one after takes a
        -- click on Buy Next.
        run.agreed = true
        run.index = 0
        NextBuy()
        if run.state == "ready" then Quote() end
        return
    elseif state == "ready" or state == "noquote" or state == "unavailable" or state == "failed"
        or state == "unconfirmed" then
        return Quote()
    elseif state == "quoted" then
        return Confirm()
    elseif state == "done" then
        run = nil
        return Render()
    end
end

-------------------------------------------------------------------------------
--  At the auction house: the window
-------------------------------------------------------------------------------
local function Build()
    panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(WIDTH, 120)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    ns.Solid(panel, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(panel, BLACK)
    panel.title = ns.Font(panel, 13, nil, T.accent)
    panel.title:SetPoint("TOPLEFT", 10, -11)
    panel.title:SetText("Shopping List")
    panel.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(WIDTH - 20, ROW_H - 2)
        row:SetPoint("TOPLEFT", 10, -TOP - (i - 1) * ROW_H)
        row:EnableMouse(true)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_H - 4, ROW_H - 4)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.remove = ns.Button(row, "X", 18, 18, function()
            if row.item and not run then
                Drop(row.item)
                Render()
            end
        end)
        row.remove:SetPoint("RIGHT")
        ns.Tooltip(row.remove, "Remove", "Takes this material off the shopping list.")
        row.note = ns.Font(row, 12, nil, T.muted)
        row.note:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
        row.note:SetJustifyH("RIGHT")
        row.name = ns.Font(row, 12, nil)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.item)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:Hide()
        panel.rows[i] = row
    end
    panel.more = ns.Font(panel, 11, nil, T.muted)
    panel.more:SetJustifyH("LEFT")
    panel.crafts = ns.Font(panel, 11, nil, T.muted)
    panel.crafts:SetWidth(WIDTH - 20)
    panel.crafts:SetJustifyH("LEFT")
    panel.crafts:SetWordWrap(true)
    panel.line1 = ns.Font(panel, 12, nil)
    panel.line1:SetWidth(WIDTH - 20)
    panel.line1:SetJustifyH("LEFT")
    panel.line2 = ns.Font(panel, 12, nil)
    panel.line2:SetWidth(WIDTH - 20)
    panel.line2:SetJustifyH("LEFT")
    panel.line2:SetWordWrap(true)
    panel.primary = ns.Button(panel, "Check Prices", 180, 24, Primary)
    panel.primary:SetPoint("BOTTOMLEFT", 10, 10)
    panel.cancel = ns.Button(panel, "Clear", 90, 24, function()
        if run then return CancelRun() end
        wipe(List())
        Render()
    end)
    panel.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.skip = ns.Button(panel, "Skip", 80, 24, Skip)
    panel.skip:SetPoint("RIGHT", panel.cancel, "LEFT", -6, 0)
    panel:Hide()
end

-- Under the Favorite Patterns window (and its buyout box) when shown, else beside the
-- auction house.
function ns.ShoppingListPlace()
    if not panel then return end
    local ah = _G.AuctionHouseFrame
    local market, confirm
    if ns.FavoritePatternsFrames then market, confirm = ns.FavoritePatternsFrames() end
    panel:ClearAllPoints()
    if confirm and confirm:IsVisible() then
        panel:SetPoint("TOPLEFT", confirm, "BOTTOMLEFT", 0, -6)
    elseif market and market:IsVisible() then
        panel:SetPoint("TOPLEFT", market, "BOTTOMLEFT", 0, -6)
    elseif ah then
        panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 8, 0)
    end
end

-- A material's price on its row: the check's once done, else an estimate from the last scan.
local function RowNote(m)
    local e
    for _, x in ipairs(run and run.items or {}) do
        if x.item == m.item then e = x end
    end
    if e and e.cost then
        if e.found == 0 then return RED .. "none listed|r" end
        local text = Money(e.cost)
        if e.short then text = ("%s  %sonly %d|r"):format(text, RED, e.found) end
        if e.warn then text = RED .. text .. "|r" end
        return text
    end
    if e and e.noanswer and not e.cost then return RED .. "no answer|r" end
    if e and e.single then return Hex(T.muted) .. "single listings: buy by hand|r" end
    local scan = ns.AuctionPrice and ns.AuctionPrice(m.item)
    return scan and (Hex(T.muted) .. "~" .. Money(scan * m.qty) .. "|r") or (Hex(T.muted) .. "no price|r")
end

local PROBLEMS = {
    noquote = "The auction house gave no final price.",
    unavailable = "The auction house has no price for it right now.",
    failed = "The purchase failed; the price may have changed.",
    unconfirmed = "No answer to the purchase yet; check your mail before trying again.",
}
local craftNames = {}

-- What the run says, and what its buttons do, for its state.
local function RunText(materials)
    local muted = Hex(T.muted)
    local state = run and run.state
    local e = Current()
    local name = e and (ItemName(e.item) or ("item " .. e.item))
    if not run then
        local est, missing = 0, 0
        for _, m in ipairs(materials) do
            local scan = ns.AuctionPrice and ns.AuctionPrice(m.item)
            if scan then est = est + scan * m.qty else missing = missing + 1 end
        end
        return ("About %s at your last scan%s."):format(Money(est),
            missing > 0 and (", %d without a price"):format(missing) or ""),
            muted .. "Check Prices looks each one up first; nothing is bought before you confirm it.|r",
            "Check Prices", true, "Clear", false
    elseif state == "checking" then
        return ("Checking prices... (%d/%d)"):format(run.index, #run.items), muted .. (name or "") .. "|r",
            "Checking...", false, "Cancel", false
    elseif state == "checked" then
        local total, count = CheckedTotal()
        local warned = 0
        for _, x in ipairs(run.items) do if x.warn or x.short then warned = warned + 1 end end
        local short = GetMoney() < total
        return ("All of it now: %s%s|r"):format(short and RED or "|cffffffff", Money(total)),
            short and (RED .. "You do not have enough gold.|r")
                or warned > 0 and (RED .. ("%d marked red: well above your last scan, or not enough listed."):format(warned) .. "|r")
                or (muted .. "Buy All asks each final price; you confirm each one.|r"),
            ("Buy All (%s)"):format(Money(total)), count > 0 and not short, "Cancel", false
    elseif state == "ready" then
        return ("Next: %dx %s, about %s"):format(e.buy, name, Money(e.cost)),
            muted .. ("Bought %d so far. The game starts each purchase only from a click."):format(run.bought) .. "|r",
            run.agreed and ("Buy Next (%s)"):format(Money(e.cost)) or "Get Price", true, "Cancel", true
    elseif state == "quoting" then
        return ("%dx %s: getting the final price..."):format(e.buy, name),
            run.agreed and (muted .. ("Buying the list: %d bought so far."):format(run.bought) .. "|r") or "",
            "Confirm", false, "Cancel", true
    elseif state == "quoted" then
        local moved = run.total > e.cost * DRIFT
        local short = GetMoney() < run.total
        return ("%dx %s: %s%s|r  %s(%s each)|r"):format(e.buy, name, (moved or short) and RED or "|cffffffff",
            Money(run.total), muted, Money(run.unit)),
            short and (RED .. "You do not have enough gold.|r")
                or moved and (RED .. ("Careful: up from %s at the check."):format(Money(e.cost)) .. "|r")
                or (muted .. ("Checked at %s."):format(Money(e.cost)) .. "|r"),
            "Confirm", not short, "Cancel", true
    elseif state == "buying" then
        return ("Buying %dx %s..."):format(e.buy, name), "", "Confirm", false, "Cancel", false
    elseif state == "done" then
        return ("Bought %d %s."):format(run.bought, run.bought == 1 and "material" or "materials"),
            muted .. "They wait in your mailbox.|r", "Close", true, "Close", false
    end
    return RED .. (PROBLEMS[state] or "") .. "|r", muted .. ("%dx %s"):format(e and e.buy or 0, name or "") .. "|r",
        "Try Again", true, "Cancel", true
end

Render = function()
    -- The profession window's column shows the same list.
    SideRender()
    if not (On() and AuctionHouseOpen()) then return panel and panel:Hide() end
    local materials = Materials()
    if #materials == 0 and not run then return panel and panel:Hide() end
    if not panel then Build() end
    local shown = math.min(#materials, MAX_ROWS)
    for i, row in ipairs(panel.rows) do
        local m = materials[i]
        row.item = m and m.item
        if m then
            local name = ItemName(m.item)
            row.icon:SetTexture(C_Item.GetItemIconByID(m.item))
            row.name:SetText(("%dx %s"):format(m.qty, name or ("item " .. m.item)))
            row.note:SetText(RowNote(m))
            row.remove:SetShown(not run)
            row:Show()
        else
            row:Hide()
        end
    end
    local y = -TOP - shown * ROW_H
    panel.more:ClearAllPoints()
    panel.more:SetPoint("TOPLEFT", 10, y)
    panel.more:SetText(#materials > MAX_ROWS and ("+%d more"):format(#materials - MAX_ROWS) or "")
    if #materials > MAX_ROWS then y = y - 16 end
    -- What it is all for.
    local names = craftNames
    wipe(names)
    for _, craft in pairs(List()) do names[#names + 1] = ("%dx %s"):format(craft.count, craft.name or "?") end
    table.sort(names)
    panel.crafts:ClearAllPoints()
    panel.crafts:SetPoint("TOPLEFT", 10, y - 4)
    panel.crafts:SetText(#names > 0 and ("For " .. table.concat(names, ", ")) or "")
    y = y - 4 - (#names > 0 and panel.crafts:GetStringHeight() or 0) - 10
    local line1, line2, primary, enabled, cancel, skip = RunText(materials)
    panel.line1:ClearAllPoints()
    panel.line1:SetPoint("TOPLEFT", 10, y)
    panel.line1:SetText(line1)
    panel.line2:ClearAllPoints()
    panel.line2:SetPoint("TOPLEFT", panel.line1, "BOTTOMLEFT", 0, -4)
    panel.line2:SetText(line2)
    y = y - panel.line1:GetStringHeight() - 4 - panel.line2:GetStringHeight()
    ns.SetButtonText(panel.primary, primary)
    panel.primary:SetEnabled(enabled)
    panel.primary:SetAlpha(enabled and 1 or 0.45)
    panel.primary:SetShown(not (run and run.state == "done"))
    ns.SetButtonText(panel.cancel, cancel)
    panel.skip:SetShown(skip)
    panel:SetHeight(-y + 10 + 24 + 10)
    ns.ShoppingListPlace()
    panel:Show()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local pending = false
local function Flush()
    pending = false
    Render()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b)
    if event == "AUCTION_HOUSE_SHOW" then
        return C_Timer.After(0.3, Render)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if run then CancelRun() end
        if panel then panel:Hide() end
        return
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if not waiting[a] then return end
        waiting[a] = nil
        if b and not pending then
            pending = true
            C_Timer.After(0, Flush)
        end
        return
    end
    local e = Current()
    if run and event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" and run.checkWaiting then
        run.checkWaiting = nil
        return CheckNext()
    end
    if not (run and e) then return end
    local state = run.state
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and state == "checking" and a == e.item then
        ReadListings(e)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and state == "checking" and type(a) == "table"
        and a.itemID == e.item then
        -- Sold as single listings, not by amount: left to buy by hand.
        e.single, e.buy = true, 0
        ScheduleCheck()
    elseif event == "COMMODITY_PRICE_UPDATED" and state == "quoting" then
        run.state, run.unit, run.total = "quoted", a, b
        Render()
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" and state == "quoting" then
        run.state = "unavailable"
        Render()
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and (state == "buying" or state == "unconfirmed") then
        run.bought = run.bought + 1
        -- All of it bought: off the list. Less than the list wanted (not enough listed): the
        -- rest stays on it.
        local list = List()
        if e.buy >= e.qty then
            Drop(e.item)
        else
            for recipeID, craft in pairs(list) do
                if craft.need[e.item] and e.buy > 0 then
                    craft.got = craft.got or {}
                    local got = craft.got[e.item] or 0
                    local took = math.min(craft.need[e.item] * craft.count - got, e.buy)
                    e.buy = e.buy - took
                    if got + took >= craft.need[e.item] * craft.count then
                        craft.need[e.item], craft.got[e.item] = nil, nil
                        if next(craft.need) == nil then list[recipeID] = nil end
                    else
                        craft.got[e.item] = got + took
                    end
                end
            end
        end
        NextBuy()
    elseif event == "COMMODITY_PURCHASE_FAILED" and state == "buying" then
        run.state = "failed"
        Render()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if run then CancelRun() end
        if panel then panel:Hide() end
        if addRow then addRow:Hide() end
        return
    end
    for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ITEM_DATA_LOAD_RESULT",
        "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED",
        "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
        pcall(events.RegisterEvent, events, event)
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "shoppingList" then
        Apply()
        if ns.ProfWindowRefresh then ns.ProfWindowRefresh() end
    end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
