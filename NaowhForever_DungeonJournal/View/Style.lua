-------------------------------------------------------------------------------
--  View/Style.lua -- what only the Dungeon Journal draws (ns.Journal.Style): its colours,
--  icons and sizes. The house look every module shares (borders, BiS ranks, cards, item
--  rows, windows) is ns.Shared.Style, read through this table.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"

J.Style = setmetatable({
    ---------------------------------------------------------------------------
    --  Colours
    ---------------------------------------------------------------------------
    -- Whose ground a zone is, in the factions' own colours.
    TERRITORY_CODE = { Alliance = "|cff4a9eff", Horde = "|cffff4d4d", Contested = "|cffe6cc80" },
    -- A faction's standing, Hated to Exalted (the game's reactions 1 to 8): red through
    -- yellow to green, then teal, blue and violet, so the high standings stand apart.
    STANDING_RGB = {
        { r = 0.80, g = 0.20, b = 0.20 }, { r = 0.93, g = 0.30, b = 0.25 }, { r = 0.93, g = 0.55, b = 0.25 },
        { r = 0.90, g = 0.78, b = 0.30 }, { r = 0.40, g = 0.80, b = 0.35 }, { r = 0.25, g = 0.80, b = 0.55 },
        { r = 0.30, g = 0.70, b = 0.95 }, { r = 0.65, g = 0.55, b = 1.00 },
    },
    -- A price's coin: the game's own, a pixel under the middle, level with the digits.
    COIN_ICON = { g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:-1|t",
                  s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:-1|t" },
    -- A quest's state: the quest log's own colours where it has one.
    QUEST_CODE = {
        prereq = "|cffff9933", prereqLog = "|cffffd100", low = "|cff9ca3af", pickup = "|cffd8dbe0",
        tooHigh = "|cffff4d4d", next = "|cffff9933", active = "|cffffd100", ready = "|cff19ff19",
        done = "|cff9ca3af",
    },

    ---------------------------------------------------------------------------
    --  Icons
    ---------------------------------------------------------------------------
    CONTESTED = MEDIA .. "swords",          -- contested ground, in the contested gold
    FACTION_ATLAS = { Alliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
                      Horde = "UI-HUD-UnitFrame-Player-PVP-HordeIcon" },
    CHAIN = MEDIA .. "chain",               -- a quest's chain
    SKULL = MEDIA .. "skull",               -- a boss's kill count
    PEOPLE = MEDIA .. "people",             -- group members on the same quest
    -- The game's quest marks: a yellow ! to pick up, a ? to hand in.
    BANG = "Interface/GossipFrame/AvailableQuestIcon",
    QUESTION = "Interface/GossipFrame/ActiveQuestIcon",
    KILL_DATE = "%a %d %b %Y, %H:%M",

    ---------------------------------------------------------------------------
    --  The page
    ---------------------------------------------------------------------------
    COMPACT_W = 560,        -- narrower (the map panel): quests put their icons on their own line

    -- The dungeon's header: its name over where it is, and the stats of what is there for you.
    TITLE_SIZE = 20,
    TITLE_H = 20,
    TITLE_GAP = 5,
    WHERE_H = 14,
    HEADER_PAD = 14,
    STAT_ICON = 14,
    STAT_GAP = 16,
    STAT_SPACE = 3,
    STAT_LINE_H = 22,       -- the stats' own line, when narrow

    -- Quest rows.
    QUEST_LEVEL_W = 24,
    QUEST_RIGHT = 12,
    QUEST_TOP = 6,
    QUEST_LINE_GAP = 3,
    QUEST_BOTTOM = 8,
    MARK = 16,
    CHAIN_SLOT = 40,        -- Chain and its step ("2/2")
    PARTY_SLOT = 32,        -- the group members on a quest and how many, while in a group

    -- Boss cards.
    BADGE = 20,             -- the kill-order number's box
    TIP_ICON = 14,
    FADED = 0.25,           -- a clicked boss's items that are not BiS or an upgrade
    FOREVER_H = 10,   -- WoW Forever's mark before a list's name: 20 wide, in its 26px column
    UNUSABLE = 0.45,        -- an item your class cannot use, with My Class Only off

    -- The drop chance: the number over its bar, scaled by the square root so 2% and 15% still
    -- look apart, and as bright as the odds: the accent from CHANCE_HIGH, the soft accent
    -- from CHANCE_FAIR, muted below.
    CHANCE_W = 40,
    CHANCE_BAR_W = 36,
    CHANCE_HIGH = 25,
    CHANCE_FAIR = 10,

    DENSE_H = 30,
    DENSE_TALL_H = 44,
    DENSE_ICON = 26,
    DENSE_CHANCE_TOP = 5,
    DENSE_BAR_BOTTOM = 6,

    -- The bosses with nothing for you, as chips at the end.
    CHIP_H = 20,
    CHIP_PAD = 8,
    CHIP_GAP = 6,

    ---------------------------------------------------------------------------
    --  The window and its list
    ---------------------------------------------------------------------------
    WINDOW_W = 1160,
    WINDOW_H = 800,
    LIST_W = 340,           -- wide enough for every dungeon's whole name, NEW and the levels
    LIST_ROW = 24,
    TERRITORY_ICON = 14,
    TERRITORY_GAP = 6,
    FACTION_W = 26,         -- each half of the faction switch beside the search
    FACTION_ICON = 18,
    FACTION_OFF = 0.35,     -- a half that is off: its crest greyed to this
    FACTION_GAP = 6,
    LIST_NAME_SIZE = 13,
    LIST_COUNT_SIZE = 12,
    LIST_BAR = 4,
    LIST_BAR_GAP = 2,
    GROUP_H = 22,
    STANDING_BAR = 6,
    LIST_STANDING_W = 30,

    ROLE_ATLAS = { T = "UI-LFG-RoleIcon-Tank-Micro", H = "UI-LFG-RoleIcon-Healer-Micro",
        D = "UI-LFG-RoleIcon-DPS-Micro" },
    ROLE_NAME = { T = "Tank", H = "Healer", D = "Damage" },
}, { __index = ns.Shared.Style })
