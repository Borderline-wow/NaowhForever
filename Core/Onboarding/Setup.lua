-- Setup.lua: Tailor my setup's questions and rules, its Apply and Restore, and a new character's profile.
local ns = _G.NaowhForever
local Setup = {}
ns.Setup = Setup

local FIRST_COPY = 2
local COPY_NAME = "%s %d"
local PICK_ANY = "Pick as many as you like."
local PURIST, ESSENTIALS, EVERYTHING = "purist", "essentials", "everything"
local RECOMMENDED, MINIMALIST, CUSTOM = "recommended", "minimalist", "custom"
local BUNDLE_QUESTIONS = { "focus", "role" }
local UNKNOWN_ORDER = 99

local character

Setup.QUESTIONS = {
    { id = "amount", title = "How much do you want Naowh Forever to do?", one = true, default = "helpful",
      hint = "You can change everything afterwards.",
      answers = {
          { "purist", "I'm a purist", "The game as it is, with a few tools." },
          { "essentials", "Just the essentials", "Keep it close to the game." },
          { "helpful", "A helpful amount", "Keep what I have, add what fits." },
          { "everything", "Everything useful", "Show me what it can do." } } },
    { id = "focus", title = "What do you spend most of your time on?", hint = PICK_ANY,
      answers = {
          { "questing", "Questing and leveling", "Out in the world." },
          { "dungeons", "Dungeons and raids", "With a group, after loot." },
          { "pvp", "PvP", "Battlegrounds and duels." },
          { "professions", "Professions and Auction House", "Crafting and trading." },
          { "collecting", "Collecting and exploring", "Every corner of the map." } } },
    { id = "role", title = "What do you play?", hint = PICK_ANY,
      answers = {
          { "tank", "Tank", "I hold the mobs." },
          { "healer", "Healer", "I keep everyone up." },
          { "melee", "Melee damage", "Up close." },
          { "ranged", "Ranged damage", "From a distance." } } },
    { id = "screen", title = "How busy should your screen be?", one = true, default = "few",
      hint = "Alerts, timers, trackers and bars.",
      answers = {
          { "clean", "Clean", "As little as possible." },
          { "few", "A few helpers", "Where they help." },
          { "all", "Show me everything", "I like to see it all." } } },
    { id = "group", title = "How often do you group up?", one = true, default = "sometimes",
      hint = "This decides the group tools.",
      answers = {
          { "solo", "Mostly solo", "I play on my own." },
          { "sometimes", "Sometimes", "Now and then." },
          { "always", "All the time", "Always in a group." } } },
    { id = "addons", title = "Are you using any of these addons?", hint = PICK_ANY,
      answers = {
          { "guide", "A quest guide", "It leads me through quests." },
          { "threat", "A threat meter", "It shows threat already." },
          { "none", "None of these", "Neither of them.", none = true } } },
    { id = "classic", title = "How well do you know Classic?", one = true, default = "played",
      hint = "This decides the guide helpers.",
      answers = {
          { "new", "New to it", "Show me the way." },
          { "played", "Played before", "I know the basics." },
          { "expert", "Know it inside out", "I know the way." } } },
}

Setup.THEMES = { "Questing", "Map and Travel", "Dungeons", "Combat", "Group", "PvP",
    "Professions", "Collecting", "Quality of Life", "Interface" }
Setup.THEME_ICONS = {
    Questing = "questing", ["Map and Travel"] = "travel", Dungeons = "dungeons", Combat = "melee",
    Group = "sometimes", PvP = "pvp", Professions = "professions", Collecting = "collecting",
    ["Quality of Life"] = "qol", Interface = "interface",
}
local THEME_OF = {}
for theme, ids in pairs({
    Questing = { "questAuto", "questRewards", "talentPoints", "xpBar", "xpTicker", "trainerPopup", "training" },
    ["Map and Travel"] = { "townMap", "mapUnexplored", "waypoints", "flightTimer", "flightGames" },
    Dungeons = { "journal", "bis", "gearSets", "naowhScore", "characterPanel", "inspectPanel",
        "equipReminder", "deathRelease", "restock", "durability", "mapEntrances", "journalTracker", "combatLogger" },
    Combat = { "threatMeter", "swingTimer", "combatAlert", "combatTimer", "cursorCooldown", "focusCastBar", "coTank",
        "healerMana", "auraBuffs", "blessings", "petTracker", "petPassive", "stealthReminder" },
    Group = { "groupInspect", "groupInspectShare", "groupButtons", "groupXP", "questShare" },
    PvP = { "pvp" },
    Professions = { "professions", "ahPrices", "ahTooltip", "bagSpace", "scrapMarker", "mailAlts", "altCounts",
        "mailExpiry" },
    Collecting = { "discovery", "completo", "rarePins", "rareAlert", "bookTracker" },
    ["Quality of Life"] = { "qol", "fastLoot", "sellJunk", "autoRepair", "restockBuy", "skipCinematics", "hideTutorials",
        "mailQuickAttach", "deleteConfirm", "quizCamp", "macros" },
    Interface = { "actionBars", "topBar", "lootFeed", "tooltipDisplay", "clock", "hideErrors", "hideScreenshot", "hideAlerts", "hideEventToasts",
        "hideZoneText", "cursorClip", "tooltipCopy", "globalCopy" },
}) do
    for _, id in ipairs(ids) do THEME_OF[id] = theme end
