-------------------------------------------------------------------------------
--  NaowhForever_Professions.lua -- Naowh's profession window. Your recipes by category
--  on the left with the ones you have not learned below them, the chosen recipe in the
--  middle (reagents and craft buttons, or where to learn it), and Blizzard's own profession
--  tabs moved onto its edge. The overview tab shows every profession as a card instead.
--
--  Blizzard's own window stays open underneath at zero alpha: hiding it would close the
--  trade skill (its OnHide calls CloseTradeSkill) and take the recipe data with it. This
--  window covers it, one strata higher, so nothing of it can be clicked. Closing either
--  one closes the profession.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

-- The Professions module's settings, its own profile section. `enabled` is the sidebar
-- switch for the whole module; off leaves Blizzard's window alone.
local S = UI.ModuleSettings("professions", {
    enabled = true,
    -- Recipe Window: all off until switched on.
    recipeFinder = false, rankAlert = false, bagReagents = false, bankReagents = false,
    vendorMaterials = false,
    -- Gathering: all off until switched on.
    gatherReminder = false, gatherInInstances = false, gatherIconSize = 40, gatherFish = false,
    -- Buying and Selling: all off until switched on.
    ahSearch = false, ahShiftClick = false, craftProfit = false, craftProfitList = false,
    buyMaterials = false,
    filterMaterials = false, filterSkillUp = false, filterProfit = false,
})
ns.ProfessionSettings = S

local MIN_H, PAD = 620, 8
-- The list is wide enough for a recipe name, its count and a full profit ("-12g 07s 09c").
local LEFT_W, MID_W = 340, 400
local MID_X = PAD + LEFT_W + PAD
local W = MID_X + MID_W + PAD
local TOP_Y = -68
-- The next-rank banner sits under the skill bar and pushes both columns down while shown.
local BANNER_Y, BANNER_H, BANNER_SHIFT = -64, 40, 46
local ROW_H, REAGENT_H, MAX_REAGENTS = 20, 36, 8
local FILTER_W = 76   -- the Filter button beside the search box, room for "Filter (3)"
local BUY_ROW_W = 22 + 2 + 40 + 2 + 22 + 12 + 90   -- -, count, +, Buy: as the Create row
local REAGENT_COL_W = 52
local SCROLL_W = 6
local MAX_PARAS, MAX_LINES = 3, 7
local PRIMARY_H, CARD_GAP = 128, 8
-- Blizzard's book cards, in the order this window's cards are laid out.
local BOOK_ORDER = { "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
    "SecondaryProfession2", "SecondaryProfession3" }
local SECONDARY_NAMES = { PROFESSIONS_COOKING or "Cooking", PROFESSIONS_FISHING or "Fishing",
    PROFESSIONS_FIRST_AID or "First Aid" }
local GOLD = { r = 1, g = 0.82, b = 0 }
local RED = { r = 1, g = 0.3, b = 0.3 }
local VENDOR_ORANGE = { r = 1, g = 0.6, b = 0.2 }
local VENDOR_ICON = "|TInterface\\GossipFrame\\VendorGossipIcon:14:14|t"
-- Enum.TradeskillRelativeDifficulty: Optimal, Medium, Easy, Trivial.
local DIFFICULTY = {
    [0] = { r = 1, g = 0.5, b = 0.25 },
    [1] = { r = 1, g = 1, b = 0 },
    [2] = { r = 0.25, g = 0.75, b = 0.25 },
    [3] = { r = 0.55, g = 0.55, b = 0.55 },
}
local TRIVIAL = 3   -- grey: no more skill from it
-- NaowhUI's look, as on the XP bar: 1px black borders, and blue bars filled with Naowh's blue
-- deepening to the left.
local BLACK = { r = 0, g = 0, b = 0 }
local BAR_FROM = CreateColor(0x00 / 255, 0x4f / 255, 0x85 / 255, 1)
local function StyleBar(bar)
    -- The dark end follows a changed accent; the shipped blue stays as it was otherwise.
    local shifted = ns.ThemeTint("accent", nil)
    local from = shifted and CreateColor(shifted.r * 0.55, shifted.g * 0.55, shifted.b * 0.55, 1) or BAR_FROM
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetGradient("HORIZONTAL", from, CreateColor(T.accent.r, T.accent.g, T.accent.b, 1))
    ns.Border(bar, BLACK)
