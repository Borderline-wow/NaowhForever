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

-- `enabled` is the sidebar switch for the whole module; off leaves Blizzard's window alone.
local S = UI.ModuleSettings("professions", {
    enabled = true,
    -- Recipe Window: all off until switched on.
    recipeFinder = false, rankAlert = false, bagReagents = false, bankReagents = false,
    vendorMaterials = false,
    -- Craft Orders: another player's linked profession in this window, to order crafts from.
    craftOrders = false, orderTip = 10,
    -- Crafting several at once shows the batch's time on the flight timer's bar.
    craftTimer = false,
    craftTimerFont = "", craftTimerFontSize = 14, craftTimerOutline = "OUTLINE", craftTimerTexture = "",
    craftTimerBgAlpha = 0.9,
    -- Materials for crafts added from the recipe pane, bought together at the auction house.
    shoppingList = false,
    -- Favourites not learned yet: offered at their trainer, their patterns listed at the AH.
    trainFavorites = false, searchFavoritesAH = false,
    -- Gathering: all off until switched on.
    gatherReminder = false, gatherInInstances = false, gatherIconSize = 40, gatherFish = false,
    gatherFont = "", gatherFontSize = 13, gatherOutline = "OUTLINE",
    -- Buying and Selling: all off until switched on.
    ahSearch = false, ahShiftClick = false, craftProfit = false, craftProfitList = false,
    buyMaterials = false, buyVendor = false,
    filterMaterials = false, filterSkillUp = false, filterProfit = false,
    filterBoE = false, filterBoP = false, filterFavorite = false,
})
ns.ProfessionSettings = S

local MIN_H, PAD = 620, 8
-- The list is wide enough for a recipe name, its count and a full profit ("-12g 07s 09c").
local LEFT_W, MID_W = 340, 400
local MID_X = PAD + LEFT_W + PAD
local W = MID_X + MID_W + PAD
-- Another player's profession adds the order column on the right.
local ORDER_W = 260
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
local Reuse = { prof = {}, cats = {}, byID = {}, learned = {}, pool = {}, shown = {}, shownU = {},
    inGroup = {}, lines = {}, parts = {}, reagents = {}, waiting = {}, none = {}, status = {}, queued = false,
    quiet = { ITEM_DATA_LOAD_RESULT = true, BAG_UPDATE_DELAYED = true, PLAYERBANKSLOTS_CHANGED = true,
        AUCTION_HOUSE_SHOW = true, AUCTION_HOUSE_CLOSED = true, TRACKED_RECIPE_UPDATE = true,
        GROUP_ROSTER_UPDATE = true },
    reread = { APPLY = true, ADDON_LOADED = true, TRADE_SKILL_SHOW = true, TRADE_SKILL_CLOSE = true,
        TRADE_SKILL_DATA_SOURCE_CHANGED = true, TRADE_SKILL_NAME_UPDATE = true, NEW_RECIPE_LEARNED = true,
        SKILL_LINES_CHANGED = true, TRADE_SKILL_FAVORITES_CHANGED = true },
    stale = true, listChanged = false, count = 0, sig = {}, BURST = 0.1 }
ns.ProfBagChanges = 0
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
-- The GUID in the last clicked link, for the crafter's name when the game does not give it.
local linkGUID
-- Set while the window shows another player's profession, to order crafts from.
local linkedMode = false

local function Own()
    if viewingLink then return false end
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then return false end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return false end
    return true
end

-- Another player's profession from a link, with Craft Orders on. A guild's or an NPC's
-- crafting stays Blizzard's.
local function Linked()
    if not S.Get("craftOrders") then return false end
    if C_TradeSkillUI.IsTradeSkillGuild() then return false end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return false end
    return C_TradeSkillUI.IsTradeSkillLinked() == true
end

local function Profession()
    local child, base = C_TradeSkillUI.GetChildProfessionInfo(), C_TradeSkillUI.GetBaseProfessionInfo()
    local src = (child and (child.maxSkillLevel or 0) > 0) and child or base
    if not src then return end
    local p = Reuse.prof
    p.id = base and base.professionID or src.professionID
    p.name = (base and base.professionName) or src.professionName or ""
    p.skill = src.skillLevel or 0
    p.max = src.maxSkillLevel or 0
    return p
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
function Reuse.ByOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
end