end
Setup.THEME_OF = THEME_OF

Setup.DETECT = {
    guide = { { "RXPGuides", "RestedXP" }, { "TourGuide", "TourGuide" }, { "ZygorGuidesViewerClassic", "Zygor" },
        { "ZygorGuidesViewer", "Zygor" } },
    threat = { { "ThreatClassic2", "ThreatClassic2" }, { "Omen", "Omen" } },
}

Setup.ITEMS = {
    qol = { name = "Quality of Life", addon = "NaowhForever_QoL", db = "qol", key = "enabled" },
    journal = { name = "Dungeon Journal", addon = "NaowhForever_DungeonJournal", db = "journal", key = "enabled" },
    bis = { name = "BiS List", addon = "NaowhForever_BiS", db = "qol", key = "bis" },
    training = { name = "Training Planner", addon = "NaowhForever_Training", db = "training", key = "enabled",
        guide = true },
    professions = { name = "Professions", addon = "NaowhForever_Professions", db = "professions", key = "enabled" },
    discovery = { name = "Discovery", addon = "NaowhForever_Discovery", db = "discovery", key = "enabled" },
    completo = { name = "Completo", addon = "NaowhForever_Completo", db = "completo", key = "enabled" },
    macros = { name = "Macros", addon = "NaowhForever_Macros", db = "macros", key = "enabled", extra = true },
    topBar = { name = "Top Bar", addon = "NaowhForever_TopBar", db = "topBar", key = "enabled" },
    actionBars = { name = "Action Bars", addon = "NaowhForever_ActionBars", db = "actionBars", key = "enabled",
        extra = true },
    gearSets = { name = "Gear & Trinkets", addon = "NaowhForever_GearSets", db = "qol", key = "gearSets" },
    blessings = { name = "Blessings", addon = "NaowhForever_Blessings", db = "qol", key = "blessings" },
    auraBuffs = { name = "AuraBuffs", addon = "NaowhForever_AuraBuffs", db = "auraBuffs", key = "enabled" },
    threatMeter = { name = "Threat Meter", addon = "NaowhForever_ThreatMeter", db = "threatMeter", key = "enabled",
        screen = true },
    groupInspect = { name = "Group Inspect", addon = "NaowhForever_GroupInspect", db = "qol", key = "groupInspect",
        group = true },
    pvp = { name = "PvP", addon = "NaowhForever_PvP", db = "pvp", key = "enabled" },
    swingTimer = { name = "Swing Timer", addon = "NaowhForever_SwingTimer", db = "swingTimer", key = "enabled",
        screen = true },

    questAuto = { name = "Quest Automation", store = "QoLSettings", needs = "qol", key = "questAccept", also = { "questTurnIn", "questGossip" } },
    questRewards = { name = "Saved Quest Rewards", store = "QoLSettings", needs = "qol", key = "questRewardPicks" },
    questShare = { name = "Share Quests With Group", store = "QoLSettings", needs = "qol", key = "questShare", group = true },
    restockBuy = { name = "Buy at Vendors", store = "QoLSettings", needs = "qol", key = "restockBuy", extra = true },
    ahTooltip = { name = "Auction House Price", store = "QoLSettings", needs = "qol", key = "ahTooltip" },
    altCounts = { name = "Alt Item Counts", store = "QoLSettings", needs = "qol", key = "altCounts" },
    mailAlts = { name = "Alts Button on Mail", store = "QoLSettings", needs = "qol", key = "mailAlts" },
    mailExpiry = { name = "Mail Expiry Warning", store = "QoLSettings", needs = "qol", key = "mailExpiry" },
    hideErrors = { name = "Hide Red Error Text", store = "QoLSettings", needs = "qol", key = "hideErrors", hide = true },
    hideScreenshot = { name = "Hide Screen Captured Text", store = "QoLSettings", needs = "qol", key = "hideScreenshot", hide = true },
    hideAlerts = { name = "Hide Alert Pop-ups", store = "QoLSettings", needs = "qol", key = "hideAlerts", hide = true },
    hideEventToasts = { name = "Hide Event Toasts", store = "QoLSettings", needs = "qol", key = "hideEventToasts", hide = true },
    hideZoneText = { name = "Hide Zone Text", store = "QoLSettings", needs = "qol", key = "hideZoneText", hide = true },
    cursorClip = { name = "Keep Cursor In Window", store = "QoLSettings", needs = "qol", key = "cursorClip", extra = true },
    tooltipCopy = { name = "Copy Shortcut", store = "QoLSettings", needs = "qol", key = "tooltipCopy", extra = true },
    globalCopy = { name = "Copy Command", store = "QoLSettings", needs = "qol", key = "globalCopy", extra = true },
    quizCamp = { name = "Quiz at the Campfire", store = "QoLSettings", needs = "qol", key = "quizCamp", guide = true },
    petPassive = { name = "Warn While Passive", store = "QoLSettings", needs = "qol", key = "petPassive" },
    talentPoints = { name = "Talent Points", store = "QoLSettings", needs = "qol", key = "talentPoints", screen = true },
    xpBar = { name = "XP Bar", store = "QoLSettings", needs = "qol", key = "xpBar", screen = true },
    xpTicker = { name = "XP per Hour", store = "QoLSettings", needs = "qol", key = "xpTicker", screen = true, hud = true },
    groupXP = { name = "Group XP", store = "QoLSettings", needs = "qol", key = "groupXP", screen = true, group = true },
    trainerPopup = { name = "Trainer Popup", store = "QoLSettings", needs = "qol", key = "trainerPopup", guide = true },
    townMap = { name = "Map Pins", store = "QoLSettings", needs = "qol", key = "townMap", guide = true },
    mapUnexplored = { name = "Unexplored Areas", store = "QoLSettings", needs = "qol", key = "mapUnexplored" },
    waypoints = { name = "Waypoint Pin", store = "QoLSettings", needs = "qol", key = "waypoints" },
    naowhScore = { name = "Naowh Score", store = "QoLSettings", key = "naowhScore" },
    characterPanel = { name = "Character Panel", store = "QoLSettings", key = "characterPanel",
        pick = "characterPanelPicked" },
    inspectPanel = { name = "Inspect Panel", store = "QoLSettings", key = "inspectPanel", pick = "inspectPanelPicked" },
    equipReminder = { name = "Equipment Reminder", store = "QoLSettings", needs = "qol", key = "equipReminder", screen = true },
    deathRelease = { name = "Death Release Protection", store = "QoLSettings", needs = "qol", key = "deathRelease" },
    restock = { name = "Restock Reminder", store = "QoLSettings", needs = "qol", key = "restock", screen = true },
    durability = { name = "Durability", store = "QoLSettings", needs = "qol", key = "durability", screen = true, hud = true },
    combatAlert = { name = "Combat Alert", store = "QoLSettings", needs = "qol", key = "combatAlert", screen = true, hud = true },
    combatTimer = { name = "Combat Timer", store = "QoLSettings", needs = "qol", key = "combatTimer", screen = true, hud = true },
    cursorCooldown = { name = "Cooldown at Cursor", store = "QoLSettings", needs = "qol", key = "cursorCooldown", screen = true },
    focusCastBar = { name = "Focus Cast Bar", store = "QoLSettings", needs = "qol", key = "focusCastBar", screen = true },
    coTank = { name = "Co-Tank Frame", store = "QoLSettings", needs = "qol", key = "coTank", screen = true },
    healerMana = { name = "Healer Mana", store = "QoLSettings", needs = "qol", key = "healerMana", screen = true },
    petTracker = { name = "Pet Tracker", store = "QoLSettings", needs = "qol", key = "petTracker", screen = true },
    stealthReminder = { name = "Stealth Reminder", store = "QoLSettings", needs = "qol", key = "stealthReminder", screen = true },
    groupButtons = { name = "On-Screen Buttons", store = "QoLSettings", needs = "qol", key = "groupButtons", screen = true,
        group = true },
    groupInspectShare = { name = "Share Your Stats", store = "QoLSettings", key = "groupInspectShare", group = true },
    ahPrices = { name = "Auction Prices", store = "QoLSettings", needs = "qol", key = "ahPrices" },
    bagSpace = { name = "Bag Space", store = "QoLSettings", needs = "qol", key = "bagSpace" },
    scrapMarker = { name = "Scrap Marker", store = "QoLSettings", needs = "qol", key = "scrapMarker" },
    lootFeed = { name = "Loot Feed", store = "QoLSettings", needs = "qol", key = "lootFeed", screen = true, hud = true },
    tooltipDisplay = { name = "Tooltip IDs", store = "QoLSettings", needs = "qol", key = "tooltipDisplay", guide = true },
    clock = { name = "Top Bar Clock", store = "TopBarSettings", db = "topBar", key = "showClock", screen = true, hud = true,
        needs = "topBar" },
    flightTimer = { name = "Flight Timer", store = "QoLSettings", needs = "qol", key = "flightTimer" },
    combatLogger = { name = "Auto Combat Logging", store = "QoLSettings", needs = "qol", key = "combatLogger",
        set = { combatLogRaids = "always", combatLogDungeons = "always" } },
    fastLoot = { name = "Faster Auto Loot", store = "QoLSettings", needs = "qol", key = "fastLoot", quiet = true },
    sellJunk = { name = "Auto Sell Junk", store = "QoLSettings", needs = "qol", key = "sellJunk", quiet = true },
    autoRepair = { name = "Auto Repair", store = "QoLSettings", needs = "qol", key = "autoRepair", quiet = true },
    skipCinematics = { name = "Skip Cinematics", store = "QoLSettings", needs = "qol", key = "skipCinematics", quiet = true },
    hideTutorials = { name = "Turn Off Tutorials", store = "QoLSettings", needs = "qol", key = "hideTutorials", quiet = true },
    mailQuickAttach = { name = "Mail Quick Attach", store = "QoLSettings", needs = "qol", key = "mailQuickAttach", quiet = true },
    deleteConfirm = { name = "Type DELETE For You", store = "QoLSettings", needs = "qol", key = "deleteConfirm", quiet = true },
    flightGames = { name = "Flight Games", store = "QoLSettings", needs = "qol", key = "flightGame", off = "off" },
    mapEntrances = { name = "Dungeon Entrances", store = "JournalSettings", db = "journal", key = "mapEntrances",
        needs = "journal" },
    journalTracker = { name = "Dungeon Quest Tracker", store = "JournalSettings", db = "journal", key = "trackerAuto",
        needs = "journal", guide = true },
    rareAlert = { name = "Rare Alerts", store = "CompletoSettings", db = "completo", key = "rareAlert", screen = true,
        needs = "completo" },
    rarePins = { name = "Rare Map Pins", store = "CompletoSettings", db = "completo", key = "rarePins",
        needs = "completo" },
    bookTracker = { name = "Library Books Tracker", store = "DiscoverySettings", db = "discovery", key = "tracker",
        screen = true, needs = "discovery" },
}

