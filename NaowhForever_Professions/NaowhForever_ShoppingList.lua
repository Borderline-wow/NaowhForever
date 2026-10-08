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
--
--  A material this character can make for less from its parts (smelting the ore, say) is not
--  bought: its parts are, a few levels down, and it shows under Make First. The recipes known
--  are recorded as each of your professions opens; prices are your last auction house scan's.
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
local MAX_DEPTH = 4   -- how many levels down a material is made from its parts

-- A per-character table in the account's settings.
local function Mine(name)
    local account = ns.AccountSettings()
    if type(account[name]) ~= "table" then account[name] = {} end
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    account[name][key] = account[name][key] or {}
    return account[name][key]
end

-- recipeID -> { name, count (crafts), need = { itemID -> per craft }, got = { itemID ->
-- already bought, kept from before Have } }.
local function List() return Mine("profShopping") end

-- itemID -> how many of it the list need not buy any more: bought, or taken off with X.
local function Have() return Mine("profShopHave") end

-- itemID -> { recipe, made (per craft), need = { itemID -> per craft }, cooldown }: what this
-- character's known recipes make, recorded as each profession opens.
local function Makes() return Mine("profMakes") end

-- Account-wide: items always bought as they are (Buy on a Make First row).
local function Keep()
    local account = ns.AccountSettings()
    if type(account.profShopKeep) ~= "table" then account.profShopKeep = {} end
    return account.profShopKeep
end

-- itemID -> the most of it the crafts on the list could use, at any level down: made or
-- bought, whichever the plan picks.
local function Reach()
    local reach, makes = {}, Makes()
    local function Use(item, qty, depth)
        reach[item] = (reach[item] or 0) + qty
        local m = makes[item]
        if m and depth < MAX_DEPTH then
            local crafts = math.ceil(qty / m.made)
            for part, per in pairs(m.need) do Use(part, per * crafts, depth + 1) end
        end
    end
    for _, craft in pairs(List()) do
        for item, per in pairs(craft.need) do Use(item, per * craft.count, 0) end
    end
    return reach
end

-- A craft taken off takes what was bought for it along: what the list counts as had never
-- passes what the crafts left could use, so an empty list starts from nothing bought.
local function Trim()
    local have, reach = Have(), Reach()
    for item, qty in pairs(have) do
        local most = reach[item] or 0
        if qty > most then have[item] = most > 0 and most or nil end
    end
end

-- What one of an item costs to buy: the last scan's price, or a vendor's when lower.
local function BuyPrice(item)
    local scan = ns.AuctionPrice and ns.AuctionPrice(item)
    local api = ns.ProfWindowAPI
    local vendor = api and api.IsVendorItem(item) and ns.AccountSettings().profVendorPrices
    vendor = vendor and vendor[item]
    if scan and vendor then return math.min(scan, vendor) end
    return scan or vendor
end

-- The cheapest way to one of an item: its cost (nil when unpriced) and whether to make it.
-- plan memoizes both; ignoreKeep asks what making would cost an item kept to buy. A recipe
-- with a cooldown (the transmutes, Mooncloth) is never planned: it makes only a few a day.
local function Cheapest(item, plan, depth, ignoreKeep)
    if not ignoreKeep and plan.cost[item] ~= nil then return plan.cost[item] or nil, plan.make[item] end
    local buy, make = BuyPrice(item), false
    local cost, m = buy, Makes()[item]
    if m and not m.cooldown and depth < MAX_DEPTH and not plan.busy[item] and (ignoreKeep or not Keep()[item]) then
        plan.busy[item] = true
        local total = 0
        for part, per in pairs(m.need) do
            local c = plan.owned[part] and 0 or Cheapest(part, plan, depth + 1)
            if not c then
                total = nil
                break
            end
            total = total + c * per
        end
        plan.busy[item] = nil
        if total and (not buy or total / m.made < buy) then cost, make = total / m.made, true end
        -- What one craft's parts cost, for Materials to weigh the whole crafts it takes.
        if make and not ignoreKeep then plan.craft[item] = total end
    end
    if not ignoreKeep then plan.cost[item], plan.make[item] = cost or false, make end
    return cost, make
end

