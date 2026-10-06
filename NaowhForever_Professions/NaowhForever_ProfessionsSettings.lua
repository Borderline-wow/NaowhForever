-------------------------------------------------------------------------------
--  NaowhForever_ProfessionsSettings.lua -- the Professions settings page (/nf > Professions):
--  your professions at the top, then the recipe window's extras, craft orders and buying.
--  The Tracking Reminder and Total Craft Timer cards sit in their own files.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local Settings = ns.Shared.Settings

local function On()
    return S.Get("enabled") == true
end

local Group = Settings.Group
local PROFESSIONS_OFF = "Turn on Professions"
local RECIPE_KEYS = { "recipeFinder", "rankAlert", "bagReagents", "bankReagents", "trainFavorites" }

local function ProfessionLine(index)
    if not index then return nil end
    local name, _, rank, maxRank = GetProfessionInfo(index)
    return name and ("%s %d/%d"):format(name, rank or 0, maxRank or 0)
end

local function Headline()
    local prof1, prof2 = GetProfessions()
    local a, b = ProfessionLine(prof1), ProfessionLine(prof2)
    if a and b then return a .. ",  " .. b end
    return a or b or "No professions learned yet"
end

local function Detail()
    if not On() then return "Turn on Professions to use Naowh's recipe window in place of the game's." end
    return "Open a profession from your spellbook: Naowh's recipe window takes the place of the game's."
end