Setup.BUNDLES = {
    questing = { why = "You spend time questing and leveling.", core = { "xpBar", "talentPoints", "townMap" },
        more = { "xpTicker", "mapUnexplored", "waypoints", "trainerPopup", "questAuto", "questRewards", "training" } },
    dungeons = { why = "You run dungeons and raids.", core = { "journal", "bis", "combatLogger" },
        more = { "gearSets", "naowhScore", "characterPanel", "inspectPanel", "equipReminder", "deathRelease",
            "restock", "durability", "mapEntrances" } },
    pvp = { why = "You play PvP.", core = { "pvp" }, more = { "combatAlert", "cursorCooldown", "focusCastBar" } },
    professions = { why = "You spend time on professions and the Auction House.", core = { "professions" },
        more = { "training", "ahPrices", "ahTooltip", "bagSpace", "scrapMarker", "mailAlts", "altCounts",
            "mailExpiry" } },
    collecting = { why = "You like collecting and exploring.", core = { "discovery" },
        more = { "completo", "mapUnexplored", "rarePins", "rareAlert", "bookTracker" } },
    tank = { why = "You tank.", core = { "threatMeter" }, more = { "coTank" } },
    healer = { why = "You heal.", core = { "healerMana" }, more = { "auraBuffs" } },
    melee = { why = "You play melee.", core = { "swingTimer" }, more = {} },
    ranged = { why = "You play ranged.", core = {}, more = {} },
}

