-------------------------------------------------------------------------------
--  NaowhForever_QoL.lua -- the QoL module: NaowhUI's QoL page, trimmed to what
--  Forever has (no Mythic+, keystones, talking heads or retail spec bars), plus the loot
--  feed and the trainer popup.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local STATUS = UI.STATUS

local S = UI.ModuleSettings("qol", {
    enabled = true,
    deathRelease = false, deathReleaseHold = 1,
    stealthReminder = false, formReminder = false,
    reminderInGroup = false, reminderHideResting = true,
    stealthShowStealthed = true, stealthDruid = "cat",
    stealthText = "STEALTH", stealthColor = { r = 0, g = 1, b = 0 }, stealthClassColor = false,
    warningText = "RESTEALTH", warningColor = { r = 1, g = 0, b = 0 }, warningClassColor = false,
    stealthFont = "", stealthFontSize = 22,
    formDruid = "none", formShadowform = false, formCombatOnly = false, formInstanceOnly = false,
    formText = "", formColor = { r = 1, g = 0.4, b = 0 }, formClassColor = false,
    formFont = "", formFontSize = 22,
    formSound = false, formSoundKey = "none", formSoundInterval = 3,
    coTank = false, coTankName = true, coTankClassColor = true, coTankDebuffs = false,
    coTankWidth = 180, coTankHeight = 30,
    coTankColor = { r = 0, g = 0.8, b = 0.2 }, coTankBgAlpha = 0.6,
    coTankNameClassColor = false, coTankNameColor = { r = 1, g = 1, b = 1 },
    coTankNameLength = 0, coTankFont = "", coTankFontSize = 12,
    coTankAnchor = "UIParent", coTankX = 0, coTankY = 0,

    deleteConfirm = false, lootConfirm = false,
    questAccept = false, questTurnIn = false, questGossip = false, questRewardPicks = true,
    combatTimer = false, combatTimerInstanceOnly = false, combatTimerChat = true,
    combatTimerSticky = false, combatTimerHidePrefix = false, combatTimerBackground = false,
    combatTimerColor = { r = 1, g = 1, b = 1 }, combatTimerClassColor = false,
    combatTimerFont = "", combatTimerFontSize = 32,
    combatLogger = false,
    globalCopy = false, copyTooltipIds = true, copyModifier = "CTRL", copyKey = "C",
    tooltipDisplay = true, tooltipSpellID = true, tooltipNPCID = true, tooltipItemID = true,
    tooltipRestricted = "hide", tooltipCopy = true, tooltipModifier = "CTRL-SHIFT", tooltipKey = "C",
    tooltipCopyFormat = "url", tooltipWowhead = "classic",
    slashCommands = false,
    lootFeed = true, lootFeedMoney = true, lootFeedXP = false, lootFeedQuality = 1,
    lootFeedQuest = true, lootFeedRep = false,
    lootFeedCount = 6, lootFeedFade = 5, lootFeedStyle = "dark", lootFeedGlow = false,
    lootFeedValue = true, lootFeedBank = true, lootFeedPrice = "vendor", lootFeedGPH = false,
    hideLootWindow = false,
    lootFeedWidth = 340, lootFeedHeight = 36, lootFeedSpacing = 0,
    lootFeedFont = "", lootFeedFontSize = 13,
    ahPrices = true, ahTooltip = true,
    xpTicker = true, xpTickerLevel = true, xpTickerElapsed = false, xpTickerTotal = false,
    xpTickerHideResting = false, xpTickerFont = "", xpTickerFontSize = 24,
    xpTickerSplits = true, xpTickerSplitCount = 4, xpTickerCompare = true,
    xpBar = false, xpBarPlayed = false, xpBarSession = false, xpBarLeveling = false,
    xpBarCompleted = false, xpBarIncomplete = false, xpBarMaxLevel = false,
    xpBarResetOnReload = false, xpBarWidth = 520, xpBarHeight = 26,
    autoRepair = false, sellJunk = false,
    restock = true, restockReagents = true, restockAmmo = true, restockAmmoTarget = 1000,
    restockFood = true, restockFoodBelow = 10, restockVendor = true, restockBagsBelow = 4,
    restockBuy = false,
    dqTracker = true, dqShowDone = false, dqAllFactions = false, dqOutside = false,
    dqSingle = false, dqSelected = "",
    townMap = true, townClass = true, townProfession = true, townFlight = true, townInn = true,
    townBank = true, townStable = false, townRepair = true, townSupplies = true,
    townVendors = false, townPinSize = 16,
    gearSets = true, gearBarSize = 32, gearMounted = "", gearResting = "",
    bis = true, bisTooltip = true, bisLootAlert = true,
    blessings = true, blessBarSize = 30, blessTimers = true, blessShowAura = true,
    blessShowFury = false,

    durability = true, durabilityBelow = 25, durabilityFont = "",
    combatAlert = false, groupDeaths = false,
    combatEnterText = "+Combat", combatEnterColor = { r = 0, g = 1, b = 0 },
    combatEnterClassColor = false,
    combatLeaveText = "-Combat", combatLeaveColor = { r = 1, g = 0, b = 0 },
    combatLeaveClassColor = false,
    combatAlertFont = "", combatAlertFontSize = 32,
    combatEnterAudio = "none", combatEnterSound = "none", combatEnterSpeech = "Combat",
    combatLeaveAudio = "none", combatLeaveSound = "none", combatLeaveSpeech = "Safe",
    combatEnterVoice = "", combatEnterVolume = 50, combatEnterRate = 0,
    combatLeaveVoice = "", combatLeaveVolume = 50, combatLeaveRate = 0,

    hideErrors = false, hideTutorials = false, hideScreenshot = false,
    skipCinematics = false,
    hideAlerts = false, hideEventToasts = false, hideZoneText = false,
    cursorClip = false,
    crosshair = false, crossSize = 20, crossThickness = 2, crossGap = 6,
    crossColor = { r = 0, g = 1, b = 0 }, crossClassColor = false, crossOpacity = 0.8,
    crossX = 0, crossY = 0, crossCombatOnly = false, crossHideMounted = false,
    crossTop = true, crossRight = true, crossBottom = true, crossLeft = true,
    crossDot = false, crossDotSize = 2,
    crossOutline = true, crossOutlineWeight = 1, crossOutlineColor = { r = 0, g = 0, b = 0 },
    crossCircle = false, crossCircleSize = 30, crossCircleColor = { r = 0, g = 1, b = 0 },
    crossMelee = false, crossMeleeColor = { r = 1, g = 0, b = 0 }, crossMeleeBorder = true,
    crossMeleeArms = false, crossMeleeDot = false, crossMeleeCircle = false,
    crossMeleeSound = false, crossMeleeSoundKey = "none", crossMeleeSoundInterval = 3,
    crossMeleeSpell = 0,
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

local PRICE_VALUES = { vendor = "Vendor Price", ahscan = "Auction (Naowh Scan)", tsm = "Auction (TSM)" }
local PRICE_ORDER = { "vendor", "ahscan", "tsm" }

local DRUID_STEALTH_VALUES = { cat = "In Cat Form", always = "In Any Form" }
local DRUID_STEALTH_ORDER = { "cat", "always" }

local DRUID_FORM_VALUES = { none = "None", cat = "Cat Form", bear = "Bear Form",
    moonkin = "Moonkin Form" }
local DRUID_FORM_ORDER = { "none", "cat", "bear", "moonkin" }

local AUDIO_VALUES = { none = "None", sound = "Sound", tts = "Text to Speech" }
local AUDIO_ORDER = { "none", "sound", "tts" }

local MODIFIER_VALUES = { CTRL = "Ctrl", SHIFT = "Shift", ALT = "Alt", NONE = "None" }
local MODIFIER_ORDER = { "CTRL", "SHIFT", "ALT", "NONE" }

local KEY_VALUES, KEY_ORDER = {}, {}
for i = 65, 90 do
    local key = string.char(i)
    KEY_VALUES[key] = key
    KEY_ORDER[#KEY_ORDER + 1] = key
end

local function ColorRow(k, text, on)
    return { type = "colorpicker", text = text, hasAlpha = false,
        getValue = function()
            local c = S.Get(k)
            return c.r, c.g, c.b
        end,
        setValue = function(r, g, b) S.Set(k, { r = r, g = g, b = b }) end,
        disabled = function() return not S.Get(on) end }
end

-- The row kit has no text box, so text is set through a prompt holding what is there now.
local function TextButton(parent, y, label, title, k)
    return UI.Widgets:Button(parent, label, y, function()
        ns.PromptText(title, S.Get(k), 0, function(v) S.Set(k, v) end)
    end)
end

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

    _, h = W:SectionHeader(parent, "XP BAR" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpBar", "XP Bar",
            "Your level, experience and percentage on one bar, with the XP of completed "
            .. "quests (gold) and rested experience (dark blue) drawn past the fill. Replaces "
            .. "Blizzard's experience bar while it is on. Move it in Unlock Mode."),
        S.Toggle("xpBarMaxLevel", "Show Bar at Max Level", nil, "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpBarPlayed", "Played Time Text",
            "Total played time and time played on this level.", "xpBar"),
        S.Toggle("xpBarSession", "Session Time Text", "How long this session has run.", "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpBarLeveling", "Leveling Time & XP/Hour Text",
            "Time to the next level at this session's rate, and the rate itself.", "xpBar"),
        S.Toggle("xpBarCompleted", "Completed & Rested Text",
            "The XP of quests ready to turn in and your rested experience, as a share of "
            .. "this level.", "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpBarIncomplete", "Show Incomplete Quests Bar",
            "The XP of quests still in progress, as a faded segment after the completed ones.",
            "xpBar"),
        S.Toggle("xpBarResetOnReload", "Reset Session Time and XP/Hour on Reload UI",
            "Off: a /reload carries on the session. A fresh login always starts a new one.",
            "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("xpBarWidth", "Width", 200, 1200, 10, nil, "xpBar"),
        S.Slider("xpBarHeight", "Height", 14, 48, 1, nil, "xpBar")
    ); y = y - h

    _, h = W:SectionHeader(parent, "QUESTING" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("questAccept", "Auto Accept Quests",
            "Accepts a quest as soon as its text opens. Hold Alt to read it first."),
        S.Toggle("questTurnIn", "Auto Turn In Quests",
            "Hands in finished quests. A quest with a choice of rewards waits for you to pick "
            .. "one, unless you saved a reward for it. Hold Alt to skip it.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("questGossip", "Pick Quests From NPCs",
            "When an NPC offers several things, goes straight to a finished quest to hand in, "
            .. "or the first quest on offer. Works with the two options above."),
        S.Toggle("questRewardPicks", "Saved Quest Rewards",
            "Alt-click a reward you can choose, in the quest log or at the quest giver, to save "
            .. "it for that quest in this profile; Alt-click it again to clear it. It is selected "
            .. "when you hand the quest in, and Auto Turn In takes it for you.")
    ); y = y - h

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
            "Text on screen while a rogue or druid is out of stealth, and optionally while "
            .. "stealthed. Hidden in combat. Move it in Unlock Mode."),
        S.Toggle("formReminder", "Stance / Form Reminder",
            "Warns while a warrior has no stance, a paladin has no aura, or a druid or priest "
            .. "is out of the form picked below. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("reminderInGroup", "Only In a Group",
            "Both reminders stay hidden while you play alone."),
        S.Toggle("reminderHideResting", "Hide While Resting",
            "Both reminders stay hidden in cities and inns.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "STEALTH REMINDER", y); y = y - h
    local stealthFonts, stealthFontOrder = UI.FontChoices(S.Get("stealthFont"))
    _, h = W:DualRow(parent, y,
        S.Toggle("stealthShowStealthed", "Show While Stealthed",
            "The stealthed text while you are in stealth, as well as the reminder when you "
            .. "are not.", "stealthReminder"),
        S.Dropdown("stealthDruid", "Druids", DRUID_STEALTH_VALUES, DRUID_STEALTH_ORDER,
            "In Cat Form reminds a druid only while in Cat Form. In Any Form reminds in every "
            .. "form but travel forms, for a druid who prowls between fights.", "stealthReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("warningColor", "Out of Stealth Colour", "stealthReminder"),
        S.Toggle("warningClassColor", "Class Colour", nil, "stealthReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("stealthColor", "Stealthed Colour", "stealthShowStealthed"),
        S.Toggle("stealthClassColor", "Class Colour", nil, "stealthShowStealthed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("stealthFont", "Font", stealthFonts, stealthFontOrder, nil, "stealthReminder"),
        S.Slider("stealthFontSize", "Font Size", 10, 60, 1, nil, "stealthReminder")
    ); y = y - h
    _, h = TextButton(parent, y, "Out of Stealth Text", "Text while out of stealth", "warningText"); y = y - h
    _, h = TextButton(parent, y, "Stealthed Text", "Text while stealthed", "stealthText"); y = y - h

    _, h = W:SectionHeader(parent, "STANCE / FORM REMINDER", y); y = y - h
    local formFonts, formFontOrder = UI.FontChoices(S.Get("formFont"))
    local _, soundNames, soundOrder = ns.SoundChoices()
    _, h = W:DualRow(parent, y,
        S.Dropdown("formDruid", "Druid Form", DRUID_FORM_VALUES, DRUID_FORM_ORDER,
            "The form a druid should be in. Forever cannot tell which spec you play, so it is "
            .. "picked here. None leaves druids alone.", "formReminder"),
        S.Toggle("formShadowform", "Priest: Shadowform",
            "Warns a priest who knows Shadowform while out of it.", "formReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("formCombatOnly", "Only In Combat", nil, "formReminder"),
        S.Toggle("formInstanceOnly", "Only In Dungeons & Raids", nil, "formReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("formColor", "Warning Colour", "formReminder"),
        S.Toggle("formClassColor", "Class Colour", nil, "formReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("formFont", "Font", formFonts, formFontOrder, nil, "formReminder"),
        S.Slider("formFontSize", "Font Size", 10, 60, 1, nil, "formReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("formSound", "Play a Sound", "Plays when the warning appears.", "formReminder"),
        S.Dropdown("formSoundKey", "Sound", soundNames, soundOrder, nil, "formSound")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("formSoundInterval", "Repeat Every (s)", 0, 10, 1,
            "Plays the sound again this often while the warning stays up. 0 plays it once.",
            "formSound"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = TextButton(parent, y, "Warning Text", "Warning text, in place of your class's own",
        "formText"); y = y - h

    _, h = W:SectionHeader(parent, "CO-TANK FRAME" .. STATUS.untested, y); y = y - h
    local coTankFonts, coTankFontOrder = UI.FontChoices(S.Get("coTankFont"))
    _, h = W:DualRow(parent, y,
        S.Toggle("coTank", "Co-Tank Frame",
            "A small health bar for the other tank in your group, shown while you are tanking: "
            .. "tank role, Bear Form or Defensive Stance. The other tank is whoever has the tank "
            .. "role or the raid's Main Tank assignment. Click it to target them. Changes made "
            .. "in combat apply when the fight ends. Move it in Unlock Mode."),
        S.Toggle("coTankDebuffs", "Co-Tank Debuffs",
            "Their debuffs next to the bar, out of combat only: the client hides auras "
            .. "from addons during a fight.", "coTank")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("coTankWidth", "Width", 50, 400, 5, nil, "coTank"),
        S.Slider("coTankHeight", "Height", 10, 80, 1, nil, "coTank")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("coTankClassColor", "Class Colour Health", nil, "coTank"),
        ColorRow("coTankColor", "Health Colour", "coTank")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("coTankBgAlpha", "Background Opacity", 0, 1, 0.05, nil, "coTank"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("coTankName", "Show Name", nil, "coTank"),
        S.Slider("coTankNameLength", "Name Length", 0, 20, 1,
            "Cuts the name to this many letters. 0 shows it whole.", "coTankName")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("coTankNameClassColor", "Class Colour Name", nil, "coTankName"),
        ColorRow("coTankNameColor", "Name Colour", "coTankName")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("coTankFont", "Font", coTankFonts, coTankFontOrder, nil, "coTankName"),
        S.Slider("coTankFontSize", "Font Size", 8, 24, 1, nil, "coTankName")
    ); y = y - h
    _, h = TextButton(parent, y, "Anchor to a Frame",
        "Frame to anchor to, such as PlayerFrame. UIParent puts it back on the screen, "
        .. "and so does dragging it in Unlock Mode.", "coTankAnchor"); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("coTankX", "X Offset", -2000, 2000, 1,
            "From the centre of the anchor frame. Only used while anchored to a frame.", "coTank"),
        S.Slider("coTankY", "Y Offset", -2000, 2000, 1,
            "From the centre of the anchor frame. Only used while anchored to a frame.", "coTank")
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
            "Auction (Naowh Scan) uses your last Scan Prices at the auction house; Auction (TSM) "
            .. "needs TradeSkillMaster. An item without an auction price counts at its vendor price.",
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

    _, h = W:SectionHeader(parent, "AUCTION PRICES" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("ahPrices", "Scan Prices Button",
            "A Scan Prices button on the auction house. It reads every listing and keeps the "
            .. "lowest buyout for each item, for this realm and faction. Blizzard allows one full "
            .. "scan every 15 minutes."),
        S.Toggle("ahTooltip", "Prices on Tooltips",
            "The last scanned price for one of an item, and how long ago the scan ran.")
    ); y = y - h
    _, h = W:Note(parent, ns.AuctionScanSummary(), y); y = y - h

    _, h = W:SectionHeader(parent, "LOOTING" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("deleteConfirm", "Auto-Fill Delete Confirmation",
            "Types DELETE into the confirmation box for you, and names the item in the dialog as a "
            .. "link you can hover for its tooltip."),
        S.Toggle("lootConfirm", "Skip Loot Confirmations",
            "Answers yes for you to Need, Greed and disenchant rolls, looting a bind-on-pickup "
            .. "item, selling an item you could still trade, and mailing a locked item.")
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
            .. "you are short on. It stays up until you have what you need or leave. Move it "
            .. "in Unlock Mode."),
        S.Toggle("restockBuy", "Buy at Vendors",
            "At a vendor who sells them, tops your class reagents and ammo up to what you carry, "
            .. "and prints what it spent. Off by default: it spends gold for you.")
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
    local sliders = ns.RestockReagentSliders()
    _, h = W:DualRow(parent, y,
        S.Slider("restockBagsBelow", "Free Slots Below", 1, 20, 1, nil, "restockVendor"),
        sliders[1] or { type = "label", text = "" }
    ); y = y - h
    for i = 2, #sliders, 2 do
        _, h = W:DualRow(parent, y, sliders[i], sliders[i + 1] or { type = "label", text = "" }); y = y - h
    end

    return y
end

function ns.BuildQoLAlertsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "DURABILITY" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("durability", "Low Durability Warning",
            "Text on screen when any piece of gear drops below the threshold. Hidden in "
            .. "combat. Move it in Unlock Mode."),
        S.Slider("durabilityBelow", "Warn Below (%)", 5, 100, 1, nil, "durability")
    ); y = y - h
    local durFonts, durFontOrder = UI.FontChoices(S.Get("durabilityFont"))
    _, h = W:DualRow(parent, y,
        S.Dropdown("durabilityFont", "Font", durFonts, durFontOrder, nil, "durability"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "COMBAT" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatAlert", "Combat Alert",
            "A short flash of text entering and leaving combat. Move it in Unlock Mode."),
        S.Toggle("groupDeaths", "Announce Group Deaths", "Shows who died in your group.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "COMBAT ALERT", y); y = y - h
    local alertFonts, alertFontOrder = UI.FontChoices(S.Get("combatAlertFont"))
    _, h = W:DualRow(parent, y,
        S.Dropdown("combatAlertFont", "Font", alertFonts, alertFontOrder, nil, "combatAlert"),
        S.Slider("combatAlertFontSize", "Font Size", 10, 72, 1, nil, "combatAlert")
    ); y = y - h
    local _, soundNames, soundOrder = ns.SoundChoices()
    local voices, voiceOrder = ns.TTSVoiceChoices()
    for _, side in ipairs({ { "combatEnter", "Entering" }, { "combatLeave", "Leaving" } }) do
        local k, name = side[1], side[2]
        _, h = W:DualRow(parent, y,
            ColorRow(k .. "Color", name .. " Colour", "combatAlert"),
            S.Toggle(k .. "ClassColor", "Class Colour", nil, "combatAlert")
        ); y = y - h
        _, h = W:DualRow(parent, y,
            S.Dropdown(k .. "Audio", name .. " Audio", AUDIO_VALUES, AUDIO_ORDER,
                "A sound, or the Speech text read aloud.", "combatAlert"),
            S.Dropdown(k .. "Sound", name .. " Sound", soundNames, soundOrder, nil, "combatAlert")
        ); y = y - h
        _, h = W:DualRow(parent, y,
            S.Dropdown(k .. "Voice", name .. " Voice", voices, voiceOrder,
                "Game Default speaks in the voice the rest of the addon uses.", "combatAlert"),
            S.Slider(k .. "Volume", name .. " Volume", 0, 100, 1, nil, "combatAlert")
        ); y = y - h
        _, h = W:DualRow(parent, y,
            S.Slider(k .. "Rate", name .. " Speech Rate", -10, 10, 1, nil, "combatAlert"),
            { type = "label", text = "" }
        ); y = y - h
        _, h = TextButton(parent, y, name .. " Text", name .. " combat text", k .. "Text"); y = y - h
        _, h = TextButton(parent, y, name .. " Speech", name .. " combat speech", k .. "Speech"); y = y - h
    end

    _, h = W:SectionHeader(parent, "COMBAT TIMER" .. STATUS.untested, y); y = y - h
    local timerFonts, timerFontOrder = UI.FontChoices(S.Get("combatTimerFont"))
    _, h = W:DualRow(parent, y,
        S.Toggle("combatTimer", "Combat Timer",
            "How long the current fight has run, on screen while you fight. Move it in Unlock Mode."),
        S.Toggle("combatTimerInstanceOnly", "Only In Instances", nil, "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatTimerChat", "Report to Chat",
            "How long the fight lasted, in chat when it ends.", "combatTimer"),
        S.Toggle("combatTimerSticky", "Keep After the Fight",
            "The last fight's time stays on screen until the next one starts.", "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatTimerHidePrefix", "Hide the COMBAT Label", nil, "combatTimer"),
        S.Toggle("combatTimerBackground", "Show Background", nil, "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("combatTimerColor", "Timer Colour", "combatTimer"),
        S.Toggle("combatTimerClassColor", "Class Colour", nil, "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("combatTimerFont", "Font", timerFonts, timerFontOrder, nil, "combatTimer"),
        S.Slider("combatTimerFontSize", "Font Size", 10, 72, 1, nil, "combatTimer")
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
            "Hides the red error text, like \"not ready yet\" and \"out of range\", and the "
            .. "voice line that comes with it."),
        S.Toggle("hideTutorials", "Hide Tutorial Pop-ups",
            "Turns off the game's tutorials and help tips. Turning this back off restores "
            .. "what you had before.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideScreenshot", "Hide Screenshot Status",
            "Hides the \"Screen captured\" text when you take a screenshot."),
        S.Toggle("skipCinematics", "Skip Cinematics",
            "Skips cinematics you have already seen on this account. Each one plays the "
            .. "first time.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideAlerts", "Hide Alert Pop-ups",
            "Hides the pop-ups for achievements, loot won and the like."),
        S.Toggle("hideEventToasts", "Hide Event Toasts",
            "Closes the banners for level ups, new zones and events.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideZoneText", "Hide Zone Text",
            "Hides the zone and subzone names that appear as you travel."),
        S.Toggle("cursorClip", "Keep Cursor In Window During Combat",
            "Stops the cursor leaving the game window while you fight, for a second monitor. "
            .. "Your own setting comes back afterwards.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "CROSSHAIR" .. STATUS.untested, y); y = y - h
    local _, soundNames, soundOrder = ns.SoundChoices()
    _, h = W:DualRow(parent, y,
        S.Toggle("crosshair", "Crosshair", "A crosshair at the middle of your screen."),
        S.Toggle("crossCombatOnly", "Only In Combat", nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossHideMounted", "Hide While Mounted", nil, "crosshair"),
        S.Slider("crossOpacity", "Opacity", 0.1, 1, 0.05, nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossSize", "Arm Length", 4, 100, 1, nil, "crosshair"),
        S.Slider("crossThickness", "Thickness", 1, 20, 1, nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossGap", "Gap", 0, 50, 1, "Space between the middle and each arm.", "crosshair"),
        ColorRow("crossColor", "Colour", "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossClassColor", "Class Colour", nil, "crosshair"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossTop", "Top Arm", nil, "crosshair"),
        S.Toggle("crossRight", "Right Arm", nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossBottom", "Bottom Arm", nil, "crosshair"),
        S.Toggle("crossLeft", "Left Arm", nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossDot", "Centre Dot", nil, "crosshair"),
        S.Slider("crossDotSize", "Dot Size", 1, 20, 1, nil, "crossDot")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossCircle", "Circle", nil, "crosshair"),
        S.Slider("crossCircleSize", "Circle Size", 10, 200, 1, nil, "crossCircle")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("crossCircleColor", "Circle Colour", "crossCircle"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossOutline", "Outline", nil, "crosshair"),
        S.Slider("crossOutlineWeight", "Outline Width", 1, 5, 1, nil, "crossOutline")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("crossOutlineColor", "Outline Colour", "crossOutline"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossX", "X Offset", -500, 500, 1, nil, "crosshair"),
        S.Slider("crossY", "Y Offset", -500, 500, 1, nil, "crosshair")
    ); y = y - h

    _, h = W:SectionHeader(parent, "CROSSHAIR MELEE RANGE", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossMelee", "Recolour Out of Melee Range",
            "Changes colour while your target is out of melee range. Warriors, rogues, hunters "
            .. "(Raptor Strike), shamans with Stormstrike, and druids in Cat or Bear Form have "
            .. "an ability it can check; anyone else can set a spell ID below.", "crosshair"),
        ColorRow("crossMeleeColor", "Out of Range Colour", "crossMelee")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossMeleeBorder", "Recolour Outline", nil, "crossMelee"),
        S.Toggle("crossMeleeArms", "Recolour Arms", nil, "crossMelee")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossMeleeDot", "Recolour Dot", nil, "crossMelee"),
        S.Toggle("crossMeleeCircle", "Recolour Circle", nil, "crossMelee")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossMeleeSound", "Play a Sound",
            "Plays as your target leaves melee range.", "crossMelee"),
        S.Dropdown("crossMeleeSoundKey", "Sound", soundNames, soundOrder, nil, "crossMeleeSound")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossMeleeSoundInterval", "Repeat Every (s)", 0, 10, 1,
            "Plays the sound again this often while out of range. 0 plays it once.",
            "crossMeleeSound"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Button(parent, "Melee Spell ID", y, function()
        ns.PromptText("Spell ID to check melee range with. 0 uses your class's own.",
            tostring(S.Get("crossMeleeSpell")), 0, function(v)
                S.Set("crossMeleeSpell", tonumber(v) or 0)
            end)
    end); y = y - h

    _, h = W:SectionHeader(parent, "ON-SCREEN EXTRAS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("fps", "FPS Counter",
            "Your frame rate on screen, updated every second. Move it in Unlock Mode."),
        S.Toggle("localMS", "Show Local MS",
            "Latency to the realm server: chat, guild and the auction house.", "fps")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("worldMS", "Show World MS",
            "Latency to the world server: combat, spells and other players.", "fps"),
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

function ns.BuildQoLToolsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "COMBAT LOGGING" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatLogger", "Auto Combat Logging",
            "Turns the combat log on in raids and off when you leave. The first time you enter "
            .. "each raid and difficulty it asks, and remembers your answer."),
        { type = "label", text = ns.CombatLogging() and "Logging now" or "Not logging" }
    ); y = y - h
    local saved, keys = ns.CombatLogInstances(), {}
    for key in pairs(saved) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return saved[a].name < saved[b].name end)
    local function InstanceRow(key)
        local entry = saved[key]
        if not entry then return { type = "label", text = "" } end
        return { type = "toggle", text = entry.name .. " (" .. entry.diffName .. ")",
            getValue = function() return entry.enabled end,
            setValue = function(v)
                entry.enabled = v
                ns.CombatLogCheck()
            end,
            disabled = function() return not S.Get("combatLogger") end }
    end
    if #keys == 0 then
        _, h = W:Note(parent, "No raids answered yet.", y); y = y - h
    end
    for i = 1, #keys, 2 do
        _, h = W:DualRow(parent, y, InstanceRow(keys[i]), InstanceRow(keys[i + 1])); y = y - h
    end
    _, h = W:Button(parent, "Forget All Raids", y, function()
        ns.Confirm("Forget every raid's answer? You will be asked again the next time you "
            .. "enter each one.", function()
                S.DB().combatLogInstances = nil
                UI:RefreshPage(true)
            end)
    end); y = y - h

    _, h = W:SectionHeader(parent, "GLOBAL COPY" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("globalCopy", "Global Copy",
            "/copy puts the text of whatever is under your cursor in a box you can copy from. "
            .. "/copy followed by a frame name copies that frame's text instead."),
        S.Toggle("copyTooltipIds", "Copy IDs From Tooltips",
            "With a tooltip showing, the key below copies its spell, item or NPC ID.", "globalCopy")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("copyModifier", "Modifier", MODIFIER_VALUES, MODIFIER_ORDER, nil, "copyTooltipIds"),
        S.Dropdown("copyKey", "Key", KEY_VALUES, KEY_ORDER, nil, "copyTooltipIds")
    ); y = y - h

    _, h = W:SectionHeader(parent, "SLASH COMMANDS" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("slashCommands", "Custom Slash Commands",
            "Short commands of your own that open a game window or run another command. A "
            .. "name another addon already uses is skipped."),
        { type = "label", text = "" }
    ); y = y - h
    local commands = ns.SlashCommandList()
    local function CommandRow(cmd)
        if not cmd then return { type = "label", text = "" } end
        return { type = "toggle", text = "/" .. cmd.name, tooltip = ns.SlashCommandSummary(cmd),
            getValue = function() return cmd.enabled end,
            setValue = function(v)
                cmd.enabled = v
                ns.RefreshSlashCommands()
            end,
            disabled = function() return not S.Get("slashCommands") end }
    end
    for i = 1, #commands, 2 do
        _, h = W:DualRow(parent, y, CommandRow(commands[i]), CommandRow(commands[i + 1])); y = y - h
    end
    _, h = W:Button(parent, "Add Command", y, function()
        ns.ShowAddSlashCommand(function() UI:RefreshPage(true) end)
    end); y = y - h
    _, h = W:Button(parent, "Remove Command", y, function()
        ns.PromptText("Command to remove, such as /cdm", "", 0, function(v)
            if ns.RemoveSlashCommand(v) then
                UI:RefreshPage(true)
            else
                ns.Print(v .. " is not one of your commands.")
            end
        end)
    end); y = y - h
    _, h = W:Button(parent, "Restore Default Commands", y, function()
        ns.Confirm("Replace your commands with the defaults?", function()
            ns.RestoreSlashCommands()
            UI:RefreshPage(true)
        end)
    end); y = y - h

    return y
end

function ns.BuildQoLTrainerPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "TRAINER POPUP" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("trainerPopup", "Trainer Popup",
            "After visiting a trainer, a small window lists the abilities you just learned. "
            .. "Abilities from a tome or a quest show a moment after you learn them. Drag one "
            .. "from the window onto your bars."),
        S.Toggle("trainerGlow", "Glow New Abilities",
            "Lights up the new abilities on your action bars until you use them.", "trainerPopup")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("trainerRanks", "Offer to Replace Lower Ranks",
            "Adds a button to the popup that swaps every lower rank on your bars for the "
            .. "highest rank you know. Keyboard and controller bars land in the same slot. "
            .. "Right-click a spell in the popup to keep its lower ranks, for downranking.",
            "trainerPopup"),
        { type = "label", text = "      Rank swaps only happen out of combat." }
    ); y = y - h
    _, h = W:Button(parent, "Check My Bars Now", y, function()
        if ns.TrainerRankCheck then ns.TrainerRankCheck() end
    end); y = y - h
    _, h = W:Button(parent, "Forget Kept Spells", y, function()
        if ns.TrainerForgetKept then ns.TrainerForgetKept() end
    end); y = y - h

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

function ns.BuildQoLTooltipPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Readable IDs appear below the tooltip. Hover a spell, item or NPC and press your shortcut to open a copy card. Copy cards open outside combat; typing never triggers the shortcut.", y); y = y - h
    _, h = W:SectionHeader(parent, "TOOLTIP DISPLAY", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("tooltipDisplay", "Tooltip Display"),
        S.Dropdown("tooltipRestricted", "Restricted IDs", { hide = "Hide Line", hidden = "Show Hidden" }, { "hide", "hidden" }, nil, "tooltipDisplay")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("tooltipSpellID", "Show Spell ID", nil, "tooltipDisplay"),
        S.Toggle("tooltipItemID", "Show Item ID", nil, "tooltipDisplay")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("tooltipNPCID", "Show NPC ID", "Creature and vehicle IDs only; never player GUIDs.", "tooltipDisplay"),
        S.Toggle("tooltipCopy", "Mouseover Copy Shortcut", nil, "tooltipDisplay")
    ); y = y - h
    _, h = W:SectionHeader(parent, "COPY CARD", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("tooltipModifier", "Modifier", { CTRL = "Ctrl", SHIFT = "Shift", ALT = "Alt", ["CTRL-SHIFT"] = "Ctrl + Shift", ["CTRL-ALT"] = "Ctrl + Alt", ["ALT-SHIFT"] = "Alt + Shift" },
            { "CTRL-SHIFT", "CTRL-ALT", "ALT-SHIFT", "CTRL", "SHIFT", "ALT" }, nil, "tooltipCopy"),
        S.Dropdown("tooltipKey", "Key", KEY_VALUES, KEY_ORDER, nil, "tooltipCopy")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("tooltipCopyFormat", "Initially Select", { id = "ID", url = "Wowhead Link" }, { "id", "url" }, nil, "tooltipCopy"),
        S.Dropdown("tooltipWowhead", "Wowhead Database", { classic = "Classic", retail = "Retail" }, { "classic", "retail" }, "Forever-specific entries may not have a matching Wowhead page.", "tooltipCopy")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Preview Copy Card", buttonText = "Preview", onClick = function() ns.PreviewTooltipCopyCard() end },
        { type = "label", text = "Select ID or link, then Ctrl+C" }
    ); y = y - h
    return y
end