-- Materials runs a few times a render: it fills these again each time, and what it returns
-- holds only until the next call.
local shopPlan = { cost = {}, make = {}, craft = {}, busy = {}, planned = {}, saves = {} }
local demand, nextDemand, toMake, buy, had = {}, {}, {}, {}, {}
local trials = {}
for depth = 0, MAX_DEPTH do trials[depth] = { left = {}, made = {} } end
local materialList, materialPool = {}, {}
local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.item < b.item
end

-- Parts on the list: not the ones you have, nor vendor ones, as Add to List leaves those off.
local function Listed(part)
    local api = ns.ProfWindowAPI
    return not shopPlan.owned[part] and not (api and api.IsVendorItem(part))
end

-- What was bought counts at every level, whatever the plan is now: ore bought to smelt still
-- counts once the bars are bought instead. Supply takes up to want of an item from `from`, as
-- it is or made from its parts there, a craft at a time, and says how many.
local function Supply(item, want, from, into, depth)
    local got = math.min(want, from[item] or 0)
    if got > 0 then from[item] = from[item] - got end
    local m = shopPlan.makes[item]
    if not m or m.cooldown or depth >= MAX_DEPTH then return got end
    -- Only bought parts make it here; one with none on the list is never made from them.
    local listed = false
    for part in pairs(m.need) do listed = listed or Listed(part) end
    local trial, trialMade = trials[depth].left, trials[depth].made
    while listed and got < want do
        wipe(trial)
        wipe(trialMade)
        for k, v in pairs(from) do trial[k] = v end
        local whole = true
        for part, per in pairs(m.need) do
            if Listed(part) and Supply(part, per, trial, trialMade, depth + 1) < per then
                whole = false
                break
            end
        end
        if not whole then break end
        for k in pairs(from) do from[k] = trial[k] end
        for k, v in pairs(trialMade) do into[k] = (into[k] or 0) + v end
        into[item] = (into[item] or 0) + m.made
        got = got + m.made
    end
    return got
end

-- What to buy: every material on the list with its amount, by name; what is made first,
-- itemID -> how many; and the plan that chose, with planned (made as the cheaper way, not
-- just from parts bought) and saves (what that saves on buying, where both are priced).
local function Materials()
    local api = ns.ProfWindowAPI
    wipe(shopPlan.cost); wipe(shopPlan.make); wipe(shopPlan.craft)
    wipe(shopPlan.busy); wipe(shopPlan.planned); wipe(shopPlan.saves)
    shopPlan.owned = api and api.Owned() or {}
    shopPlan.makes = Makes()
    local makes = shopPlan.makes
    wipe(demand); wipe(toMake); wipe(buy); wipe(had)
    for _, craft in pairs(List()) do
        for item, per in pairs(craft.need) do
            demand[item] = (demand[item] or 0) + per * craft.count - (craft.got and craft.got[item] or 0)
        end
    end
    for item, qty in pairs(Have()) do had[item] = qty end
    -- What is left: made where cheaper, the crafts it takes going to made and their parts to
    -- what is needed, a level a pass; bought otherwise.
    for depth = 0, MAX_DEPTH do
        wipe(nextDemand)
        for item, qty in pairs(demand) do
            if qty > 0 then qty = qty - Supply(item, qty, had, toMake, depth) end
            if qty > 0 then
                local _, make = Cheapest(item, shopPlan, 0)
                local m, price, craft = makes[item], BuyPrice(item), shopPlan.craft[item]
                local crafts = m and math.ceil(qty / m.made)
                -- Whole crafts against what is needed: 3 bars bought can cost less than 2
                -- crafts of 2, though one bar made costs less than one bought.
                if make and price and craft and crafts * craft >= qty * price then make = false end
                if make and depth < MAX_DEPTH then
                    toMake[item] = (toMake[item] or 0) + crafts * m.made
                    shopPlan.planned[item] = true
                    if price and craft then shopPlan.saves[item] = (shopPlan.saves[item] or 0) + qty * price - crafts * craft end
                    for part, per in pairs(m.need) do
                        if Listed(part) then nextDemand[part] = (nextDemand[part] or 0) + per * crafts end
                    end
                else
                    buy[item] = (buy[item] or 0) + qty
                end
            end
        end
        demand, nextDemand = nextDemand, demand
        if next(demand) == nil then break end
    end
    local n = 0
    for item, qty in pairs(buy) do
        n = n + 1
        local m = materialPool[n] or {}
        materialPool[n] = m
        m.item, m.qty, m.name = item, qty, ItemName(item) or ""
        materialList[n] = m
    end
    for i = n + 1, #materialList do materialList[i] = nil end
    table.sort(materialList, ByName)
    return materialList, toMake, shopPlan