Setup.PURIST = { "qol", "bis", "journal", "groupInspect", "groupInspectShare", "naowhScore", "characterPanel", "inspectPanel",
    "flightTimer", "flightGames", "hideErrors", "petPassive" }

Setup.QUIET_ESSENTIALS = { fastLoot = true, sellJunk = true }

Setup.CORE = { "journal", "bis", "naowhScore", "characterPanel", "inspectPanel", "lootFeed", "flightTimer",
    "flightGames" }

Setup.CLASS = {
    PALADIN = { "blessings" }, HUNTER = { "petTracker", "petPassive" }, WARLOCK = { "petTracker", "petPassive" },
    ROGUE = { "stealthReminder" }, DRUID = { "stealthReminder" },
}

Setup.OVERLAP = {
    guide = { why = "You use a quest guide.", off = { "questAuto", "questRewards" } },
    threat = { why = "You use a threat meter.", off = { "threatMeter" } },
}

local WHY = {
    base = "From the %s setup.", clean = "You picked a clean screen.", all = "You want to see everything.",
    solo = "You mostly play solo.", always = "You group up all the time.", new = "You are new to Classic.",
    expert = "You know Classic inside out.", class = "For your class.", needs = "%s needs it.",
    needed = "Needs %s, which stays off.", stays = "Stays as you have it.",
    core = "Core of Naowh Forever.", purist = "You're a purist.", kept = "Doesn't change how the game plays.",
    quiet = "Saves you time; the game plays the same.", everything = "You want everything useful.",
}

