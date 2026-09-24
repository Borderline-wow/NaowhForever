-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_QoL.lua -- the QoL module: NaowhUI's QoL page, trimmed to what
--  Forever has (no Mythic+, keystones, talking heads or retail spec bars), plus the loot
--  feed and the trainer popup.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local UI = ns.UI
local STATUS = UI.STATUS

local S = UI.ModuleSettings("qol", {
    enabled = true,
    deathRelease = false, deathReleaseHold = 1,
    stealthReminder = false, formReminder = false,
    reminderInGroup = false, reminderHideResting = true,
    coTank = false, coTankName = true, coTankClassColor = true, coTankDebuffs = false,
    coTankWidth = 180, coTankHeight = 30,

    deleteConfirm = false,
    lootFeed = true, lootFeedMoney = true, lootFeedXP = false, lootFeedQuality = 1,
    lootFeedQuest = true, lootFeedRep = true,
    lootFeedCount = 6, lootFeedFade = 5, lootFeedStyle = "dark", lootFeedGlow = true,
    lootFeedValue = true, lootFeedBank = true, lootFeedPrice = "vendor", lootFeedGPH = false,
    hideLootWindow = false,
    lootFeedWidth = 340, lootFeedHeight = 36, lootFeedSpacing = 0,
    lootFeedFont = "", lootFeedFontSize = 13,
    xpTicker = true, xpTickerLevel = true, xpTickerElapsed = false, xpTickerTotal = false,
    xpTickerHideResting = false, xpTickerFont = "", xpTickerFontSize = 24,
    xpTickerSplits = true, xpTickerSplitCount = 4, xpTickerCompare = true,
    autoRepair = false, sellJunk = false,
    restock = true, restockReagents = true, restockAmmo = true, restockAmmoTarget = 1000,
    restockFood = true, restockFoodBelow = 10, restockVendor = true, restockBagsBelow = 4,
    restockShowFor = 12, restockBuy = false,
    dqTracker = true, dqShowDone = false, dqAllFactions = false,
    townMap = true, townClass = true, townProfession = true, townFlight = true, townInn = true,
    townBank = true, townStable = false, townRepair = true, townSupplies = true,
    townVendors = false, townPinSize = 16,
    gearSets = true, gearBarSize = 32, gearMounted = "", gearResting = "",
    bis = true, bisTooltip = true, bisLootAlert = true,

    durability = true, durabilityBelow = 25,
    combatAlert = false, groupDeaths = false,

    hideErrors = false, hideTutorials = false, hideScreenshot = false,
    skipCinematics = false,
    fps = false, localMS = false, worldMS = false,

    trainerPopup = true, trainerGlow = true, trainerRanks = true,

    flightTimer = true, flightQuotes = true, quizFlight = true, quizCamp = true,
})
ns.QoLSettings = S

local QUALITY_VALUES = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
    [4] = "Epic" }
local QUALITY_ORDER = { 0, 1, 2, 3, 4 }

local STYLE_VALUES = { dark = "Dark", light = "Light" }
local STYLE_ORDER = { "dark", "light" }

local PRICE_VALUES = { vendor = "Vendor Price", tsm = "Auction (TSM)" }
local PRICE_ORDER = { "vendor", "tsm" }