end
local Button, EditBox = ns.Button, ns.NewEditBox
-- A flat checkbox to match: a dark square with the black border, Naowh's blue square inside
-- when checked, the border lit blue on hover. A real CheckButton, so GetChecked, SetChecked and
-- OnClick work as with Blizzard's; add tooltips with HookScript to keep the hover.
local CHECK_SIZE = 14
local function CheckBox(parent)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(CHECK_SIZE, CHECK_SIZE)
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    local border = ns.Border(box, BLACK)
    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
    box:SetCheckedTexture(mark)
    box:SetScript("OnEnter", function() border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
    box:SetScript("OnLeave", function() border:SetColor(0, 0, 0, 1) end)
    return box
end
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
-- Mining's crafting window opens with Smelting, not a spell named after the profession.
local SMELTING = 2656

local win, hooked
local categories, entries, rows, unlearned = {}, {}, {}, {}
local collapsed = {}
local selectedID, offset, query = nil, 0, ""
-- An unlearned recipe (a RecipeData row) when one is chosen; it takes over the middle column.
local selectedUnlearned
-- The two top-level sections; `key` is where a header remembers being opened or closed, and
-- `sub` headers sit indented beneath one.
local LEARNED = { name = "Learned", key = "profLearnedCollapsed", closed = false }
local UNLEARNED = { name = "Unlearned", key = "profUnlearnedCollapsed", closed = false }
-- The unlearned recipes split by what stands between you and them; only the ones you can learn
-- now start open.
local UNLEARNED_GROUPS = {
    { status = "ready", name = "Learnable now", key = "profUnlearnedReadyCollapsed", closed = false, sub = true },
    { status = "later", name = "Needs more skill", key = "profUnlearnedLaterCollapsed", closed = true, sub = true },
    { status = "rank", name = "Needs next rank", key = "profUnlearnedRankCollapsed", closed = true, sub = true },
}

local function On()
    return S.Get("enabled")
end

-- Set when another player's profession link is clicked in chat. Opened from a closed window,
-- a link does not always read as linked yet, so the window took it for your own.
local viewingLink, linkClicked

local function Own()
    if viewingLink then return false end
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then return false end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return false end
    return true
end

local function Profession()
    local child, base = C_TradeSkillUI.GetChildProfessionInfo(), C_TradeSkillUI.GetBaseProfessionInfo()
    local src = (child and (child.maxSkillLevel or 0) > 0) and child or base
    if not src then return end
    return {
        id = base and base.professionID or src.professionID,
        name = (base and base.professionName) or src.professionName or "",
        skill = src.skillLevel or 0,
        max = src.maxSkillLevel or 0,
    }
end

local function NextStrata(strata)
    for i, s in ipairs(STRATA) do
        if s == strata then return STRATA[math.min(i + 1, #STRATA)] end
    end
    return "HIGH"
end

local function SetColor(fs, c)
    fs:SetTextColor(c.r, c.g, c.b, 1)
end

-- ns.Button has no disabled look of its own, so a disabled one is dimmed.
local function EnableButton(button, on)
    button:SetEnabled(on)
    button:SetAlpha(on and 1 or 0.45)
end

-------------------------------------------------------------------------------
--  Recipes
-------------------------------------------------------------------------------
local function Collect()
    wipe(categories)
    local byID = {}
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.learned then
            local catID = info.categoryID or 0
            local cat = byID[catID]
            if not cat then
                local ci = catID > 0 and C_TradeSkillUI.GetCategoryInfo(catID)
                cat = { id = catID, name = ci and ci.name or OTHER or "Other", order = ci and ci.uiOrder or 999,
                    recipes = {}, sub = true }
                byID[catID] = cat
                categories[#categories + 1] = cat
            end
            cat.recipes[#cat.recipes + 1] = info
        end
    end
    table.sort(categories, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    unlearned = ns.RecipeFinder and ns.RecipeFinder.Unlearned() or {}
end

local function GroupClosed(group)
    local v = S.Get(group.key)
    if v == nil then return group.closed end
    return v
end

local function IsCollapsed(cat)
    if query ~= "" then return false end
    if cat.key then return GroupClosed(cat) end
    return collapsed[cat.name]
end

local function ToggleCollapsed(cat)
    if cat.key then
        S.Set(cat.key, not GroupClosed(cat))
    else
        collapsed[cat.name] = not collapsed[cat.name] or nil
    end
end

local function Matches(info)
    return query == "" or (info.name and info.name:lower():find(query, 1, true) ~= nil)
end

-- The Filter menu's test for a learned recipe (`info`) or an unlearned one (`r`). Set further
-- down, once the craft counts and the profit it reads exist.
local PassesFilter
-- Whether Buy Materials has anything to buy for a recipe, and resetting its craft count; both
-- set in the Buy Materials section.
local HasBuyableMaterials, ResetBuyCount

local function BuildEntries()
    wipe(entries)
    local first, found
    local learnedAt, learnedCount = #entries + 1, 0
    entries[learnedAt] = { cat = LEARNED }
    local learnedOpen = not IsCollapsed(LEARNED)
    for _, cat in ipairs(categories) do
        local shown = {}
        for _, info in ipairs(cat.recipes) do
            if Matches(info) and PassesFilter(info) then shown[#shown + 1] = info end
        end
        if #shown > 0 then
            learnedCount = learnedCount + #shown
            if learnedOpen then entries[#entries + 1] = { cat = cat } end
            -- A search opens every category, so a match is never hidden in a closed one.
            local open = learnedOpen and not IsCollapsed(cat)
            for _, info in ipairs(shown) do
                first = first or info.recipeID
                if info.recipeID == selectedID then found = true end
                if open then entries[#entries + 1] = { recipe = info } end
            end
        end
    end
    LEARNED.count = learnedCount
    if learnedCount == 0 then table.remove(entries, learnedAt) end

    local shownU, foundU = {}, false
    for _, r in ipairs(unlearned) do
        local name = C_Spell.GetSpellName(r.spell) or ""
        if (query == "" or name:lower():find(query, 1, true)) and PassesFilter(nil, r) then
            shownU[#shownU + 1] = r
        end
    end
    if #shownU > 0 then
        UNLEARNED.count = #shownU
        entries[#entries + 1] = { cat = UNLEARNED }
        local open = not IsCollapsed(UNLEARNED)
        for _, group in ipairs(UNLEARNED_GROUPS) do
            local inGroup = {}
            for _, r in ipairs(shownU) do
                if ns.RecipeFinder.Status(r) == group.status then inGroup[#inGroup + 1] = r end
            end
            group.count = #inGroup
            if open and #inGroup > 0 then entries[#entries + 1] = { cat = group } end
            local groupOpen = open and not IsCollapsed(group)
            for _, r in ipairs(inGroup) do
                if r == selectedUnlearned then foundU = true end
                if groupOpen then entries[#entries + 1] = { unlearned = r } end
            end
        end
    end

    if not foundU then selectedUnlearned = nil end
    if not found then selectedID = first end
end

local function SelectedInfo()
    return not selectedUnlearned and selectedID and C_TradeSkillUI.GetRecipeInfo(selectedID)
end

-- itemID and quantity per reagent. The schematic call is the current API; the reagent-info
-- pair is the older one, kept as a fallback in case Forever still answers only that.
local function Reagents(recipeID)
    local out = {}
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if ok and schematic and schematic.reagentSlotSchematics then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local reagent = slot.reagents and slot.reagents[1]
            if slot.required ~= false and reagent and reagent.itemID then
                out[#out + 1] = { itemID = reagent.itemID, need = slot.quantityRequired or 1 }
            end
        end
        return out
    end
    if C_TradeSkillUI.GetRecipeNumReagents then
        for i = 1, C_TradeSkillUI.GetRecipeNumReagents(recipeID) or 0 do
            local _, _, need = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, i)
            local link = C_TradeSkillUI.GetRecipeReagentItemLink(recipeID, i)
            local itemID = link and C_Item.GetItemInfoInstant(link)
            if itemID then out[#out + 1] = { itemID = itemID, need = need or 1 } end
        end
    end
    return out
end

-- The item a recipe makes and how many of it one craft makes at least, or nil for a recipe
-- that makes none, such as an enchant.
-- A recipe's output never changes, so it is read once; false for one that makes no item.
local outputCache = {}
local function OutputItem(recipeID)
    local cached = outputCache[recipeID]
    if cached ~= nil then
        if cached then return cached[1], cached[2] end
        return
    end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    local id = ok and schematic and schematic.outputItemID
    if id and id > 0 then
        outputCache[recipeID] = { id, math.max(1, schematic.quantityMin or 1) }
        return outputCache[recipeID][1], outputCache[recipeID][2]
    end
    local okData, data = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
    id = okData and type(data) == "table" and data.itemID
    if id and id > 0 then
        outputCache[recipeID] = { id, 1 }
        return id, 1
    end
    -- Only a schematic that loaded and makes nothing is final; a failed read is tried again.
    if ok and schematic then outputCache[recipeID] = false end
end

local function AuctionHouseOpen()
    local ah = _G.AuctionHouseFrame
    return ah and ah:IsShown() and ah.SearchBar ~= nil
end

-- An item's name, or nil while the client has yet to load it; ITEM_DATA_LOAD_RESULT then
-- redraws the window.
local function ItemName(itemID)
    local name = itemID and C_Item.GetItemNameByID(itemID)
    if itemID and not name then C_Item.RequestLoadItemDataByID(itemID) end
    return name
end

-- Shows a search button for a name while the auction house is open, and keeps a name beside
-- it from running under the button.
local function ShowSearch(button, name, nameText, parent)
    button.itemName = S.Get("ahSearch") and AuctionHouseOpen() and name or nil
    button:SetShown(button.itemName ~= nil)
    if nameText then
        if button:IsShown() then
            nameText:SetPoint("RIGHT", button, "LEFT", -8, 0)
        else
            nameText:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
        end
    end
end

-- Types a name into the auction house search on its Buy tab and runs the search.
local function SearchAuctionHouse(name)
    if not (name and AuctionHouseOpen()) then return end
    local ah = _G.AuctionHouseFrame
    if ah.SetDisplayMode and _G.AuctionHouseFrameDisplayMode then
        pcall(ah.SetDisplayMode, ah, _G.AuctionHouseFrameDisplayMode.Buy)
    end
    ah.SearchBar:SetSearchText(name)
    ah.SearchBar:StartSearch()
end

-- True while the cursor is in a chat box. The active chat window alone does not say it:
-- with some chat settings there always is one, typing or not.
local function TypingInChat()
    local box = ChatFrameUtil.GetActiveWindow()
    return box ~= nil and box:HasFocus()
end

-- Shift-click on an item: with the auction house open and Shift-Click Searches AH on, it
-- searches the auction house for it; while you type in chat, or otherwise, it links it in
-- chat, through ChatFrameUtil (the ChatEdit_ names are deprecated). itemID may be nil (a
-- recipe that makes no item), which just links.
local function ShiftClick(itemID, link)
    if S.Get("ahShiftClick") and AuctionHouseOpen() and not TypingInChat() then
        local name = ItemName(itemID)
        if name then return SearchAuctionHouse(name) end
    end
    if link then ChatFrameUtil.InsertLink(link) end
end

local function ItemCount(itemID)
    return C_Item.GetItemCount(itemID, false, false, true) or 0
end

local function BankCount(itemID)
    return math.max(0, (C_Item.GetItemCount(itemID, true, false, true) or 0) - ItemCount(itemID))
end

-- How many you can make from your bags. Forever answers numAvailable with 0, so it is worked
-- out from the reagents when the game gives nothing.
local function Craftable(info)
    if (info.numAvailable or 0) > 0 then return info.numAvailable end
    local reagents = Reagents(info.recipeID)
    if #reagents == 0 then return 0 end
    local n = math.huge
    for _, r in ipairs(reagents) do
        n = math.min(n, math.floor(ItemCount(r.itemID) / math.max(r.need, 1)))
    end
    return n
end

-- Reagents trade-goods vendors sell for gold, without limit. Merchants you visit add to this
-- (account-wide), so anything missing here is picked up the first time you see it sold.
local VENDOR_REAGENTS = {
    [2880] = true, [3466] = true, -- Weak Flux, Strong Flux
    [2320] = true, [2321] = true, [4291] = true, [8343] = true, [14341] = true, -- threads
    [3371] = true, [3372] = true, [8925] = true, [18256] = true, -- vials
    [4289] = true, [2678] = true, [2692] = true, [3713] = true, [2665] = true, -- salt, spices
    [159] = true, [1179] = true, -- Refreshing Spring Water, Ice Cold Milk
    [6217] = true, [3857] = true, [4470] = true, [4399] = true, [4400] = true, -- rod, coal, wood, stocks
    [2324] = true, [2325] = true, [2604] = true, [6260] = true, [6261] = true, -- bleach, dyes
    [4340] = true, [4341] = true, [4342] = true, [10290] = true,
}

local function LearnedVendorItems()
    local account = ns.AccountSettings()
    account.profVendorItems = account.profVendorItems or {}
    return account.profVendorItems
end

local function IsVendorItem(itemID)
    return VENDOR_REAGENTS[itemID] or LearnedVendorItems()[itemID] or false
end

-- What one of a reagent costs at a vendor, per item, as last seen at a merchant (account-wide).
local function VendorPrices()
    local account = ns.AccountSettings()
    account.profVendorPrices = account.profVendorPrices or {}
    return account.profVendorPrices
end

-------------------------------------------------------------------------------
--  Crafting profit
-------------------------------------------------------------------------------
local AH_CUT = 0.05   -- the auction house keeps 5% of a sale
local PROFIT_GREEN = { r = 0.3, g = 0.82, b = 0.48 }
-- The profit block: three lines, the amounts starting past the widest label.
-- The label-to-amount gap; RenderProfit sizes the columns to what they hold, from the
-- starting widths here.
local PROFIT_LINE, PROFIT_LABEL_W, PROFIT_VALUE_W, PROFIT_GAP = 16, 58, 96, 8
local PROFIT_H = 3 * PROFIT_LINE

-- One of an item bought at its cheapest: a vendor's price when one was seen selling it, else
-- the lowest buyout at the last scan. Nil when neither is known.
local function BuyPrice(itemID)
    local vendor = VendorPrices()[itemID]
    local ah = ns.AuctionPrice and ns.AuctionPrice(itemID)
    if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
    if ah then return ah, "ah" end
end

-- Crafting profit is on and this realm and faction's auction house has been scanned.
local function ProfitShown()
    return S.Get("craftProfit") and ns.AuctionScanTime and ns.AuctionScanTime() ~= nil
end

-- Reagents unchecked in the recipe pane: ones you already have, left out of every recipe's
-- cost until checked again.
local function Owned()
    local db = S.DB()
    if type(db.craftOwned) ~= "table" then db.craftOwned = {} end
    return db.craftOwned
end

-- What one craft costs in bought reagents and fetches on the auction house after its cut.
-- `sale` is nil when the item had no listing at the last scan, or makes no item at all.
local function CraftValue(recipeID, output, made)
    local v = { cost = 0, missing = 0, owned = 0, parts = {}, output = output, made = made or 1 }
    local ok, reagents = pcall(Reagents, recipeID)
    local owned = Owned()
    for _, r in ipairs(ok and reagents or {}) do
        local each, from = BuyPrice(r.itemID)
        local have = owned[r.itemID] == true
        v.parts[#v.parts + 1] = { itemID = r.itemID, need = r.need, each = each, from = from, owned = have }
        if have then
            v.owned = v.owned + 1
        elseif each then
            v.cost = v.cost + each * r.need
        else
            v.missing = v.missing + 1
        end
    end
    local each = output and ns.AuctionPrice and ns.AuctionPrice(output)
    v.each = each
    v.sale = each and math.floor(each * v.made * (1 - AH_CUT))
    return v
end

-- "12g 07s 09c", "6s 00c", "8c": from the largest coin down to copper, the smaller coins two
-- digits wide so amounts line up. Plain text: the letters take the amount's own colour.
local COINS = { { 10000, "g" }, { 100, "s" }, { 1, "c" } }
local function Money(copper)
    local left = math.floor(math.abs(copper) + 0.5)
    local parts = {}
    for _, coin in ipairs(COINS) do
        local n = math.floor(left / coin[1])
        left = left - n * coin[1]
        if #parts > 0 then
            parts[#parts + 1] = ("%02d"):format(n) .. coin[2]
        elseif n > 0 or coin[1] == 1 then
            parts[#parts + 1] = n .. coin[2]
        end
    end
    local text = table.concat(parts, " ")
    return copper < 0 and ("-" .. text) or text
end

-- How many you could make buying the vendor reagents: only the others limit it. Nil when
-- every reagent comes from a vendor, as the number would mean nothing.
local function CraftableWithVendor(info)
    local n
    for _, r in ipairs(Reagents(info.recipeID)) do
        if not IsVendorItem(r.itemID) then
            local can = math.floor(ItemCount(r.itemID) / math.max(r.need, 1))
            n = n and math.min(n, can) or can
        end
    end
    return n
end

local function Craft(count)
    local info = SelectedInfo()
    if not info or count < 1 then return end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, info.recipeID, count)
    if not ok then ns.Print("Could not craft: " .. tostring(err)) end
end

local function Hex(c)
    return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

-- "3" from your bags; with the vendor option on, "3 | 6", the second in orange, when buying
-- the vendor reagents would let you make more, or just the orange "6" when you can make none.
local function FormatCraftCount(info)
    local have = Craftable(info)
    local plain = have > 0 and tostring(have) or ""
    if not S.Get("vendorMaterials") then return plain end
    local withVendor = CraftableWithVendor(info)
    if not withVendor or withVendor <= have then return plain end
    local orange = Hex(VENDOR_ORANGE) .. withVendor .. "|r"
    if have == 0 then return orange end
    return plain .. " | " .. orange
end

-- One craft's profit in copper, or nil when it is not known: crafting profit off, no scan, a
-- reagent without a price, or an item that was not listed.
-- Cached per recipe until the next full render, so scrolling and the filter do not price
-- every recipe again; false for one whose profit is not known.
local profitCache = {}
local function RecipeProfit(recipeID, output, made)
    if not (output and ProfitShown()) then return end
    local profit = profitCache[recipeID]
    if profit == nil then
        local v = CraftValue(recipeID, output, made)
        profit = v.sale and v.missing == 0 and #v.parts > 0 and v.sale - v.cost or false
        profitCache[recipeID] = profit
    end
    return profit or nil
end

-- A recipe's profit for its row in the list and the colour for it: "" when it is off or not
-- known (no scan, a reagent without a price, or an item that was not listed). The row's font
-- takes the colour, green or red.
local function ListProfit(recipeID, output, made)
    local profit = S.Get("craftProfitList") and RecipeProfit(recipeID, output, made)
    if not profit then return "", T.fg end
    return (profit >= 0 and "+" or "") .. Money(profit), profit >= 0 and PROFIT_GREEN or RED
end

-------------------------------------------------------------------------------
--  Filter
-------------------------------------------------------------------------------
-- The Filter menu, as in Blizzard's window, plus Profitable. Have Materials and Has Skill-Up
-- concern the recipes you know; an unlearned recipe cannot be made, so Have Materials hides
-- those too.
local FILTERS = {
    { key = "filterMaterials", text = "Have Materials" },
    { key = "filterSkillUp", text = "Has Skill-Up" },
    { key = "filterProfit", text = "Profitable", profit = true },
}

-- Profitable only counts while there are prices to judge by.
local function FilterOn(f)
    return S.Get(f.key) and (not f.profit or ProfitShown())
end

PassesFilter = function(info, r)
    if info then
        if FilterOn(FILTERS[1]) and Craftable(info) == 0 then return false end
        if FilterOn(FILTERS[2]) and info.relativeDifficulty == TRIVIAL then return false end
        if FilterOn(FILTERS[3]) then
            local profit = RecipeProfit(info.recipeID, OutputItem(info.recipeID))
            if not (profit and profit > 0) then return false end
        end
        return true
    end
    if FilterOn(FILTERS[1]) then return false end
    if FilterOn(FILTERS[3]) then
        local read, made = OutputItem(r.spell)
        local profit = RecipeProfit(r.spell, r.item or read, made)
        if not (profit and profit > 0) then return false end
    end
    return true
end

local function ActiveFilters()
    local n = 0
    for _, f in ipairs(FILTERS) do
        if FilterOn(f) then n = n + 1 end
    end
    return n
end

local function UpdateFilterLabel()
    if not (win and win.filter) then return end
    local n = ActiveFilters()
    ns.SetButtonText(win.filter, n > 0 and ("Filter (%d)"):format(n) or "Filter")
end

-- One line of the profit block: its label, the amount, and a muted note after it. Hidden when
-- `value` is nil.
local function SetProfitLine(line, label, value, note)
    line.label:SetText(label or "")
    line.value:SetText(value or "")
    line.note:SetText(note or "")
    line:SetShown(value ~= nil)
end

-- Three lines under a recipe: what its reagents cost to buy, what it sells for, and the
-- profit. Hidden until the auction house has been scanned on this realm and faction.
local function RenderProfit(block, recipeID, output, made)
    if not (S.Get("craftProfit") and ns.AuctionScanTime and ns.AuctionScanTime()) then
        block.value = nil
        return block:Hide()
    end
    local v = CraftValue(recipeID, output, made)
    block.value = v
    if #v.parts == 0 then
        block.value = nil
        return block:Hide()
    end
    local none = Hex(T.muted) .. "-|r"
    SetProfitLine(block.buy, "Buy for:", Money(v.cost),
        v.missing > 0 and ("+ %d unpriced"):format(v.missing) or nil)
    local sell, sellNote, profit, profitNote
    if output then
        sell = v.each and Money(v.each * v.made) or none
        sellNote = not v.each and "not listed at the last scan"
            or v.made > 1 and ("for %d"):format(v.made) or nil
        if not v.sale then
            profit = none
        elseif v.missing > 0 then
            profit, profitNote = none, "some reagents have no price"
        else
            local p = v.sale - v.cost
            profit = Hex(p >= 0 and PROFIT_GREEN or RED) .. (p >= 0 and "+" or "") .. Money(p) .. "|r"
            profitNote = "after the 5% cut"
        end
    end
    SetProfitLine(block.sell, "Sell for:", sell, sellNote)
    SetProfitLine(block.profit, "Profit:", profit, profitNote)
    -- The columns fit what they hold: the amounts end together right after the longest label,
    -- as wide as the longest amount, with the notes straight after.
    local labelW, valueW = 0, 0
    for _, line in ipairs({ block.buy, block.sell, block.profit }) do
        if line:IsShown() then
            labelW = math.max(labelW, line.label:GetStringWidth())
            valueW = math.max(valueW, line.value:GetStringWidth())
        end
    end
    for _, line in ipairs({ block.buy, block.sell, block.profit }) do
        line.value:ClearAllPoints()
        line.value:SetPoint("LEFT", math.ceil(labelW) + PROFIT_GAP, 0)
        line.value:SetWidth(math.ceil(valueW) + 1)
    end
    block:Show()
end

-------------------------------------------------------------------------------
--  Rendering
-------------------------------------------------------------------------------
local Render, RenderList, RenderDetail, RenderLearn

-- The counts and skills fill a column at the left of the rows, as wide as the widest one on
-- screen and right-aligned in it, so every icon and name starts at the same place. The icons
-- never start left of ICON_X, keeping recipes indented under their headers.
local COUNT_X, COUNT_GAP, ICON_X = 4, 6, 24
local function AlignRows(visible)
    local width = 0
    for i = 1, visible do
        local row, e = rows[i], entries[i + offset]
        if row and e and not e.cat then width = math.max(width, row.count:GetStringWidth()) end
    end
    local iconX = math.max(ICON_X, width > 0 and COUNT_X + width + COUNT_GAP or 0)
    for i = 1, visible do
        local row, e = rows[i], entries[i + offset]
        if row and e and not e.cat then
            row.count:ClearAllPoints()
            row.count:SetPoint("RIGHT", row, "LEFT", iconX - COUNT_GAP, 0)
            row.icon:SetPoint("LEFT", iconX, 0)
        end
    end
end

local function VisibleRows()
    return math.max(1, math.floor((win.list:GetHeight()) / ROW_H))
end

RenderList = function()
    local visible = VisibleRows()
    offset = math.min(offset, math.max(0, #entries - visible))
    for i = 1, visible do
        local row = rows[i]
        local e = entries[i + offset]
        if e then
            if not row then
                row = win.BuildRow(i)
                rows[i] = row
            end
            row.entry = e
            row.icon:ClearAllPoints()
            if e.cat then
                local label = e.cat.count and ("%s (%d)"):format(e.cat.name, e.cat.count) or e.cat.name
                row.text:SetText((IsCollapsed(e.cat) and "+  " or "-  ") .. label)
                SetColor(row.text, GOLD)
                row.text:SetPoint("LEFT", e.cat.sub and 14 or 4, 0)
                row.count:SetText("")
                row.profit:SetText("")
                row.icon:Hide()
                row.head:Show()
                row.sel:Hide()
            elseif e.unlearned then
                local r = e.unlearned
                local c = ns.RecipeFinder.Color(r)
                row.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
                row.icon:Show()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetText(C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell))
                SetColor(row.text, c)
                row.count:SetText(ns.RecipeFinder.Skill(r))
                SetColor(row.count, c)
                local read, made = OutputItem(r.spell)
                local profit, color = ListProfit(r.spell, r.item or read, made)
                row.profit:SetText(profit)
                SetColor(row.profit, color)
                row.head:Hide()
                row.sel:SetShown(r == selectedUnlearned)
            else
                local info = e.recipe
                SetColor(row.count, T.fg)
                row.icon:SetTexture(info.icon)
                row.icon:Show()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetText(info.name)
                SetColor(row.text, DIFFICULTY[info.relativeDifficulty] or T.fg)
                row.count:SetText(FormatCraftCount(info))
                local profit, color = ListProfit(info.recipeID, OutputItem(info.recipeID))
                row.profit:SetText(profit)
                SetColor(row.profit, color)
                row.head:Hide()
                row.sel:SetShown(not selectedUnlearned and info.recipeID == selectedID)
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
    AlignRows(visible)

    -- The scrollbar follows the list; hidden when everything fits.
    local bar, maxOffset = win.scroll, math.max(0, #entries - visible)
    if not bar then return end
    bar:SetShown(maxOffset > 0)
    if maxOffset > 0 then
        bar.thumb:SetHeight(math.max(20, bar:GetHeight() * visible / #entries))
        bar.syncing = true
        bar:SetMinMaxValues(0, maxOffset)
        bar:SetValue(offset)
        bar.syncing = nil
    end
end

-- Fills up to `max` reagent rows. With `target`, each vendor reagent says how many to buy to make
-- that many.
local function FillReagents(rows, reagents, target, max)
    local showBags, showBank = S.Get("bagReagents"), S.Get("bankReagents")
    local cols = (showBags and 1 or 0) + (showBank and 1 or 0)
    -- The checkboxes decide what the profit counts and what Buy Materials buys.
    local checks = ProfitShown() or (S.Get("buyMaterials") and AuctionHouseOpen())
    local owned = Owned()
    for i, r in ipairs(rows) do
        local data = i <= max and reagents[i]
        if data then
            local name = C_Item.GetItemNameByID(data.itemID)
            if not name then C_Item.RequestLoadItemDataByID(data.itemID) end
            local have = ItemCount(data.itemID)
            r.itemID = data.itemID
            r.icon:SetTexture(C_Item.GetItemIconByID(data.itemID))
            -- Checked: bought, counted in the cost. Unchecked: you have it.
            r.check:SetShown(checks)
            r.check:SetChecked(not owned[data.itemID])
            r.icon:ClearAllPoints()
            if checks then
                r.icon:SetPoint("LEFT", r.check, "RIGHT", 6, 0)
            else
                r.icon:SetPoint("LEFT")
            end
            r.icon:SetDesaturated(checks and owned[data.itemID] == true)
            local buy = target and IsVendorItem(data.itemID) and target * data.need - have or 0
            r.count:SetText(("%d/%d"):format(have, data.need)
                .. (buy > 0 and ("   %sbuy %d more|r"):format(Hex(VENDOR_ORANGE), buy) or ""))
            SetColor(r.count, have >= data.need and T.fg or RED)
            r.bagsLabel:SetShown(showBags)
            r.bags:SetShown(showBags)
            r.bankLabel:SetShown(showBank)
            r.bank:SetShown(showBank)
            r.bagsLabel:ClearAllPoints()
            r.bagsLabel:SetPoint("TOPRIGHT", showBank and -REAGENT_COL_W or 0, -2)
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -2)
            r.name:SetPoint("RIGHT", -cols * REAGENT_COL_W - 6, 0)
            if showBags then
                r.bags:SetText(have)
                SetColor(r.bags, have > 0 and T.fg or T.muted)
            end
            if showBank then
                local bank = BankCount(data.itemID)
                r.bank:SetText(bank)
                SetColor(r.bank, bank > 0 and T.accent or T.muted)
            end
            r.vendor = IsVendorItem(data.itemID)
            r.name:SetText((name or "") .. (r.vendor and "  " .. VENDOR_ICON or ""))
            r:Show()
        else
            r:Hide()
        end
    end
end

RenderLearn = function(r)
    local l = win.learn
    l.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
    l.name:SetText(C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell))
    SetColor(l.name, ns.RecipeFinder.Color(r))
    l.req:SetText(ns.RecipeFinder.Requirement(r))
    -- The item it makes (read from the recipe when the data has none), and the recipe itself
    -- when one is sold or dropped; trainer recipes have none.
    local read, made = OutputItem(r.spell)
    local output = r.item or read
    ShowSearch(l.search, output and (ItemName(output) or C_Spell.GetSpellName(r.spell)))
    RenderProfit(l.profit, r.spell, output, made)
    ShowSearch(l.searchRecipe, ItemName(r.recipe))
    l.searchRecipe:ClearAllPoints()
    if l.search:IsShown() then
        l.searchRecipe:SetPoint("TOPRIGHT", l.search, "BOTTOMRIGHT", 0, -4)
    else
        l.searchRecipe:SetPoint("TOPRIGHT", l, "TOPRIGHT", -12, -14)
    end
    local beside = (l.search:IsShown() and l.search) or (l.searchRecipe:IsShown() and l.searchRecipe)
    if beside then
        l.name:SetPoint("TOPRIGHT", beside, "TOPLEFT", -8, 0)
    else
        l.name:SetPoint("TOPRIGHT", l, "TOPRIGHT", -12, -16)
    end
    -- The requirement starts at x 68 (past the icon); with both buttons stacked, Search Recipe
    -- sits beside it, so it stops short of that and wraps.
    local stacked = l.search:IsShown() and l.searchRecipe:IsShown()
    l.req:SetWidth(MID_W - 80 - (stacked and l.searchRecipe:GetWidth() + 8 or 0))
    for _, fs in ipairs(l.paras) do fs:Hide() end
    for _, line in ipairs(l.lines) do line:Hide() end
    local y, nPara, nLine = -72, 0, 0
    for _, entry in ipairs(ns.RecipeFinder.Describe(r)) do
        if entry.para then
            nPara = nPara + 1
            local fs = l.paras[nPara]
            if not fs then break end
            if nPara > 1 then y = y - 8 end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 14, y)
            fs:SetText(entry.text)
            fs:Show()
            y = y - fs:GetStringHeight() - 6
        else
            nLine = nLine + 1
            local line = l.lines[nLine]
            if not line then break end
            line.npc = entry.npc
            line.text:SetText(entry.text)
            SetColor(line.text, entry.npc and T.accent or T.fg)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 20, y)
            line:Show()
            y = y - 18
        end
    end

    -- What it will take to craft, when the game knows the recipe's reagents before you learn it.
    local ok, reagents = pcall(Reagents, r.spell)
    if not ok then reagents = {} end
    local height = l:GetHeight() > 0 and l:GetHeight() or (MIN_H + TOP_Y - PAD)
    -- Room is left at the bottom for the crafting profit lines and the waypoint hint under them.
    local fit = math.floor((height + y - 14 - (PROFIT_H + 36)) / REAGENT_H)
    l.reagentsLabel:SetShown(#reagents > 0 and fit > 0)
    l.reagentsLabel:ClearAllPoints()
    l.reagentsLabel:SetPoint("TOPLEFT", 14, y - 14)
    FillReagents(l.reagents, reagents, nil, math.max(0, fit))
end

RenderDetail = function()
    local d = win.detail
    if selectedUnlearned then
        d:Hide()
        win.empty:Hide()
        win.learn:Show()
        return RenderLearn(selectedUnlearned)
    end
    win.learn:Hide()
    local info = SelectedInfo()
    d:SetShown(info ~= nil)
    win.empty:SetShown(info == nil)
    if not info then return end

    d.icon:SetTexture(info.icon)
    d.name:SetText(info.name)
    SetColor(d.name, DIFFICULTY[info.relativeDifficulty] or T.fg)
    local output, made = OutputItem(info.recipeID)
    ShowSearch(d.search, output and (ItemName(output) or info.name), d.name, d)
    RenderProfit(d.profit, info.recipeID, output, made)

    local ok, desc = pcall(C_TradeSkillUI.GetRecipeDescription, info.recipeID, {})
    local lines = { ok and desc or "" }
    local okReq, reqs = pcall(C_TradeSkillUI.GetRecipeRequirements, info.recipeID)
    -- A requirement not met (not at an anvil, no hammer in the bags) greys out the craft buttons.
    local unmet = false
    if okReq and reqs and #reqs > 0 then
        local parts = {}
        for _, req in ipairs(reqs) do
            if req.met == false then unmet = true end
            local c = req.met and T.fg or RED
            parts[#parts + 1] = ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, req.name)
        end
        lines[#lines + 1] = "Requires: " .. table.concat(parts, ", ")
    end
    local okCd, cooldown = pcall(C_TradeSkillUI.GetRecipeCooldown, info.recipeID)
    if okCd and cooldown and cooldown > 0 then
        lines[#lines + 1] = "|cffff4d4dCooldown: " .. SecondsToTime(cooldown) .. "|r"
    end
    d.desc:SetText(table.concat(lines, "\n"))

    d.reagentsLabel:ClearAllPoints()
    d.reagentsLabel:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -14)
    local reagents = Reagents(info.recipeID)
    -- The crafts the orange count promises: each vendor reagent says how many to buy for them.
    local target = S.Get("vendorMaterials") and CraftableWithVendor(info)
    if target and target <= Craftable(info) then target = nil end
    FillReagents(d.reagents, reagents, target, MAX_REAGENTS)
    -- Buy Materials right under the reagents it buys, on the right.
    local last = d.reagents[math.min(#reagents, MAX_REAGENTS)]
    ResetBuyCount(info.recipeID)
    d.buyRow:SetShown(last ~= nil and S.Get("buyMaterials") and AuctionHouseOpen()
        and HasBuyableMaterials(info.recipeID))
    if last then
        d.buyRow:ClearAllPoints()
        -- The reagent rows end 4px short of where Create ends (10 from the pane's edge).
        d.buyRow:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 4, -4)
    end
    local okTrack, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, info.recipeID, false)
    d.track:SetShown(okTrack and C_TradeSkillUI.SetRecipeTracked ~= nil)
    d.track:SetChecked(okTrack and tracked == true)

    ns.SetButtonText(win.createAll, ("Create All (%d)"):format(Craftable(info)))
    EnableButton(win.create, not unmet)
    EnableButton(win.createAll, not unmet)
end

-- What a next-rank alert says, shared by the banner and the overview cards: the rank, what
-- it takes, and the teacher with where they stand.
local function RankLines(a)
    local npc = a.npc
    return ("%s%s|r is ready to learn."):format(ns.RecipeFinder.Hex(GOLD), a.rankName), a.how .. ".",
        npc and ("%s - %s %.1f, %.1f"):format(npc[2], ns.RecipeFinder.ZoneName(npc[4]), npc[5], npc[6])
            or "No teacher recorded for your faction."
end

-- Shows the banner when the open profession can take its next rank, and moves the search
-- box and the middle column below it.
local function RenderRankBanner(prof)
    local banner = win.rankBanner
    local a
    if ns.ProfessionRank and ns.RecipeFinder and Own() then
        local line, skill, max = ns.RecipeFinder.Current()
        a = line and ns.ProfessionRank.For(line, skill, max, prof.name)
    end
    local npc = a and a.npc
    if a then
        banner.npc = npc
        local rank, how, where = RankLines(a)
        banner.text:SetText(("%s %s\n%s%s|r"):format(rank, how, ns.RecipeFinder.Hex(T.muted), where))
        banner.waypoint:SetShown(npc ~= nil)
    end
    banner:SetShown(a ~= nil)
    local top = a and (TOP_Y - BANNER_SHIFT) or TOP_Y
    win.search:SetPoint("TOPLEFT", PAD, top)
    win.mid:SetPoint("TOPLEFT", MID_X, top)
end

Render = function()
    local prof = Profession()
    if not prof then return end
    wipe(profitCache)
    win.title:SetText(prof.name)
    win.rank:SetMinMaxValues(0, math.max(prof.max, 1))
    win.rank:SetValue(prof.skill)
    win.rankText:SetText(("%s %d/%d"):format(prof.name, prof.skill, prof.max))
    RenderRankBanner(prof)

    Collect()
    BuildEntries()
    RenderList()
    RenderDetail()
    UpdateFilterLabel()
end

-------------------------------------------------------------------------------
--  Tabs
-------------------------------------------------------------------------------
-- Blizzard's profession tabs (the overview book, then every profession with a crafting
-- window, Fishing included) switch profession by casting its spell, which only Blizzard's
-- code may do. So the real tabs move onto this window's edge instead of being rebuilt: the
-- chain hangs off the overview tab, and they ignore their invisible parent's alpha.
local savedTabPoints

local function BlizzardTabs()
    local pf = ProfessionsFrame
    local head = pf.ProfessionsOverviewTab
    if not head then return end
    local all = { head }
    for _, tab in ipairs(pf.rightProfessionTabs or {}) do all[#all + 1] = tab end
    return head, all
end

local function DockTabs(on)
    local head, all = BlizzardTabs()
    if not head then return end
    if on then
        if not savedTabPoints then
            savedTabPoints = {}
            for i = 1, head:GetNumPoints() do savedTabPoints[i] = { head:GetPoint(i) } end
        end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", win, "TOPRIGHT", 0, -60)
    elseif savedTabPoints then
        head:ClearAllPoints()
        for _, pt in ipairs(savedTabPoints) do head:SetPoint(unpack(pt)) end
        savedTabPoints = nil
    end
    for _, tab in ipairs(all) do
        if tab.SetIgnoreParentAlpha then tab:SetIgnoreParentAlpha(on) end
    end
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function CloseAll()
    HideUIPanel(ProfessionsFrame)
end

-- A "Reagents:" label and the rows under it, one reagent per line: icon, name, have/need, and
-- the Bags and Bank columns on the right (a muted label over each number).
local function BuildReagents(parent)
    local label = ns.Font(parent, 12, nil, GOLD)
    label:SetText("Reagents:")
    local rows = {}
    for i = 1, MAX_REAGENTS do
        local r = CreateFrame("Button", nil, parent)
        r:SetSize(MID_W - 28, REAGENT_H - 4)
        r:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6 - (i - 1) * REAGENT_H)
        -- Shown with crafting profit: uncheck a reagent you have to leave it out of the cost.
        r.check = CheckBox(r)
        r.check:SetPoint("LEFT", 1, 0)
        r.check:SetScript("OnClick", function(self)
            Owned()[r.itemID] = not self:GetChecked() or nil
            wipe(profitCache)
            BuildEntries()
            RenderList()
            RenderDetail()
        end)
        r.check:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Count in the cost", 1, 1, 1)
            GameTooltip:AddLine("Uncheck a reagent you already have: the crafting profit then leaves it "
                .. "out, for every recipe that uses it.", T.muted.r, T.muted.g, T.muted.b, true)
            GameTooltip:Show()
        end)
        r.check:HookScript("OnLeave", GameTooltip_Hide)
        r.check:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(REAGENT_H - 6, REAGENT_H - 6)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local function Column(right)
            local head = ns.Font(r, 11, nil, T.muted)
            head:SetPoint("TOPRIGHT", right, -2)
            head:SetWidth(REAGENT_COL_W)
            head:SetJustifyH("RIGHT")
            local value = ns.Font(r, 12, nil)
            value:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -1)
            value:SetWidth(REAGENT_COL_W)
            value:SetJustifyH("RIGHT")
            return head, value
        end
        r.bankLabel, r.bank = Column(0)
        r.bankLabel:SetText("Bank")
        r.bagsLabel, r.bags = Column(-REAGENT_COL_W)
        r.bagsLabel:SetText("Bags")
        r.name = ns.Font(r, 12, nil)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.count = ns.Font(r, 12, nil)
        r.count:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
        r:SetScript("OnClick", function(self)
            if IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(self.itemID)
                ShiftClick(self.itemID, link)
            end
        end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            if self.vendor then
                GameTooltip:AddLine(VENDOR_ICON .. " Sold by vendors", VENDOR_ORANGE.r, VENDOR_ORANGE.g,
                    VENDOR_ORANGE.b)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        rows[i] = r
    end
    return label, rows
end

-- The crafting profit lines; hovering them breaks the cost down per reagent.
local function BuildProfit(parent)
    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(MID_W - 28, PROFIT_H)
    block:EnableMouse(true)
    -- Buy, Sell and Profit, one under the other with their amounts lined up.
    for i, key in ipairs({ "buy", "sell", "profit" }) do
        local line = CreateFrame("Frame", nil, block)
        line:SetPoint("TOPLEFT", 0, -(i - 1) * PROFIT_LINE)
        line:SetPoint("RIGHT")
        line:SetHeight(PROFIT_LINE)
        line.label = ns.Font(line, 12, nil, GOLD)
        line.label:SetPoint("LEFT")
        -- The amounts right-aligned in one column; anything said about them after it.
        line.value = ns.Font(line, 12, nil)
        line.value:SetPoint("LEFT", PROFIT_LABEL_W, 0)
        line.value:SetWidth(PROFIT_VALUE_W)
        line.value:SetJustifyH("RIGHT")
        line.value:SetWordWrap(false)
        line.note = ns.Font(line, 12, nil, T.muted)
        line.note:SetPoint("LEFT", line.value, "RIGHT", 8, 0)
        line.note:SetPoint("RIGHT")
        line.note:SetJustifyH("LEFT")
        line.note:SetWordWrap(false)
        block[key] = line
    end
    block:SetScript("OnEnter", function(self)
        local v = self.value
        if not v then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Crafting Profit", GOLD.r, GOLD.g, GOLD.b)
        for _, p in ipairs(v.parts) do
            local name = C_Item.GetItemNameByID(p.itemID) or ("Item " .. p.itemID)
            local right = p.owned and ns.Color("muted", "you have it")
                or p.each and (Money(p.each * p.need) .. (p.from == "vendor" and "  (vendor)" or "  (AH)"))
                or "no price"
            GameTooltip:AddDoubleLine(("%s x%d"):format(name, p.need), right, 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine(v.owned > 0 and "Materials to buy" or "Materials", Money(v.cost),
            GOLD.r, GOLD.g, GOLD.b, 1, 1, 1)
        if v.sale then
            GameTooltip:AddDoubleLine("Sells for, less 5% cut", Money(v.sale), GOLD.r, GOLD.g, GOLD.b, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Vendor prices are the ones last seen at a merchant; the rest are the "
            .. "lowest buyouts at your last auction house scan. Uncheck a reagent you already have "
            .. "to leave it out of the cost.", T.muted.r, T.muted.g, T.muted.b, true)
        if ns.AuctionScanSummary then
            GameTooltip:AddLine(ns.AuctionScanSummary(), T.muted.r, T.muted.g, T.muted.b, true)
        end
        GameTooltip:Show()
    end)
    block:SetScript("OnLeave", GameTooltip_Hide)
    block:Hide()
    return block
end

-------------------------------------------------------------------------------
--  Buy Materials
-------------------------------------------------------------------------------
-- Buys the chosen recipe's missing reagents on the auction house, one confirmation each. The
-- game only lets a purchase run from a click, so every step is a button: Get Price asks the
-- auction house for the real price of the amount, Buy pays it. Nothing is bought without Buy.
-- A material sold as single listings rather than by amount gets Search AH instead.
local OVERPRICED = 1.25   -- warn when the live price is this far above the last scan

-- What to buy for `crafts` more of a recipe: the full amount of each checked reagent vendors do
-- not sell, whatever is already in the bags (unchecking a reagent is how to leave one out).
local function MaterialsToBuy(recipeID, crafts)
    local out, owned = {}, Owned()
    local ok, reagents = pcall(Reagents, recipeID)
    for _, r in ipairs(ok and reagents or {}) do
        if not owned[r.itemID] and not IsVendorItem(r.itemID) then
            out[#out + 1] = { itemID = r.itemID, quantity = r.need * crafts }
        end
    end
    return out
end

-- Whether a recipe has anything Buy Materials could ever buy, for showing its button.
HasBuyableMaterials = function(recipeID)
    local owned = Owned()
    local ok, reagents = pcall(Reagents, recipeID)
    for _, r in ipairs(ok and reagents or {}) do
        if not owned[r.itemID] and not IsVendorItem(r.itemID) then return true end
    end
    return false
end

local buyer, buyEvents
local RenderBuyer

-- How many crafts to buy for: Buy Materials' own box, not Create's.
local function Crafts()
    local box = win and win.detail and win.detail.buyQty
    return math.max(1, tonumber(box and box:GetText() or "") or 1)
end

-- Back to 1 craft whenever another recipe is chosen, so a large number never carries over.
local buyRecipe
ResetBuyCount = function(recipeID)
    if recipeID ~= buyRecipe then
        buyRecipe = recipeID
        win.detail.buyQty:SetText("1")
    end
end

local function CraftsText(n)
    return n == 1 and "1 craft" or (n .. " crafts")
end

local SEARCH_TIMEOUT = 5   -- seconds to wait for the auction house before saying so
local BUY_TIMEOUT = 15     -- a purchase can take longer to settle than a search
local searchGen = 0          -- invalidates the timeout of an older search

-- Buy opens this on the first material and searches it at once, the way the auction house's
-- own Buy tab does, adding up the cheapest listings. Buy in the box then asks for the final
-- price, and only Confirm pays. The states, each shown by RenderBuyer:
--   searching -> listed -> (Buy) quoting -> quoted -> (Confirm) buying -> the next material
-- with short, single, noanswer, noquote, unavailable and failed on the way (Try Again).
local function CancelQuote()
    if buyer.state == "quoting" or buyer.state == "quoted" then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    end
end

local function CloseBuyer()
    if not buyer then return end
    CancelQuote()
    searchGen = searchGen + 1
    buyEvents:UnregisterAllEvents()
    buyer:Hide()
    if ns.ProfWindowRefresh then ns.ProfWindowRefresh() end
end

local function Search()
    local item = buyer.list[buyer.index]
    local key = C_AuctionHouse.MakeItemKey(item.itemID)
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    buyer.state = "searching"
    searchGen = searchGen + 1
    local gen = searchGen
    C_AuctionHouse.SendSearchQuery(key, sorts, true)
    C_Timer.After(SEARCH_TIMEOUT, function()
        if gen == searchGen and buyer.state == "searching" then
            buyer.state = "noanswer"
            RenderBuyer()
        end
    end)
end

local function NextMaterial()
    buyer.index = buyer.index + 1
    if buyer.index > #buyer.list then
        buyer.state = "done"
    else
        Search()
    end
    RenderBuyer()
end

-- The search came back for a material sold by amount: add up the cheapest listings until the
-- amount is covered, leaving out your own, then ask for the final price.
local function ReadListings(item)
    local want, have, total = item.quantity, 0, 0
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(item.itemID) or 0 do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(item.itemID, i)
        if r then
            local n = math.min((r.quantity or 0) - (r.numOwnerItems or 0), want - have)
            if n > 0 then have, total = have + n, total + n * r.unitPrice end
            if have >= want then break end
        end
    end
    if have < want and not C_AuctionHouse.HasFullCommoditySearchResults(item.itemID) then
        -- More listings exist than the first page brought; this event fires again with them.
        C_AuctionHouse.RequestMoreCommoditySearchResults(item.itemID)
        return
    end
    buyer.found, buyer.estimate = have, total
    buyer.state = have < want and "short" or "listed"
    RenderBuyer()
end

-- Asking for the final price only works from a click (as the auction house's own Buy button
-- does), so it waits for Buy; no answer within the timeout says so.
local function Quote(item)
    buyer.state = "quoting"
    searchGen = searchGen + 1
    local gen = searchGen
    C_AuctionHouse.StartCommoditiesPurchase(item.itemID, item.quantity)
    C_Timer.After(SEARCH_TIMEOUT, function()
        if gen == searchGen and buyer.state == "quoting" then
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            buyer.state = "noquote"
            RenderBuyer()
        end
    end)
end

-- Buy asks for the final price and Confirm pays; both run inside their click, as the game
-- requires. Confirm is the only thing that spends gold.
local function Primary()
    local item = buyer.list[buyer.index]
    local state = buyer.state
    if state == "done" then return CloseBuyer() end
    if state == "single" then return SearchAuctionHouse(C_Item.GetItemNameByID(item.itemID)) end
    if state == "listed" then
        Quote(item)
    elseif state == "quoted" then
        buyer.state = "buying"
        searchGen = searchGen + 1
        local gen = searchGen
        C_AuctionHouse.ConfirmCommoditiesPurchase(item.itemID, item.quantity)
        C_Timer.After(BUY_TIMEOUT, function()
            if gen == searchGen and buyer.state == "buying" then
                buyer.state = "unconfirmed"
                RenderBuyer()
            end
        end)
    elseif state == "noanswer" or state == "noquote" or state == "failed" or state == "unavailable"
        or state == "short" or state == "unconfirmed" then
        Search()
    end
    RenderBuyer()
end

local function BuildBuyer()
    buyer = CreateFrame("Frame", nil, win)
    buyer:SetSize(320, 170)
    buyer:SetPoint("CENTER", win.mid, "CENTER", 0, 20)
    buyer:SetFrameLevel(win:GetFrameLevel() + 60)
    buyer:EnableMouse(true)
    ns.Solid(buyer, "BACKGROUND", T.bg, 0.98):SetAllPoints()
    ns.Border(buyer, BLACK)
    buyer.title = ns.Font(buyer, 14, nil, T.accent)
    buyer.title:SetPoint("TOP", 0, -10)
    buyer.icon = buyer:CreateTexture(nil, "ARTWORK")
    buyer.icon:SetSize(36, 36)
    buyer.icon:SetPoint("TOPLEFT", 14, -34)
    buyer.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    buyer.name = ns.Font(buyer, 13, nil)
    buyer.name:SetPoint("LEFT", buyer.icon, "RIGHT", 10, 0)
    buyer.name:SetPoint("RIGHT", -14, 0)
    buyer.name:SetJustifyH("LEFT")
    buyer.line1 = ns.Font(buyer, 12, nil)
    buyer.line1:SetPoint("TOPLEFT", buyer.icon, "BOTTOMLEFT", 0, -10)
    buyer.line1:SetPoint("RIGHT", -14, 0)
    buyer.line1:SetJustifyH("LEFT")
    buyer.line2 = ns.Font(buyer, 12, nil)
    buyer.line2:SetPoint("TOPLEFT", buyer.line1, "BOTTOMLEFT", 0, -4)
    buyer.line2:SetPoint("RIGHT", -14, 0)
    buyer.line2:SetJustifyH("LEFT")
    buyer.line2:SetWordWrap(true)

    buyer.cancel = Button(buyer, "Cancel", 80, 24, CloseBuyer)
    buyer.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
    buyer.skip = Button(buyer, "Skip", 80, 24, function()
        CancelQuote()
        NextMaterial()
    end)
    buyer.skip:SetPoint("RIGHT", buyer.cancel, "LEFT", -6, 0)
    buyer.primary = Button(buyer, "Confirm", 110, 24, Primary)
    buyer.primary:SetPoint("BOTTOMLEFT", 10, 10)

    buyEvents = CreateFrame("Frame")
    buyEvents:SetScript("OnEvent", function(_, event, a, b)
        if event == "AUCTION_HOUSE_CLOSED" then return CloseBuyer() end
        local item = buyer.list[buyer.index]
        if not item then return end
        local state = buyer.state
        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and state == "searching" and a == item.itemID then
            return ReadListings(item)
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and state == "searching"
            and type(a) == "table" and a.itemID == item.itemID then
            buyer.state = "single"
        elseif event == "COMMODITY_PRICE_UPDATED" and state == "quoting" then
            buyer.state, buyer.unit, buyer.total = "quoted", a, b
        elseif event == "COMMODITY_PRICE_UNAVAILABLE" and state == "quoting" then
            buyer.state = "unavailable"
        -- A purchase that answers after its timeout still went through.
        elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and (state == "buying" or state == "unconfirmed") then
            buyer.bought = buyer.bought + 1
            return NextMaterial()
        elseif event == "COMMODITY_PURCHASE_FAILED" and state == "buying" then
            buyer.state = "failed"
        else
            return
        end
        RenderBuyer()
    end)
    buyer:Hide()
end

-- The final price against the last scan: red when it is well above, or when you cannot pay.
local function PriceWarning(each, total, scanEach)
    if GetMoney() < total then return Hex(RED) .. "You do not have enough gold.|r", true end
    if scanEach and each > scanEach * OVERPRICED then
        return ("%sCareful: %d%% above your last scan (%s each).|r"):format(Hex(RED),
            math.floor((each / scanEach - 1) * 100 + 0.5), Money(scanEach))
    end
    if scanEach then return Hex(T.muted) .. ("Last scan: %s each."):format(Money(scanEach)) .. "|r" end
    return ""
end

RenderBuyer = function()
    local b = buyer
    local done = b.state == "done"
    b.skip:SetShown(not done)
    b.cancel:SetShown(not done)
    -- Moving on while a purchase is paying would leave it spent but not counted.
    EnableButton(b.skip, b.state ~= "buying")
    EnableButton(b.cancel, b.state ~= "buying")
    if done then
        b.title:SetText("Buy Materials for " .. CraftsText(b.crafts))
        b.icon:Hide()
        b.name:SetText(#b.list == 0 and "Nothing to buy: every material is unchecked or sold by vendors."
            or ("Bought %d of %d materials."):format(b.bought, #b.list))
        b.line1:SetText("")
        b.line2:SetText("")
        ns.SetButtonText(b.primary, "Close")
        return EnableButton(b.primary, true)
    end

    local item = b.list[b.index]
    local name = C_Item.GetItemNameByID(item.itemID) or ("Item " .. item.itemID)
    local scanEach = ns.AuctionPrice and ns.AuctionPrice(item.itemID)
    local muted = Hex(T.muted)
    b.title:SetText(("Buy Materials for %s  (%d/%d)"):format(CraftsText(b.crafts), b.index, #b.list))
    b.icon:SetTexture(C_Item.GetItemIconByID(item.itemID))
    b.icon:Show()
    b.name:SetText(("%d x %s"):format(item.quantity, name))

    local label, enabled = "Confirm", false
    local line1, line2 = "", ""
    local state = b.state
    if state == "searching" then
        line1 = "Searching the auction house..."
    elseif state == "listed" then
        label = "Buy"
        line1 = ("Cheapest %d add up to %s."):format(item.quantity, Money(b.estimate))
        local warn, blocked = PriceWarning(b.estimate / item.quantity, b.estimate, scanEach)
        line2, enabled = warn ~= "" and warn or (muted .. "Buy asks for the final price.|r"), not blocked
    elseif state == "quoting" then
        line1 = ("Cheapest %d add up to %s. Getting the final price..."):format(item.quantity,
            Money(b.estimate))
    elseif state == "noquote" then
        label, enabled = "Try Again", true
        line1 = "The auction house gave no final price."
        line2 = muted .. "Try Again searches it once more.|r"
    elseif state == "quoted" then
        line1 = ("Costs %s  %s(%s each)|r"):format(Money(b.total), muted, Money(b.unit))
        local warn, blocked = PriceWarning(b.unit, b.total, scanEach)
        line2, enabled = warn, not blocked
    elseif state == "buying" then
        line1 = "Buying..."
    elseif state == "unconfirmed" then
        label, enabled = "Try Again", true
        line1 = "No answer to the purchase yet."
        line2 = muted .. "It may still have gone through: check your bags before trying again.|r"
    elseif state == "short" then
        label, enabled = "Try Again", true
        line1 = ("Only %d listed right now."):format(b.found)
        line2 = muted .. "Skip it, or lower the number of crafts.|r"
    elseif state == "unavailable" then
        label, enabled = "Try Again", true
        line1 = "The auction house has no price for it right now."
    elseif state == "noanswer" then
        label, enabled = "Try Again", true
        line1 = "No answer from the auction house."
        line2 = muted .. "Searches are limited to a few a second; try again in a moment.|r"
    elseif state == "failed" then
        label, enabled = "Try Again", true
        line1 = Hex(RED) .. "The purchase failed; the price may have changed.|r"
    elseif state == "single" then
        label, enabled = "Search AH", true
        line1 = "Sold as single listings, not by amount."
        line2 = muted .. "Search AH shows them to buy yourself; Skip moves on.|r"
    end
    b.line1:SetText(line1)
    b.line2:SetText(line2)
    ns.SetButtonText(b.primary, label)
    EnableButton(b.primary, enabled)
end

-- Opened by Buy's click, which also starts the first search.
local function OpenBuyer(recipeID, crafts)
    if not buyer then BuildBuyer() end
    buyer.list = MaterialsToBuy(recipeID, crafts)
    buyer.index, buyer.bought, buyer.crafts = 1, 0, crafts
    for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
        "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
        "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED" }) do
        pcall(buyEvents.RegisterEvent, buyEvents, event)
    end
    if #buyer.list == 0 then
        buyer.state = "done"
    else
        Search()
    end
    buyer:Show()
    RenderBuyer()
end

-- Walking up to an anvil or forge changes whether a recipe's requirements are met. Listened to
-- only while the window is open; the event fires often, so only the recipe pane redraws, at
-- most twice a second.
local usable, usablePending = CreateFrame("Frame"), false
usable:SetScript("OnEvent", function()
    if usablePending then return end
    usablePending = true
    C_Timer.After(0.5, function()
        usablePending = false
        if win:IsShown() and win.detail:IsShown() then RenderDetail() end
    end)
end)

local function Build()
    win = CreateFrame("Frame", "NaowhForeverProfessions", UIParent)
    win:SetWidth(W)
    win:HookScript("OnShow", function() usable:RegisterEvent("SPELL_UPDATE_USABLE") end)
    -- Closing the window mid-purchase lets go of a price the auction house is holding.
    win:HookScript("OnHide", function()
        usable:UnregisterAllEvents()
        if buyer and buyer:IsShown() then CloseBuyer() end
    end)
    win:EnableMouse(true)
    win:Hide()
    ns.Solid(win, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(win, BLACK)

    local logo = win:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\LogoSmall.tga", nil, nil, "TRILINEAR")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 10, -5)
    win.title = ns.Font(win, 15, "OUTLINE", T.accent)
    win.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    local close = Button(win, "X", 22, 22, CloseAll)
    close:SetPoint("TOPRIGHT", -8, -7)

    -- Skill rank across the recipe and detail columns.
    local rank = CreateFrame("StatusBar", nil, win)
    rank:SetPoint("TOPLEFT", PAD + 2, -40)
    rank:SetSize(W - PAD * 2 - 4, 18)
    ns.Solid(rank, "BACKGROUND", T.panel, 1):SetAllPoints()
    StyleBar(rank)
    win.rank = rank
    win.rankText = ns.Font(rank, 12, "OUTLINE")
    win.rankText:SetPoint("CENTER")

    -- The next profession rank, once your skill is high enough for it.
    local banner = CreateFrame("Frame", nil, win)
    banner:SetPoint("TOPLEFT", PAD, BANNER_Y)
    banner:SetSize(W - PAD * 2, BANNER_H)
    ns.Solid(banner, "BACKGROUND", GOLD, 0.12):SetAllPoints()
    ns.Border(banner, BLACK)
    banner.icon = banner:CreateTexture(nil, "ARTWORK")
    banner.icon:SetTexture("Interface\\GossipFrame\\TrainerGossipIcon")
    banner.icon:SetSize(16, 16)
    banner.icon:SetPoint("LEFT", 8, 0)
    banner.waypoint = Button(banner, "Waypoint", 86, 22, function()
        ns.ProfessionRank.Waypoint(banner.npc)
    end)
    banner.waypoint:SetPoint("RIGHT", -4, 0)
    banner.waypoint:HookScript("OnEnter", function(self)
        local npc = self:GetParent().npc
        if not npc then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(npc[2], 1, 1, 1)
        GameTooltip:AddLine(("%s %.1f, %.1f"):format(ns.RecipeFinder.ZoneName(npc[4]), npc[5], npc[6]),
            T.muted.r, T.muted.g, T.muted.b)
        GameTooltip:AddLine("Click to set a waypoint.", T.accent.r, T.accent.g, T.accent.b)
        GameTooltip:Show()
    end)
    banner.waypoint:HookScript("OnLeave", GameTooltip_Hide)
    banner.text = ns.Font(banner, 12, nil)
    banner.text:SetPoint("LEFT", banner.icon, "RIGHT", 8, 0)
    banner.text:SetPoint("RIGHT", banner.waypoint, "LEFT", -8, 0)
    banner.text:SetJustifyH("LEFT")
    banner.text:SetWordWrap(true)
    banner.text:SetSpacing(2)
    if banner.text.SetMaxLines then banner.text:SetMaxLines(2) end
    banner:Hide()
    win.rankBanner = banner

    -- Left column: search and the recipe list.
    local search = EditBox(win)
    win.search = search
    search:SetPoint("TOPLEFT", PAD, TOP_Y)
    search:SetSize(LEFT_W - FILTER_W - 6, 22)

    -- Blizzard's Filter menu, beside the search box; it says how many filters are on.
    local function Refilter()
        offset = 0
        Render()
    end
    local filter = Button(win, "Filter", FILTER_W, 22, function()
        MenuUtil.CreateContextMenu(win.filter, function(_, root)
            root:CreateTitle("Filter")
            for _, f in ipairs(FILTERS) do
                local box = root:CreateCheckbox(f.text, function() return S.Get(f.key) == true end, function()
                    S.Set(f.key, not S.Get(f.key))
                    Refilter()
                end)
                if f.profit and not ProfitShown() then
                    box:SetEnabled(false)
                    box:SetTooltip(function(tooltip)
                        GameTooltip_SetTitle(tooltip, f.text)
                        GameTooltip_AddNormalLine(tooltip, "Scan the auction house (Scan Prices) first.")
                    end)
                end
            end
            root:CreateDivider()
            root:CreateCheckbox("Unlearned Recipes", function() return S.Get("recipeFinder") == true end,
                function()
                    S.Set("recipeFinder", not S.Get("recipeFinder"))
                    Refilter()
                end)
            root:CreateButton("Reset Filters", function()
                for _, f in ipairs(FILTERS) do S.Set(f.key, false) end
                Refilter()
            end)
        end)
    end)
    win.filter = filter
    filter:SetPoint("LEFT", search, "RIGHT", 6, 0)
    search.hint = ns.Font(search, 12, nil, T.muted)
    search.hint:SetPoint("LEFT", 6, 0)
    search.hint:SetText(SEARCH or "Search")
    -- Clears the search; only there while something is typed.
    search:SetTextInsets(6, 22, 0, 0)
    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -2, 0)
    clear.text = ns.Font(clear, 13, nil, T.muted)
    clear.text:SetPoint("CENTER")
    clear.text:SetText("X")
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)
    clear:SetScript("OnEnter", function() SetColor(clear.text, T.accent) end)
    clear:SetScript("OnLeave", function() SetColor(clear.text, T.muted) end)
    clear:Hide()
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        clear:SetShown(text ~= "")
        query = text:lower()
        offset = 0
        BuildEntries()
        RenderList()
        RenderDetail()
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)

    local list = CreateFrame("Frame", nil, win)
    list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    list:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, PAD)
    list:SetWidth(LEFT_W)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.min(math.max(0, #entries - VisibleRows()), math.max(0, offset - delta * 2))
        RenderList()
    end)
    ns.Solid(list, "BACKGROUND", T.panel, 0.6):SetAllPoints()
    win.list = list

    local bar = CreateFrame("Slider", nil, list)
    bar:SetPoint("TOPRIGHT", -2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetWidth(SCROLL_W)
    bar:SetOrientation("VERTICAL")
    bar:SetValueStep(1)
    ns.Solid(bar, "BACKGROUND", T.line, 0.6):SetAllPoints()
    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 0.8)
    bar.thumb:SetSize(SCROLL_W, 40)
    bar:SetThumbTexture(bar.thumb)
    bar:SetScript("OnValueChanged", function(self, value)
        if self.syncing then return end
        offset = math.floor(value + 0.5)
        RenderList()
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta) list:GetScript("OnMouseWheel")(list, delta) end)
    win.scroll = bar

    function win.BuildRow(i)
        local row = CreateFrame("Button", nil, list)
        row:SetSize(LEFT_W - SCROLL_W - 6, ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        row.head = ns.Solid(row, "BACKGROUND", T.line, 0.6)
        row.head:SetAllPoints()
        row.sel = ns.Solid(row, "BACKGROUND", T.accent, 0.25)
        row.sel:SetAllPoints()
        row.hl = ns.Solid(row, "HIGHLIGHT", T.fg, 0.06)
        row.hl:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_H - 4, ROW_H - 4)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        -- The crafting profit on the right edge, so every row's amount ends in one line; the
        -- count or skill in a column on the left, placed by AlignRows.
        row.profit = ns.Font(row, 12, nil)
        row.profit:SetPoint("RIGHT", -6, 0)
        row.profit:SetJustifyH("RIGHT")
        row.count = ns.Font(row, 12, nil)
        row.count:SetJustifyH("RIGHT")
        row.text = ns.Font(row, 12, nil)
        row.text:SetPoint("RIGHT", row.profit, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local e = self.entry
            if e.cat then
                ToggleCollapsed(e.cat)
                BuildEntries()
                RenderList()
            elseif e.unlearned then
                selectedUnlearned = e.unlearned
                RenderList()
                RenderDetail()
            elseif IsModifiedClick("CHATLINK") then
                local id = e.recipe.recipeID
                ShiftClick((OutputItem(id)), C_TradeSkillUI.GetRecipeLink(id))
            else
                selectedID, selectedUnlearned = e.recipe.recipeID, nil
                RenderList()
                RenderDetail()
            end
        end)
        row:SetScript("OnEnter", function(self)
            local r = self.entry.unlearned
            if r then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(r.spell)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(("Required skill: %d  (%s)"):format(ns.RecipeFinder.Skill(r),
                    ns.RecipeFinder.Tag(r)), 1, 1, 1)
                GameTooltip:Show()
                return
            end
            if not self.entry.recipe then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, self.entry.recipe.recipeID) then
                GameTooltip:SetSpellByID(self.entry.recipe.recipeID)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnMouseWheel", function(_, delta) list:GetScript("OnMouseWheel")(list, delta) end)
        return row
    end

    -- Middle column: the chosen recipe.
    local mid = CreateFrame("Frame", nil, win)
    win.mid = mid
    mid:SetPoint("TOPLEFT", MID_X, TOP_Y)
    mid:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", MID_X, PAD)
    mid:SetWidth(MID_W)
    ns.Solid(mid, "BACKGROUND", T.panel, 0.6):SetAllPoints()

    win.empty = ns.Font(mid, 13, nil, T.muted)
    win.empty:SetPoint("CENTER")
    win.empty:SetText("No recipes match.")

    local d = CreateFrame("Frame", nil, mid)
    d:SetAllPoints()
    win.detail = d
    local iconBtn = CreateFrame("Button", nil, d)
    iconBtn:SetSize(44, 44)
    iconBtn:SetPoint("TOPLEFT", 14, -14)
    d.icon = iconBtn:CreateTexture(nil, "ARTWORK")
    d.icon:SetAllPoints()
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    iconBtn:SetScript("OnEnter", function(self)
        local info = SelectedInfo()
        if not info then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, info.recipeID) then
            GameTooltip:SetSpellByID(info.recipeID)
        end
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", GameTooltip_Hide)
    d.name = ns.Font(d, 16, nil)
    d.name:SetPoint("LEFT", iconBtn, "RIGHT", 10, 0)
    d.name:SetPoint("RIGHT", -12, 0)
    d.name:SetJustifyH("LEFT")

    -- Only while the auction house is open, and only for a recipe that makes an item.
    d.search = Button(d, "Search AH", 84, 22, function() SearchAuctionHouse(d.search.itemName) end)
    d.search:SetPoint("RIGHT", d, "TOPRIGHT", -12, -36)
    ns.Tooltip(d.search, "Search AH", "Searches the auction house for the item this recipe makes.")
    d.search:Hide()

    d.desc = ns.Font(d, 12, nil)
    d.desc:SetPoint("TOPLEFT", iconBtn, "BOTTOMLEFT", 0, -12)
    d.desc:SetWidth(MID_W - 28)
    d.desc:SetJustifyH("LEFT")
    d.desc:SetSpacing(2)

    d.reagentsLabel, d.reagents = BuildReagents(d)
    -- Blizzard's Track Recipe, on the right of the Reagents: line: the recipe's reagents in the
    -- objective tracker. The label sits at x 14, so the offset puts the box at the pane's edge.
    d.track = CheckBox(d)
    -- Ending in line with the reagent rows' Bank column (they end 14 from the pane's edge).
    d.track:SetPoint("RIGHT", d.reagentsLabel, "LEFT", MID_W - 28, 0)
    d.track.text = ns.Font(d.track, 12, nil)
    d.track.text:SetPoint("RIGHT", d.track, "LEFT", -6, 0)
    d.track.text:SetText(_G.PROFESSIONS_TRACK_RECIPE or "Track Recipe")
    d.track:SetScript("OnClick", function(self)
        local info = SelectedInfo()
        local on = self:GetChecked()
        if not (info and pcall(C_TradeSkillUI.SetRecipeTracked, info.recipeID, on, false)) then
            self:SetChecked(not on)
        end
    end)
    d.track:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.text:GetText(), 1, 1, 1)
        GameTooltip:AddLine("Shows this recipe's reagents in your objective tracker, with how many "
            .. "you have of each.", T.muted.r, T.muted.g, T.muted.b, true)
        GameTooltip:Show()
    end)
    d.track:HookScript("OnLeave", GameTooltip_Hide)
    -- Just above the craft buttons.
    d.profit = BuildProfit(d)
    d.profit:SetPoint("BOTTOMLEFT", 14, 44)
    -- Under the reagent list, while the auction house is open (RenderDetail places it): how
    -- many crafts to buy for, with its own - and +, and Buy Materials.
    -- Sized and spaced like the Create row at the bottom, so the two line up.
    local row = CreateFrame("Frame", nil, d)
    row:SetSize(BUY_ROW_W, 24)
    d.buyRow = row
    d.buyMats = Button(row, "Buy", 90, 24, function()
        local info = SelectedInfo()
        if info then OpenBuyer(info.recipeID, Crafts()) end
    end)
    d.buyMats:SetPoint("RIGHT")
    ns.Tooltip(d.buyMats, "Buy Materials", "Buys on the auction house the materials for that many "
        .. "crafts, whatever is already in your bags: every checked reagent that vendors do not "
        .. "sell. Set the number with the - and + beside it; uncheck a reagent to leave it out. "
        .. "Each material asks for the price now and waits for you to confirm.")
    local buyQty = EditBox(row)
    buyQty:SetSize(40, 24)
    buyQty:SetNumeric(true)
    buyQty:SetMaxLetters(3)
    buyQty:SetJustifyH("CENTER")
    buyQty:SetText("1")
    buyQty:SetScript("OnEscapePressed", buyQty.ClearFocus)
    buyQty:SetScript("OnEnterPressed", buyQty.ClearFocus)
    d.buyQty = buyQty
    local buyPlus = Button(row, "+", 22, 24, function()
        buyQty:SetText(tostring(math.min(999, Crafts() + 1)))
    end)
    buyPlus:SetPoint("RIGHT", d.buyMats, "LEFT", -12, 0)
    buyQty:SetPoint("RIGHT", buyPlus, "LEFT", -2, 0)
    local buyMinus = Button(row, "-", 22, 24, function()
        buyQty:SetText(tostring(math.max(1, Crafts() - 1)))
    end)
    buyMinus:SetPoint("RIGHT", buyQty, "LEFT", -2, 0)
    ns.Tooltip(buyQty, "Crafts to Buy For", "How many crafts Buy Materials buys the materials for.")
    row:Hide()

    -- Craft controls along the bottom of the middle column.
    local create = Button(d, "Create", 90, 24, function()
        Craft(tonumber(win.qty:GetText()) or 1)
    end)
    create:SetPoint("BOTTOMRIGHT", -10, 10)
    win.create = create
    local qty = EditBox(d)
    qty:SetSize(40, 24)
    qty:SetNumeric(true)
    qty:SetMaxLetters(3)
    qty:SetJustifyH("CENTER")
    qty:SetText("1")
    qty:SetScript("OnEscapePressed", qty.ClearFocus)
    qty:SetScript("OnEnterPressed", qty.ClearFocus)
    win.qty = qty
    local plus = Button(d, "+", 22, 24, function()
        qty:SetText(tostring(math.min(999, (tonumber(qty:GetText()) or 1) + 1)))
    end)
    plus:SetPoint("RIGHT", create, "LEFT", -12, 0)
    qty:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = Button(d, "-", 22, 24, function()
        qty:SetText(tostring(math.max(1, (tonumber(qty:GetText()) or 1) - 1)))
    end)
    minus:SetPoint("RIGHT", qty, "LEFT", -2, 0)
    win.createAll = Button(d, "Create All", 120, 24, function()
        local info = SelectedInfo()
        if info then Craft(Craftable(info)) end
    end)
    win.createAll:SetPoint("BOTTOMLEFT", 10, 10)

    -- The middle column for an unlearned recipe: where to learn it.
    local l = CreateFrame("Frame", nil, mid)
    l:SetAllPoints()
    l:Hide()
    win.learn = l
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetSize(44, 44)
    l.icon:SetPoint("TOPLEFT", 14, -14)
    l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    l.name = ns.Font(l, 16, nil)
    l.name:SetPoint("TOPLEFT", l.icon, "TOPRIGHT", 10, -2)
    l.name:SetPoint("TOPRIGHT", -12, -16)
    l.name:SetJustifyH("LEFT")
    -- Under the name, wrapping onto a second line when the Search Recipe button leaves it
    -- less room; the text below starts past two lines.
    l.req = ns.Font(l, 12, nil)
    l.req:SetPoint("TOPLEFT", l.icon, "TOPRIGHT", 10, -24)
    l.req:SetJustifyH("LEFT")
    l.req:SetWordWrap(true)

    -- Only while the auction house is open: the item the recipe makes, and the recipe itself.
    l.search = Button(l, "Search AH", 96, 20, function() SearchAuctionHouse(l.search.itemName) end)
    l.search:SetPoint("TOPRIGHT", -12, -14)
    ns.Tooltip(l.search, "Search AH", "Searches the auction house for the item this recipe makes.")
    l.search:Hide()
    l.searchRecipe = Button(l, "Search Recipe", 96, 20, function()
        SearchAuctionHouse(l.searchRecipe.itemName)
    end)
    ns.Tooltip(l.searchRecipe, "Search Recipe",
        "Searches the auction house for the recipe itself, to learn it.")
    l.searchRecipe:Hide()
    l.paras = {}
    for i = 1, MAX_PARAS do
        local fs = ns.Font(l, 12, nil)
        fs:SetWidth(MID_W - 28)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetSpacing(2)
        l.paras[i] = fs
    end
    l.lines = {}
    for i = 1, MAX_LINES do
        local line = CreateFrame("Button", nil, l)
        line:SetSize(MID_W - 36, 16)
        line.text = ns.Font(line, 12, nil)
        line.text:SetPoint("LEFT")
        line.text:SetPoint("RIGHT")
        line.text:SetJustifyH("LEFT")
        line.text:SetWordWrap(false)
        line:SetScript("OnClick", function(self)
            local npc = self.npc
            if npc and ns.PlaceWaypoint then ns.PlaceWaypoint(npc[2], npc[4], npc[5], npc[6]) end
        end)
        line:SetScript("OnEnter", function(self)
            if not self.npc then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.npc[2], 1, 1, 1)
            GameTooltip:AddLine("Click to set a waypoint.", T.accent.r, T.accent.g, T.accent.b)
            GameTooltip:Show()
        end)
        line:SetScript("OnLeave", GameTooltip_Hide)
        l.lines[i] = line
    end
    l.reagentsLabel, l.reagents = BuildReagents(l)
    -- In the room RenderLearn leaves free under the reagents.
    local hint = ns.Font(l, 11, nil, T.muted)
    hint:SetPoint("BOTTOMLEFT", 14, 10)
    hint:SetText("Click a trainer or vendor to set a waypoint.")
    l.profit = BuildProfit(l)
    l.profit:SetPoint("BOTTOMLEFT", hint, "TOPLEFT", 0, 8)

    -- The overview: two primary profession cards, then Cooking, Fishing and First Aid.
    local book = CreateFrame("Frame", nil, win)
    book:SetPoint("TOPLEFT", PAD, -40)
    book:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    book:Hide()
    win.book = book
    local innerW = W - PAD * 2
    local cardW = (innerW - CARD_GAP * 2) / 3
    book.cards = {}
    for i = 1, #BOOK_ORDER do
        local primary = i <= 2
        local card = CreateFrame("Frame", nil, book)
        ns.Solid(card, "BACKGROUND", T.panel, 0.6):SetAllPoints()
        ns.Border(card, BLACK)
        card.primary = primary
        if primary then
            card:SetPoint("TOPLEFT", 0, -(i - 1) * (PRIMARY_H + CARD_GAP))
            card:SetSize(innerW, PRIMARY_H)
        else
            local x = (i - 3) * (cardW + CARD_GAP)
            card:SetPoint("TOPLEFT", x, -2 * (PRIMARY_H + CARD_GAP))
            card:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", x, 0)
            card:SetWidth(cardW)
        end
        card.name = ns.Font(card, 14, nil, GOLD)
        local bar = CreateFrame("StatusBar", nil, card)
        ns.Solid(bar, "BACKGROUND", T.bg, 1):SetAllPoints()
        StyleBar(bar)
        if primary then
            card.name:SetPoint("TOPLEFT", 12, -10)
            bar:SetPoint("TOPLEFT", 250, -52)
            bar:SetSize(innerW - 250 - 44, 18)
        else
            card.name:SetPoint("TOP", 0, -12)
            bar:SetPoint("TOP", 0, -38)
            bar:SetSize(cardW - 24, 18)
        end
        card.bar = bar
        card.barText = ns.Font(bar, 12, "OUTLINE")
        card.barText:SetPoint("CENTER")
        card.missing = ns.Font(card, 12, nil, T.muted)
        card.missing:SetPoint("CENTER", 0, primary and -8 or 0)
        card.missing:SetWidth((primary and innerW or cardW) - 40)
        card.missing:SetWordWrap(true)

        -- The next profession rank, once the skill is high enough for it, under the skill
        -- bar; click for a waypoint. Above Blizzard's card, which is docked over this one.
        local strip = CreateFrame("Button", nil, card)
        strip:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
        strip:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
        strip:SetHeight(primary and 38 or 50)
        strip:SetFrameLevel(card:GetFrameLevel() + 12)
        ns.Solid(strip, "BACKGROUND", GOLD, 0.12):SetAllPoints()
        ns.Border(strip, BLACK)
        strip.text = ns.Font(strip, 12, nil)
        strip.text:SetPoint("TOPLEFT", 8, -7)
        strip.text:SetPoint("TOPRIGHT", -8, -7)
        strip.text:SetJustifyH(primary and "LEFT" or "CENTER")
        strip.text:SetWordWrap(true)
        strip.text:SetSpacing(2)
        strip:SetScript("OnClick", function(self)
            if self.alert then ns.ProfessionRank.Waypoint(self.alert.npc) end
        end)
        strip:SetScript("OnEnter", function(self)
            local a = self.alert
            if not a then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(a.rankName, GOLD.r, GOLD.g, GOLD.b)
            GameTooltip:AddLine(a.how, 1, 1, 1, true)
            if a.npc then
                GameTooltip:AddLine(("%s - %s %.1f, %.1f"):format(a.npc[2], ns.RecipeFinder.ZoneName(a.npc[4]),
                    a.npc[5], a.npc[6]), T.muted.r, T.muted.g, T.muted.b)
                GameTooltip:AddLine("Click to set a waypoint.", T.accent.r, T.accent.g, T.accent.b)
            end
            GameTooltip:Show()
        end)
        strip:SetScript("OnLeave", GameTooltip_Hide)
        strip:Hide()
        card.rankStrip = strip
        book.cards[i] = card
    end
end

-------------------------------------------------------------------------------
--  The overview
-------------------------------------------------------------------------------
-- Forever's GetProfessions answers prof1, prof2, First Aid, Fishing, Cooking; the cards run
-- Cooking, Fishing, First Aid, as Blizzard's book does.
local function BookIndices()
    local prof1, prof2, firstAid, fishing, cooking = GetProfessions()
    return { prof1, prof2, cooking, fishing, firstAid }
end

local function RenderRankStrip(card, a)
    local strip = card.rankStrip
    strip.alert = a
    strip:SetShown(a ~= nil)
    if not a then return end
    local rank, how, where = RankLines(a)
    local muted, click = ns.RecipeFinder.Hex(T.muted), a.npc and (ns.RecipeFinder.Hex(T.accent) .. "Click for a waypoint.|r")
    if card.primary then
        strip.text:SetText(("%s %s\n%s%s|r%s"):format(rank, how, muted, where, click and ("  " .. click) or ""))
    else
        strip.text:SetText(("%s\n%s\n%s%s|r%s"):format(rank, how, muted, where, click and ("\n" .. click) or ""))
    end
    strip:SetHeight(strip.text:GetStringHeight() + 14)
end

local function RenderBook()
    win.title:SetText(TRADE_SKILLS or "Professions")
    local indices = BookIndices()
    for i, card in ipairs(win.book.cards) do
        local index = indices[i]
        if index then
            local name, _, rank, maxRank, _, _, line, modifier = GetProfessionInfo(index)
            card.name:SetText(name)
            RenderRankStrip(card, ns.ProfessionRank and ns.ProfessionRank.For(line, rank, maxRank, name))
            card.bar:SetMinMaxValues(0, math.max(maxRank or 0, 1))
            card.bar:SetValue(rank or 0)
            card.barText:SetText(("%d/%d%s"):format(rank or 0, maxRank or 0,
                (modifier or 0) > 0 and (" (+%d)"):format(modifier) or ""))
            card.bar:Show()
            card.missing:Hide()
        else
            card.name:SetText(card.primary and (PROFESSIONS_FIRST_PROFESSION or "Primary Profession")
                or SECONDARY_NAMES[i - 2])
            card.missing:SetText(card.primary and (PROFESSIONS_MISSING_PROFESSION or
                "Visit a profession trainer to learn one.") or "Not learned yet.")
            card.bar:Hide()
            card.missing:Show()
            card.rankStrip:Hide()
        end
    end
end

-- The spell buttons (Smelting, Find Minerals, Bait and Tackle...) cast their spell and the red
-- cross unlearns, so they stay Blizzard's own. Blizzard's whole card moves into ours: a card
-- draws its buttons as part of itself, so a button moved alone stays as invisible as the card
-- it belongs to. The card's own art, name and bar go transparent, our card shows instead, and
-- Blizzard's code keeps laying the buttons out inside it. The buttons stay children of that
-- card, which is where their click reads the spellbook offset from, so casting is untouched.
-- They are secure, so this happens out of combat only, and is undone whenever the overview
-- is not showing, so nothing secure hangs off this window in any other state.
local docked = {}
local bookDocked, bookPending = false, nil
local CARD_ART = { "Background", "ProfessionName", "specialization", "missingHeader", "missingText", "StatusBar" }

local function Place(frame, place, level)
    frame:ClearAllPoints()
    place(frame)
    frame:SetFrameStrata(win:GetFrameStrata())
    frame:SetFrameLevel(level)
end

-- parent, when given, adopts the frame and hides its card art.
local function Dock(frame, place, level, parent)
    local saved = docked[frame]
    if not saved then
        local points = {}
        for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
        saved = { points = points, parent = frame:GetParent(), strata = frame:GetFrameStrata(),
            level = frame:GetFrameLevel(), art = {} }
        docked[frame] = saved
        if parent then
            frame:SetParent(parent)
            for _, key in ipairs(CARD_ART) do
                local region = frame[key]
                if type(region) == "table" and region.SetAlpha then
                    local art = { region = region, alpha = region:GetAlpha() }
                    if region.IsMouseEnabled then
                        art.mouse = region:IsMouseEnabled()
                        region:EnableMouse(false)
                    end
                    region:SetAlpha(0)
                    saved.art[#saved.art + 1] = art
                end
            end
        end
    end
    saved.place, saved.onLevel = place, level
    Place(frame, place, level)
end

local function Redock()
    if not bookDocked or InCombatLockdown() then return end
    for frame, saved in pairs(docked) do Place(frame, saved.place, saved.onLevel) end
end

local function Undock()
    for frame, saved in pairs(docked) do
        frame:SetParent(saved.parent)
        frame:ClearAllPoints()
        for _, pt in ipairs(saved.points) do frame:SetPoint(unpack(pt)) end
        frame:SetFrameStrata(saved.strata)
        frame:SetFrameLevel(saved.level)
        for _, art in ipairs(saved.art) do
            art.region:SetAlpha(art.alpha)
            if art.mouse ~= nil then art.region:EnableMouse(art.mouse) end
        end
    end
    wipe(docked)
end

local function DockBook(on)
    if on == bookDocked then
        bookPending = nil
        return
    end
    if InCombatLockdown() then
        bookPending = on
        return
    end
    bookPending, bookDocked = nil, on
    if not on then return Undock() end
    local content = ProfessionsFrame.BookPage and ProfessionsFrame.BookPage.ProfessionsContentFrame
    if not content then return end
    for i, key in ipairs(BOOK_ORDER) do
        local blizz, card = content[key], win.book.cards[i]
        if blizz then
            Dock(blizz, function(f) f:SetAllPoints(card) end, card:GetFrameLevel() + 3, card)
            if type(blizz.UnlearnButton) == "table" then
                Dock(blizz.UnlearnButton, function(f) f:SetPoint("LEFT", card.bar, "RIGHT", 6, 0) end,
                    card:GetFrameLevel() + 10)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Taking over from Blizzard's window
-------------------------------------------------------------------------------
local function Deactivate()
    if win then win:Hide() end
    if ProfessionsFrame then
        DockTabs(false)
        DockBook(false)
        ProfessionsFrame:SetAlpha(1)
    end
end

-- mode is "craft" (a profession's recipes) or "book" (the overview).
local function Activate(mode)
    local pf = ProfessionsFrame
    if not win then
        Build()
        win:SetFrameStrata(NextStrata(pf:GetFrameStrata()))
        win:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, 0)
    end
    pf:SetAlpha(0)
    -- Never narrower or shorter than Blizzard's window, so none of it is left clickable.
    -- Resizing waits for peace: the overview's secure buttons may hang off this window.
    if not InCombatLockdown() then
        win:SetSize(math.max(W, pf:GetWidth()), math.max(MIN_H, pf:GetHeight()))
    end
    if not win:IsShown() then
        selectedID, selectedUnlearned, offset = nil, nil, 0
        win:Show()
    end
    DockTabs(true)
    local book = mode == "book"
    win.search:SetShown(not book)
    win.filter:SetShown(not book)
    win.list:SetShown(not book)
    win.mid:SetShown(not book)
    win.rank:SetShown(not book)
    if book then win.rankBanner:Hide() end
    win.book:SetShown(book)
    DockBook(book)
    if book then
        RenderBook()
        Redock()
    else
        Render()
    end
end

-- The overview tab shows Blizzard's book page (invisible, like the rest of its window); the
-- keybind can open it with no profession open at all.
local function BookOpen()
    local book = ProfessionsFrame.BookPage
    return book and book:IsShown()
end

local function Update()
    if not (On() and ProfessionsFrame and ProfessionsFrame:IsShown() and Own()) then return Deactivate() end
    if BookOpen() then return Activate("book") end
    if Profession() then return Activate("craft") end
    Deactivate()
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Update()
    end)
end
ns.ProfWindowRefresh = Queue

-- A link clicked while Blizzard's window was loaded but closed makes Forever cast every one of
-- your own professions at once and land on the last, never the link's. A second click opens it,
-- so when the first one lands on your own profession, click it once more.
local RETRY_AFTER = 0.5
local retrying

-- The link view ends when the window closes (not the close the click itself may cause) or when
-- you open one of your own professions, which is a cast of its spell. Casts are only listened
-- to while a link is being viewed.
local casts = CreateFrame("Frame")

local function Settled()
    return viewingLink and GetTime() - linkClicked > 1
end

local function StopLinkView()
    viewingLink = nil
    casts:UnregisterAllEvents()
end

local function EndLinkView()
    if Settled() then StopLinkView() end
end

local function OwnProfessionSpell(spellID)
    local name = C_Spell.GetSpellName(spellID)
    if not name then return false end
    for _, index in pairs({ GetProfessions() }) do
        if GetProfessionInfo(index) == name then return true end
    end
    return spellID == SMELTING
end

casts:SetScript("OnEvent", function(_, _, _, _, spellID)
    -- Not the burst of casts the click itself set off.
    if Settled() and OwnProfessionSpell(spellID) then
        StopLinkView()
        Queue()
    end
end)

-- A trade link reads trade:<crafter GUID>:<spell>:<skill line>; your own links stay yours.
hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
    if not On() then return end
    local guid = type(link) == "string" and link:match("^trade:([^:]+)")
    if not guid or guid == UnitGUID("player") then return end
    viewingLink, linkClicked = true, GetTime()
    casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    Queue()
    if retrying then return end
    C_Timer.After(RETRY_AFTER, function()
        if not viewingLink or C_TradeSkillUI.IsTradeSkillLinked() then return end
        retrying = true
        SetItemRef(link, text, button, chatFrame)
        retrying = nil
    end)
end)

-- At a merchant: remember the reagents it sells for plain gold and without a stock limit.
-- With crafting profit on, also what each costs, for the reagent cost.
local function ScanMerchant()
    local learn, price = S.Get("vendorMaterials"), S.Get("craftProfit")
    if not (learn or price) then return end
    local learned, prices = LearnedVendorItems(), VendorPrices()
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        local cost, stack, available, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then
                cost, stack, available, extended = info.price, info.stackCount, info.numAvailable,
                    info.hasExtendedCost
            end
        else
            local _
            _, _, cost, stack, available, _, _, extended = GetMerchantItemInfo(i)
        end
        if itemID and (cost or 0) > 0 and available == -1 and not extended
            and select(12, C_Item.GetItemInfo(itemID)) == Enum.ItemClass.Tradegoods then
            if learn then learned[itemID] = true end
            if price then prices[itemID] = cost / math.max(stack or 1, 1) end
        end
    end
end

local merchant = CreateFrame("Frame")
merchant:RegisterEvent("MERCHANT_SHOW")
merchant:RegisterEvent("MERCHANT_UPDATE")
merchant:SetScript("OnEvent", ScanMerchant)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= "Blizzard_Professions" then return end
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if bookPending ~= nil then DockBook(bookPending) end
    end
    if not hooked and ProfessionsFrame then
        hooked = true
        ProfessionsFrame:HookScript("OnShow", Queue)
        ProfessionsFrame:HookScript("OnHide", function()
            EndLinkView()
            Deactivate()
        end)
        ProfessionsFrame:HookScript("OnSizeChanged", Queue)
        local book = ProfessionsFrame.BookPage
        if book then
            book:HookScript("OnShow", Queue)
            book:HookScript("OnHide", Queue)
            if book.Update then hooksecurefunc(book, "Update", Redock) end
            if book.FormatProfession then hooksecurefunc(book, "FormatProfession", Redock) end
        end
    end
    Queue()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then return Deactivate() end
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
        "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_NAME_UPDATE", "NEW_RECIPE_LEARNED",
        "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "PLAYER_REGEN_ENABLED",
        "PLAYERBANKSLOTS_CHANGED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
        "TRACKED_RECIPE_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_Professions") then events:RegisterEvent("ADDON_LOADED") end
    events:GetScript("OnEvent")(events, "APPLY")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" then Apply() end
    if key == "vendorMaterials" or key == "bagReagents" or key == "bankReagents" or key == "ahSearch"
        or key == "craftProfit" or key == "craftProfitList" or key == "buyMaterials" then
        Queue()
    end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-------------------------------------------------------------------------------
--  Settings page
-------------------------------------------------------------------------------
function ns.BuildProfessionsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    -- The window itself first, then buying and selling at the auction house, then the
    -- gathering reminder, which lives outside the window.
    _, h = W:SectionHeader(parent, "RECIPE WINDOW", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("recipeFinder", "Unlearned Recipes",
            "Lists the recipes you have not learned yet below your own. Click one to see the "
            .. "skill it needs, what it costs and where it comes from: the nearest trainers, the "
            .. "vendor selling its manual, or the mobs that drop it. Click a trainer or vendor "
            .. "to set a waypoint."),
        S.Toggle("rankAlert", "Next Rank Alert",
            "When a profession's skill is high enough for its next rank (Journeyman, Expert, "
            .. "Artisan), a banner under the skill bar and on its card in the overview says what "
            .. "it takes and who teaches it: the "
            .. "nearest trainer, book vendor or quest giver. Click Waypoint to mark them on your "
            .. "map. Reaching it also says so once in chat; /naowh profrank repeats that.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagReagents", "Reagents in Bags",
            "Adds a Bags column to the chosen recipe's reagents, showing how many of each you carry."),
        S.Toggle("bankReagents", "Reagents in Bank",
            "Adds a Bank column to the chosen recipe's reagents, showing how many of each are in "
            .. "your bank.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "BUYING AND SELLING", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("craftProfit", "Crafting Profit",
            "Once you have scanned the auction house (Scan Prices), the chosen recipe shows what "
            .. "its reagents cost to buy and what the item sells for, and the profit after the 5% "
            .. "auction house cut. Each reagent is priced at its cheapest: a vendor's price once "
            .. "you have seen a vendor sell it, else the lowest buyout at your last scan. Uncheck "
            .. "a reagent you already have to leave it out of the cost, for every recipe that "
            .. "uses it. Hover the lines for the breakdown."),
        S.Toggle("craftProfitList", "Profit in Recipe List",
            "Also shows each recipe's profit at the right of its row in the list, green or red. "
            .. "Recipes whose profit is not known show none.", "craftProfit")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("ahShiftClick", "Shift-Click Searches AH",
            "While the auction house is open, Shift-click a recipe or a reagent to search the "
            .. "auction house for the item: what the recipe makes, or the reagent. While you "
            .. "type in chat, Shift-click still links it.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("ahSearch", "Search AH Button",
            "While the auction house is open, a Search AH button next to the chosen recipe's "
            .. "name searches it for the item the recipe makes. Unlearned recipes also get "
            .. "Search Recipe, for the pattern, plans or manual that teaches it. Recipes that "
            .. "make no item, such as enchants, get no Search AH."),
        S.Toggle("vendorMaterials", "Crafts with Vendor Buys",
            "Adds a second, orange number next to each recipe: how many you could make after "
            .. "buying the reagents vendors sell, such as Weak Flux or Coarse Thread. The recipe's "
            .. "reagents then say how many of each to buy.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("buyMaterials", "Buy Materials",
            "While the auction house is open, a Buy button under the chosen recipe's reagents "
            .. "buys the materials for as many crafts as you set beside it: every checked reagent "
            .. "that vendors do not sell. Each one shows its price first and is only bought when "
            .. "you click Confirm."),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "GATHERING", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("gatherReminder", "Tracking Reminder",
            "Shows an icon on screen while you know Find Herbs, Find Minerals or Find Fish but are "
            .. "tracking none of them. Click it to start tracking: left-click for the first, "
            .. "right-click for the second, middle-click for the third. Hover it to see which is "
            .. "which. Hidden in combat. Move it in Unlock Mode."),
        S.Slider("gatherIconSize", "Icon Size", 24, 80, 1, nil, "gatherReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("gatherInInstances", "Show in Dungeons and Raids",
            "Also reminds you inside instances. Off by default: few have herbs or ore.",
            "gatherReminder"),
        S.Toggle("gatherFish", "Include Find Fish",
            "Counts Find Fish as a tracking to remind you of, once you have learned it. Turn "
            .. "off if you only track fish now and then.", "gatherReminder")
    ); y = y - h

    return y
end