local function RecipeSummary(store)
    local n = 0
    for _, key in ipairs(RECIPE_KEYS) do
        if store.Get(key) then n = n + 1 end
    end
    return ("%d of %d on"):format(n, #RECIPE_KEYS)
end

local function OrdersSummary(store)
    return ("Suggested tip %d%% of value"):format(store.Get("orderTip"))
end

local function BuyingSummary(store)
    local profit, ah, vendor = store.Get("craftProfit"), store.Get("buyMaterials"), store.Get("buyVendor")
    if not (profit or ah or vendor) then return "No prices or buying" end
    return (profit and "Profit" or "No profit") .. (ah and ", buys on the AH" or "")
        .. (vendor and ", buys at vendors" or "")
end

local function ProfitOn() return On() and S.Get("craftProfit") == true end

local page = Settings.Page("Professions/Settings", S)

page:Window({
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "recipeWindow", name = "Recipe Window", order = 10,
    help = "What Naowh's profession window adds to each recipe: the ones you have not learned yet, your next "
        .. "rank, and how many of each reagent you have.",
    summary = RecipeSummary,
    rows = {
        { key = "recipeFinder", label = "Unlearned Recipes", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "Lists the recipes you have not learned yet below your own. Click one to see the skill it "
              .. "needs, what it costs and where it comes from: the nearest trainers, the vendor selling its "
              .. "manual, or the mobs that drop it. Click a trainer or vendor to set a waypoint." },
        { key = "rankAlert", label = "Next Rank Alert", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "When a profession's skill is high enough for its next rank (Journeyman, Expert, Artisan), a "
              .. "banner under the skill bar and on its card in the overview says what it takes and who "
              .. "teaches it: the nearest trainer, book vendor or quest giver. Click Waypoint to mark them on "
              .. "your map. Reaching it also says so once in chat; /naowh profrank repeats that." },
        { key = "bagReagents", label = "Reagents in Bags", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "Adds a Bags column to the chosen recipe's reagents, showing how many of each you carry." },
        { key = "bankReagents", label = "Reagents in Bank", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "Adds a Bank column to the chosen recipe's reagents, showing how many of each are in your "
              .. "bank." },
        { key = "trainFavorites", label = "Train Favorites", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "At a profession trainer who teaches any of your favourite recipes that you can learn now "
              .. "(star one before its name, or right-click it in the list), a window beside the trainer's "
              .. "lists them with their cost: Learn one, or Learn All." },
    },
})

page:Card({
    id = "craftOrders", name = "Craft Orders", order = 20, switch = "craftOrders",
    help = "Opens another player's profession link in this window, to order crafts from them. Choose a recipe, "
        .. "set how many crafts, tick the materials you bring (or type how many), and Add to Order. The order "
        .. "on the right has a suggested tip per craft that you can change; Ask sends the crafter one message "
        .. "per craft with the amount, your materials and the tip: in party chat when they are in your party, "
        .. "else as a whisper. Prices and the tip need an auction house scan.",
    summary = OrdersSummary,
    rows = {
        { key = "orderTip", label = "Suggested Tip", slider = { 0, 50, 1 }, unit = "%", needs = On,
          why = PROFESSIONS_OFF,
          help = "The share of what the items sell for that the suggested tip adds on top of paying back the "
              .. "crafter's own materials. At least 1s unless set to 0." },
    },
})

page:Card({
    id = "buying", name = "Buying and Selling", order = 40,
    help = "Prices, profit and buying the reagents of the chosen recipe, at the auction house or a vendor.",
    summary = BuyingSummary,
    rows = {
        Group("Prices"),
        { key = "craftProfit", label = "Crafting Profit", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "Once you have scanned the auction house (Scan Prices), the chosen recipe shows what its "
              .. "reagents cost to buy and what the item sells for, and the profit after the 5% auction house "
              .. "cut. Each reagent is priced at its cheapest: a vendor's price once you have seen a vendor "
              .. "sell it, else the lowest buyout at your last scan. Uncheck a reagent you already have to "
              .. "leave it out of the cost, for every recipe that uses it. Hover the lines for the breakdown." },
        { key = "craftProfitList", label = "Profit in Recipe List", toggle = true, needs = ProfitOn,
          why = "Needs Crafting Profit",
          help = "Also shows each recipe's profit at the right of its row in the list, green or red. Recipes "
              .. "whose profit is not known show none." },
        Group("Auction House"),
        { key = "ahShiftClick", label = "Shift-Click Searches AH", toggle = true, needs = On,
          why = PROFESSIONS_OFF,
          help = "While the auction house is open, Shift-click a recipe or a reagent to search the auction "
              .. "house for the item: what the recipe makes, or the reagent. While you type in chat, "
              .. "Shift-click still links it." },
        { key = "ahSearch", label = "Search AH Button", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "While the auction house is open, a Search AH button next to the chosen recipe's name "
              .. "searches it for the item the recipe makes. Unlearned recipes also get Search Recipe, for the "
              .. "pattern, plans or manual that teaches it. Recipes that make no item, such as enchants, get "
              .. "no Search AH." },
        { key = "buyMaterials", label = "Buy on AH", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "While the auction house is open, a Buy button under the chosen recipe's reagents buys the "
              .. "materials for as many crafts as you set beside it: every checked reagent that vendors do not "
              .. "sell. Each one shows its price first and is only bought when you click Confirm." },
        { key = "searchFavoritesAH", label = "Search Favorites AH", toggle = true, needs = On,
          why = PROFESSIONS_OFF,
          help = "At the auction house, a window beside it lists the patterns, plans and manuals of your "
              .. "favourite recipes that you have not learned or bought, with what they cost now. Buy finds "
              .. "the cheapest and asks before Accept buys it." },
        { key = "shoppingList", label = "Shopping List", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "Adds \"- [1] + Add to List\" under a recipe's reagents: the materials Buy on AH would buy for "
              .. "that many crafts go on a shopping list, from anywhere. At the auction house the list shows "
              .. "beside it: Check Prices looks each one up and warns in red when one is well above your last "
              .. "scan, then Buy All goes through the list one material at a time, each bought only when you "
              .. "confirm its final price." },
        Group("Vendors"),
        { key = "vendorMaterials", label = "Crafts with Vendor Buys", toggle = true, needs = On,
          why = PROFESSIONS_OFF,
          help = "Adds a second, orange number next to each recipe: how many you could make after buying the "
              .. "reagents vendors sell, such as Weak Flux or Coarse Thread. The recipe's reagents then say "
              .. "how many of each to buy." },
        { key = "buyVendor", label = "Buy at Vendor", toggle = true, needs = On, why = PROFESSIONS_OFF,
          help = "While a merchant is open, a Buy button under the chosen recipe's reagents buys from them, in "
              .. "one click, every checked reagent they sell, such as Coarse Thread or Weak Flux, for as many "
              .. "crafts as you set beside it. The total cost shows beside the button; hover Buy for each "
              .. "reagent." },
    },
})