function ns.BuildQoLGeneralPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "XP PER HOUR" .. STATUS.ready, y); y = y - h
    local xpFonts, xpFontOrder = UI.FontChoices(S.Get("xpTickerFont"))
    _, h = W:DualRow(parent, y,
        S.Toggle("xpTicker", "XP per Hour",
            "Your experience per hour on screen, with time to level, session length and "
            .. "XP this session, counted from when you logged in. Hidden at max level. Hover it "
            .. "for Start, Pause and Reset (also /naowh xp start, pause or reset). Move it in "
            .. "Unlock Mode."),
        S.Toggle("xpTickerLevel", "Show Ding Time",
            "How long the next level takes at your current rate.", "xpTicker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpTickerElapsed", "Show Elapsed", "How long this session has run.",
            "xpTicker"),
        S.Toggle("xpTickerTotal", "Show XP per Session", "Experience gained this session.",
            "xpTicker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpTickerSplits", "Level Splits",
            "Each level cut into equal parts of experience, with the time each part took. "
            .. "Times count only while you are logged in.", "xpTicker"),
        S.Slider("xpTickerSplitCount", "Splits per Level", 1, 10, 1,
            "Changing it restarts the splits of the level you are on.", "xpTickerSplits")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpTickerCompare", "Compare to Previous Level",
            "Each finished split shows how much faster (green) or slower (red) it was than "
            .. "the same split of your previous level.", "xpTickerSplits"),
        S.Toggle("xpTickerHideResting", "Hide While Resting",
            "Hidden in cities and inns.", "xpTicker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("xpTickerFont", "Font", xpFonts, xpFontOrder, nil, "xpTicker"),
        S.Slider("xpTickerFontSize", "Font Size", 8, 32, 1, nil, "xpTicker")
    ); y = y - h
    _, h = W:Button(parent, "Reset XP per Hour", y, function()
        if ns.ResetXPTicker then ns.ResetXPTicker() end
    end); y = y - h

    _, h = W:SectionHeader(parent, "DEATH RELEASE" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("deathRelease", "Death Release Protection",
            "Release Spirit has to be held down for a moment inside a dungeon or raid, so "
            .. "a stray click never sends you on a corpse run while a battle res is coming."),
        S.Slider("deathReleaseHold", "Hold Time (s)", 0.5, 3, 0.1, nil, "deathRelease")
    ); y = y - h

    _, h = W:SectionHeader(parent, "STEALTH & FORM REMINDER" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("stealthReminder", "Stealth Reminder",
            "Text on screen while a rogue or cat-form druid is out of stealth."),
        S.Toggle("formReminder", "Stance / Form Reminder",
            "Warns when you are in no stance, form or aura, for the classes that have one.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("reminderInGroup", "Only In a Group"),
        S.Toggle("reminderHideResting", "Hide While Resting")
    ); y = y - h

    _, h = W:SectionHeader(parent, "CO-TANK FRAME" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("coTank", "Co-Tank Frame",
            "A small health bar for the other tank in your group."),
        S.Toggle("coTankDebuffs", "Co-Tank Debuffs",
            "Their debuffs next to the bar, out of combat only: the client hides auras "
            .. "from addons during a fight.", "coTank")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("coTankName", "Show Name", nil, "coTank"),
        S.Toggle("coTankClassColor", "Class Colour Health", nil, "coTank")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("coTankWidth", "Width", 50, 400, 5, nil, "coTank"),
        S.Slider("coTankHeight", "Height", 10, 80, 1, nil, "coTank")
    ); y = y - h

    return y
end

function ns.BuildQoLLootPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "LOOT FEED" .. STATUS.ready, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeed", "Loot Feed",
            "Everything you loot pops up on screen with its icon, amount and value, stacking "
            .. "upward and fading out. Hover a line for the item's tooltip. Move it in Unlock Mode."),
        S.Toggle("lootFeedMoney", "Show Money", nil, "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedQuest", "Show Quest Rewards",
            "A line for each quest you turn in, with the experience and money it gave. "
            .. "Reward items show as their own lines.", "lootFeed"),
        S.Toggle("lootFeedRep", "Show Reputation",
            "A line for every reputation gain, from quests and kills alike.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedXP", "Show Kill Experience",
            "A line for the experience from each kill. Quest experience is on the quest's "
            .. "own line.", "lootFeed"),
        S.Toggle("lootFeedValue", "Show Item Value",
            "What each line is worth, in gold, silver and copper.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("lootFeedQuality", "Lowest Quality Shown", QUALITY_VALUES, QUALITY_ORDER,
            nil, "lootFeed"),
        S.Slider("lootFeedCount", "Lines Shown", 3, 12, 1, nil, "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("lootFeedFade", "Display Time (s)", 0.5, 10, 0.5,
            "How long each line stays before it fades.", "lootFeed"),
        S.Dropdown("lootFeedStyle", "Style", STYLE_VALUES, STYLE_ORDER, nil, "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedGlow", "Glow", "A soft glow beside each icon.", "lootFeed"),
        S.Toggle("lootFeedBank", "Count Bank Items",
            "The number on each icon counts your bank as well as your bags.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("lootFeedPrice", "Price Source", PRICE_VALUES, PRICE_ORDER,
            "Auction prices need TradeSkillMaster. Without it, vendor prices are used.",
            "lootFeed"),
        S.Toggle("lootFeedGPH", "Gold per Hour",
            "A running gold per hour beside the newest line, counting money and item value "
            .. "since your first loot this session.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideLootWindow", "Hide Blizzard Loot Window",
            "Takes everything the moment you loot, with Blizzard's loot window kept out of "
            .. "sight, so the feed is all you see. Works with or without the game's auto loot. "
            .. "Hold Shift while looting to get the window back. It also appears whenever "
            .. "something cannot be taken: a group roll, a locked item, or bags too full."),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Button(parent, "Reset Gold per Hour", y, function()
        if ns.ResetLootFeedSession then ns.ResetLootFeedSession() end
    end); y = y - h

    _, h = W:SectionHeader(parent, "LOOT FEED APPEARANCE", y); y = y - h
    local fonts, fontOrder = UI.FontChoices(S.Get("lootFeedFont"))
    _, h = W:DualRow(parent, y,
        S.Slider("lootFeedWidth", "Width", 200, 600, 5, nil, "lootFeed"),
        S.Slider("lootFeedHeight", "Line Height",  20, 64, 1,
            "The icon grows and shrinks with it.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("lootFeedSpacing", "Spacing", 0, 20, 1, "Space between lines.", "lootFeed"),
        S.Dropdown("lootFeedFont", "Font", fonts, fontOrder, nil, "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("lootFeedFontSize", "Font Size", 8, 24, 1,
            "The item name. Values and the bag count scale with it.", "lootFeed"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "LOOTING" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("deleteConfirm", "Auto-Fill Delete Confirmation",
            "Types DELETE into the confirmation box for you."),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "VENDORS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("autoRepair", "Auto Repair", "Repairs all gear when you open a vendor who can."),
        S.Toggle("sellJunk", "Auto Sell Junk", "Sells grey items when you open a vendor.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "RESTOCK" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("restock", "Restock Reminder",
            "When you reach a city or inn, a flashing list in the middle of the screen of what "
            .. "you are short on. Move it in Unlock Mode."),
        S.Slider("restockShowFor", "Display Time (s)", 3, 30, 1, nil, "restock")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("restockReagents", "Class Reagents",
            "The reagents your known spells use, such as Arcane Powder, candles, seeds, Symbols "
            .. "of Kings and Flash Powder, matched to the highest rank you know.", "restock"),
        S.Toggle("restockAmmo", "Ammo", "The arrows or shot in your ammo slot.", "restock")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("restockAmmoTarget", "Ammo to Carry", 200, 4000, 100, nil, "restockAmmo"),
        S.Toggle("restockFood", "Food & Drink", "Reminds you when you carry little food and drink.",
            "restock")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("restockFoodBelow", "Food & Drink Below", 1, 40, 1, nil, "restockFood"),
        S.Toggle("restockVendor", "Junk & Full Bags",
            "Reminds you to vendor junk, and when your bags are nearly full.", "restock")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("restockBagsBelow", "Free Slots Below", 1, 20, 1, nil, "restockVendor"),
        S.Toggle("restockBuy", "Buy at Vendors",
            "At a vendor who sells them, tops your class reagents and ammo up to what you carry, "
            .. "and prints what it spent. Off by default: it spends gold for you.")
    ); y = y - h

    return y
end

function ns.BuildQoLAlertsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "DURABILITY" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("durability", "Low Durability Warning",
            "Text on screen when any piece of gear drops below the threshold."),
        S.Slider("durabilityBelow", "Warn Below (%)", 5, 100, 1, nil, "durability")
    ); y = y - h

    _, h = W:SectionHeader(parent, "COMBAT" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatAlert", "Combat Alert", "A short flash of text entering and leaving combat."),
        S.Toggle("groupDeaths", "Announce Group Deaths", "Shows who died in your group.")
    ); y = y - h

    return y
end

function ns.BuildQoLInterfacePage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "UI CLUTTER" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideErrors", "Hide Error Messages",
            "Hides the red \"not ready yet\" and \"out of range\" text."),
        S.Toggle("hideTutorials", "Hide Tutorial Pop-ups")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideScreenshot", "Hide Screenshot Status"),
        S.Toggle("skipCinematics", "Skip Cinematics", "Skips cinematics you have already seen.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "ON-SCREEN EXTRAS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("fps", "FPS Counter"),
        S.Toggle("localMS", "Show Local MS", nil, "fps")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("worldMS", "Show World MS", nil, "fps"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "TOWN MAP" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("townMap", "Town Map Pins",
            "Trainers, vendors, innkeepers, flight masters and more pinned on the world map for "
            .. "your faction, with their name and title on hover. No more asking a guard."),
        S.Slider("townPinSize", "Pin Size", 10, 28, 1, nil, "townMap")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("townClass", "Class Trainers", "Your class's trainers only.", "townMap"),
        S.Toggle("townProfession", "Profession Trainers", nil, "townMap")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("townFlight", "Flight Masters", nil, "townMap"),
        S.Toggle("townInn", "Innkeepers", nil, "townMap")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("townBank", "Bank & Auction House", nil, "townMap"),
        S.Toggle("townRepair", "Repairs", nil, "townMap")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("townSupplies", "Reagents, Ammo & Food", nil, "townMap"),
        S.Toggle("townStable", "Stable Masters", nil, "townMap")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("townVendors", "Other Vendors", "Trade goods and every other merchant.", "townMap"),
        { type = "label", text = "" }
    ); y = y - h

    return y
end

function ns.BuildQoLTrainerPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "TRAINER POPUP" .. STATUS.ready, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("trainerPopup", "Trainer Popup",
            "After visiting a trainer, a small window lists the abilities you just learned."),
        S.Toggle("trainerGlow", "Glow New Abilities",
            "Lights up the new abilities on your action bars until you use them.", "trainerPopup")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("trainerRanks", "Offer to Replace Lower Ranks",
            "Adds a button to the popup that swaps every lower rank on your bars for the "
            .. "one you just learned. Keyboard and controller bars land in the same slot.",
            "trainerPopup"),
        { type = "label", text = "      Rank swaps only happen out of combat." }
    ); y = y - h

    return y
end

function ns.BuildQoLFlightPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "FLIGHT TIMER" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("flightTimer", "Flight Timer",
            "Where you are flying and how long is left. The first flight on a route counts up; "
            .. "after that it counts down to landing. Move it in Unlock Mode."),
        S.Toggle("flightQuotes", "Streamer Quotes",
            "A reminder from a streamer beside the timer, like \"Grab some water\", changing "
            .. "every 45 seconds.", "flightTimer")
    ); y = y - h

    _, h = W:SectionHeader(parent, "QUIZ" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("quizFlight", "Quiz While Flying",
            "A WoW quiz opens when a flight starts and closes when you land."),
        S.Toggle("quizCamp", "Quiz at the Campfire",
            "The quiz opens when you sit down at a campfire and closes when you stand up.")
    ); y = y - h
    _, h = W:Button(parent, "Open the Quiz", y, function()
        if ns.ToggleQuiz then ns.ToggleQuiz() end
    end); y = y - h

    return y
end