local function Picked(answers, id, key)
    local value = answers[id]
    if type(value) == "table" then return value[key] == true end
    return value == key
end

local function Question(id)
    for _, question in ipairs(Setup.QUESTIONS) do
        if question.id == id then return question end
    end
end

local function Chosen(answers, id)
    local q = Question(id)
    local value = answers[id]
    if value == nil and q then value = q.default end
    return value
end

local function Set(p, id, on, reason)
    if Setup.ITEMS[id] and not p.forced[id] then p.want[id], p.why[id] = on, reason end
end

local function Bundle(p, bundle)
    for _, id in ipairs(bundle.core) do Set(p, id, true, bundle.why) end
    if p.amount == ESSENTIALS then return end
    for _, id in ipairs(bundle.more) do Set(p, id, true, bundle.why) end
end

local function PuristBase(p)
    for id in pairs(Setup.ITEMS) do p.want[id], p.why[id] = false, WHY.purist end
    for _, id in ipairs(Setup.PURIST) do p.want[id], p.why[id], p.forced[id] = true, WHY.kept, true end
end

local function PresetBase(p, base, ctx)
    local baseWhy = WHY.base:format(ctx.presetName and ctx.presetName(base) or base)
    for id in pairs(Setup.ITEMS) do
        local value = ctx.base(base, id)
        if value ~= nil then p.want[id], p.why[id] = value == true, baseWhy end
    end
end

local function QuietItems(p)
    for id, item in pairs(Setup.ITEMS) do
        if item.quiet and (p.amount ~= ESSENTIALS or Setup.QUIET_ESSENTIALS[id]) then
            p.want[id], p.why[id], p.forced[id] = true, WHY.quiet, p.purist or nil
        end
    end
end

local function AnsweredBundles(p, answers)
    for _, q in ipairs(BUNDLE_QUESTIONS) do
        for _, a in ipairs(Question(q).answers) do
            if Picked(answers, q, a[1]) then Bundle(p, Setup.BUNDLES[a[1]]) end
        end
    end
end

local function ItemTraits(p, item, id, screen, group, classic)
    if screen == "clean" and item.screen then Set(p, id, false, WHY.clean) end
    if screen == "clean" and item.hide then Set(p, id, true, WHY.clean) end
    if p.amount == EVERYTHING and item.extra then Set(p, id, true, WHY.everything) end
    if screen == "all" and item.hud then Set(p, id, true, WHY.all) end
    if group == "solo" and item.group then Set(p, id, false, WHY.solo) end
    if group == "always" and item.group then Set(p, id, true, WHY.always) end
    if classic == "new" and item.guide then Set(p, id, true, WHY.new) end
    if classic == "expert" and item.guide then Set(p, id, false, WHY.expert) end
