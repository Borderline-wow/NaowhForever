-------------------------------------------------------------------------------
--  NaowhForever_QoL.lua -- the QoL module: NaowhUI's QoL page trimmed to what Forever has,
--  plus the loot feed and the trainer popup.
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
    coTank = false, coTankName = true, coTankClassColor = true, coTankDebuffs = true,
    coTankWidth = 180, coTankHeight = 30,
    coTankColor = { r = 0, g = 0.8, b = 0.2 }, coTankBgAlpha = 0.6,
    coTankNameClassColor = false, coTankNameColor = { r = 1, g = 1, b = 1 },
    coTankNameLength = 0, coTankFont = "", coTankFontSize = 12,
    coTankAnchor = "UIParent", coTankX = 0, coTankY = 0,
    coTankDebuffFilter = "important", coTankDebuffCap = 3, coTankDebuffSize = 22,
    coTankDebuffSpacing = 2, coTankDebuffPosition = "top", coTankDebuffGrow = "CENTER",
    coTankDebuffX = 0, coTankDebuffY = 3,
    coTankDebuffDuration = true, coTankDebuffDurationSize = 10,
    coTankDebuffStacks = true, coTankDebuffStackSize = 10, coTankDebuffTooltips = false,

    deleteConfirm = false, lootConfirm = false,
    questAccept = false, questTurnIn = false, questGossip = false, questRewardPicks = true,
    questSkipModifier = "ALT",
    questShare = false,
    combatTimer = false, combatTimerInstanceOnly = false, combatTimerChat = true,
    combatTimerSticky = false, combatTimerHidePrefix = false, combatTimerBackground = false,
    combatTimerColor = { r = 1, g = 1, b = 1 }, combatTimerClassColor = false,
    combatTimerFont = "", combatTimerFontSize = 32,
    combatLogger = false,
    globalCopy = false, copyTooltipIds = true, copyModifier = "CTRL", copyKey = "C",
    -- Supporter badges. On by default so everyone sees them, except the group banner, which
    -- Naowh asked to start off.
    badgeChat = true, badgeCard = true, badgeTooltip = true,
    badgeBanner = false, badgeBannerSkipGuild = true,
    tooltipDisplay = true, tooltipSpellID = true, tooltipNPCID = true, tooltipItemID = true,
    tooltipRestricted = "hide", tooltipCopy = true, tooltipModifier = "CTRL-SHIFT", tooltipKey = "C",
    tooltipCopyFormat = "url", tooltipWowhead = "classic",
    slashCommands = false,
    lootFeed = true, lootFeedMoney = true, lootFeedXP = false, lootFeedQuality = 1,
    lootFeedQuest = true, lootFeedRep = false,
    lootFeedCount = 6, lootFeedFade = 5, lootFeedStyle = "dark", lootFeedGlow = false,
    lootFeedValue = true, lootFeedBank = true, lootFeedPrice = "vendor", lootFeedGPH = false,
    hideLootWindow = false, fastLoot = false,
    lootFeedWidth = 340, lootFeedHeight = 36, lootFeedSpacing = 0, lootFeedGrowth = "up",
    lootFeedFont = "", lootFeedFontSize = 13,
    ahPrices = true, ahTooltip = true,
    altCounts = false, mailAlts = false, mailQuickAttach = false, mailExpiry = false,
    xpTicker = true, xpTickerLevel = true, xpTickerElapsed = true, xpTickerTotal = false,
    xpTickerHideResting = false, xpTickerFont = "", xpTickerFontSize = 24,
    xpTickerSplits = true, xpTickerSplitCount = 4, xpTickerCompare = true, xpTickerHistoryCount = 10,
    groupXP = false, groupXPShowSelf = true, groupXPWidth = 260,
    xpBar = false, xpBarLeftText = "level", xpBarCenterText = "xp", xpBarRightText = "percent",
    xpBarTopLeft = "played", xpBarTopRight = "none", xpBarBottomLeft = "leveling",
    xpBarBottom = "none", xpBarBottomRight = "xphour", xpBarIncomplete = false, xpBarMaxLevel = false,
    xpBarResetOnReload = false, xpBarWidth = 520, xpBarHeight = 26,
    autoRepair = false, sellJunk = false,
    restock = true, restockReagents = true, restockAmmo = true, restockAmmoTarget = 1000,
    restockFood = true, restockFoodBelow = 10, restockFoodMinLevel = 0, restockFoodMaxLevel = 60, restockVendor = true, restockBagsBelow = 4,
    restockBuy = false,
    bagSpace = false, bagSpaceCount = 4, bagSpaceSize = 36, bagSpaceGrow = "RIGHT",
    bagSpaceMaxQuality = 2, bagSpaceJunkFirst = false, bagSpaceAuction = true,
    bagSpaceProtect = true, bagSpaceFreeBelow = 0, bagSpaceHideCombat = true,
    bagSpaceOnFull = true, bagSpaceShowFree = true, bagSpaceStack = true, bagSpaceOldFirst = false,
    bagSpaceTipVendor = true, bagSpaceTipAuction = true, bagSpaceTipDelete = true, bagSpaceTipIgnore = true,
    dqTracker = true, dqShowDone = false, dqAllFactions = false, dqOutside = false,
    dqSingle = false, dqSelected = "",
    townCapitalsOnly = true, townSpiritHealers = true, townZoneLinks = true,
    townMap = true, townClass = true, townProfession = true, townFlight = true, townInn = true,
    townBank = true, townStable = false, townRepair = true, townSupplies = true,
    townVendors = false, townPinSize = 16,
    gearSets = true, gearBarVisible = true, trinketBar = false, trinketSize = 36, trinketSpacing = 4, gearBarSize = 32, gearMounted = "", gearResting = "",
    bis = true, bisTooltip = true, bisLootAlert = true,
    blessings = true, blessSpacing = 6, blessGroupSpacing = 6, blessTimerSize = 14, blessShowLabels = true, blessBarSize = 30, blessTimers = true, blessShowAura = true,
    blessShowFury = false,

    durability = true, durabilityBelow = 25, durabilityFont = "",
    talentPoints = false, talentPointsFont = "",
    combatAlert = false, groupDeaths = false,
    combatEnterText = "+Combat", combatEnterColor = { r = 0, g = 1, b = 0 },
    combatEnterClassColor = false,
    combatLeaveText = "-Combat", combatLeaveColor = { r = 1, g = 0, b = 0 },
    combatLeaveClassColor = false,
    combatAlertFont = "", combatAlertFontSize = 32,
    combatEnterAudio = "none", combatEnterSound = "voice:combat", combatEnterSpeech = "Combat",
    combatLeaveAudio = "none", combatLeaveSound = "voice:safe", combatLeaveSpeech = "Safe",
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

    petTracker = false, petPassive = true, petLowHealth = false, petLowHealthBelow = 25,
    petInstanceOnly = false, petCombatOnly = false, petHideMounted = true, petShowIcon = true,
    petColor = { r = 1, g = 0, b = 0 }, petClassColor = false, petFont = "", petFontSize = 20,
    petMissingText = "Pet Missing", petPassiveText = "Pet Passive", petLowHealthText = "Pet Low HP",
    equipReminder = false, equipOnInstance = true, equipOnReadyCheck = true, equipAutoHide = 10,
    equipIconSize = 40, equipEnchants = false, equipEnchantRules = {},
    emoteDetection = false, emotePattern = "prepares,places", emoteColor = { r = 1, g = 1, b = 1 },
    emoteFont = "", emoteFontSize = 16, emoteSound = true, emoteSoundKey = "none",
    autoEmote = false, autoEmoteCooldown = 2, autoEmoteList = "698: prepares a ritual of summoning",

    mouseRing = false, mouseShape = "ring.tga", mouseSize = 48,
    mouseColor = { r = 1, g = 0.66, b = 0 }, mouseClassColor = false,
    mouseShowOOC = true, mouseOpacityCombat = 1, mouseOpacityOOC = 1,
    mouseHideOnClick = false, mouseHideAfk = false,
    mouseBorder = false, mouseBorderColor = { r = 1, g = 1, b = 1 }, mouseBorderClassColor = false,
    mouseBorderWeight = 2,
    mouseDot = false, mouseDotSize = 6, mouseDotColor = { r = 1, g = 1, b = 1 },
    mouseDotClassColor = false,
    mouseFadeIdle = false, mouseFadeDelay = 2, mouseFadeOpacity = 0,
    mouseGCD = true, mouseHideBackground = false, mouseGCDColor = { r = 0.004, g = 0.56, b = 0.91 },
    mouseGCDClassColor = false, mouseReadyColor = { r = 0, g = 0.8, b = 0.3 }, mouseReadyMatch = false,
    mouseGCDAlpha = 1, mouseCastSwipe = true, mouseCastColor = { r = 0.004, g = 0.56, b = 0.91 },
    mouseCastClassColor = false, mouseSwipeDelay = 0.08,
    mouseTrail = false, mouseTrailShape = "glow", mouseTrailColor = { r = 1, g = 1, b = 1 },
    mouseTrailClassColor = false, mouseTrailSparkle = false, mouseTrailLength = 20,
    mouseTrailDuration = 2, mouseTrailSize = 24, mouseTrailBrightness = 0.8,
    mouseMelee = false, mouseMeleeBorder = true, mouseMeleeRing = false,
    mouseMeleeSound = false, mouseMeleeSoundKey = "none", mouseMeleeSoundInterval = 3,

    gcdTracker = false, gcdDuration = 5, gcdIconSize = 32, gcdSpacing = 4, gcdDirection = "RIGHT",
    gcdFadeStart = 0.5, gcdStack = true, gcdCombatOnly = false,
    gcdWorld = true, gcdDungeon = true, gcdRaid = true, gcdPvP = true,
    gcdBlocklist = "6603, 75", gcdTimelineColor = { r = 0.01, g = 0.56, b = 0.91 },
    gcdTimelineHeight = 4, gcdDowntime = false,
    focusCastBar = false, focusWidth = 250, focusHeight = 24,
    focusBgColor = { r = 0.12, g = 0.12, b = 0.12 }, focusBgAlpha = 0.8,
    focusReadyColor = { r = 0.01, g = 0.56, b = 0.91 }, focusReadyClassColor = false,
    focusCooldownColor = { r = 0.5, g = 0.5, b = 0.5 },
    focusColorNonInt = true, focusNonIntColor = { r = 0.8, g = 0.2, b = 0.2 },
    focusInterruptedColor = { r = 0.51, g = 0.51, b = 0.51 },
    focusIcon = true, focusIconSide = "LEFT", focusSpellName = true, focusNameLength = 0,
    focusTarget = true, focusTime = true, focusShield = true,
    focusTick = true, focusTickColor = { r = 1, g = 1, b = 1 }, focusTickClassColor = false,
    focusFont = "", focusFontSize = 12,
    focusTextColor = { r = 1, g = 1, b = 1 }, focusTextClassColor = false,
    focusHideFriendly = false, focusHideNonInt = false, focusHideOnCooldown = false,
    focusFadeTime = 0.75, focusInterrupter = false,
    focusAudio = "none", focusSound = "none", focusSpeech = "Interrupt",
    focusVoice = "", focusVolume = 50, focusRate = 0,

    trainerPopup = true, trainerGlow = true, trainerRanks = true,

    flightTimer = true, flightTimerScale = 1, flightEarlyLanding = false, flightQuotes = false, quizFlight = true, quizCamp = true,
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