end

-- A material taken off the list (X at the auction house): as if you had it.
local function Drop(item, qty)
    local have = Have()
    have[item] = (have[item] or 0) + (qty or 0)
end

-- The classic recipes on a cooldown (Wowhead Classic): the transmutes but Elemental Fire, which
-- share one, and Mooncloth. A shared cooldown can read 0 on the spell itself.
local COOLDOWN_RECIPES = {
    [17187] = true,                                    -- Transmute: Arcanite, 2 days
    [11479] = true, [11480] = true,                    -- Iron to Gold, Mithril to Truesilver
    [17559] = true, [17560] = true, [17561] = true, [17562] = true,  -- the elemental transmutes,
    [17563] = true, [17564] = true, [17565] = true, [17566] = true,  -- 1 day
    [18560] = true,                                    -- Mooncloth, 4 days
}

-- A recipe with a cooldown: a known one, its spell's own, or one running now (a day cooldown
-- counts too); one seen running is remembered (`was`).
local function HasCooldown(recipeID, was)
    if was or COOLDOWN_RECIPES[recipeID] then return true end
    local base = GetSpellBaseCooldown and GetSpellBaseCooldown(recipeID)
    if base and base > 0 then return true end
    local ok, left, isDay = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
    return ok and ((left and left > 0) or isDay) and true or false
end

-- Records what this character's open profession makes, for Materials: only its own, never
-- another player's opened from a link, a guild's or an NPC's. Each recipe keeps its profession,
-- so one no longer known, or of a profession dropped since, is forgotten.
local function Learn()
    local api = ns.ProfWindowAPI
    if not (api and api.Own and C_TradeSkillUI.GetAllRecipeIDs) or not api.Own() then return end
    local makes = Makes()
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    local prof = base and base.professionID
    local seen = {}
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.learned then
            local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
            local output = ok and schematic and schematic.outputItemID
            if output and output > 0 then
                local need = {}
                local okR, reagents = pcall(api.Reagents, id)
                for _, r in ipairs(okR and reagents or {}) do need[r.itemID] = r.need end
                if next(need) then
                    local old = makes[output]
                    makes[output] = { recipe = id, made = math.max(1, schematic.quantityMin or 1), need = need,
                        cooldown = HasCooldown(id, old and old.recipe == id and old.cooldown), prof = prof }
                    seen[output] = true
                end
            end
        end
    end
    if not prof then return end
    -- The professions you have, by skill line; only trusted when the open one is among them.
    local mine = {}
    for _, index in pairs({ GetProfessions() }) do
        local line = select(7, GetProfessionInfo(index))
        if line then mine[line] = true end
    end
    for output, m in pairs(makes) do
        if (m.prof == prof and not seen[output]) or (mine[prof] and m.prof and not mine[m.prof]) then
            makes[output] = nil
        end
    end
end

-- "About 1g 20s at your last scan, 2h ago"; materials without a price are counted out.
local function Estimate(materials, unpriced)
    local est, missing = 0, 0
    for _, m in ipairs(materials) do
        local price = BuyPrice(m.item)
        if price then est = est + price * m.qty else missing = missing + 1 end
    end
    local at = ns.AuctionScanTime and ns.AuctionScanTime()
    return ("About %s at your last scan%s%s"):format(Money(est),
        at and (", " .. ns.AuctionAge(time() - at) .. " ago") or " (none yet)",
        missing > 0 and (", %d %s"):format(missing, unpriced) or "")
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
-- their order: the crafts on the list (each with - and + for how many, and X), every material
-- with an estimate from the last scan, and Clear. Add to List fills it at once, so it is plain
-- what it did.
local SIDE_W, SIDE_ROW_H, SIDE_CRAFTS, SIDE_MATERIALS, SIDE_MADE = 260, 20, 6, 12, 6
local side
local crafts, craftPool, madeList, madePool = {}, {}, {}, {}
local function ByCraftName(a, b) return (a.craft.name or "") < (b.craft.name or "") end