local function Collect()
    wipe(categories)
    local byID, learned, used = Reuse.byID, Reuse.learned, 0
    wipe(byID)
    wipe(learned)
    local ids = C_TradeSkillUI.GetAllRecipeIDs() or Reuse.none
    Reuse.count = #ids
    for _, id in ipairs(ids) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info then
            learned[id] = info.learned and true or false
            info.numAvailable = nil
        end
        if info and info.learned then
            local catID = info.categoryID or 0
            local cat = byID[catID]
            if not cat then
                local ci = catID > 0 and C_TradeSkillUI.GetCategoryInfo(catID)
                used = used + 1
                cat = Reuse.cats[used]
                if not cat then
                    cat = { recipes = {}, sub = true }
                    Reuse.cats[used] = cat
                end
                cat.id, cat.name, cat.order = catID, ci and ci.name or OTHER or "Other", ci and ci.uiOrder or 999
                wipe(cat.recipes)
                byID[catID] = cat
                categories[#categories + 1] = cat
            end
            cat.recipes[#cat.recipes + 1] = info
        end
    end
    table.sort(categories, Reuse.ByOrder)
    unlearned = not linkedMode and ns.RecipeFinder and ns.RecipeFinder.Unlearned(learned) or Reuse.none
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
-- Buy at Vendor, filled in after Buy on AH: the open merchant's reagents for a recipe.
local Vendor = {}

function Reuse.Add(kind, value)
    local n = #entries + 1
    local e = Reuse.pool[n]
    if not e then
        e = {}
        Reuse.pool[n] = e
    end
    e.cat, e.recipe, e.unlearned = nil, nil, nil
    e[kind] = value
    entries[n] = e
end

local function BuildEntries()
    wipe(entries)
    local first, found
    local learnedAt, learnedCount = #entries + 1, 0
    Reuse.Add("cat", LEARNED)
    local learnedOpen = not IsCollapsed(LEARNED)
    local shown = Reuse.shown
    for _, cat in ipairs(categories) do
        wipe(shown)
        for _, info in ipairs(cat.recipes) do
            if Matches(info) and PassesFilter(info) then shown[#shown + 1] = info end
        end
        if #shown > 0 then
            learnedCount = learnedCount + #shown
            if learnedOpen then Reuse.Add("cat", cat) end
            -- A search opens every category, so a match is never hidden in a closed one.
            local open = learnedOpen and not IsCollapsed(cat)
            for _, info in ipairs(shown) do
                first = first or info.recipeID
                if info.recipeID == selectedID then found = true end
                if open then Reuse.Add("recipe", info) end
            end
        end
    end
    LEARNED.count = learnedCount
    if learnedCount == 0 then entries[learnedAt] = nil end

    local shownU, foundU = Reuse.shownU, false
    wipe(shownU)
    for _, r in ipairs(unlearned) do
        if (query == "" or (C_Spell.GetSpellName(r.spell) or ""):lower():find(query, 1, true))
            and PassesFilter(nil, r) then
            shownU[#shownU + 1] = r
            Reuse.status[r] = ns.RecipeFinder.Status(r)
        end
    end
    if #shownU > 0 then
        UNLEARNED.count = #shownU
        Reuse.Add("cat", UNLEARNED)
        local open = not IsCollapsed(UNLEARNED)
        local inGroup = Reuse.inGroup
        for _, group in ipairs(UNLEARNED_GROUPS) do
            wipe(inGroup)
            for _, r in ipairs(shownU) do
                if Reuse.status[r] == group.status then inGroup[#inGroup + 1] = r end
            end
            group.count = #inGroup
            if open and #inGroup > 0 then Reuse.Add("cat", group) end
            local groupOpen = open and not IsCollapsed(group)
            for _, r in ipairs(inGroup) do
                if r == selectedUnlearned then foundU = true end
                if groupOpen then Reuse.Add("unlearned", r) end
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
-- pair is the older one, kept as a fallback in case Forever still answers only that. A
-- recipe's reagents never change, so the schematic's list is read once and shared: callers
-- only read it.
local function Reagents(recipeID)
    local cached = Reuse.reagents[recipeID]
    if cached then return cached end
    local out
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if ok and schematic and schematic.reagentSlotSchematics then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local reagent = slot.reagents and slot.reagents[1]
            if slot.required ~= false and reagent and reagent.itemID then
                out = out or {}
                out[#out + 1] = { itemID = reagent.itemID, need = slot.quantityRequired or 1 }
            end
        end
        Reuse.reagents[recipeID] = out
        return out or Reuse.none
    end
    if C_TradeSkillUI.GetRecipeNumReagents then
        for i = 1, C_TradeSkillUI.GetRecipeNumReagents(recipeID) or 0 do
            local _, _, need = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, i)
            local link = C_TradeSkillUI.GetRecipeReagentItemLink(recipeID, i)
            local itemID = link and C_Item.GetItemInfoInstant(link)
            if itemID then
                out = out or {}
                out[#out + 1] = { itemID = itemID, need = need or 1 }
            end
        end
    end
    return out or Reuse.none
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

-- An item's name, or nil while the client has yet to load it; ITEM_DATA_LOAD_RESULT for an
-- item asked for here then redraws the window, once it has loaded.
function Reuse.Request(itemID)
    Reuse.waiting[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end
ns.ProfRequestItem = Reuse.Request

local function ItemName(itemID)
    local name = itemID and C_Item.GetItemNameByID(itemID)
    if itemID and not name then Reuse.Request(itemID) end
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
-- RenderProfit sizes the columns to what they hold, from the starting widths here.
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

-- For the shopping list (NaowhForever_ShoppingList.lua), which adds its row to the recipe
-- pane: the chosen recipe, its reagents, and which of them Buy on AH would buy.
ns.ProfWindowAPI = { SelectedInfo = SelectedInfo, Reagents = Reagents, Owned = Owned,
    IsVendorItem = IsVendorItem, Linked = function() return linkedMode end, Own = Own }

-- What one craft costs in bought reagents and fetches on the auction house after its cut,
-- filled into `v` (its block's own table). `sale` is nil when the item had no listing at the
-- last scan, or makes no item at all.
local function CraftValue(recipeID, output, made, v)
    v.cost, v.missing, v.owned, v.output, v.made = 0, 0, 0, output, made or 1
    local ok, reagents = pcall(Reagents, recipeID)
    local owned, n = Owned(), 0
    for _, r in ipairs(ok and reagents or Reuse.none) do
        local each, from = BuyPrice(r.itemID)
        local have = owned[r.itemID] == true
        n = n + 1
        local p = v.parts[n] or {}
        v.parts[n] = p
        p.itemID, p.need, p.each, p.from, p.owned = r.itemID, r.need, each, from, have
        if have then
            v.owned = v.owned + 1
        elseif each then
            v.cost = v.cost + each * r.need
        else
            v.missing = v.missing + 1
        end
    end
    for i = n + 1, #v.parts do v.parts[i] = nil end
    local each = output and ns.AuctionPrice and ns.AuctionPrice(output)
    v.each = each
    v.sale = each and math.floor(each * v.made * (1 - AH_CUT))
    return v
end

-- "12g 07s 09c", "6s 00c", "8c": from the largest coin down to copper, the smaller coins two
-- digits wide so amounts line up. Plain text: the letters take the amount's own colour.
-- `plus` puts a "+" before an amount that is not negative.
local COINS = { { 10000, "g" }, { 100, "s" }, { 1, "c" } }
local function Money(copper, plus)
    local left = math.floor(math.abs(copper) + 0.5)
    local g, s, c = math.floor(left / 10000), math.floor(left % 10000 / 100), left % 100
    local sign = copper < 0 and "-" or plus and "+" or ""
    if g > 0 then return ("%s%dg %02ds %02dc"):format(sign, g, s, c) end
    if s > 0 then return ("%s%ds %02dc"):format(sign, s, c) end
    return ("%s%dc"):format(sign, c)
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
        profit = false
        local each = ns.AuctionPrice and ns.AuctionPrice(output)
        local ok, reagents = pcall(Reagents, recipeID)
        if each and ok and #reagents > 0 then
            local owned, cost, missing = Owned(), 0, 0
            for _, r in ipairs(reagents) do
                if owned[r.itemID] ~= true then
                    local price = BuyPrice(r.itemID)
                    if price then
                        cost = cost + price * r.need
                    else
                        missing = missing + 1
                    end
                end
            end
            if missing == 0 then profit = math.floor(each * (made or 1) * (1 - AH_CUT)) - cost end
        end
        profitCache[recipeID] = profit
    end
    return profit or nil
end

-- "" when the list profit is off or not known; the row's font takes the colour.
local function ListProfit(recipeID, output, made)
    -- Not in another player's list: you are ordering those, not crafting to sell.
    local profit = not linkedMode and S.Get("craftProfitList") and RecipeProfit(recipeID, output, made)
    if not profit then return "", T.fg end
    return Money(profit, true), profit >= 0 and PROFIT_GREEN or RED
end

-------------------------------------------------------------------------------
--  Filter
-------------------------------------------------------------------------------
-- The Filter menu, as in Blizzard's window, plus Profitable. Have Materials and Has Skill-Up
-- concern the recipes you know; an unlearned recipe cannot be made, so Have Materials hides
-- those too. Below a divider, how the item made binds (C_Item.GetItemInfo's bindType: 1 on
-- pickup, 2 on equip, 0 never; never counts as on equip for now, see PassesFilter).
local FILTERS = {
    { key = "filterFavorite", text = "Favorites" },
    { key = "filterMaterials", text = "Have Materials" },
    { key = "filterSkillUp", text = "Has Skill-Up" },
    { key = "filterProfit", text = "Profitable", profit = true },
    { key = "filterBoE", text = "Bind on Equip", bind = 2, divider = true },
    { key = "filterBoP", text = "Bind on Pickup", bind = 1 },
}
for _, f in ipairs(FILTERS) do FILTERS[f.key] = f end

-- Favourite recipes: kept in the profile (craftFavorites), by spell ID, which is also a known
-- recipe's recipeID. A known one is told to the game as well, so a favourite set in Blizzard's
-- own window counts too; an unlearned one (a RecipeData row) lives only here, and the trainer
-- and auction house reminders (NaowhForever_FavoriteRecipes.lua) read it.
FILTERS.favorites = {}
ns.ProfFavorites = FILTERS.favorites

function FILTERS.favorites.Store()
    local db = S.DB()
    if type(db.craftFavorites) ~= "table" then db.craftFavorites = {} end
    return db.craftFavorites
end

-- `info` is a known recipe's info, or an unlearned recipe's RecipeData row.
function FILTERS.favorites.Is(info)
    if not info then return false end
    local own = FILTERS.favorites.Store()[info.recipeID or info.spell]
    if own ~= nil then return own end
    return info.favorite == true
end

function FILTERS.favorites.Toggle(info)
    if not info then return end
    local on = not FILTERS.favorites.Is(info)
    FILTERS.favorites.Store()[info.recipeID or info.spell] = on
    if not info.recipeID then return end
    info.favorite = on
    if C_TradeSkillUI.SetRecipeFavorite then pcall(C_TradeSkillUI.SetRecipeFavorite, info.recipeID, on) end
end

-- The favourite star before an unlearned recipe's name, in the pane saying where to learn it.
function FILTERS.favorites.BuildLearnStar(l)
    l.fav = CreateFrame("Button", nil, l)
    l.fav:SetSize(18, 18)
    l.fav:SetPoint("TOPLEFT", l.icon, "TOPRIGHT", 10, 0)
    l.fav.tex = l.fav:CreateTexture(nil, "ARTWORK")
    l.fav.tex:SetAllPoints()
    -- RenderList and RenderDetail are declared further down, so the window redraws through
    -- its refresh instead.
    l.fav:SetScript("OnClick", function()
        if not selectedUnlearned then return end
        FILTERS.favorites.Toggle(selectedUnlearned)
        if ns.ProfWindowRefresh then ns.ProfWindowRefresh() end
    end)
    ns.Tooltip(l.fav, "Favorite", "Makes this recipe a favourite, or no longer one. With Train "
        .. "Favorites on, a trainer who teaches it offers it when you visit; with Search Favorites "
        .. "AH on, its pattern, plans or manual is listed at the auction house to search for.")
end

-- A star texture, filled for a favourite and hollow for not: the auction house's star,
-- else the reputation star's two halves.
function FILTERS.favorites.Star(texture, on)
    local atlas = on and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off"
    if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        texture:SetDesaturated(false)
        texture:SetAlpha(1)
    else
        texture:SetTexture("Interface\\COMMON\\ReputationStar")
        texture:SetTexCoord(on and 0 or 0.5, on and 0.5 or 1, 0, 0.5)
    end
end

-- Profitable only counts while there are prices to judge by.
local function FilterOn(f)
    return S.Get(f.key) and (not f.profit or ProfitShown())
end

PassesFilter = function(info, r)
    -- The filters are about your own crafting; another player's list shows everything.
    if linkedMode then return true end
    -- Favorites: only your favourites, learned or not.
    if FilterOn(FILTERS.filterFavorite) and not FILTERS.favorites.Is(info or r) then return false end
    -- Bind on Equip or Pickup: the item made has to bind one of the ticked ways. An item not
    -- loaded yet is asked for; ITEM_DATA_LOAD_RESULT then redraws the list.
    local boe, bop = FilterOn(FILTERS.filterBoE), FilterOn(FILTERS.filterBoP)
    if boe or bop then
        local item
        if info then
            item = OutputItem(info.recipeID)
        else
            item = r.item or OutputItem(r.spell)
        end
        local bind = item and select(14, C_Item.GetItemInfo(item))
        if item and bind == nil then Reuse.Request(item) end
        -- On the beta much crafted gear does not bind at all and still sells on the auction
        -- house, so for now an item that never binds (0) counts as Bind on Equip too.
        local asBoE = bind == FILTERS.filterBoE.bind or bind == 0
        if not ((boe and asBoE) or (bop and bind == FILTERS.filterBoP.bind)) then
            return false
        end
    end
    if info then
        if FilterOn(FILTERS.filterMaterials) and Craftable(info) == 0 then return false end
        if FilterOn(FILTERS.filterSkillUp) and info.relativeDifficulty == TRIVIAL then return false end
        if FilterOn(FILTERS.filterProfit) then
            local profit = RecipeProfit(info.recipeID, OutputItem(info.recipeID))
            if not (profit and profit > 0) then return false end
        end
        return true
    end
    if FilterOn(FILTERS.filterMaterials) then return false end
    if FilterOn(FILTERS.filterProfit) then
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

local function SetProfitLine(line, label, value, note)
    line.label:SetText(label or "")
    line.value:SetText(value or "")
    line.note:SetText(note or "")
    line:SetShown(value ~= nil)
end

-- The columns fit what they hold: the amounts end together right after the longest label,
-- as wide as the longest amount, with the notes straight after.
local function FitProfitLines(lines)
    local labelW, valueW = 0, 0
    for _, line in ipairs(lines) do
        if line:IsShown() then
            labelW = math.max(labelW, line.label:GetStringWidth())
            valueW = math.max(valueW, line.value:GetStringWidth())
        end
    end
    for _, line in ipairs(lines) do
        line.value:ClearAllPoints()
        line.value:SetPoint("LEFT", math.ceil(labelW) + PROFIT_GAP, 0)
        line.value:SetWidth(math.ceil(valueW) + 1)
    end
end

-- Three lines under a recipe: what its reagents cost to buy, what it sells for, and the
-- profit. Hidden until the auction house has been scanned on this realm and faction.
local function RenderProfit(block, recipeID, output, made)
    if not (S.Get("craftProfit") and ns.AuctionScanTime and ns.AuctionScanTime()) then
        block.value = nil
        return block:Hide()
    end
    local v = CraftValue(recipeID, output, made, block.calc)
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
            profit = Hex(p >= 0 and PROFIT_GREEN or RED) .. Money(p, true) .. "|r"
            profitNote = "after the 5% cut"
        end
    end
    SetProfitLine(block.sell, "Sell for:", sell, sellNote)
    SetProfitLine(block.profit, "Profit:", profit, profitNote)
    FitProfitLines(block.lines)
    block:Show()
end

-------------------------------------------------------------------------------
--  Craft orders
-------------------------------------------------------------------------------
-- In another player's profession: pick the crafts you want from them and how many, tick the
-- materials you bring, and send them the order, one message per craft. Orders are kept per
-- crafter until sent (or a reload), so closing the link and opening it again keeps them.
-- One table for all of it: the file is close to Lua's limit of 200 locals.
local Order = {
    MAX = 9,
    MIN_TIP = 100,      -- 1s
    GAP = 0.4,          -- seconds between the whispers of one order
    MAX_MSG = 255,      -- a chat message's length, item links counted in full
    byCrafter = {},
    -- Whispered with Invite, one picked at random.
    INVITE_LINES = {
        "Hi! Inviting you to my group for some crafts from your profession.",
        "Hey, sending you an invite. I'd like to order a few crafts from you.",
        "Hi there! Invite incoming, got some crafting work for you if you're up for it.",
        "Hey! Saw your profession, inviting you so I can ask for a few crafts.",
        "Hello! Mind joining my group? I'd like a few things crafted, with a tip of course.",
        "Hi! Sent you an invite for some crafts, easier to sort out in party chat.",
    },
    -- How each craft of an order is asked for, one picked at random: the count, then the item.
    ASK_LINES = {
        "Could you craft %dx %s for me?",
        "Would you make %dx %s for me?",
        "Could I get %dx %s from you?",
        "Any chance you could craft %dx %s?",
        "Would you mind making %dx %s for me?",
        "Can you make %dx %s for me?",
    },
    last = {},
}

-- One of `lines` at random, never the one picked from them last time.
function Order.Pick(lines)
    local last = Order.last[lines]
    local pick = math.random(#lines - (last and 1 or 0))
    if last and pick >= last then pick = pick + 1 end
    Order.last[lines] = pick
    return lines[pick]
end

-- Who the open link belongs to, "Name" or "Name-Realm".
function Order.Crafter()
    local _, name = C_TradeSkillUI.IsTradeSkillLinked()
    if type(name) == "string" and name ~= "" then return name end
    if linkGUID then
        local _, _, _, _, _, n, realm = GetPlayerInfoByGUID(linkGUID)
        if n and n ~= "" then return (realm and realm ~= "") and (n .. "-" .. realm) or n end
    end
end

function Order.Get()
    local who = Order.Crafter()
    if not who then return end
    local o = Order.byCrafter[who]
    if not o then
        o = { who = who, list = {}, drafts = {} }
        Order.byCrafter[who] = o
    end
    -- The link's GUID finds them in your group whatever form the name comes in.
    if linkedMode and linkGUID then o.guid = linkGUID end
    return o
end

-- A recipe's order line: made the first time the recipe is chosen, on the order once added.
-- It keeps what it needs to show and whisper after the link is closed.
function Order.Draft(info)
    local o = info and Order.Get()
    if not o then return end
    local d = o.drafts[info.recipeID]
    if not d then
        local output, made = OutputItem(info.recipeID)
        d = { recipeID = info.recipeID, name = info.name, icon = info.icon, output = output,
            made = made or 1, reagents = Reagents(info.recipeID), crafts = 1, bring = {} }
        o.drafts[info.recipeID] = d
    end
    if #d.reagents == 0 then d.reagents = Reagents(info.recipeID) end
    return d
end

function Order.Index(o, d)
    for i, e in ipairs(o.list) do
        if e == d then return i end
    end
end

-- How many of a reagent you bring: all the crafts need once ticked (true), or the number
-- typed, never more than they need.
function Order.Bringing(d, r)
    local total = r.need * d.crafts
    local b = d.bring[r.itemID]
    if b == true then return total end
    return math.min(b or 0, total)
end

-- Rounded as a tip is paid: to the silver under 1g, to 10s under 10g, else to the gold.
function Order.Round(copper)
    local step = copper < 10000 and 100 or copper < 100000 and 1000 or 10000
    return math.floor(copper / step + 0.5) * step
end

-- What an order line is worth: the materials the crafter puts in, what the items sell for,
-- and the suggested tip, which pays back their materials plus a share (orderTip %) of what
-- the items sell for, or of all the materials for a recipe that makes no item.
function Order.Value(d)
    local v = { theirs = 0, all = 0, missing = 0, theirsCount = 0, bringCount = 0, parts = {} }
    for _, r in ipairs(d.reagents) do
        local total = r.need * d.crafts
        local mine = Order.Bringing(d, r)
        local each, from = BuyPrice(r.itemID)
        v.parts[#v.parts + 1] = { itemID = r.itemID, total = total, mine = mine, each = each, from = from }
        if mine > 0 then v.bringCount = v.bringCount + 1 end
        if total > mine then v.theirsCount = v.theirsCount + 1 end
        if each then
            v.theirs = v.theirs + each * (total - mine)
            v.all = v.all + each * total
        else
            v.missing = v.missing + 1
        end
    end
    local each = d.output and ns.AuctionPrice and ns.AuctionPrice(d.output)
    v.value = each and each * d.made * d.crafts
    v.pct = S.Get("orderTip") or 10
    local base = v.value or (v.missing == 0 and v.all > 0 and v.all) or nil
    if base then
        local share = v.pct > 0 and math.max(Order.MIN_TIP, base * v.pct / 100) or 0
        v.pay = Order.Round(v.theirs + share)
    end
    return v
end

-- The tip you set for a line, else the suggested one.
function Order.Pay(d, v)
    return d.tip or v.pay
end

-- "2g 50s", "35s", "8c": for chat, leaving out the coins that are zero.
function Order.Short(copper)
    copper = math.floor(copper + 0.5)
    local parts = {}
    for _, coin in ipairs(COINS) do
        local n = math.floor(copper / coin[1])
        copper = copper - n * coin[1]
        if n > 0 then parts[#parts + 1] = n .. coin[2] end
    end
    return #parts > 0 and table.concat(parts, " ") or "0c"
end

-- A typed tip: "2g 50s", "2g50s", "75s", or a plain number of gold ("2.5"). Nil when empty or
-- not an amount.
function Order.Parse(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" then return end
    local gold = tonumber(text)
    if gold then return math.max(0, math.floor(gold * 10000 + 0.5)) end
    -- Every part must be an amount with its coin ("2.5g", "1g50s"): anything left over is not a tip.
    local total, bad = 0, false
    local rest = text:gsub("([%d%.]+)([gsc])", function(n, coin)
        n = tonumber(n)
        if not n then bad = true return "" end
        total = total + n * (coin == "g" and 10000 or coin == "s" and 100 or 1)
        return ""
    end)
    if bad or rest ~= "" then return end
    return math.floor(total + 0.5)
end

function Order.Link(itemID, fallback)
    local _, link = C_Item.GetItemInfo(itemID)
    return link or ("[" .. (C_Item.GetItemNameByID(itemID) or fallback or ("Item " .. itemID)) .. "]")
end

-- An order line's messages: one, or more when the item links run past what one message
-- holds. In party chat each starts with the crafter's name, so the group sees who it is for.
--   Could you craft 5x [Heavy Silk Bandage] for me? I bring 10x [Silk Cloth]. Tip: 2g 50s.
function Order.Messages(d, name)
    local v = Order.Value(d)
    local what = d.output and Order.Link(d.output, d.name)
        or C_TradeSkillUI.GetRecipeLink(d.recipeID) or ("[" .. (d.name or "?") .. "]")
    local ask = Order.Pick(Order.ASK_LINES):format(d.crafts, what)
    -- "Name, could you craft..." in party chat.
    if name then ask = name .. ", " .. ask:sub(1, 1):lower() .. ask:sub(2) end
    local pieces = { ask }
    local mats = {}
    for _, p in ipairs(v.parts) do
        if p.mine > 0 then
            mats[#mats + 1] = ("%dx %s"):format(p.mine, Order.Link(p.itemID))
                .. (p.mine < p.total and (" (of %d)"):format(p.total) or "")
        end
    end
    if #mats == 0 then
        pieces[#pieces + 1] = "No materials from me."
    else
        pieces[#pieces + 1] = "I bring"
        for i, m in ipairs(mats) do pieces[#pieces + 1] = m .. (i < #mats and "," or ".") end
    end
    local pay = Order.Pay(d, v)
    if pay and pay > 0 then
        pieces[#pieces + 1] = ("Tip: %s."):format(Order.Short(pay))
    end
    local out, line = {}, ""
    for _, piece in ipairs(pieces) do
        local joined = line == "" and piece or (line .. " " .. piece)
        if #joined > Order.MAX_MSG and line ~= "" then
            out[#out + 1] = line
            line = piece
        else
            line = joined
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end

-- "party" or "raid" when the crafter is in your group, else nil. Matched by the link's GUID,
-- else by name with your own realm left off: the link may name them "Name-Realm" where the
-- group says "Name".
function Order.Grouped(o)
    if not (o and IsInGroup()) then return end
    local raid = IsInRaid()
    local want = Ambiguate(o.who, "none")
    for i = 1, raid and GetNumGroupMembers() or GetNumSubgroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        local guid = UnitGUID(unit)
        local name = GetUnitName(unit, true)
        if (o.guid and guid == o.guid) or (name and Ambiguate(name, "none") == want) then
            return raid and "raid" or "party"
        end
    end
end

-- Where the order goes: party chat (instance chat in a dungeon-finder group) when the
-- crafter is in your party, else a whisper; in a raid too, where it would reach everyone.
function Order.Channel(o)
    if Order.Grouped(o) ~= "party" then return "WHISPER" end
    return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
end

-- Sends the whole order, a moment apart so chat does not throttle it, and empties it.
function Order.Send()
    local o = Order.Get()
    if not (o and #o.list > 0) then return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local who = o.who
    local channel = Order.Channel(o)
    local short = Ambiguate(who, "short")
    local messages = {}
    for _, d in ipairs(o.list) do
        for _, m in ipairs(Order.Messages(d, channel ~= "WHISPER" and short or nil)) do
            messages[#messages + 1] = m
        end
    end
    for i, m in ipairs(messages) do
        C_Timer.After((i - 1) * Order.GAP, function()
            send(m, channel, nil, channel == "WHISPER" and who or nil)
        end)
    end
    o.sent = ("Asked %s %sfor %s."):format(short, channel == "WHISPER" and ""
        or channel == "INSTANCE_CHAT" and "in instance chat " or "in party chat ",
        #o.list == 1 and "1 craft" or (#o.list .. " crafts"))
    wipe(o.list)
    wipe(o.drafts)
end

-------------------------------------------------------------------------------
--  Rendering
-------------------------------------------------------------------------------
local Render, RenderList, RenderDetail, RenderLearn

-- "x5" in the count column for a recipe on the order.
function Order.Count(recipeID)
    local o = Order.Get()
    local d = o and o.drafts[recipeID]
    if d and Order.Index(o, d) then return Hex(T.accent) .. "x" .. d.crafts .. "|r" end
    return ""
end

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
                row.fav:Hide()
                row.text:SetPoint("RIGHT", row.profit, "LEFT", -6, 0)
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
                local fav = FILTERS.favorites.Is(r)
                row.fav:SetShown(fav)
                row.text:SetPoint("RIGHT", fav and row.fav or row.profit, "LEFT", fav and -4 or -6, 0)
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
                row.count:SetText(linkedMode and Order.Count(info.recipeID) or FormatCraftCount(info))
                local fav = not linkedMode and FILTERS.favorites.Is(info)
                row.fav:SetShown(fav)
                row.text:SetPoint("RIGHT", fav and row.fav or row.profit, "LEFT", fav and -4 or -6, 0)
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
        or (S.Get("buyVendor") and Vendor.Open())
    local owned = Owned()
    for i, r in ipairs(rows) do
        local data = i <= max and reagents[i]
        if data then
            local name = C_Item.GetItemNameByID(data.itemID)
            if not name then Reuse.Request(data.itemID) end
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
            r.draft = nil
            r.bringRow:Hide()
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

-- The reagent rows of an order line: a box to tick for each material you bring, how many you
-- bring beside it, and how many the crafts need against what your bags hold.
function Order.FillReagents(rows, d)
    for i, r in ipairs(rows) do
        local data = d.reagents[i]
        if data then
            local name = ItemName(data.itemID)
            local total, mine = data.need * d.crafts, Order.Bringing(d, data)
            local have = ItemCount(data.itemID)
            r.itemID, r.draft = data.itemID, d
            r.icon:SetTexture(C_Item.GetItemIconByID(data.itemID))
            r.check:Show()
            r.check:SetChecked(mine > 0)
            r.icon:ClearAllPoints()
            r.icon:SetPoint("LEFT", r.check, "RIGHT", 6, 0)
            r.icon:SetDesaturated(false)
            r.count:SetText(("%d needed   %s%d in bags|r"):format(total,
                Hex(have >= mine and T.muted or RED), have))
            SetColor(r.count, T.fg)
            r.bagsLabel:Hide()
            r.bags:Hide()
            r.bankLabel:Hide()
            r.bank:Hide()
            r.bringRow:Show()
            if not r.bring:HasFocus() then r.bring:SetText(tostring(mine)) end
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -2)
            r.name:SetPoint("RIGHT", r.bringRow, "LEFT", -8, 0)
            r.vendor = IsVendorItem(data.itemID)
            r.name:SetText((name or "") .. (r.vendor and "  " .. VENDOR_ICON or ""))
            r:Show()
        else
            r.draft = nil
            r:Hide()
        end
    end
end

-- The chosen recipe's order line, or nil outside another player's profession.
function Order.Current()
    return linkedMode and Order.Draft(SelectedInfo()) or nil
end

-- The crafter's materials and the tip, for the chosen recipe. What the items sell for only
-- goes into the suggested tip: you are ordering them, not crafting to sell.
Order.RenderValue = function()
    local block = win.detail.orderValue
    local d = Order.Current()
    if not d or #d.reagents == 0 then
        block.value = nil
        return block:Hide()
    end
    local v = Order.Value(d)
    block.value = v
    local none = Hex(T.muted) .. "-|r"
    SetProfitLine(block.theirs, "Their materials:", Money(v.theirs),
        v.missing > 0 and ("+ %d unpriced"):format(v.missing)
        or v.theirsCount == 0 and "you bring them all" or nil)
    if d.tip then
        SetProfitLine(block.pay, "Your tip:", Money(d.tip),
            v.pay and ("suggested %s"):format(Money(v.pay)) or nil)
    else
        SetProfitLine(block.pay, "Suggested tip:", v.pay and Money(v.pay) or none,
            v.pay and ("their materials + %d%%"):format(v.pct) or "scan the auction house first")
    end
    FitProfitLines(block.lines)
    block:Show()
end

-- The middle column in another player's profession: the reagents to tick, the amounts, and
-- "- [n] + Add to Order" in place of the craft buttons.
function Order.RenderDetail(info)
    local d = win.detail
    local draft = Order.Draft(info)
    d.track:Hide()
    d.buyRow:Hide()
    d.orderRow:SetShown(draft ~= nil)
    d.bringHead:SetShown(draft ~= nil and #draft.reagents > 0)
    if not draft then
        FillReagents(d.reagents, {}, nil, 0)
        return Order.RenderValue()
    end
    Order.FillReagents(d.reagents, draft)
    Order.RenderValue()
    if not d.orderQty:HasFocus() then d.orderQty:SetText(tostring(draft.crafts)) end
    local o = Order.Get()
    local added = Order.Index(o, draft)
    ns.SetButtonText(d.orderAdd, added and "Remove" or "Add to Order")
    EnableButton(d.orderAdd, added ~= nil or #o.list < Order.MAX)
end

-- The order column: every craft on the order with its tip, and Ask.
Order.Render = function()
    local p = win and win.order
    if not (p and linkedMode) then return end
    local o = Order.Get()
    local list = o and o.list or {}
    p.title:SetText(o and Ambiguate(o.who, "short") or "")
    -- Greyed out once they are in your group, or while you may not invite.
    local mayInvite = not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    p.invite:SetShown(o ~= nil)
    EnableButton(p.invite, o ~= nil and not Order.Grouped(o) and mayInvite)
    local total = 0
    for i, row in ipairs(p.rows) do
        local d = list[i]
        row.draft = d
        if d then
            local v = Order.Value(d)
            row.icon:SetTexture(d.icon or (d.output and C_Item.GetItemIconByID(d.output)))
            row.name:SetText(("%dx %s"):format(d.crafts, d.name or ""))
            local sub
            if #v.parts == 0 then
                sub = ""
            elseif v.bringCount == 0 then
                sub = "No materials from you"
            elseif v.theirsCount == 0 then
                sub = "You bring all materials"
            else
                sub = ("You bring %d of %d materials"):format(v.bringCount, #v.parts)
            end
            row.sub:SetText(sub)
            local pay = Order.Pay(d, v)
            total = total + (pay or 0)
            if not row.tip:HasFocus() then row.tip:SetText(pay and pay > 0 and Order.Short(pay) or "") end
            row.sel:SetShown(not selectedUnlearned and d.recipeID == selectedID)
            row:Show()
        else
            row:Hide()
        end
    end
    p.empty:SetShown(#list == 0)
    p.empty:SetText(o and o.sent or ("Choose a recipe, set how many crafts, tick the materials "
        .. "you bring and click Add to Order."))
    SetColor(p.empty, o and o.sent and T.accent or T.muted)
    p.total:SetText(#list > 0 and ("Tips: %s"):format(Money(total)) or "")
    -- The name is in the header above; the button says where the order will go.
    local channel = o and Order.Channel(o)
    ns.SetButtonText(p.send, channel == "PARTY" and "Ask in Party"
        or channel == "INSTANCE_CHAT" and "Ask in Instance" or "Ask by Whisper")
    EnableButton(p.send, #list > 0)
    EnableButton(p.clear, #list > 0)
end

RenderLearn = function(r)
    local l = win.learn
    l.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
    l.name:SetText(C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell))
    SetColor(l.name, ns.RecipeFinder.Color(r))
    FILTERS.favorites.Star(l.fav.tex, FILTERS.favorites.Is(r))
    l.req:SetText(ns.RecipeFinder.Requirement(r))
    -- The item it makes (read from the recipe when the data has none), and the recipe itself
    -- when one is sold or dropped; trainer recipes have none.
    local read, made = OutputItem(r.spell)
    local output = r.item or read
    l.iconButton.item, l.iconButton.spell = output, r.spell
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
    -- The shopping list's row shows only for one of your own recipes, placed further down.
    if ns.ShoppingListRender then ns.ShoppingListRender(nil) end
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
    -- Your own recipes only: another player's are theirs to favour.
    d.fav:SetShown(not linkedMode)
    FILTERS.favorites.Star(d.fav.tex, FILTERS.favorites.Is(info))
    SetColor(d.name, DIFFICULTY[info.relativeDifficulty] or T.fg)
    local output, made = OutputItem(info.recipeID)
    ShowSearch(d.search, not linkedMode and output and (ItemName(output) or info.name) or nil, d.name, d)
    -- In another player's profession the order controls stand in for the craft buttons.
    for _, control in ipairs(win.craftControls) do control:SetShown(not linkedMode) end
    if linkedMode then
        d.profit.value = nil
        d.profit:Hide()
    else
        d.orderRow:Hide()
        d.bringHead:Hide()
        d.orderValue.value = nil
        d.orderValue:Hide()
        RenderProfit(d.profit, info.recipeID, output, made)
    end

    local ok, desc = pcall(C_TradeSkillUI.GetRecipeDescription, info.recipeID, Reuse.none)
    local lines = Reuse.lines
    wipe(lines)
    lines[1] = ok and desc or ""
    local okReq, reqs = pcall(C_TradeSkillUI.GetRecipeRequirements, info.recipeID)
    -- A requirement not met (not at an anvil, no hammer in the bags) greys out the craft buttons.
    -- Another player's recipe is theirs to meet, so it shows none.
    local unmet = false
    if linkedMode then okReq = false end
    if okReq and reqs and #reqs > 0 then
        local parts = Reuse.parts
        wipe(parts)
        for _, req in ipairs(reqs) do
            if req.met == false then unmet = true end
            local c = req.met and T.fg or RED
            parts[#parts + 1] = ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, req.name)
        end
        lines[#lines + 1] = "Requires: " .. table.concat(parts, ", ")
    end
    local okCd, cooldown = pcall(C_TradeSkillUI.GetRecipeCooldown, info.recipeID)
    if not linkedMode and okCd and cooldown and cooldown > 0 then
        lines[#lines + 1] = "|cffff4d4dCooldown: " .. SecondsToTime(cooldown) .. "|r"
    end
    Reuse.drawnRecipe, Reuse.drawnUnmet = info.recipeID, unmet
    Reuse.drawnCooldown = okCd and cooldown and cooldown > 0 and math.floor(cooldown) or 0
    -- More crafts than the bags have room for: Create All stops at what fits.
    local can = Craftable(info)
    local room = not linkedMode and ns.CraftBagRoom and ns.CraftBagRoom(output, made, Reagents(info.recipeID), can)
    if room and can > room then
        lines[#lines + 1] = ("|cffff4d4dBags: room for %d of %d.|r"):format(room, can)
    end
    win.createAll.count = room and math.min(can, room) or can
    d.desc:SetText(table.concat(lines, "\n"))

    d.reagentsLabel:ClearAllPoints()
    d.reagentsLabel:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -14)
    if linkedMode then return Order.RenderDetail(info) end
    local reagents = Reagents(info.recipeID)
    -- The crafts the orange count promises: each vendor reagent says how many to buy for them.
    local target = S.Get("vendorMaterials") and CraftableWithVendor(info)
    if target and target <= Craftable(info) then target = nil end
    FillReagents(d.reagents, reagents, target, MAX_REAGENTS)
    -- Buy Materials right under the reagents it buys, on the right.
    local last = d.reagents[math.min(#reagents, MAX_REAGENTS)]
    ResetBuyCount(info.recipeID)
    -- At the auction house it buys there; at a merchant, what that merchant sells.
    local atAH = S.Get("buyMaterials") and AuctionHouseOpen() and HasBuyableMaterials(info.recipeID)
    local atVendor = not atAH and not AuctionHouseOpen() and S.Get("buyVendor") and Vendor.Open()
        and Vendor.Sells(info.recipeID)
    d.buyRow:SetShown(last ~= nil and (atAH or atVendor) and true or false)
    d.buyRow.vendor = atVendor and true or false
    Vendor.Note()
    -- Buy All (x) at a merchant: x is the orange count, the crafts buying the vendor reagents
    -- would allow. Shown only while that is more than you can make now, and never at the
    -- auction house, where that count means nothing.
    local all = atVendor and CraftableWithVendor(info) or nil
    if all and all <= Craftable(info) then all = nil end
    d.buyAll.crafts = all
    d.buyAll:SetShown(d.buyRow:IsShown() and all ~= nil)
    if all then ns.SetButtonText(d.buyAll, ("Buy All (%d)"):format(all)) end
    if last then
        d.buyRow:ClearAllPoints()
        -- The reagent rows end 4px short of where Create ends (10 from the pane's edge).
        d.buyRow:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 4, -4)
    end
    if ns.ShoppingListRender then ns.ShoppingListRender(info, last) end
    local okTrack, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, info.recipeID, false)
    d.track:SetShown(okTrack and C_TradeSkillUI.SetRecipeTracked ~= nil)
    d.track:SetChecked(okTrack and tracked == true)

    ns.SetButtonText(win.createAll, ("Create All (%d)"):format(win.createAll.count))
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
    local who = linkedMode and Order.Crafter()
    local name = who and ("%s's %s"):format(Ambiguate(who, "short"), prof.name) or prof.name
    win.title:SetText(name)
    win.rank:SetMinMaxValues(0, math.max(prof.max, 1))
    win.rank:SetValue(prof.skill)
    win.rankText:SetText(("%s %d/%d"):format(name, prof.skill, prof.max))
    RenderRankBanner(prof)

    local sig = Reuse.sig
    if Reuse.listChanged and not Reuse.stale
        and #(C_TradeSkillUI.GetAllRecipeIDs() or Reuse.none) ~= Reuse.count then
        Reuse.stale = true
    end
    Reuse.listChanged = false
    if Reuse.stale or sig.id ~= prof.id or sig.skill ~= prof.skill or sig.max ~= prof.max
        or sig.linked ~= linkedMode or sig.who ~= who then
        Reuse.stale = false
        sig.id, sig.skill, sig.max, sig.linked, sig.who = prof.id, prof.skill, prof.max, linkedMode, who
        Collect()
    end
    BuildEntries()
    RenderList()
    RenderDetail()
    Order.Render()
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

local function DockTabs(on)
    local head = ProfessionsFrame.ProfessionsOverviewTab
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
    if head.SetIgnoreParentAlpha then head:SetIgnoreParentAlpha(on) end
    for _, tab in ipairs(ProfessionsFrame.rightProfessionTabs or Reuse.none) do
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
            -- In another player's profession: whether you bring this reagent for the order.
            if linkedMode then
                if r.draft then r.draft.bring[r.itemID] = self:GetChecked() or nil end
                RenderDetail()
                Order.Render()
                return
            end
            Owned()[r.itemID] = not self:GetChecked() or nil
            wipe(profitCache)
            BuildEntries()
            RenderList()
            RenderDetail()
        end)
        r.check:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if linkedMode then
                GameTooltip:AddLine("I bring this", 1, 1, 1)
                GameTooltip:AddLine("Tick a material you hand the crafter: all the crafts need of it. "
                    .. "Use - and + beside it to bring only part.", T.muted.r, T.muted.g,
                    T.muted.b, true)
                return GameTooltip:Show()
            end
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
        -- In another player's profession, in place of the Bags and Bank columns: "- [n] +", how
        -- many of it you bring for the order, under the "Your materials" heading.
        r.bringRow = CreateFrame("Frame", nil, r)
        r.bringRow:SetSize(18 + 2 + 36 + 2 + 18, 18)
        r.bringRow:SetPoint("RIGHT")
        r.bringRow:Hide()
        local function Step(delta)
            if not r.draft then return end
            local data
            for _, reagent in ipairs(r.draft.reagents) do
                if reagent.itemID == r.itemID then data = reagent end
            end
            if not data then return end
            local total = data.need * r.draft.crafts
            local n = math.max(0, math.min(total, Order.Bringing(r.draft, data) + delta))
            r.draft.bring[r.itemID] = n > 0 and (n == total or n) or nil
            RenderDetail()
            Order.Render()
        end
        local minus = Button(r.bringRow, "-", 18, 18, function() Step(-1) end)
        minus:SetPoint("LEFT")
        local plus = Button(r.bringRow, "+", 18, 18, function() Step(1) end)
        plus:SetPoint("RIGHT")
        r.bring = EditBox(r.bringRow)
        r.bring:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        r.bring:SetPoint("RIGHT", plus, "LEFT", -2, 0)
        r.bring:SetHeight(18)
        r.bring:SetTextInsets(2, 2, 0, 0)
        r.bring:SetNumeric(true)
        r.bring:SetMaxLetters(4)
        r.bring:SetJustifyH("CENTER")
        r.bring:SetScript("OnTextChanged", function(self, user)
            if not (user and r.draft) then return end
            local n = tonumber(self:GetText() or "")
            r.draft.bring[r.itemID] = (n and n > 0) and n or nil
            r.check:SetChecked(n ~= nil and n > 0)
            Order.RenderValue()
            Order.Render()
        end)
        r.bring:SetScript("OnEscapePressed", r.bring.ClearFocus)
        r.bring:SetScript("OnEnterPressed", r.bring.ClearFocus)
        -- Shows the number as capped at what the crafts need.
        r.bring:SetScript("OnEditFocusLost", function() RenderDetail() end)
        ns.Tooltip(r.bring, "Your Materials", "How many of this material you hand the crafter. "
            .. "Ticking the box fills in all the crafts need; - and + change it by one.")
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

-- A block of amount lines, one under the other with their amounts lined up; `keys` name them.
local function BuildLines(parent, keys)
    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(MID_W - 28, #keys * PROFIT_LINE)
    block:EnableMouse(true)
    block.lines = {}
    for i, key in ipairs(keys) do
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
        block.lines[i] = line
    end
    block:SetScript("OnLeave", GameTooltip_Hide)
    block:Hide()
    return block
end

-- The crafting profit lines, Buy, Sell and Profit; hovering them breaks the cost down per
-- reagent.
local function BuildProfit(parent)
    local block = BuildLines(parent, { "buy", "sell", "profit" })
    block.calc = { parts = {} }
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
    return block
end

-- An order line's amounts under the reagents: the crafter's materials and the tip; hovering
-- breaks the materials down.
function Order.BuildValue(parent)
    local block = BuildLines(parent, { "theirs", "pay" })
    block:SetScript("OnEnter", function(self)
        local v = self.value
        if not v then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Craft Order", GOLD.r, GOLD.g, GOLD.b)
        for _, p in ipairs(v.parts) do
            local name = C_Item.GetItemNameByID(p.itemID) or ("Item " .. p.itemID)
            local theirs = p.total - p.mine
            local right = theirs == 0 and ns.Color("muted", "you bring it")
                or p.each and (Money(p.each * theirs) .. (p.mine > 0 and ("  (%d of theirs)"):format(theirs) or ""))
                or "no price"
            GameTooltip:AddDoubleLine(("%s x%d"):format(name, p.total), right, 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("The suggested tip pays back the crafter's materials plus %d%% of what "
            .. "the items sell for (of all the materials, for a recipe that makes no item), "
            .. "rounded, at least 1s. Set a tip of your own in the order list on the right. "
            .. "Change the share in the Professions settings."):format(v.pct),
            T.muted.r, T.muted.g, T.muted.b, true)
        if ns.AuctionScanSummary then
            GameTooltip:AddLine(ns.AuctionScanSummary(), T.muted.r, T.muted.g, T.muted.b, true)
        end
        GameTooltip:Show()
    end)
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

-- Confirm is the only thing that spends gold.
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
        b.title:SetText("Buy on AH for " .. CraftsText(b.crafts))
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
    b.title:SetText(("Buy on AH for %s  (%d/%d)"):format(CraftsText(b.crafts), b.index, #b.list))
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

-------------------------------------------------------------------------------
--  Buy at Vendor
-------------------------------------------------------------------------------
-- At a merchant, Buy buys in one click every checked reagent the merchant sells, for that many
-- crafts, the full amount as Buy on AH does. Only plain gold purchases: nothing with an extended
-- cost (tokens, honour). A merchant sells some items several to a purchase, so the amount rounds
-- up to whole purchases, and limited stock caps it.
function Vendor.Open()
    local frame = _G.MerchantFrame
    return frame ~= nil and frame:IsShown()
end

-- This merchant's slot for an item: its index, the price of one purchase, how many one purchase
-- gives, and how many purchases are left (-1 for no limit). Nil when not sold for plain gold.
function Vendor.Find(itemID)
    for i = 1, GetMerchantNumItems() do
        if GetMerchantItemID(i) == itemID then
            local price, stack, available, extended
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = C_MerchantFrame.GetItemInfo(i)
                if info then
                    price, stack, available, extended = info.price, info.stackCount, info.numAvailable,
                        info.hasExtendedCost
                end
            else
                local _
                _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
            end
            if (price or 0) > 0 and not extended then
                return i, price, math.max(stack or 1, 1), available or -1
            end
            return
        end
    end
end

-- What Buy would buy for `crafts` of a recipe here, and what it all costs. With `topUp` (Buy
-- All) only what the bags lack for that many crafts, as the orange "buy N more" says.
function Vendor.List(recipeID, crafts, topUp)
    local out, total, owned = {}, 0, Owned()
    local ok, reagents = pcall(Reagents, recipeID)
    for _, r in ipairs(ok and reagents or {}) do
        local index, price, stack, available = Vendor.Find(r.itemID)
        if index and not owned[r.itemID] then
            local want = r.need * crafts - (topUp and ItemCount(r.itemID) or 0)
            local buys = math.max(0, math.ceil(want / stack))
            if available >= 0 then buys = math.min(buys, available) end
            if buys > 0 then
                out[#out + 1] = { index = index, itemID = r.itemID, count = buys * stack,
                    cost = buys * price, short = available >= 0 and buys * stack < want }
                total = total + buys * price
            end
        end
    end
    return out, total
end

-- Whether this merchant sells anything the recipe takes, for showing Buy.
function Vendor.Sells(recipeID)
    return #Vendor.List(recipeID, 1) > 0
end

-- The cost beside the row, red when you cannot pay it.
function Vendor.Note()
    local row = win and win.detail and win.detail.buyRow
    if not row then return end
    local info = row.vendor and SelectedInfo()
    if not info then return row.cost:SetText("") end
    local _, total = Vendor.List(info.recipeID, Crafts())
    row.cost:SetText(Money(total))
    SetColor(row.cost, GetMoney() < total and RED or T.muted)
end

-- The Buy (and Buy All) tooltip at a merchant: each reagent it buys and what it costs.
function Vendor.Tooltip(crafts, topUp)
    local info = SelectedInfo()
    if not info then return end
    local list, total = Vendor.List(info.recipeID, crafts or Crafts(), topUp)
    GameTooltip:AddLine(" ")
    for _, e in ipairs(list) do
        local name = C_Item.GetItemNameByID(e.itemID) or ("Item " .. e.itemID)
        GameTooltip:AddDoubleLine(("%dx %s"):format(e.count, name) .. (e.short and "  (all it has)" or ""),
            Money(e.cost), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Total", Money(total), GOLD.r, GOLD.g, GOLD.b, 1, 1, 1)
end

-- Buys it all, each item in as few purchases as the merchant allows at a time.
function Vendor.Buy(recipeID, crafts, topUp)
    local list, total = Vendor.List(recipeID, crafts, topUp)
    if #list == 0 then return end
    if GetMoney() < total then
        return ns.Print(("Buy at Vendor: that costs %s, more than you have."):format(Money(total)))
    end
    local parts = {}
    for _, e in ipairs(list) do
        local left = e.count
        local most = math.max(1, GetMerchantItemMaxStack(e.index) or left)
        while left > 0 do
            local n = math.min(left, most)
            BuyMerchantItem(e.index, n)
            left = left - n
        end
        parts[#parts + 1] = ("%dx %s"):format(e.count, Order.Link(e.itemID))
    end
    ns.Print(("Bought %s for %s."):format(table.concat(parts, ", "), Money(total)))
end

-- Walking up to an anvil or forge changes whether a recipe's requirements are met. Listened to
-- only while the window is open; the event fires often, so only the recipe pane redraws, at
-- most twice a second.
local usable, usablePending = CreateFrame("Frame"), false
function Reuse.UsableChanged()
    if linkedMode or selectedUnlearned then return true end
    local info = SelectedInfo()
    if not info or info.recipeID ~= Reuse.drawnRecipe then return true end
    local unmet = false
    local okReq, reqs = pcall(C_TradeSkillUI.GetRecipeRequirements, info.recipeID)
    if okReq and reqs then
        for i = 1, #reqs do
            if reqs[i].met == false then unmet = true end
        end
    end
    local okCd, cooldown = pcall(C_TradeSkillUI.GetRecipeCooldown, info.recipeID)
    local cd = okCd and cooldown and cooldown > 0 and math.floor(cooldown) or 0
    return unmet ~= Reuse.drawnUnmet or cd ~= Reuse.drawnCooldown
end

function Reuse.Usable()
    usablePending = false
    if win:IsShown() and win.detail:IsShown() and Reuse.UsableChanged() then RenderDetail() end
end
usable:SetScript("OnEvent", function()
    if usablePending then return end
    usablePending = true
    C_Timer.After(0.5, Reuse.Usable)
end)

-- The order row in the middle column, where the craft buttons are in your own profession.
function Order.BuildControls(d)
    -- Another player's profession: how many crafts to order, and Add to Order, where Create is.
    local function OrderChanged()
        RenderList()
        RenderDetail()
        Order.Render()
    end
    local orderRow = CreateFrame("Frame", nil, d)
    orderRow:SetPoint("BOTTOMLEFT", 10, 10)
    orderRow:SetPoint("BOTTOMRIGHT", -10, 10)
    orderRow:SetHeight(24)
    orderRow:Hide()
    d.orderRow = orderRow
    d.orderAdd = Button(orderRow, "Add to Order", 120, 24, function()
        local draft, o = Order.Current(), Order.Get()
        if not (draft and o) then return end
        local at = Order.Index(o, draft)
        if at then
            table.remove(o.list, at)
        elseif #o.list < Order.MAX then
            o.list[#o.list + 1] = draft
            o.sent = nil
            -- The whispers link the items, which need their data loaded.
            if draft.output then C_Item.RequestLoadItemDataByID(draft.output) end
            for _, r in ipairs(draft.reagents) do C_Item.RequestLoadItemDataByID(r.itemID) end
        end
        OrderChanged()
    end)
    d.orderAdd:SetPoint("RIGHT")
    ns.Tooltip(d.orderAdd, "Add to Order", "Puts this recipe on the order on the right, with the "
        .. "number of crafts and the materials you bring. Changes made here after adding it "
        .. ("change the order too. Up to %d recipes per order."):format(Order.MAX))
    local orderQty = EditBox(orderRow)
    orderQty:SetSize(40, 24)
    orderQty:SetNumeric(true)
    orderQty:SetMaxLetters(3)
    orderQty:SetJustifyH("CENTER")
    orderQty:SetText("1")
    local function SetCrafts(n)
        local draft = Order.Current()
        if not draft then return end
        draft.crafts = math.min(999, math.max(1, n))
        OrderChanged()
    end
    orderQty:SetScript("OnTextChanged", function(self, user)
        local n = tonumber(self:GetText() or "")
        if user and n and n > 0 then SetCrafts(n) end
    end)
    orderQty:SetScript("OnEscapePressed", orderQty.ClearFocus)
    orderQty:SetScript("OnEnterPressed", orderQty.ClearFocus)
    orderQty:SetScript("OnEditFocusLost", function() RenderDetail() end)
    ns.Tooltip(orderQty, "Crafts", "How many crafts to ask for.")
    d.orderQty = orderQty
    local orderPlus = Button(orderRow, "+", 22, 24, function()
        local draft = Order.Current()
        if draft then SetCrafts(draft.crafts + 1) end
    end)
    orderPlus:SetPoint("RIGHT", d.orderAdd, "LEFT", -12, 0)
    orderQty:SetPoint("RIGHT", orderPlus, "LEFT", -2, 0)
    local orderMinus = Button(orderRow, "-", 22, 24, function()
        local draft = Order.Current()
        if draft then SetCrafts(draft.crafts - 1) end
    end)
    orderMinus:SetPoint("RIGHT", orderQty, "LEFT", -2, 0)
    local craftsLabel = ns.Font(orderRow, 12, nil, GOLD)
    craftsLabel:SetPoint("RIGHT", orderMinus, "LEFT", -8, 0)
    craftsLabel:SetText("Crafts:")
    d.orderValue = Order.BuildValue(d)
    d.orderValue:SetPoint("BOTTOMLEFT", 14, 44)
    -- Over the reagents' "- [n] +" column, on the Reagents: line.
    d.bringHead = ns.Font(d, 12, nil, GOLD)
    d.bringHead:SetPoint("RIGHT", d.reagentsLabel, "LEFT", MID_W - 28, 0)
    d.bringHead:SetText("Your materials")
    d.bringHead:Hide()
end

-- The order column on the right.
function Order.BuildPanel()
    -- Right column, in another player's profession only: the order to whisper them.
    local order = CreateFrame("Frame", nil, win)
    order:SetPoint("TOPLEFT", W, TOP_Y)
    order:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", W, PAD)
    order:SetWidth(ORDER_W)
    ns.Solid(order, "BACKGROUND", T.panel, 0.6):SetAllPoints()
    order:Hide()
    win.order = order
    -- Invites the crafter, so the order can go to party chat; trade chat moves on quickly.
    order.invite = Button(order, "Invite", 64, 20, function()
        local who = Order.Crafter()
        if not who then return end
        -- A word first, so the invite does not come out of nowhere; one of a few, never the
        -- same twice in a row.
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        send(Order.Pick(Order.INVITE_LINES), "WHISPER", nil, who)
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(who)
        else
            InviteUnit(who)
        end
    end)
    order.invite:SetPoint("TOPRIGHT", -8, -12)
    ns.Tooltip(order.invite, "Invite", "Invites the crafter to your group, with a whisper saying "
        .. "it is for crafts from their profession. Once they are in your "
        .. "party, Ask sends the order in party chat instead of whispering it. Greyed out once "
        .. "they are in your group, or while you are in a group and not its leader or an assistant.")
    -- "Order for" over the crafter's name, so a long name keeps the whole width beside Invite.
    order.label = ns.Font(order, 11, nil, T.muted)
    order.label:SetPoint("TOPLEFT", 10, -8)
    order.label:SetText("Order for")
    order.title = ns.Font(order, 14, nil, GOLD)
    order.title:SetPoint("TOPLEFT", order.label, "BOTTOMLEFT", 0, -3)
    order.title:SetPoint("RIGHT", order.invite, "LEFT", -6, 0)
    order.title:SetJustifyH("LEFT")
    order.title:SetWordWrap(false)
    order.rows = {}
    local ORDER_ROW_H = 44
    for i = 1, Order.MAX do
        local row = CreateFrame("Button", nil, order)
        row:SetSize(ORDER_W - 12, ORDER_ROW_H - 4)
        row:SetPoint("TOPLEFT", 6, -44 - (i - 1) * ORDER_ROW_H)
        row.sel = ns.Solid(row, "BACKGROUND", T.accent, 0.25)
        row.sel:SetAllPoints()
        row.hl = ns.Solid(row, "HIGHLIGHT", T.fg, 0.06)
        row.hl:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.remove = Button(row, "X", 18, 18, function()
            local o = Order.Get()
            local at = o and Order.Index(o, row.draft)
            if at then table.remove(o.list, at) end
            RenderList()
            RenderDetail()
            Order.Render()
        end)
        row.remove:SetPoint("RIGHT", -2, 0)
        ns.Tooltip(row.remove, "Remove", "Takes this craft off the order.")
        -- The tip for this craft, the suggested one until you type your own; emptying it goes
        -- back to the suggestion.
        row.tip = EditBox(row)
        row.tip:SetSize(76, 20)
        row.tip:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
        row.tip:SetJustifyH("RIGHT")
        row.tip:SetMaxLetters(16)
        row.tip:SetScript("OnEscapePressed", row.tip.ClearFocus)
        row.tip:SetScript("OnEnterPressed", row.tip.ClearFocus)
        row.tip:SetScript("OnEditFocusLost", function(self)
            if not row.draft then return end
            row.draft.tip = Order.Parse(self:GetText())
            RenderDetail()
            Order.Render()
        end)
        ns.Tooltip(row.tip, "Tip", "What you pay the crafter for this craft, sent with the "
            .. "whisper. Filled in with the suggested tip; type your own as 2g 50s, 75s or 2.5 "
            .. "(gold). Empty it to go back to the suggestion.")
        row.name = ns.Font(row, 12, nil)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
        row.name:SetPoint("RIGHT", row.tip, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.sub = ns.Font(row, 11, nil, T.muted)
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.sub:SetPoint("RIGHT", row.tip, "LEFT", -6, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        -- Click to choose the recipe again, to change its crafts or materials.
        row:SetScript("OnClick", function(self)
            if not self.draft then return end
            selectedID, selectedUnlearned = self.draft.recipeID, nil
            BuildEntries()
            RenderList()
            RenderDetail()
            Order.Render()
        end)
        row:SetScript("OnEnter", function(self)
            local d = self.draft
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if d.output then
                GameTooltip:SetItemByID(d.output)
            else
                GameTooltip:SetSpellByID(d.recipeID)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:Hide()
        order.rows[i] = row
    end
    order.empty = ns.Font(order, 12, nil, T.muted)
    order.empty:SetPoint("TOPLEFT", 14, -50)
    order.empty:SetPoint("RIGHT", -14, 0)
    order.empty:SetJustifyH("LEFT")
    order.empty:SetWordWrap(true)
    order.empty:SetSpacing(2)
    order.send = Button(order, "Ask by Whisper", 150, 24, function()
        for _, row in ipairs(order.rows) do row.tip:ClearFocus() end
        Order.Send()
        RenderList()
        RenderDetail()
        Order.Render()
    end)
    order.send:SetPoint("BOTTOMLEFT", 10, 10)
    ns.Tooltip(order.send, "Ask for the Order", "Sends the crafter one message per craft: how "
        .. "many you want, the materials you bring and your tip. In party chat, starting with "
        .. "their name, when they are in your party; else as a whisper (also in a raid). The "
        .. "order is emptied once sent.")
    order.clear = Button(order, "Clear", 80, 24, function()
        local o = Order.Get()
        if o then wipe(o.list) end
        RenderList()
        RenderDetail()
        Order.Render()
    end)
    order.clear:SetPoint("BOTTOMRIGHT", -10, 10)
    ns.Tooltip(order.clear, "Clear", "Empties the order without sending it.")
    order.total = ns.Font(order, 12, nil, GOLD)
    order.total:SetPoint("BOTTOMLEFT", order.send, "TOPLEFT", 2, 8)
end

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
                if f.divider then root:CreateDivider() end
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
        -- A small star on a favourite, just left of the profit; the name stops short of it.
        row.fav = row:CreateTexture(nil, "OVERLAY")
        row.fav:SetSize(12, 12)
        row.fav:SetPoint("RIGHT", row.profit, "LEFT", -4, 0)
        FILTERS.favorites.Star(row.fav, true)
        row.fav:Hide()
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self, button)
            local e = self.entry
            -- Right-click makes a recipe you know a favourite, or no longer one.
            if button == "RightButton" then
                if (e.recipe or e.unlearned) and not linkedMode then
                    FILTERS.favorites.Toggle(e.recipe or e.unlearned)
                    BuildEntries()
                    RenderList()
                    RenderDetail()
                end
                return
            end
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
    -- The favourite star, before the name: click to make the recipe a favourite or not.
    d.fav = CreateFrame("Button", nil, d)
    d.fav:SetSize(18, 18)
    d.fav:SetPoint("LEFT", iconBtn, "RIGHT", 10, 0)
    d.fav.tex = d.fav:CreateTexture(nil, "ARTWORK")
    d.fav.tex:SetAllPoints()
    d.fav:SetScript("OnClick", function()
        local info = SelectedInfo()
        if not info then return end
        FILTERS.favorites.Toggle(info)
        BuildEntries()
        RenderList()
        RenderDetail()
    end)
    ns.Tooltip(d.fav, "Favorite", "Makes this recipe a favourite, or no longer one. Favourites "
        .. "get a star in the list, and the Filter menu's Favorites shows only them. Right-click "
        .. "a recipe in the list does the same.")
    d.name = ns.Font(d, 16, nil)
    d.name:SetPoint("LEFT", d.fav, "RIGHT", 6, 0)
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
        if not info then return end
        if row.vendor then return Vendor.Buy(info.recipeID, Crafts()) end
        OpenBuyer(info.recipeID, Crafts())
    end)
    d.buyMats:SetPoint("RIGHT")
    d.buyMats:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.vendor then
            GameTooltip:AddLine("Buy at Vendor", 1, 1, 1)
            GameTooltip:AddLine("Buys from this merchant, in one click, every checked reagent it "
                .. "sells, for that many crafts, whatever is already in your bags. Set the number "
                .. "with the - and + beside it; uncheck a reagent to leave it out.", T.muted.r,
                T.muted.g, T.muted.b, true)
            Vendor.Tooltip()
        else
            GameTooltip:AddLine("Buy on AH", 1, 1, 1)
            GameTooltip:AddLine("Buys on the auction house the materials for that many crafts, "
                .. "whatever is already in your bags: every checked reagent that vendors do not "
                .. "sell. Set the number with the - and + beside it; uncheck a reagent to leave it "
                .. "out. Each material asks for the price now and waits for you to confirm.",
                T.muted.r, T.muted.g, T.muted.b, true)
        end
        GameTooltip:Show()
    end)
    d.buyMats:HookScript("OnLeave", GameTooltip_Hide)
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
    ns.Tooltip(buyQty, "Crafts to Buy For", "How many crafts Buy buys the materials for.")
    -- At a merchant: what Buy costs, left of the - button.
    row.cost = ns.Font(row, 12, nil, T.muted)
    row.cost:SetPoint("RIGHT", buyMinus, "LEFT", -8, 0)
    buyQty:SetScript("OnTextChanged", function() Vendor.Note() end)
    -- At a merchant: enough of its reagents for the orange count of crafts, at the pane's left
    -- edge as Create All is (the row starts BUY_ROW_W right of it).
    -- ns.Button calls its click with no arguments, so the count is read off the button.
    d.buyAll = Button(row, "Buy All", 110, 24, function()
        local info, crafts = SelectedInfo(), d.buyAll.crafts
        if info and crafts then Vendor.Buy(info.recipeID, crafts, true) end
    end)
    d.buyAll:SetPoint("LEFT", row, "LEFT", -BUY_ROW_W, 0)
    d.buyAll:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Buy All at Vendor", 1, 1, 1)
        GameTooltip:AddLine(("Buys what your bags lack of this merchant's reagents for %d crafts, "
            .. "the orange number next to the recipe, so Create All can make them all. Uncheck a "
            .. "reagent to leave it out."):format(self.crafts or 0), T.muted.r, T.muted.g,
            T.muted.b, true)
        Vendor.Tooltip(self.crafts, true)
        GameTooltip:Show()
    end)
    d.buyAll:HookScript("OnLeave", GameTooltip_Hide)
    d.buyAll:Hide()
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
        -- As many as the reagents allow and the bags have room for (RenderDetail sets it).
        if info then Craft(win.createAll.count or Craftable(info)) end
    end)
    win.createAll:SetPoint("BOTTOMLEFT", 10, 10)
    -- Hidden in another player's profession, where the order row takes their place.
    win.craftControls = { create, qty, plus, minus, win.createAll }

    Order.BuildControls(d)

    -- The middle column for an unlearned recipe: where to learn it.
    local l = CreateFrame("Frame", nil, mid)
    l:SetAllPoints()
    l:Hide()
    win.learn = l
    -- The icon shows the item the recipe makes on hover (the spell for one that makes none),
    -- as on a learned recipe; shift-click links it. RenderLearn sets what it is.
    local learnIcon = CreateFrame("Button", nil, l)
    learnIcon:SetSize(44, 44)
    learnIcon:SetPoint("TOPLEFT", 14, -14)
    l.iconButton = learnIcon
    l.icon = learnIcon:CreateTexture(nil, "ARTWORK")
    l.icon:SetAllPoints()
    l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    learnIcon:SetScript("OnEnter", function(self)
        if not (self.item or self.spell) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item then
            GameTooltip:SetItemByID(self.item)
        else
            GameTooltip:SetSpellByID(self.spell)
        end
        GameTooltip:Show()
    end)
    learnIcon:SetScript("OnLeave", GameTooltip_Hide)
    learnIcon:SetScript("OnClick", function(self)
        if not IsModifiedClick("CHATLINK") then return end
        local link = self.item and select(2, C_Item.GetItemInfo(self.item))
            or self.spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(self.spell)
        if link then ChatFrameUtil.InsertLink(link) end
    end)
    FILTERS.favorites.BuildLearnStar(l)
    l.name = ns.Font(l, 16, nil)
    l.name:SetPoint("TOPLEFT", l.fav, "TOPRIGHT", 6, -2)
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

    Order.BuildPanel()

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
    wipe(Reuse.waiting)
    ns.ProfBagChanges = ns.ProfBagChanges + 1
    if win and bookDocked and InCombatLockdown() then
        win:SetAlpha(0)
    elseif win then
        win:Hide()
    end
    if ProfessionsFrame then
        DockTabs(false)
        DockBook(false)
        ProfessionsFrame:SetAlpha(1)
    end
end

-- Once the window has been dragged it stays where it was put, and Blizzard's window is pinned
-- under it so none of it is left clickable elsewhere. The overview's secure buttons hang off
-- both windows, so neither may move in combat. One table: the file is at Lua's local limit.
local Drag = {}

function Drag.Follow()
    if not (win and win:IsShown() and S.Get("windowPos")) then return end
    if InCombatLockdown() then
        Drag.pending = true
        return
    end
    Drag.pending, Drag.following = nil, true
    ProfessionsFrame:ClearAllPoints()
    ProfessionsFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    Drag.following = false
end

function Drag.Place()
    local pos = S.Get("windowPos")
    win:ClearAllPoints()
    if pos then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        win:SetPoint("TOPLEFT", ProfessionsFrame, "TOPLEFT", 0, 0)
    end
end

function Drag.Save()
    S.Set("windowPos", { x = win:GetLeft(), y = win:GetTop() })
end

-- mode is "craft" (a profession's recipes), "linked" (another player's, to order from) or
-- "book" (the overview).
local function Activate(mode)
    local pf = ProfessionsFrame
    if not win then
        Build()
        if ns.ShoppingListAttach then ns.ShoppingListAttach(win) end
        win:SetFrameStrata(NextStrata(pf:GetFrameStrata()))
        win:SetMovable(true)
        win:SetClampedToScreen(true)
        ns.AllowOffscreen(win)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            -- Off Blizzard's window first, or pinning that one under this would anchor in a loop.
            Drag.Save()
            Drag.Place()
            Drag.Follow()
            self:StartMoving()
        end)
        win:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            Drag.Save()
            Drag.Place()
        end)
        Drag.Place()
    end
    pf:SetAlpha(0)
    win:SetAlpha(1)
    local linked = mode == "linked"
    -- The right column: another player's order, or your shopping list while that is on.
    local wide = linked or (mode == "craft" and ns.ShoppingListWide and ns.ShoppingListWide())
    local width = wide and W + ORDER_W + PAD or W
    -- Never narrower or shorter than Blizzard's window, so none of it is left clickable.
    -- Resizing waits for peace: the overview's secure buttons may hang off this window.
    if not InCombatLockdown() then
        win:SetSize(math.max(width, pf:GetWidth()), math.max(MIN_H, pf:GetHeight()))
    end
    if not win:IsShown() or linked ~= linkedMode or mode ~= Reuse.mode then Reuse.stale = true end
    Reuse.mode = mode
    if not win:IsShown() or linked ~= linkedMode then
        selectedID, selectedUnlearned, offset = nil, nil, 0
        win:Show()
        Drag.Follow()
    end
    linkedMode = linked
    win.rank:SetWidth(width - PAD * 2 - 4)
    win.order:SetShown(linked)
    DockTabs(true)
    local book = mode == "book"
    win.search:SetShown(not book)
    -- Another player's list has no filters, so the search takes the Filter button's room.
    win.search:SetWidth(linked and LEFT_W or (LEFT_W - FILTER_W - 6))
    win.filter:SetShown(not book and not linked)
    win.list:SetShown(not book)
    win.mid:SetShown(not book)
    win.rank:SetShown(not book)
    if book then win.rankBanner:Hide() end
    if not (bookDocked and InCombatLockdown()) then win.book:SetShown(book) end
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
    if not (On() and ProfessionsFrame and ProfessionsFrame:IsShown()) then return Deactivate() end
    -- K opens the book while the game still holds the last linked profession: the book wins,
    -- unless a link was just clicked.
    if BookOpen() and not viewingLink and not C_TradeSkillUI.IsTradeSkillGuild() then
        return Activate("book")
    end
    if Linked() then
        if Profession() then return Activate("linked") end
        return Deactivate()
    end
    if not Own() then return Deactivate() end
    if BookOpen() then return Activate("book") end
    if Profession() then return Activate("craft") end
    Deactivate()
end

function Reuse.Flush()
    Reuse.queued = false
    Update()
end

local function Queue()
    if Reuse.queued then return end
    Reuse.queued = true
    C_Timer.After(0, Reuse.Flush)
end

function Reuse.Soon()
    if Reuse.queued then return end
    Reuse.queued = true
    C_Timer.After(Reuse.BURST, Reuse.Flush)
end

function Reuse.Refresh(reread)
    if reread then Reuse.stale = true end
    Queue()
end
ns.ProfWindowRefresh = Reuse.Refresh

-- A link clicked while Blizzard's window was loaded but closed makes Forever cast every one of
-- your own professions at once and land on the last, never the link's. A second click opens it,
-- so when the first one lands on your own profession, click it once more.
local RETRY_AFTER = 0.5
local retrying

-- The link view ends when the window closes (not the close the click itself may cause) or when
-- you open one of your own professions, which is a cast of its spell. Casts are only listened
-- to while a link is being viewed.
local casts = CreateFrame("Frame")
local SETTLE = 1

local function Settled()
    return viewingLink and GetTime() - linkClicked > SETTLE
end

local function StopLinkView()
    viewingLink = nil
    casts:UnregisterAllEvents()
end

-- Closed in the first second, the close may be the click's own on its way to the link, so look
-- again once that has passed: still closed, the link view is over.
local function EndLinkView()
    if not viewingLink then return end
    if Settled() then return StopLinkView() end
    local clicked = linkClicked
    C_Timer.After(SETTLE - (GetTime() - clicked) + 0.05, function()
        if viewingLink and linkClicked == clicked and not ProfessionsFrame:IsShown() then StopLinkView() end
    end)
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
-- Only a plain click opens the link: Shift or Ctrl puts it in chat and no window opens.
hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
    if not On() or IsShiftKeyDown() or IsControlKeyDown() then return end
    local guid = type(link) == "string" and link:match("^trade:(Player%-%d+%-%x+):")
    if not guid or guid == UnitGUID("player") then return end
    viewingLink, linkClicked, linkGUID = true, GetTime(), guid
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
merchant:RegisterEvent("MERCHANT_CLOSED")
-- Opening or closing a merchant shows or hides Buy at Vendor in the recipe pane.
merchant:SetScript("OnEvent", function(_, event)
    if event ~= "MERCHANT_CLOSED" then ScanMerchant() end
    if event ~= "MERCHANT_UPDATE" and S.Get("buyVendor") then Queue() end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name, loaded)
    if event == "BAG_UPDATE_DELAYED" then ns.ProfBagChanges = ns.ProfBagChanges + 1 end
    if event == "ITEM_DATA_LOAD_RESULT" then
        if not Reuse.waiting[name] then return end
        Reuse.waiting[name] = nil
        if not loaded then return end
    end
    if Reuse.quiet[event] and not (win and win:IsShown()) then return end
    if event == "GROUP_ROSTER_UPDATE" and not linkedMode then return end
    if event == "ADDON_LOADED" then
        if name ~= "Blizzard_Professions" then return end
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if bookPending ~= nil then DockBook(bookPending) end
        if Drag.pending then Drag.Follow() end
    end
    if not hooked and ProfessionsFrame then
        hooked = true
        ProfessionsFrame:HookScript("OnShow", Queue)
        ProfessionsFrame:HookScript("OnHide", function()
            EndLinkView()
            Deactivate()
        end)
        ProfessionsFrame:HookScript("OnSizeChanged", Queue)
        -- The panel manager re-places it whenever any panel opens, closes or resizes.
        hooksecurefunc(ProfessionsFrame, "SetPoint", function()
            if not Drag.following then Drag.Follow() end
        end)
        local book = ProfessionsFrame.BookPage
        if book then
            book:HookScript("OnShow", Queue)
            book:HookScript("OnHide", Queue)
            if book.Update then hooksecurefunc(book, "Update", Redock) end
            if book.FormatProfession then hooksecurefunc(book, "FormatProfession", Redock) end
        end
    end
    if Reuse.reread[event] then Reuse.stale = true end
    if event == "TRADE_SKILL_LIST_UPDATE" then Reuse.listChanged = true end
    if Reuse.quiet[event] or event == "TRADE_SKILL_LIST_UPDATE" then return Reuse.Soon() end
    Queue()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then return Deactivate() end
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
        "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_NAME_UPDATE", "NEW_RECIPE_LEARNED",
        "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "PLAYER_REGEN_ENABLED",
        "PLAYERBANKSLOTS_CHANGED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
        "TRACKED_RECIPE_UPDATE", "GROUP_ROSTER_UPDATE", "TRADE_SKILL_FAVORITES_CHANGED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_Professions") then events:RegisterEvent("ADDON_LOADED") end
    events:GetScript("OnEvent")(events, "APPLY")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" then Apply() end
    if key == "vendorMaterials" or key == "bagReagents" or key == "bankReagents" or key == "ahSearch"
        or key == "craftProfit" or key == "craftProfitList" or key == "buyMaterials" or key == "buyVendor"
        or key == "craftOrders" or key == "orderTip" then
        Queue()
    end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