end

local function Traits(p, answers)
    local screen, group, classic = Chosen(answers, "screen"), Chosen(answers, "group"), Chosen(answers, "classic")
    for id, item in pairs(Setup.ITEMS) do ItemTraits(p, item, id, screen, group, classic) end
end

local function Overlaps(p, answers)
    for key, overlap in pairs(Setup.OVERLAP) do
        if Picked(answers, "addons", key) then
            for _, id in ipairs(overlap.off) do
                Set(p, id, false, overlap.why)
                p.forced[id] = true
            end
        end
    end
end

local function Answered(p, answers, ctx)
    AnsweredBundles(p, answers)
    for _, id in ipairs(Setup.CLASS[ctx.class] or {}) do Set(p, id, true, WHY.class) end
    Traits(p, answers)
    Overlaps(p, answers)
    for _, id in ipairs(Setup.CORE) do
        p.want[id], p.why[id], p.forced[id] = true, WHY.core, true
    end
end

local function Kept(p, ctx, id)
    return not p.purist and ctx.read(id) == false and ctx.mine(id) == true
end

local function Needs(item, links, id)
    return item.needs and { item.needs } or links[id]
end

local function MeetNeeds(p, ctx, links)
    for id, item in pairs(Setup.ITEMS) do
        for _, need in ipairs(Needs(item, links, id) or {}) do
            local needOn = p.want[need]
            if needOn == nil then needOn = ctx.read(need) end
            if p.want[id] and needOn == false and not Kept(p, ctx, id) then
                if p.forced[need] then
                    p.want[id], p.why[id] = false, WHY.needed:format(Setup.ITEMS[need].name)
                else
                    p.want[need], p.why[need] = true, WHY.needs:format(item.name)
                end
            end
        end
    end
end

local function Entry(p, ctx, links, id, item, now)
    local suggest = p.want[id]
    if suggest == nil then suggest = now end
    local mine = not p.purist and suggest ~= now and ctx.mine(id) == true
    return { id = id, name = item.name, theme = THEME_OF[id], now = now, suggest = suggest,
        on = (mine and now) or (not mine and suggest), why = p.why[id] or WHY.stays, mine = mine,
        module = item.addon ~= nil, loaded = not ctx.loaded or ctx.loaded(id) == true,
        idle = item.addon ~= nil and not now and ctx.enabled ~= nil and ctx.enabled(id) == true,
        needs = Needs(item, links, id) }
end

local themeOrder = {}
for i, theme in ipairs(Setup.THEMES) do themeOrder[theme] = i end

local function ByTheme(a, b)
    if a.theme ~= b.theme then return (themeOrder[a.theme] or UNKNOWN_ORDER) < (themeOrder[b.theme] or UNKNOWN_ORDER) end
    return a.name < b.name
end