-- One craft more or fewer of a recipe on the list; never under one (X takes it off).
local function Step(recipeID, by)
    local craft = recipeID and List()[recipeID]
    if not craft then return end
    craft.count = math.max(1, math.min(999, craft.count + by))
    Trim()
    if Render then Render() end
end

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
    side.madeHead = ns.Font(side, 12, nil, { r = 1, g = 0.82, b = 0 })
    side.madeHead:SetText("Make First")
    side.crafts, side.materials, side.made = {}, {}, {}
    side.total = ns.Font(side, 12, nil)
    side.total:SetPoint("BOTTOMLEFT", 10, 16)
    side.total:SetPoint("RIGHT", -100, 0)
    side.total:SetJustifyH("LEFT")
    side.total:SetWordWrap(true)
    side.clear = ns.Button(side, "Clear", 80, 24, function()
        wipe(List())
        Trim()
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
    local list = List()
    local materials, made, plan = Materials()
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
                        Trim()
                        if Render then Render() end
                    end
                end)
                row.remove:SetPoint("RIGHT")
                ns.Tooltip(row.remove, "Remove", "Takes this craft and its materials off the list.")
                row.plus = ns.Button(row, "+", 16, 16, function() Step(row.recipeID, 1) end)
                row.plus:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
                ns.Tooltip(row.plus, "One More", "Adds the materials for one more craft.")
                row.minus = ns.Button(row, "-", 16, 16, function() Step(row.recipeID, -1) end)
                row.minus:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
                ns.Tooltip(row.minus, "One Fewer", "Takes the materials for one craft off the list.")
                row.note:SetPoint("RIGHT", row.minus, "LEFT", -6, 0)
            end
            row.minus:SetEnabled(e.craft.count > 1)
            row.minus:SetAlpha(e.craft.count > 1 and 1 or 0.45)
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
    for i = 1, math.max(#materials, #side.materials) do
        local m = materials[i]
        local row = (m or side.materials[i]) and SideRow(side.materials, i, true)
        if m and i <= SIDE_MATERIALS then
            local price = BuyPrice(m.item)
            -- Kept to buy, though making it would cost less: Make goes back to that.
            local make = false
            if Keep()[m.item] then make = select(2, Cheapest(m.item, plan, 0, true)) end
            if make and not row.make then
                row.make = ns.Button(row, "Make", 40, 16, function()
                    if row.item then
                        Keep()[row.item] = nil
                        if Render then Render() end
                    end
                end)
                row.make:SetPoint("RIGHT")
                ns.Tooltip(row.make, "Make It", "Buys its cheaper parts instead, to make it yourself.")
            end
            if row.make then row.make:SetShown(make and true or false) end
            row.note:ClearAllPoints()
            if make then row.note:SetPoint("RIGHT", row.make, "LEFT", -6, 0) else row.note:SetPoint("RIGHT") end
            row.item = m.item
            row.icon:SetTexture(C_Item.GetItemIconByID(m.item))
            row.name:SetText(("%dx %s"):format(m.qty, ItemName(m.item) or ("item " .. m.item)))
            row.note:SetText(price and ("~" .. Money(price * m.qty)) or "no price")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, y)
            row:Show()
            y = y - SIDE_ROW_H
        elseif row then
            row:Hide()
        end
    end
    -- What is made first, with what it saves on buying it.
    local makes = madeList
    n = 0
    for item, qty in pairs(made) do
        n = n + 1
        local e = madePool[n] or {}
        madePool[n] = e
        e.item, e.qty, e.name = item, qty, ItemName(item) or ""
        makes[n] = e
    end
    for i = n + 1, #makes do makes[i] = nil end
    table.sort(makes, ByName)
    side.madeHead:SetShown(#makes > 0)
    if #makes > 0 then
        y = y - 8
        side.madeHead:ClearAllPoints()
        side.madeHead:SetPoint("TOPLEFT", 10, y)
        y = y - 18
    end
    for i = 1, math.max(#makes, #side.made) do
        local e = makes[i]
        local row = (e or side.made[i]) and SideRow(side.made, i, true)
        if e and i <= SIDE_MADE then
            if not row.keep then
                row.keep = ns.Button(row, "Buy", 34, 16, function()
                    if row.item then
                        Keep()[row.item] = true
                        if Render then Render() end
                    end
                end)
                row.keep:SetPoint("RIGHT")
                ns.Tooltip(row.keep, "Buy It", "Buys it as it is instead of its parts.")
                row.note:SetPoint("RIGHT", row.keep, "LEFT", -6, 0)
            end
            -- Made from parts already bought, though the plan buys it now: nothing to switch.
            local planned = plan.planned[e.item]
            row.keep:SetShown(planned and true or false)
            row.note:SetPoint("RIGHT", planned and row.keep or row, planned and "LEFT" or "RIGHT", planned and -6 or 0, 0)
            local saves = plan.saves[e.item]
            row.item = e.item
            row.icon:SetTexture(C_Item.GetItemIconByID(e.item))
            row.name:SetText(("%dx %s"):format(e.qty, ItemName(e.item) or ("item " .. e.item)))
            if not planned then
                row.note:SetText("parts bought")
            else
                row.note:SetText(saves and ("saves ~" .. Money(saves)) or "no AH price")
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, y)
            row:Show()
            y = y - SIDE_ROW_H
        elseif row then
            row:Hide()
        end
    end
    side.total:SetText(#materials > 0 and Estimate(materials, "unpriced") or "")
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
                Drop(row.item, row.qty)
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
        Trim()
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
    local price = BuyPrice(m.item)
    return price and (Hex(T.muted) .. "~" .. Money(price * m.qty) .. "|r") or (Hex(T.muted) .. "no price|r")
end

local PROBLEMS = {
    noquote = "The auction house gave no final price.",
    unavailable = "The auction house has no price for it right now.",
    failed = "The purchase failed; the price may have changed.",
    unconfirmed = "No answer to the purchase yet; check your mail before trying again.",
}
local craftNames, madeNames = {}, {}

-- What the run says, and what its buttons do, for its state.
local function RunText(materials)
    local muted = Hex(T.muted)
    local state = run and run.state
    local e = Current()
    local name = e and (ItemName(e.item) or ("item " .. e.item))
    if not run then
        return Estimate(materials, "without a price") .. ".",
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
    local materials, made = Materials()
    if #materials == 0 and not run then return panel and panel:Hide() end
    if not panel then Build() end
    local shown = math.min(#materials, MAX_ROWS)
    for i, row in ipairs(panel.rows) do
        local m = materials[i]
        row.item, row.qty = m and m.item, m and m.qty
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
    local first = madeNames
    wipe(first)
    for item, qty in pairs(made) do first[#first + 1] = ("%dx %s"):format(qty, ItemName(item) or ("item " .. item)) end
    table.sort(first)
    panel.crafts:ClearAllPoints()
    panel.crafts:SetPoint("TOPLEFT", 10, y - 4)
    panel.crafts:SetText((#names > 0 and ("For " .. table.concat(names, ", ")) or "")
        .. (#first > 0 and (". Make first: " .. table.concat(first, ", ")) or ""))
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
local learnAt, learned = 0, nil
events:SetScript("OnEvent", function(_, event, a, b)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        if event == "TRADE_SKILL_SHOW" then learned = nil end
        -- Once the list settles: it updates in bursts as a profession opens.
        learnAt = GetTime()
        local at = learnAt
        return C_Timer.After(0.5, function()
            if learnAt == at and On() then
                -- Every craft fires an update too: learn again only when the recipes changed.
                local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
                local ids = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs()
                local key = (base and base.professionID or 0) .. ":" .. (ids and #ids or 0)
                if key ~= learned then
                    learned = key
                    Learn()
                end
                if Render then Render() end
            end
        end)
    elseif event == "AUCTION_HOUSE_SHOW" then
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
        -- Bought: off the list; less than it wanted (not enough listed), the rest stays on it.
        -- With everything bought, the list is done.
        Drop(e.item, e.buy)
        if #(Materials()) == 0 then
            wipe(List())
            Trim()
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
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do
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