local DEBUFF_FILTER_VALUES = { important = "Boss & Important", nonplayer = "Non-Player Auras",
    all = "All Debuffs", dispellable = "Dispellable by You" }
local DEBUFF_FILTER_ORDER = { "important", "nonplayer", "all", "dispellable" }

local DEBUFF_POS_VALUES = { top = "Above", bottom = "Below", left = "Left", right = "Right",
    topleft = "Top Left", topright = "Top Right", bottomleft = "Bottom Left",
    bottomright = "Bottom Right", center = "Centre" }
local DEBUFF_POS_ORDER = { "top", "bottom", "left", "right", "topleft", "topright",
    "bottomleft", "bottomright", "center" }

local DEBUFF_GROW_VALUES = { CENTER = "Centred", RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
local DEBUFF_GROW_ORDER = { "CENTER", "RIGHT", "LEFT", "UP", "DOWN" }

local DRUID_FORM_VALUES = { none = "None", cat = "Cat Form", bear = "Bear Form",
    moonkin = "Moonkin Form" }
local DRUID_FORM_ORDER = { "none", "cat", "bear", "moonkin" }

local AUDIO_VALUES = { none = "None", sound = "Sound", tts = "Text to Speech" }
local AUDIO_ORDER = { "none", "sound", "tts" }

local RING_SHAPES = {
    { "ring.tga", "Circle" }, { "thin_ring.tga", "Thin Circle" }, { "thick_ring.tga", "Thick Circle" },
    { "nq_circle.tga", "Filled Circle" }, { "nq_circle_hard.tga", "Hard Circle" },
    { "nq_ring1.tga", "Ring 1" }, { "nq_ring2.tga", "Ring 2" }, { "nq_ring3.tga", "Ring 3" },
    { "nq_ring4.tga", "Ring 4" }, { "nq_ring_soft1.tga", "Soft Ring 1" },
    { "nq_ring_soft2.tga", "Soft Ring 2" }, { "nq_ring_soft3.tga", "Soft Ring 3" },
    { "nq_ring_soft4.tga", "Soft Ring 4" }, { "nq_glow.tga", "Glow" }, { "nq_glow_large.tga", "Large Glow" },
    { "nq_glow_reversed.tga", "Reversed Glow" }, { "nq_cross1.tga", "Cross 1" },
    { "nq_cross2.tga", "Cross 2" }, { "nq_cross3.tga", "Cross 3" }, { "nq_star.tga", "Star" },
    { "nq_swirl.tga", "Swirl" }, { "nq_sphere.tga", "Sphere" },
}
local SHAPE_VALUES, SHAPE_ORDER = {}, {}
for _, shape in ipairs(RING_SHAPES) do
    SHAPE_VALUES[shape[1]] = shape[2]
    SHAPE_ORDER[#SHAPE_ORDER + 1] = shape[1]
end

local TRAIL_VALUES = { glow = "Glow", circle = "Circle", ring = "Ring", star = "Star", sparkle = "Sparkle" }
local TRAIL_ORDER = { "glow", "circle", "ring", "star", "sparkle" }

local SIDE_VALUES = { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" }
local SIDE_ORDER = { "LEFT", "RIGHT", "TOP", "BOTTOM" }

local DIRECTION_VALUES = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
local DIRECTION_ORDER = { "RIGHT", "LEFT", "UP", "DOWN" }

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

local function TextControl(label, title, key)
    return { type = "button", text = label, buttonText = "Edit", onClick = function()
        ns.PromptText(title, S.Get(key), 0, function(value) S.Set(key, value) end)
    end }
end

function ns.BuildQoLQuestingPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:SectionHeader(parent, "QUESTING", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("questAccept", "Auto Accept Quests",
            "Accepts a quest as soon as its text opens. Hold the Skip Modifier to read it first."),
        S.Toggle("questTurnIn", "Auto Turn In Quests",
            "Hands in finished quests. A quest with a choice of rewards waits for you to pick "
            .. "one, unless you saved a reward for it. Hold the Skip Modifier to skip it.")
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
    _, h = W:DualRow(parent, y,
        S.Toggle("questShare", "Share Quests With Group",
            "While you are in a group, shares each quest you accept from an NPC with the "
            .. "others, if the quest can be shared. A quest someone shared with you is not "
            .. "shared again. Hold the Skip Modifier as you accept to keep it to yourself."),
        S.Dropdown("questSkipModifier", "Skip Modifier", { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift" },
            { "ALT", "CTRL", "SHIFT" },
            "Hold it to skip Auto Accept, Auto Turn In, Pick Quests From NPCs and sharing for that quest.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "XP PER HOUR" .. STATUS.ready, y); y = y - h
    local xpFonts, xpFontOrder = UI.FontChoices(S.Get("xpTickerFont"))
    _, h = W:Feature(parent, y,
        S.Toggle("xpTicker", "XP per Hour",
            "Your experience per hour on screen, with time to level, session length and "
            .. "recent level times. Hidden at max level. Hover it "
            .. "for Start, Pause and Reset (also /naowh xp start, pause or reset). Move it in "
            .. "Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpTickerLevel", "Show Ding Time",
            "How long the next level takes at your current rate.", "xpTicker"),
        S.Toggle("xpTickerElapsed", "Show Time", "How long this session has run.",
            "xpTicker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpTickerHideResting", "Hide While Resting", "Hidden in cities and inns.", "xpTicker"),
        S.Toggle("xpTickerSplits", "Level History", "Completed levels, newest first. No placeholder rows.", "xpTicker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("xpTickerHistoryCount", "Levels Shown", 1, 10, 1, "The most recent completed levels.", "xpTickerSplits"),
        S.Dropdown("xpTickerFont", "Font", xpFonts, xpFontOrder, nil, "xpTicker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("xpTickerFontSize", "Font Size", 8, 32, 1, nil, "xpTicker"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Button(parent, "Reset XP per Hour", y, function()
        if ns.ResetXPTicker then ns.ResetXPTicker() end
    end); y = y - h

    _, h = W:SectionHeader(parent, "XP BAR", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("xpBar", "XP Bar",
            "Your level, experience and percentage on one bar, with the XP of completed "
            .. "quests (gold) and rested experience (dark blue) drawn past the fill. Replaces "
            .. "Blizzard's experience bar while it is on. Move it in Unlock Mode.|n|n"
            .. "Ctrl + right-click the bar to reset the session time and XP/Hour.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpBarMaxLevel", "Show Bar at Max Level", nil, "xpBar"),
        S.Toggle("xpBarIncomplete", "Show Incomplete Quests Bar",
            "The XP of quests still in progress, as a faded segment after the completed ones.",
            "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("xpBarResetOnReload", "Reset Session Time and XP/Hour on Reload UI",
            "Off: a /reload carries on the session. A fresh login always starts a new one.",
            "xpBar"),
        S.Slider("xpBarWidth", "Width", 200, 1200, 10, nil, "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("xpBarHeight", "Height", 14, 48, 1, nil, "xpBar"),
        { type = "label", text = "" }
    ); y = y - h

    local textValues = { none = "None", level = "Level", xp = "Current / Max XP", percent = "XP Percent", rested = "Rested Percent" }
    local textOrder = { "none", "level", "xp", "percent", "rested" }
    _, h = W:DualRow(parent, y,
        S.Dropdown("xpBarLeftText", "Left Text", textValues, textOrder, nil, "xpBar"),
        S.Dropdown("xpBarCenterText", "Center Text", textValues, textOrder, nil, "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("xpBarRightText", "Right Text", textValues, textOrder, nil, "xpBar"),
        { type = "label", text = "" }
    ); y = y - h

    local slotValues = { none = "None", played = "Played Time", session = "Session Time",
        completed = "Completed Quests", rested = "Rested Experience", leveling = "Time to Level",
        xphour = "XP per Hour" }
    local slotOrder = { "none", "played", "session", "completed", "rested", "leveling", "xphour" }
    local slotTip = "The text shown at this spot outside the bar. Completed Quests, Rested "
        .. "Experience, Time to Level and XP per Hour are hidden at max level."
    _, h = W:DualRow(parent, y,
        S.Dropdown("xpBarTopLeft", "Top Left", slotValues, slotOrder, slotTip, "xpBar"),
        S.Dropdown("xpBarTopRight", "Top Right", slotValues, slotOrder, slotTip, "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("xpBarBottomLeft", "Bottom Left", slotValues, slotOrder, slotTip, "xpBar"),
        S.Dropdown("xpBarBottom", "Bottom", slotValues, slotOrder, slotTip, "xpBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("xpBarBottomRight", "Bottom Right", slotValues, slotOrder, slotTip, "xpBar"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "GROUP XP" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("groupXP", "Group XP",
            "A bar per group member with their level and how far through it they are. Only "
            .. "members running Naowh Forever with Group XP on share their experience; anyone "
            .. "else shows their level. Updates wait until combat ends. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("groupXPShowSelf", "Show Yourself", nil, "groupXP"),
        S.Slider("groupXPWidth", "Width", 160, 500, 10, nil, "groupXP")
    ); y = y - h

    return y
end

function ns.BuildQoLGeneralPage(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "Death Release", y); y = y - h
    _, h = W:Note(parent, "Hold to release inside dungeons and raids.", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("deathRelease", "Death Release Protection",
            "Release Spirit has to be held down for a moment inside a dungeon or raid, so "
            .. "a stray click never sends you on a corpse run while a battle res is coming.")
    ); y = y - h
    local hold = S.Slider("deathReleaseHold", "Hold Time (s)", 0.5, 3, 0.1, nil, "deathRelease")
    hold.trackWidth = 220
    _, h = W:DualRow(parent, y, hold); y = y - h

    y = y - 16
    local stealth = S.Toggle("stealthReminder", "Stealth Reminder", "Out-of-combat stealth status for rogues and druids.")
    _, h = W:Feature(parent, y, stealth, "Enable Stealth Reminder"); y = y - h
    _, h = W:Note(parent, "Out-of-combat stealth status for rogues and druids.", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("reminderInGroup", "Only In a Group", nil, "stealthReminder"),
        S.Toggle("reminderHideResting", "Hide While Resting", nil, "stealthReminder")
    ); y = y - h
    local stealthFonts, stealthFontOrder = UI.FontChoices(S.Get("stealthFont"))
    _, h = W:DualRow(parent, y,
        S.Toggle("stealthShowStealthed", "Show While Stealthed",
            "The stealthed text while you are in stealth, as well as the reminder when you "
            .. "are not.", "stealthReminder"),
        S.Dropdown("stealthDruid", "Druids", DRUID_STEALTH_VALUES, DRUID_STEALTH_ORDER,
            "In Cat Form reminds a druid only while in Cat Form. In Any Form reminds in every "
            .. "form but travel forms, for a druid who prowls between fights.", "stealthReminder")
    ); y = y - h
    _, h = W:Disclosure(parent, y, "Appearance & text", "appearance"); y = y - h
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
    _, h = W:DualRow(parent, y,
        TextControl("Out of Stealth Text", "Text while out of stealth", "warningText"),
        TextControl("Stealthed Text", "Text while stealthed", "stealthText")
    ); y = y - h
    W:EndDisclosure(parent)
    W:EndFeature(parent)
    y = y - 16

    local coTankFonts, coTankFontOrder = UI.FontChoices(S.Get("coTankFont"))
    _, h = W:Feature(parent, y,
        S.Toggle("coTank", "Co-Tank Frame",
            "A small health bar for the other tank in your group, shown while you are tanking: "
            .. "tank role, Bear Form, Defensive Stance or Righteous Fury. The other tank is "
            .. "whoever has the tank role or the raid's Main Tank assignment. Click it to target "
            .. "them. Changes made in combat apply when the fight ends. Move it in Unlock Mode.")
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

    _, h = W:Disclosure(parent, y,
        S.Toggle("coTankDebuffs", "Co-Tank Debuffs",
            "Shows the other tank's debuffs beside their health bar, in combat too: tank-buster "
            .. "stacks, boss debuffs and anything you can dispel.", "coTank"), "debuffs"
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("coTankDebuffFilter", "Filter", DEBUFF_FILTER_VALUES, DEBUFF_FILTER_ORDER,
            nil, "coTankDebuffs"),
        S.Slider("coTankDebuffCap", "Max Icons", 1, 8, 1, nil, "coTankDebuffs")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("coTankDebuffSize", "Icon Size", 10, 48, 1, nil, "coTankDebuffs"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("coTankDebuffPosition", "Position", DEBUFF_POS_VALUES, DEBUFF_POS_ORDER,
            nil, "coTankDebuffs"),
        S.Dropdown("coTankDebuffGrow", "Grow", DEBUFF_GROW_VALUES, DEBUFF_GROW_ORDER,
            nil, "coTankDebuffs")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("coTankDebuffX", "Offset X", -200, 200, 1, nil, "coTankDebuffs"),
        S.Slider("coTankDebuffY", "Offset Y", -200, 200, 1, nil, "coTankDebuffs")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("coTankDebuffSpacing", "Spacing", 0, 12, 1, nil, "coTankDebuffs"),
        S.Toggle("coTankDebuffTooltips", "Show Tooltips",
            "Off by default: the bar under the icons is click-to-target.", "coTankDebuffs")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("coTankDebuffDuration", "Show Time Left", nil, "coTankDebuffs"),
        S.Slider("coTankDebuffDurationSize", "Time Left Size", 6, 20, 1, nil, "coTankDebuffDuration")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("coTankDebuffStacks", "Show Stacks", nil, "coTankDebuffs"),
        S.Slider("coTankDebuffStackSize", "Stacks Size", 6, 20, 1, nil, "coTankDebuffStacks")
    ); y = y - h

    W:EndDisclosure(parent)
    W:EndFeature(parent)
    return y
end

function ns.BuildQoLLootPage(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "LOOTING", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("deleteConfirm", "Auto-Fill Delete Confirmation",
            "Types DELETE into the confirmation box for you, and names the item in the dialog as a "
            .. "link you can hover for its tooltip."),
        S.Toggle("fastLoot", "Faster Auto Loot", "Loots automatically without hiding the loot window. Hold Shift to loot manually.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "VENDORS", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("autoRepair", "Auto Repair", "Repairs all gear when you open a vendor who can."),
        S.Toggle("sellJunk", "Auto Sell Junk", "Sells grey items when you open a vendor.")
    ); y = y - h

    _, h = W:SectionHeader(parent, "AUCTION PRICES", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("ahPrices", "Scan Prices Button",
            "A Scan Prices button on the auction house. It reads every listing and keeps the "
            .. "lowest buyout for each item, for this realm and faction. Blizzard allows one full "
            .. "scan every 15 minutes."),
        { type = "label", text = "Price on tooltips: QoL > Tooltip Display" }
    ); y = y - h
    _, h = W:Note(parent, ns.AuctionScanSummary(), y); y = y - h

    _, h = W:SectionHeader(parent, "MAIL & ALTS", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("altCounts", "Alt Item Counts",
            "Item tooltips show how many your characters on this realm and faction hold in "
            .. "their bags, bank and mailbox. Each character is counted once you log in on it, "
            .. "and its bank once you open it."),
        S.Toggle("mailAlts", "Alts Button on Mail",
            "An Alts button beside the mailbox's Send tab lists your characters on this realm "
            .. "and faction with their level and gold. Pick one to fill the To box.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mailQuickAttach", "Quick Attach",
            "An Attach button beside the mailbox's Send tab: attach every trade good, one type "
            .. "of trade good, or your unbound gear in one click."),
        S.Toggle("mailExpiry", "Mail Expiry Warning",
            "At login, names any of your characters with mail that expires within three days. "
            .. "It knows each character's mail from the last time it opened a mailbox.")
    ); y = y - h
    local forget
    forget, h = W:Button(parent, "Forget a Character", y, function() ns.OpenForgetAltMenu(forget._btn) end); y = y - h

    _, h = W:SectionHeader(parent, "RESTOCK", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("restock", "Restock Reminder",
            "When you reach a city or inn, a flashing list in the middle of the screen of what "
            .. "you are short on. It stays up until you have what you need or leave. Move it "
            .. "in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("restockBuy", "Buy at Vendors",
            "At a vendor who sells them, tops your class reagents and ammo up to what you carry, "
            .. "and prints what it spent. Off by default: it spends gold for you.", "restock"),
        S.Toggle("restockReagents", "Class Reagents",
            "The reagents your known spells use, such as Arcane Powder, candles, seeds, Symbols "
            .. "of Kings and Flash Powder, matched to the highest rank you know.", "restock")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("restockAmmo", "Ammo", "The arrows or shot in your ammo slot.", "restock"),
        S.Slider("restockAmmoTarget", "Ammo to Carry", 200, 4000, 100, nil, "restockAmmo")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("restockFood", "Food & Drink", "Counts food and drink separately across all stacks. Warriors and rogues do not need drink.",
            "restock"),
        S.Slider("restockFoodBelow", "Food & Drink Below", 1, 40, 1, nil, "restockFood")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("restockVendor", "Junk & Full Bags",
            "Reminds you to vendor junk, and when your bags are nearly full.", "restock"),
        S.Slider("restockFoodMinLevel", "Food Minimum Required Level", 0, 60, 1,
            "Only count food and drink whose required level is within this range.", "restockFood")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("restockFoodMaxLevel", "Food Maximum Required Level", 0, 60, 1,
            "The same required-level filter applies to every stack, not each item separately.", "restockFood"),
        { type = "label", text = "" }
    ); y = y - h
    local sliders = ns.RestockReagentSliders()
    _, h = W:DualRow(parent, y,
        S.Slider("restockBagsBelow", "Free Slots Below", 1, 20, 1, nil, "restockVendor"),
        sliders[1] or { type = "label", text = "" }
    ); y = y - h
    for i = 2, #sliders, 2 do
        _, h = W:DualRow(parent, y, sliders[i], sliders[i + 1] or { type = "label", text = "" }); y = y - h
    end

    _, h = W:SectionHeader(parent, "BAG SPACE", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("bagSpace", "Bag Space",
            "The cheapest items in your bags as a row of icons, cheapest first. Ctrl-click an icon "
            .. "to delete it, or click it to sell it while a vendor is open. Middle-click to ignore "
            .. "an item. A key binding picks up the cheapest item. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("bagSpaceCount", "Items Shown", 1, 8, 1, nil, "bagSpace"),
        S.Dropdown("bagSpaceMaxQuality", "Highest Quality Offered", QUALITY_VALUES, QUALITY_ORDER,
            "Items above this quality are never offered.", "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagSpaceJunkFirst", "Grey Items First",
            "Grey items come before everything else, whatever they sell for.", "bagSpace"),
        S.Toggle("bagSpaceAuction", "Count Auction Prices",
            "An item worth more at the auction house than at a vendor is valued at its auction "
            .. "price, from your last Scan Prices or TradeSkillMaster.", "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagSpaceProtect", "Protect Needed Items",
            "Never offers reagents, ammo, quest items, keys, items in an equipment set or items "
            .. "on your BiS list.", "bagSpace"),
        S.Slider("bagSpaceFreeBelow", "Only With Free Slots Below", 0, 30, 1,
            "Shows the row only once your bags are this full. 0 shows it all the time.", "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagSpaceHideCombat", "Hide in Combat", nil, "bagSpace"),
        S.Toggle("bagSpaceOnFull", "Show When Bags Are Full",
            "An \"Inventory is full\" error brings the row up for 20 seconds, even with more free "
            .. "slots than the threshold above.", "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagSpaceShowFree", "Show Free Slots",
            "Free bag slots out of your total, above the row. Hover it for each bag.", "bagSpace"),
        S.Toggle("bagSpaceStack", "Offer to Stack",
            "A Stack button at the start of the row when part-filled stacks of the same item can "
            .. "be combined, with how many slots it frees. Nothing is deleted.", "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagSpaceOldFirst", "Outlevelled Food & Potions First",
            "Food, drink and potions 10 or more levels below you are marked OLD; this puts them "
            .. "first.", "bagSpace"),
        S.Slider("bagSpaceSize", "Icon Size", 24, 56, 1, nil, "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("bagSpaceGrow", "Direction", DIRECTION_VALUES, DIRECTION_ORDER, nil, "bagSpace"),
        S.Toggle("bagSpaceTipVendor", "Tooltip: Vendor Price",
            "What the whole stack sells for at a vendor, and each item's price.", "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagSpaceTipAuction", "Tooltip: Auction Price",
            "What the stack fetches at the auction house, from your last Scan Prices or "
            .. "TradeSkillMaster.", "bagSpace"),
        S.Toggle("bagSpaceTipDelete", "Tooltip: Delete Hint",
            "The Ctrl-click line, and Click to sell while a vendor is open.", "bagSpace")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bagSpaceTipIgnore", "Tooltip: Ignore Hint", "The Middle-click line.", "bagSpace"),
        { type = "label", text = "" }
    ); y = y - h
    local keyRow
    keyRow, h = W:DualRow(parent, y,
        { type = "label", text = "Pick Up Cheapest Item" },
        { type = "label", text = "" }
    ); y = y - h
    if ns.KeyField and keyRow then   -- keyRow is nil while the settings search scans this page
        ns.KeyField(keyRow._leftRegion, "NAOWHFOREVER_BAGSPACE_PICKUP", "Pick Up Cheapest Item")
    end
    _, h = W:Button(parent, "Ignore List", y, function()
        if ns.ShowBagSpaceIgnoreList then ns.ShowBagSpaceIgnoreList() end
    end); y = y - h

    _, h = W:SectionHeader(parent, "LOOT FEED", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("lootFeed", "Loot Feed",
            "Everything you loot pops up on screen with its icon, amount and value, stacking "
            .. "in your chosen direction and fading out. Hover a line for the item's tooltip. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedMoney", "Show Money", nil, "lootFeed"),
        S.Toggle("lootFeedQuest", "Show Quest Rewards",
            "A line for each quest you turn in, with the experience and money it gave. "
            .. "Reward items show as their own lines.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedRep", "Show Reputation",
            "A line for every reputation gain, from quests and kills alike.", "lootFeed"),
        S.Toggle("lootFeedXP", "Show Kill Experience",
            "A line for the experience from each kill. Quest experience is on the quest's "
            .. "own line.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedValue", "Show Item Value",
            "What each line is worth, in gold, silver and copper.", "lootFeed"),
        S.Dropdown("lootFeedQuality", "Lowest Quality Shown", QUALITY_VALUES, QUALITY_ORDER,
            nil, "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("lootFeedCount", "Lines Shown", 3, 12, 1, nil, "lootFeed"),
        S.Slider("lootFeedFade", "Display Time (s)", 0.5, 10, 0.5,
            "How long each line stays before it fades.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("lootFeedStyle", "Style", STYLE_VALUES, STYLE_ORDER, nil, "lootFeed"),
        S.Toggle("lootFeedGlow", "Glow", "A soft glow beside each icon.", "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedBank", "Count Bank Items",
            "The number on each icon counts your bank as well as your bags.", "lootFeed"),
        S.Dropdown("lootFeedPrice", "Price Source", PRICE_VALUES, PRICE_ORDER,
            "Auction (Naowh Scan) uses your last Scan Prices at the auction house; Auction (TSM) "
            .. "needs TradeSkillMaster. An item without an auction price counts at its vendor price.",
            "lootFeed")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("lootFeedGPH", "Gold per Hour",
            "A running gold per hour beside the newest line, counting money and item value "
            .. "since your first loot this session.", "lootFeed"),
        S.Toggle("hideLootWindow", "Hide Blizzard Loot Window",
            "Takes everything the moment you loot, with Blizzard's loot window kept out of "
            .. "sight, so the feed is all you see. Works with or without the game's auto loot. "
            .. "Hold Shift while looting to get the window back. It also appears whenever "
            .. "something cannot be taken: a group roll, a locked item, or bags too full.")
    ); y = y - h
    _, h = W:Button(parent, "Reset Gold per Hour", y, function()
        if ns.ResetLootFeedSession then ns.ResetLootFeedSession() end
    end); y = y - h

    _, h = W:Feature(parent, y, { type = "label", text = "Loot Feed Appearance" }); y = y - h
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
        S.Dropdown("lootFeedGrowth", "Growth Direction", { up = "Up", down = "Down" },
            { "up", "down" }, "The newest line stays at the anchor; older lines stack in this direction.",
            "lootFeed")
    ); y = y - h


    return y
end

function ns.BuildQoLAlertsPage(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "TALENT POINTS" .. STATUS.untested, y); y = y - h
    local talentFonts, talentFontOrder = UI.FontChoices(S.Get("talentPointsFont"))
    _, h = W:DualRow(parent, y,
        S.Toggle("talentPoints", "Unspent Talent Points",
            "Text on screen while you have talent points to spend. Hidden in combat. Move it in "
            .. "Unlock Mode."),
        S.Dropdown("talentPointsFont", "Font", talentFonts, talentFontOrder, nil, "talentPoints")
    ); y = y - h

    _, h = W:SectionHeader(parent, "COMBAT", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("groupDeaths", "Announce Group Deaths", "Shows who died in your group."),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("combatAlert", "Combat Alert",
            "A short flash of text entering and leaving combat. Move it in Unlock Mode.")
    ); y = y - h
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
                "A sound, or the Speech text read aloud. Text to Speech can stutter on some PCs, "
                .. "as the game waits while Windows speaks it; a Sound costs nothing.", "combatAlert"),
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
        _, h = W:DualRow(parent, y,
            TextControl(name .. " Text", name .. " combat text", k .. "Text"),
            TextControl(name .. " Speech", name .. " combat speech", k .. "Speech")
        ); y = y - h
    end

    _, h = W:SectionHeader(parent, "DURABILITY", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("durability", "Low Durability Warning",
            "Text on screen when any piece of gear drops below the threshold. Hidden in "
            .. "combat. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("durabilityBelow", "Warn Below (%)", 5, 100, 1, nil, "durability"),
        { type = "label", text = "" }
    ); y = y - h
    local durFonts, durFontOrder = UI.FontChoices(S.Get("durabilityFont"))
    _, h = W:DualRow(parent, y,
        S.Dropdown("durabilityFont", "Font", durFonts, durFontOrder, nil, "durability"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "COMBAT TIMER", y); y = y - h
    local timerFonts, timerFontOrder = UI.FontChoices(S.Get("combatTimerFont"))
    _, h = W:Feature(parent, y,
        S.Toggle("combatTimer", "Combat Timer",
            "How long the current fight has run, on screen while you fight. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatTimerInstanceOnly", "Only In Instances", nil, "combatTimer"),
        S.Toggle("combatTimerChat", "Report to Chat",
            "How long the fight lasted, in chat when it ends.", "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatTimerSticky", "Keep After the Fight",
            "The last fight's time stays on screen until the next one starts.", "combatTimer"),
        S.Toggle("combatTimerHidePrefix", "Hide the COMBAT Label", nil, "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatTimerBackground", "Show Background", nil, "combatTimer"),
        ColorRow("combatTimerColor", "Timer Colour", "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("combatTimerClassColor", "Class Colour", nil, "combatTimer"),
        S.Dropdown("combatTimerFont", "Font", timerFonts, timerFontOrder, nil, "combatTimer")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("combatTimerFontSize", "Font Size", 10, 72, 1, nil, "combatTimer"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "PET TRACKER", y); y = y - h
    local petFonts, petFontOrder = UI.FontChoices(S.Get("petFont"))
    _, h = W:Feature(parent, y,
        S.Toggle("petTracker", "Pet Tracker",
            "A warning while a hunter or warlock has no pet out. A warlock who sacrificed their "
            .. "demon is left alone. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("petPassive", "Warn While Passive", "Also warns while your pet is set to passive.",
            "petTracker"),
        S.Toggle("petLowHealth", "Warn on Low Pet Health",
            "Also warns while your pet's health is under the threshold, in combat too.", "petTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("petLowHealthBelow", "Low Health Below (%)", 5, 90, 1, nil, "petLowHealth"),
        S.Toggle("petCombatOnly", "Only In Combat", nil, "petTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("petInstanceOnly", "Only In Dungeons & Raids", nil, "petTracker"),
        S.Toggle("petHideMounted", "Hide While Mounted",
            "Also hidden for a few seconds after you dismount, while the pet comes back.", "petTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("petShowIcon", "Show Icon", nil, "petTracker"),
        ColorRow("petColor", "Colour", "petTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("petClassColor", "Class Colour", nil, "petTracker"),
        S.Dropdown("petFont", "Font", petFonts, petFontOrder, nil, "petTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("petFontSize", "Font Size", 12, 48, 1, nil, "petTracker"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = TextButton(parent, y, "Missing Text", "Text while your pet is missing", "petMissingText"); y = y - h
    _, h = TextButton(parent, y, "Passive Text", "Text while your pet is passive", "petPassiveText"); y = y - h
    _, h = TextButton(parent, y, "Low Health Text", "Text while your pet is low on health",
        "petLowHealthText"); y = y - h

    _, h = W:SectionHeader(parent, "EQUIPMENT REMINDER", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("equipReminder", "Equipment Reminder",
            "Your trinkets, weapons and ranged slot in a small window when you enter a dungeon "
            .. "or raid, or on a ready check, so a wrong trinket gets noticed before the pull. "
            .. "Drag the window to move it.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("equipEnchants", "Enchant Check",
            "Adds a line that flags any slot whose enchant is missing or differs from the ones "
            .. "you captured below. Hover it for the details.", "equipReminder"),
        S.Toggle("equipOnInstance", "Show Entering Dungeons & Raids", nil, "equipReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("equipOnReadyCheck", "Show on Ready Check", nil, "equipReminder"),
        S.Slider("equipAutoHide", "Hide After (s)", 0, 60, 1,
            "0 keeps it up until you close it.", "equipReminder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("equipIconSize", "Icon Size", 24, 64, 1, nil, "equipReminder"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Button(parent, "Capture Current Enchants", y, function()
        local count = ns.CaptureEnchants()
        ns.Print(("Captured %d enchant%s from your gear. The enchant check expects these from now on.")
            :format(count, count == 1 and "" or "s"))
    end); y = y - h
    _, h = W:Button(parent, "Show Equipment Check", y, function()
        if ns.ShowEquipmentReminder then ns.ShowEquipmentReminder() end
    end); y = y - h

    _, h = W:SectionHeader(parent, "EMOTE DETECTION", y); y = y - h
    local emoteFonts, emoteFontOrder = UI.FontChoices(S.Get("emoteFont"))
    _, h = W:Feature(parent, y,
        S.Toggle("emoteDetection", "Emote Detection",
            "An alert when an emote in a dungeon or raid contains one of your words, such as "
            .. "someone putting down a feast. Out of combat only. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("emoteSound", "Play a Sound", nil, "emoteDetection"),
        S.Dropdown("emoteSoundKey", "Sound", soundNames, soundOrder, nil, "emoteSound")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("emoteColor", "Text Colour", "emoteDetection"),
        S.Dropdown("emoteFont", "Font", emoteFonts, emoteFontOrder, nil, "emoteDetection")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("emoteFontSize", "Font Size", 10, 32, 1, nil, "emoteDetection"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = TextButton(parent, y, "Words to Watch For",
        "Words to watch for in emotes, separated by commas", "emotePattern"); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("autoEmote", "Auto Emotes",
            "An /emote of your own in a dungeon or raid when you start casting one of the spells "
            .. "below, so the group knows a summon is coming. Started in combat, it waits for "
            .. "the fight to end.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("autoEmoteCooldown", "Cooldown (s)", 0, 30, 1,
            "The shortest time between two auto emotes.", "autoEmote"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = TextButton(parent, y, "Auto Emote Spells",
        "Spell ID and emote, separated by semicolons, such as 698: prepares a ritual of summoning",
        "autoEmoteList"); y = y - h

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

    _, h = W:SectionHeader(parent, "SUPPORTER BADGES", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("badgeChat", "Chat Badges",
            "The Naowh Forever N next to the name of Naowh, the developers, the moderators and "
            .. "our Legendary patrons in chat."),
        S.Toggle("badgeCard", "Hover Card",
            "Hover a badged name in chat to see their card.", "badgeChat")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("badgeTooltip", "Tooltip Line",
            "A line in their colour on their player tooltip."),
        S.Toggle("badgeBanner", "Group Banner",
            "A banner and a sound when one of them joins your group.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("badgeBannerSkipGuild", "No Banner For Guild Members",
            "Skips the banner when they're in your guild.", "badgeBanner")
    ); y = y - h

    _, h = W:SectionHeader(parent, "CROSSHAIR" .. STATUS.untested, y); y = y - h
    local _, soundNames, soundOrder = ns.SoundChoices()
    _, h = W:Feature(parent, y,
        S.Toggle("crosshair", "Crosshair", "A crosshair at the middle of your screen.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("crossCombatOnly", "Only In Combat", nil, "crosshair"),
        S.Toggle("crossHideMounted", "Hide While Mounted", nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossOpacity", "Opacity", 0.1, 1, 0.05, nil, "crosshair"),
        S.Slider("crossSize", "Arm Length", 4, 100, 1, nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossThickness", "Thickness", 1, 20, 1, nil, "crosshair"),
        S.Slider("crossGap", "Gap", 0, 50, 1, "Space between the middle and each arm.", "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("crossColor", "Colour", "crosshair"),
        S.Toggle("crossClassColor", "Class Colour", nil, "crosshair")
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
        S.Toggle("crossOutline", "Outline", nil, "crosshair")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossOutlineWeight", "Outline Width", 1, 5, 1, nil, "crossOutline"),
        ColorRow("crossOutlineColor", "Outline Colour", "crossOutline")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("crossX", "X Offset", -500, 500, 1, nil, "crosshair"),
        S.Slider("crossY", "Y Offset", -500, 500, 1, nil, "crosshair")
    ); y = y - h
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

    _, h = W:SectionHeader(parent, "MOUSE RING" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("mouseRing", "Mouse Ring",
            "A ring around your cursor so you never lose it in a busy fight, with your global "
            .. "cooldown and casts swept around it.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseShowOOC", "Show Out of Combat", nil, "mouseRing"),
        S.Toggle("mouseHideOnClick", "Hide While Right-Click Held",
            "Hidden while you turn the camera with the right mouse button.", "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseHideAfk", "Hide While Away", "Hidden while you are away, outside instances.",
            "mouseRing"),
        S.Dropdown("mouseShape", "Shape", SHAPE_VALUES, SHAPE_ORDER, nil, "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseSize", "Size", 16, 128, 1, nil, "mouseRing"),
        ColorRow("mouseColor", "Ring Colour", "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseClassColor", "Class Colour", nil, "mouseRing"),
        S.Slider("mouseOpacityCombat", "Opacity In Combat", 0.1, 1, 0.05,
            "Also used inside dungeons and raids.", "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseOpacityOOC", "Opacity Out of Combat", 0.1, 1, 0.05, nil, "mouseRing"),
        S.Toggle("mouseBorder", "Border", nil, "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseBorderWeight", "Border Width", 1, 10, 1, nil, "mouseBorder"),
        ColorRow("mouseBorderColor", "Border Colour", "mouseBorder")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseBorderClassColor", "Class Colour", nil, "mouseBorder"),
        S.Toggle("mouseDot", "Centre Dot", nil, "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseDotSize", "Dot Size", 1, 20, 1, nil, "mouseDot"),
        ColorRow("mouseDotColor", "Dot Colour", "mouseDot")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseDotClassColor", "Class Colour", nil, "mouseDot"),
        S.Toggle("mouseFadeIdle", "Fade When Idle", "Fades out while the cursor stays still.",
            "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseFadeDelay", "Fade After (s)", 0.5, 10, 0.5, nil, "mouseFadeIdle"),
        S.Slider("mouseFadeOpacity", "Idle Opacity", 0, 1, 0.05, nil, "mouseFadeIdle")
    ); y = y - h

    _, h = W:SectionHeader(parent, "MOUSE RING GCD & CASTS", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("mouseGCD", "GCD Sweep",
            "Your global cooldown swept around the ring, and a ready ring once it is over.",
            "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseHideBackground", "Hide Ring Under the Sweep",
            "Only the sweep and the ready ring show.", "mouseGCD"),
        ColorRow("mouseGCDColor", "Sweep Colour", "mouseGCD")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseGCDClassColor", "Class Colour", nil, "mouseGCD"),
        ColorRow("mouseReadyColor", "Ready Colour", "mouseGCD")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseReadyMatch", "Ready Matches Sweep", nil, "mouseGCD"),
        S.Toggle("mouseCastSwipe", "Cast Sweep", "Your casts and channels swept around the ring too.",
            "mouseGCD")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("mouseCastColor", "Cast Sweep Colour", "mouseCastSwipe"),
        S.Toggle("mouseCastClassColor", "Class Colour", nil, "mouseCastSwipe")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseGCDAlpha", "Sweep Opacity", 0.1, 1, 0.05, nil, "mouseGCD"),
        S.Slider("mouseSwipeDelay", "Sweep Delay (s)", 0, 0.5, 0.01,
            "Waits this long before a sweep starts, so one that is over at once does not flicker.",
            "mouseGCD")
    ); y = y - h

    _, h = W:SectionHeader(parent, "MOUSE RING TRAIL", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("mouseTrail", "Trail", "A fading trail behind the cursor.", "mouseRing")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("mouseTrailShape", "Trail Shape", TRAIL_VALUES, TRAIL_ORDER, nil, "mouseTrail"),
        ColorRow("mouseTrailColor", "Trail Colour", "mouseTrail")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseTrailClassColor", "Class Colour", nil, "mouseTrail"),
        S.Toggle("mouseTrailSparkle", "Sparkle", "Each point of the trail in a colour of its own.",
            "mouseTrail")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseTrailSize", "Trail Size", 4, 64, 1, nil, "mouseTrail"),
        S.Slider("mouseTrailLength", "Trail Length", 5, 60, 1, nil, "mouseTrail")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseTrailDuration", "Trail Duration (s)", 0.1, 5, 0.1, nil, "mouseTrail"),
        S.Slider("mouseTrailBrightness", "Trail Brightness", 0.1, 1, 0.05, nil, "mouseTrail")
    ); y = y - h

    _, h = W:SectionHeader(parent, "MOUSE RING MELEE RANGE", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("mouseMelee", "Recolour Out of Melee Range",
            "Turns the ring red while your target is out of melee range. Uses the same ability "
            .. "as the crosshair's melee check, Melee Spell ID included.", "mouseRing")
    ); y = y - h
    -- The ready ring only exists with GCD Sweep on, so recolouring it needs both.
    local readyRecolour = S.Toggle("mouseMeleeRing", "Recolour Ready Ring",
        "The ready ring shows with GCD Sweep on.", "mouseMelee")
    readyRecolour.disabled = function() return not (S.Get("mouseMelee") and S.Get("mouseGCD")) end
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseMeleeBorder", "Recolour Border", nil, "mouseMelee"),
        readyRecolour
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mouseMeleeSound", "Play a Sound", "Plays as your target leaves melee range.",
            "mouseMelee"),
        S.Dropdown("mouseMeleeSoundKey", "Sound", soundNames, soundOrder, nil, "mouseMeleeSound")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("mouseMeleeSoundInterval", "Repeat Every (s)", 0, 10, 1,
            "Plays the sound again this often while out of range. 0 plays it once.", "mouseMeleeSound"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "TOWN MAP" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("townMap", "Town Map Pins",
            "Trainers, vendors, innkeepers, flight masters and more pinned on the world map for "
            .. "your faction, with their name and title on hover. No more asking a guard.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("townPinSize", "Pin Size", 10, 28, 1, nil, "townMap"),
        S.Toggle("townCapitalsOnly", "Town Pins Only in Capitals", "Keeps vendors and trainers off questing maps.", "townMap")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("townSpiritHealers", "Spirit Healers", "Shows graveyards supplied by the game map.", "townMap"),
        S.Toggle("townZoneLinks", "Clickable Zone Exits", "Click an exit to open the adjoining zone map.", "townMap")
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

    _, h = W:SectionHeader(parent, "GLOBAL COPY" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("globalCopy", "Global Copy",
            "/copy puts the text of whatever is under your cursor in a box you can copy from. "
            .. "/copy followed by a frame name copies that frame's text instead.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("copyTooltipIds", "Copy IDs From Tooltips",
            "With a tooltip showing, the key below copies its spell, item or NPC ID.", "globalCopy"),
        S.Dropdown("copyModifier", "Modifier", MODIFIER_VALUES, MODIFIER_ORDER, nil, "copyTooltipIds")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("copyKey", "Key", KEY_VALUES, KEY_ORDER, nil, "copyTooltipIds"),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "SLASH COMMANDS" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("slashCommands", "Custom Slash Commands",
            "Short commands of your own that open a game window or run another command. A "
            .. "name another addon already uses is skipped.")
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
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Add Command", buttonText = "Add", onClick = function()
            ns.ShowAddSlashCommand(function() UI:RefreshPage(true) end)
        end },
        { type = "button", text = "Remove Command", buttonText = "Remove", onClick = function()
            ns.PromptText("Command to remove, such as /cdm", "", 0, function(v)
                if ns.RemoveSlashCommand(v) then UI:RefreshPage(true)
                else ns.Print(v .. " is not one of your commands.") end
            end)
        end }
    ); y = y - h
    _, h = W:Button(parent, "Restore Default Commands", y, function()
        ns.Confirm("Replace your commands with the defaults?", function()
            ns.RestoreSlashCommands()
            UI:RefreshPage(true)
        end)
    end); y = y - h

    _, h = W:SectionHeader(parent, "COMBAT LOGGING" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("combatLogger", "Auto Combat Logging",
            "Turns the combat log on in raids and off when you leave. The first time you enter "
            .. "each raid and difficulty it asks, and remembers your answer.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = ns.CombatLogging() and "Logging now" or "Not logging" },
        { type = "label", text = "" }
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

    _, h = W:SectionHeader(parent, "FLIGHT TIMER" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("flightTimer", "Flight Timer",
            "The route you are flying as a line between its two ends, the stops on the way "
            .. "sliding past you, and the time left to landing. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("flightEarlyLanding", "Land Early Button",
            "A button beside the timer that lands you at the next flight point.", "flightTimer"),
        S.Slider("flightTimerScale", "Scale", 0.5, 2, 0.05, nil, "flightTimer")
    ); y = y - h

    return y
end

function ns.BuildQoLTooltipPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Readable IDs appear below the tooltip. Hover a spell, item or NPC and press your shortcut to open a copy card. Copy cards open outside combat; typing never triggers the shortcut.", y); y = y - h
    _, h = W:SectionHeader(parent, "TOOLTIP DISPLAY", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("tooltipDisplay", "Tooltip Display")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("tooltipRestricted", "Restricted IDs", { hide = "Hide Line", hidden = "Show Hidden" }, { "hide", "hidden" }, nil, "tooltipDisplay"),
        S.Toggle("tooltipSpellID", "Show Spell ID", nil, "tooltipDisplay")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("tooltipItemID", "Show Item ID", nil, "tooltipDisplay"),
        S.Toggle("tooltipNPCID", "Show NPC ID", "Creature and vehicle IDs only; never player GUIDs.", "tooltipDisplay")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("tooltipCopy", "Mouseover Copy Shortcut", nil, "tooltipDisplay"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Copy Card" }); y = y - h
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

    _, h = W:SectionHeader(parent, "ITEM TOOLTIPS", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("ahTooltip", "Auction House Price",
            "Item tooltips show the item's price at your last auction house scan, for one of it, "
            .. "and how long ago that was. Scan with the Scan Prices button on the auction house "
            .. "(QoL > Loot & Items)."),
        { type = "label", text = "" }
    ); y = y - h
    return y
end

function ns.BuildQoLCastingPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "GCD TRACKER" .. STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("gcdTracker", "GCD Tracker",
            "Your recent casts as icons scrolling away from a point, with a bar underneath while "
            .. "you were casting or on the global cooldown. Gaps in the bar are time spent doing "
            .. "nothing. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("gcdCombatOnly", "Only In Combat", nil, "gcdTracker"),
        S.Toggle("gcdWorld", "Show in the World", nil, "gcdTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("gcdDungeon", "Show in Dungeons", nil, "gcdTracker"),
        S.Toggle("gcdRaid", "Show in Raids", nil, "gcdTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("gcdPvP", "Show in Battlegrounds", nil, "gcdTracker"),
        S.Dropdown("gcdDirection", "Direction", DIRECTION_VALUES, DIRECTION_ORDER, nil, "gcdTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("gcdDuration", "Time Shown (s)", 2, 15, 1, nil, "gcdTracker"),
        S.Slider("gcdIconSize", "Icon Size", 16, 64, 1, nil, "gcdTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("gcdSpacing", "Spacing", 0, 20, 1, nil, "gcdTracker"),
        S.Slider("gcdFadeStart", "Fade From", 0, 0.95, 0.05,
            "How far along an icon starts to fade, from 0 (at once) to 0.95 (at the very end).",
            "gcdTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("gcdStack", "Stack Overlapping Casts",
            "Casts within 0.3s of each other sit side by side instead of on top of each other.",
            "gcdTracker"),
        ColorRow("gcdTimelineColor", "Activity Bar Colour", "gcdTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("gcdTimelineHeight", "Activity Bar Height", 1, 12, 1, nil, "gcdTracker"),
        S.Toggle("gcdDowntime", "Downtime Summary",
            "After each fight longer than 15 seconds, how long you spent neither casting nor on "
            .. "the global cooldown, in chat.", "gcdTracker")
    ); y = y - h
    _, h = TextButton(parent, y, "Hidden Spells",
        "Spell IDs never shown, separated by commas. 6603 is Auto Attack, 75 is Auto Shot.",
        "gcdBlocklist"); y = y - h

    _, h = W:SectionHeader(parent, "FOCUS CAST BAR" .. STATUS.untested, y); y = y - h
    local focusFonts, focusFontOrder = UI.FontChoices(S.Get("focusFont"))
    local _, soundNames, soundOrder = ns.SoundChoices()
    local voices, voiceOrder = ns.TTSVoiceChoices()
    _, h = W:Feature(parent, y,
        S.Toggle("focusCastBar", "Focus Cast Bar",
            "Your focus target's casts on a bar of their own, coloured by whether your interrupt "
            .. "is ready, with a tick where it comes off cooldown and a shield on casts you cannot "
            .. "interrupt. Your interrupt is the first you know of Pummel, Shield Bash, Kick, "
            .. "Counterspell, Earth Shock, Silence and Feral Charge. Move it in Unlock Mode.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusHideFriendly", "Hide Friendly Casts", nil, "focusCastBar"),
        S.Slider("focusWidth", "Width", 100, 600, 5, nil, "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("focusHeight", "Height", 10, 60, 1, nil, "focusCastBar"),
        ColorRow("focusReadyColor", "Interrupt Ready Colour", "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusReadyClassColor", "Class Colour", nil, "focusCastBar"),
        ColorRow("focusCooldownColor", "Interrupt on Cooldown Colour", "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("focusInterruptedColor", "Interrupted Colour", "focusCastBar"),
        S.Toggle("focusColorNonInt", "Colour Uninterruptible Casts", nil, "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        ColorRow("focusNonIntColor", "Uninterruptible Colour", "focusColorNonInt"),
        ColorRow("focusBgColor", "Background Colour", "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("focusBgAlpha", "Background Opacity", 0, 1, 0.05, nil, "focusCastBar"),
        S.Toggle("focusIcon", "Show Icon", nil, "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("focusIconSide", "Icon Side", SIDE_VALUES, SIDE_ORDER, nil, "focusIcon"),
        S.Toggle("focusSpellName", "Show Spell Name", nil, "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("focusNameLength", "Name Length", 0, 40, 1,
            "Cuts the name to about this many letters. 0 shows it whole.", "focusSpellName"),
        S.Toggle("focusTarget", "Show Cast Target", "Who the cast is aimed at, in their class colour.",
            "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusTime", "Show Time Left", nil, "focusCastBar"),
        S.Toggle("focusShield", "Uninterruptible Shield", nil, "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusTick", "Interrupt Ready Tick",
            "A tick on the bar where your interrupt comes off cooldown. Hidden while it is ready.",
            "focusCastBar"),
        ColorRow("focusTickColor", "Tick Colour", "focusTick")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusTickClassColor", "Class Colour", nil, "focusTick"),
        ColorRow("focusTextColor", "Text Colour", "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusTextClassColor", "Class Colour", nil, "focusCastBar"),
        S.Dropdown("focusFont", "Font", focusFonts, focusFontOrder, nil, "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("focusFontSize", "Font Size", 8, 24, 1, nil, "focusCastBar"),
        S.Toggle("focusHideNonInt", "Hide Uninterruptible Casts", nil, "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusHideOnCooldown", "Hide While Interrupt Is on Cooldown", nil, "focusCastBar"),
        S.Slider("focusFadeTime", "Interrupted Fade (s)", 0, 3, 0.05,
            "How long an interrupted cast stays up. 0 hides it at once.", "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusInterrupter", "Show Who Interrupted", nil, "focusCastBar"),
        S.Dropdown("focusAudio", "Cast Start Audio", AUDIO_VALUES, AUDIO_ORDER,
            "A sound, or the Speech text read aloud, as each cast starts.", "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("focusSound", "Sound", soundNames, soundOrder, nil, "focusCastBar"),
        S.Dropdown("focusVoice", "Voice", voices, voiceOrder,
            "Game Default speaks in the voice the rest of the addon uses.", "focusCastBar")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("focusVolume", "Volume", 0, 100, 1, nil, "focusCastBar"),
        S.Slider("focusRate", "Speech Rate", -10, 10, 1, nil, "focusCastBar")
    ); y = y - h
    _, h = TextButton(parent, y, "Speech Text", "Spoken as a cast starts", "focusSpeech"); y = y - h

    return y
end