function Setup.Plan(answers, ctx)
    local amount = Chosen(answers, "amount")
    local base = amount == EVERYTHING and RECOMMENDED or amount == ESSENTIALS and MINIMALIST
    local p = { want = {}, why = {}, forced = {}, amount = amount, purist = amount == PURIST }
    if p.purist then PuristBase(p) end
    if base then PresetBase(p, base, ctx) end
    QuietItems(p)
    if not p.purist then Answered(p, answers, ctx) end
    local links = ctx.links or {}
    MeetNeeds(p, ctx, links)
    local entries = {}
    for id, item in pairs(Setup.ITEMS) do
        local now = ctx.read(id)
        if now ~= nil then entries[#entries + 1] = Entry(p, ctx, links, id, item, now) end
    end
    Setup.Settle(entries)
    table.sort(entries, ByTheme)
    return entries
end

local function ByID(entries)
    local by = {}
    for _, e in ipairs(entries) do by[e.id] = e end
    return by
end

function Setup.Settle(entries)
    local by, blocked, changed = ByID(entries), {}, true
    while changed do
        changed = false
        for _, e in ipairs(entries) do
            for _, need in ipairs(e.on and e.needs or {}) do
                local n = by[need]
                if n and not n.on then
                    if n.mine or blocked[n.id] then
                        e.on, e.why, blocked[e.id] = false, WHY.needed:format(n.name), true
                    else
                        n.on, n.why = true, WHY.needs:format(e.name)
                    end
                    changed = true
                end
            end
        end
    end
end

function Setup.Toggle(entries, id, on)
    local by = ByID(entries)
    local function Flip(e, value)
        if not e or e.on == value then return end
        e.on = value
        if value then
            for _, need in ipairs(e.needs or {}) do Flip(by[need], true) end
        else
            for _, other in ipairs(entries) do
                for _, need in ipairs(other.on and other.needs or {}) do
                    if need == e.id then Flip(other, false) end
                end
            end
        end
    end
    Flip(by[id], on)
end

function Setup.Skips(answers)
    return answers.amount == "purist"
end

function Setup.Differs(e)
    return e.on ~= e.now or (e.idle and not e.on)
end

function Setup.Counts(entries)
    local on, off, stay = 0, 0, 0
    for _, e in ipairs(entries) do
        if not Setup.Differs(e) then stay = stay + 1 elseif e.on then on = on + 1 else off = off + 1 end
    end
    return on, off, stay
end

function Setup.NeedsReload(entries)
    local by = ByID(entries)
    for _, e in ipairs(entries) do
        if e.module and Setup.Differs(e) then
            if e.now and not e.on then return true end
            if e.on and not e.loaded then return true end
            for _, need in ipairs(e.on and e.needs or {}) do
                if by[need] and by[need].module and not by[need].loaded then return true end
            end
        end
    end
    return false
end

local savedStores = {}

local function SavedStore(db)
    if savedStores[db] then return savedStores[db] end
    local s = { key = db }
    function s.Get(k)
        local values = ns.SettingsRoot()[db]
        return type(values) == "table" and values[k] == true
    end
    function s.Set(k, v)
        local root = ns.SettingsRoot()
        if type(root[db]) ~= "table" then root[db] = {} end
        root[db][k] = v
    end
    function s.Default() return false end
    savedStores[db] = s
    return s
end

local function Store(item)
    local store = item.store and ns[item.store]
    if store or item.addon or not item.db then return store end
    return SavedStore(item.db)
end

local function Module(item)
    for _, mod in ipairs(ns.ModuleAddons and ns.ModuleAddons() or {}) do
        if mod.addon == item.addon then return mod end
    end
end

local function Links()
    local byAddon, links = {}, {}
    for id, item in pairs(Setup.ITEMS) do
        if item.addon then byAddon[item.addon] = id end
    end
    for id, item in pairs(Setup.ITEMS) do
        if item.addon and ns.LinkedAddons then
            local list = ns.LinkedAddons(item.addon, true)
            for i = 2, #list do
                if byAddon[list[i]] then
                    links[id] = links[id] or {}
                    links[id][#links[id] + 1] = byAddon[list[i]]
                end
            end
        end
    end
    return links
end

local function EnableState(addon, who)
    if who then return C_AddOns.GetAddOnEnableState(addon, who) end
    return C_AddOns.GetAddOnEnableState(addon)
end

local function SetAddOn(addon, on, who)
    local set = on and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn
    if who then return set(addon, who) end
    set(addon)
end

local function ModuleOn(item)
    local mod = Module(item)
    if not mod then return nil end
    if character and EnableState(item.addon, character) == 0 then return false end
    return mod.on == true
end

local function Read(id)
    local item = Setup.ITEMS[id]
    if item.addon then return ModuleOn(item) end
    local store = Store(item)
    if not store then return nil end
    if item.off then return store.Get(item.key) ~= item.off end
    return store.Get(item.key) == true
end

local function Base(preset, id)
    local item = Setup.ITEMS[id]
    local P = ns.PRESETS and ns.PRESETS[preset]
    local store = Store(item)
    local db = item.db or (store and store.key)
    local values = P and db and P.profile[db]
    local value = values and values[item.key]
    if value == nil and store then value = store.Default(item.key) end
    if value == nil and item.addon then
        local mod = Module(item)
        if mod and mod.store then value = mod.store.Default(mod.key) end
    end
    if item.off and value ~= nil then return value ~= item.off end
    return value
end

local function Mine(id)
    local yours = ns.SettingsRoot().setupYours
    if type(yours) == "table" and yours[id] then return true end
    local preset = ns.QoLSettings.Get("preset")
    local now = Read(id)
    local ref = Base(ns.PRESETS and ns.PRESETS[preset] and preset or "", id)
    if ref == nil then return false end
    return now ~= (ref == true)
end

local function Enabled(id)
    local item = Setup.ITEMS[id]
    return item.addon ~= nil and EnableState(item.addon, character) > 0
end

local function Loaded(id)
    local item = Setup.ITEMS[id]
    return item.addon ~= nil and C_AddOns.IsAddOnLoaded(item.addon)
end

function Setup.ForCharacter(on)
    character = on and UnitGUID("player") or nil
end

function Setup.Context()
    local _, class = UnitClass("player")
    return { read = Read, base = Base, mine = Mine, loaded = Loaded, enabled = Enabled, class = class, links = Links(),
        presetName = function(key) return ns.PRESETS[key] and ns.PRESETS[key].name or key end }
end

function Setup.Detected()
    local found = {}
    for key, addons in pairs(Setup.DETECT) do
        for _, addon in ipairs(addons) do
            if not found[key] and C_AddOns.IsAddOnLoaded(addon[1]) then found[key] = addon[2] end
        end
    end
    return found
end

local function AddonsNow()
    local states = {}
    for _, mod in ipairs(ns.ModuleAddons()) do states[mod.addon] = EnableState(mod.addon, character) > 0 end
    return states
end

function Setup.Backup()
    ns.AccountSettings().setupBefore = { profile = ns.ActiveProfileName(), root = CopyTable(ns.SettingsRoot()),
        addons = AddonsNow(), character = character }
end

function Setup.CanRestore()
    local saved = ns.AccountSettings().setupBefore
    return type(saved) == "table" and saved.profile == ns.ActiveProfileName()
end

function Setup.Restore()
    if not Setup.CanRestore() then return false end
    local saved = ns.AccountSettings().setupBefore
    local root = ns.SettingsRoot()
    for k in pairs(root) do root[k] = nil end
    for k, v in pairs(saved.root) do root[k] = type(v) == "table" and CopyTable(v) or v end
    for addon, on in pairs(saved.addons) do SetAddOn(addon, on, saved.character) end
    ns.AccountSettings().setupBefore = nil
    return true
end

local function EnableModule(item, mod)
    local reload = false
    for _, addon in ipairs(ns.LinkedAddons(item.addon, true)) do
        if EnableState(addon, character) == 0 then SetAddOn(addon, true, character) end
        if not C_AddOns.IsAddOnLoaded(addon) then reload = true end
    end
    if mod and mod.store then
        mod.store.Set(mod.key, true)
        return reload
    end
    local root = ns.SettingsRoot()
    if type(root[item.db]) ~= "table" then root[item.db] = {} end
    root[item.db][item.key] = true
    return true
end

local function ApplyModule(item, change)
    local mod = Module(item)
    if change.on then return EnableModule(item, mod) end
    for _, addon in ipairs(ns.LinkedAddons(item.addon, false)) do SetAddOn(addon, false, character) end
    return change.now
end

local function ApplySetting(item, change)
    local store = Store(item)
    if item.off then
        if not change.on then
            store.Set(item.key, item.off)
        elseif store.Get(item.key) == item.off then
            store.Set(item.key, store.Default(item.key))
        end
    else
        store.Set(item.key, change.on)
    end
    for _, key in ipairs(item.also or {}) do store.Set(key, change.on) end
    if not change.on then return end
    for key, value in pairs(item.set or {}) do
        if store.Get(key) == store.Default(key) then store.Set(key, value) end
    end
end

local function Yours(entries)
    local yours = {}
    for _, change in ipairs(entries) do
        if change.on ~= change.suggest then yours[change.id] = true end
    end
    return yours
end

function Setup.Apply(entries)
    Setup.Backup()
    local reload = false
    for _, change in ipairs(entries) do
        local item = Setup.ITEMS[change.id]
        if item.pick and change.on then Store(item).Set(item.pick, true) end
        if Setup.Differs(change) then
            if not item.addon then
                ApplySetting(item, change)
            elseif ApplyModule(item, change) then
                reload = true
            end
        end
    end
    ns.SettingsRoot().setupYours = Yours(entries)
    ns.QoLSettings.Set("preset", CUSTOM)
    return reload
end

local function FreeName(name)
    local free, n = name, FIRST_COPY
    while ns.ProfileExists(free) do
        free, n = COPY_NAME:format(name, n), n + 1
    end
    return free
end

function Setup.ShareProfile(profile)
    if profile == ns.ActiveProfileName() then return false end
    return ns.SwitchProfile(profile) == true
end

function Setup.OwnProfile(name)
    local own = FreeName(name)
    if not ns.CopyProfile(ns.ActiveProfileName(), own) then return false end
    return ns.SwitchProfile(own) == true
end
