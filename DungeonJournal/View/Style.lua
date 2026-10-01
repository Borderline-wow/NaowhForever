-------------------------------------------------------------------------------
--  View/Style.lua -- how the Dungeon Journal looks: every colour, size, spacing and icon,
--  in one place (ns.Journal.Style). Change the look here; the files that draw it read these.
--
--  Names end in what they hold: _CODE a colour escape ("|cffff8000"), _RGB a colour table
--  { r, g, b } (0-1). The theme's own colours (T.fg, T.muted, T.accent...) come from the
--  addon's theme instead; they are read when a row is made, so a theme change shows after
--  a /reload. Sizes are in pixels at the addon's UI scale.
-------------------------------------------------------------------------------
local J = _G.NaowhForever.Journal

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"

J.Style = {
    ---------------------------------------------------------------------------
    --  Colours
    ---------------------------------------------------------------------------
    -- Naowh's house style: a 1px black border round cards, badges, chips, icons, buttons
    -- and panels. The accent (Naowh blue, the theme's T.accent) marks what is picked.
    BORDER_RGB = { r = 0, g = 0, b = 0 },
    -- An item level above yours.
    RED_CODE = "|cfff87171",
    -- Naowh's gold: tips, and the contested zones.
    GOLD_CODE = "|cffe6cc80",
    TIP_RGB = { r = 0.9, g = 0.8, b = 0.5 },
    -- BiS in legendary orange, so it stands apart from blue item names.
    BIS_CODE = "|cffff8000",
    BIS_RGB = { r = 1, g = 0.5, b = 0 },
    -- New looks (appearances) in cyan, clear of BiS orange for colour-blind eyes too.
    LOOK_CODE = "|cff66d9ef",
    LOOK_RGB = { r = 0x66 / 255, g = 0xd9 / 255, b = 0xef / 255 },
    -- Upgrade, in the game's uncommon green.
    UPGRADE_CODE = "|cff1eff00",
    -- You have it: what you wear (its bar), a party member with the quest.
    HAVE_RGB = { r = 0.3, g = 0.82, b = 0.48 },
    -- Whose ground a zone is, in the factions' own colours.
    TERRITORY_CODE = { Alliance = "|cff4a9eff", Horde = "|cffff4d4d", Contested = "|cffe6cc80" },
    -- A quest's state: the quest log's own colours where it has one.
    QUEST_CODE = {
        prereq = "|cffff9933", prereqLog = "|cffffd100", low = "|cff9ca3af", pickup = "|cffd8dbe0",
        tooHigh = "|cffff4d4d", next = "|cffff9933", active = "|cffffd100", ready = "|cff19ff19",
        done = "|cff9ca3af",
    },

    ---------------------------------------------------------------------------
    --  Icons: the addon's own (Media/, drawn by Tools/make_media.py, white so they take
    --  any colour) and the game's
    ---------------------------------------------------------------------------
    ARROW = MEDIA .. "chevron",             -- section titles and links; turned down while open
    HANGER = MEDIA .. "hanger",             -- new looks
    STAR = MEDIA .. "star",                 -- your BiS, in BIS_RGB
    UPGRADE_ATLAS = "bags-greenarrow",      -- an upgrade: the game's own green arrow from the bags
    -- The factions' crests, as the game's own unit frames show them.
    CONTESTED = MEDIA .. "swords",          -- contested ground, in the contested gold
    FACTION_ATLAS = { Alliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
                      Horde = "UI-HUD-UnitFrame-Player-PVP-HordeIcon" },
    PIN = MEDIA .. "pin",                   -- waypoints and the entrance
    CHAIN = MEDIA .. "chain",               -- a quest's chain
    INFO = MEDIA .. "info",                 -- Naowh's tip
    LOGO = MEDIA .. "LogoAddon",            -- the Naowh logo, left of the window's title
    LOGO_SMALL = MEDIA .. "LogoSmall",      -- the same at text size, in a tooltip line
    SKULL = MEDIA .. "skull",               -- a boss's kill count
    BAG = MEDIA .. "bag",                   -- loot with no kill, in a boss's history
    PEOPLE = MEDIA .. "people",             -- group members on the same quest
    CROSS = MEDIA .. "cross",               -- turns off the filter that folded bosses away
    FUNNEL = MEDIA .. "funnel",             -- Filters
    OPACITY = MEDIA .. "opacity",           -- the window's opacity
    ROUND = MEDIA .. "circle_mask",         -- a filled circle: the slider's knob and ends, the chance bar's
    LIST_SHOWN = MEDIA .. "sidebar_shown",  -- the dungeon list's button, while it shows
    LIST_HIDDEN = MEDIA .. "sidebar_hidden",
    -- The game's quest marks: a yellow ! to pick up, a ? to hand in; and its check.
    BANG = "Interface/GossipFrame/AvailableQuestIcon",
    QUESTION = "Interface/GossipFrame/ActiveQuestIcon",
    CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready",
    -- Between a place and a person, or what an item is and its level: a middle dot.
    PLACE_DOT = " \194\183 ",
    -- A kill's or an item's date and time, in their tooltips.
    KILL_DATE = "%a %d %b %Y, %H:%M",

    ---------------------------------------------------------------------------
    --  The page
    ---------------------------------------------------------------------------
    GAP = 6,                -- between the parts of a row
    INDENT = 20,            -- quests and notes line up here
    COMPACT_W = 560,        -- narrower (the map panel): quests put their icons on their own line
    SECTION_H = 28,         -- a section title over its line
    SECTION_SPACE = 8,      -- under a section title, before what it holds
    NOTE_PAD = 6,           -- under a note

    ---------------------------------------------------------------------------
    --  The dungeon's header: its name over where it is, and the stats of what is there for
    --  you (quests, BiS, new looks)
    ---------------------------------------------------------------------------
    TITLE_SIZE = 20,
    TITLE_H = 20,
    TITLE_GAP = 5,          -- between the name and the line under it
    WHERE_H = 14,
    HEADER_PAD = 14,        -- under the header
    STAT_ICON = 14,
    STAT_GAP = 16,          -- between two stats
    STAT_SPACE = 3,         -- between a stat's icon and its number
    STAT_LINE_H = 22,       -- the stats' own line, when narrow

    ---------------------------------------------------------------------------
    --  Quest rows
    ---------------------------------------------------------------------------
    QUEST_LEVEL_W = 24,     -- the level's column
    QUEST_RIGHT = 12,       -- a quest row's right edge to its icons, inside its stripe
    QUEST_TOP = 6,          -- above the title
    QUEST_LINE_GAP = 3,     -- between the title and where
    QUEST_BOTTOM = 8,       -- under where
    MARK = 16,              -- the quest mark
    ACTION = 16,            -- the Chain and Waypoint icons
    CHAIN_SLOT = 40,        -- Chain and its step ("2/2")
    PARTY_SLOT = 32,        -- the group members on a quest and how many ("2"), while in a group
    WAYPOINT_SLOT = 20,
    ACTIONS_LINE_H = 20,    -- the mark and icons' own line, when narrow

    ---------------------------------------------------------------------------
    --  Boss cards: a faint fill with a hairline edge, as many across as fit at CARD_MIN_W
    --  each, up to MAX_COLUMNS; the cards in a row share a height
    ---------------------------------------------------------------------------
    CARD_FILL = 0.025,      -- the fill: the text colour, this faint
    CARD_PAD = 10,          -- from the card's edge to its contents
    CARD_GAP = 10,          -- between cards, across and down
    CARD_BOTTOM = 6,        -- under the last item
    CARD_MIN_W = 310,
    MAX_COLUMNS = 3,
    BADGE = 20,             -- the kill-order number's box
    BOSS_HEADER_H = 38,
    BOSS_NAME_SIZE = 15,
    TIP_ICON = 14,          -- Naowh's (i)
    FADED = 0.25,           -- a clicked boss's items that are not BiS or an upgrade
    STRIPE = 0.025,         -- every other row of a long list (the quests, the dungeon list): a
                            -- faint band in the text colour, so a wide row reads across
    NEW_TAG_SIZE = 9,       -- NEW before a new dungeon's name in the list, small
    UNUSABLE = 0.45,        -- an item your class cannot use, with My Class Only off

    ---------------------------------------------------------------------------
    --  Item rows: the icon in its black border, beside two lines, the name in its quality
    --  colour
    ---------------------------------------------------------------------------
    ICON = 30,
    ITEM_H = 40,
    -- The drop chance: the number over its bar. The bar is scaled by the square root, so
    -- 2% and 15% still look apart, and it is as bright as the odds: the accent from
    -- CHANCE_HIGH, the soft accent from CHANCE_FAIR, muted below that.
    CHANCE_W = 40,
    CHANCE_BAR_W = 36,
    CHANCE_HIGH = 25,
    CHANCE_FAIR = 10,

    ---------------------------------------------------------------------------
    --  The bosses with nothing for you, as chips at the end
    ---------------------------------------------------------------------------
    CHIP_H = 20,
    CHIP_PAD = 8,
    CHIP_GAP = 6,

    ---------------------------------------------------------------------------
    --  The window, its dungeon list, and the panels beside the map and at the cursor
    ---------------------------------------------------------------------------
    WINDOW_W = 1160,
    WINDOW_H = 780,
    WINDOW_HEADER = 52,     -- the title bar, to its rule
    WINDOW_PAD = 12,
    WINDOW_CARD_FILL = 0.035,   -- the window's two cards, over its gradient
    WINDOW_CARD_EDGE = 0.7,
    CONTENT_INSET = 22,     -- from a window card's edge to what is in it
    SCROLLBAR = 16,
    LIST_W = 340,           -- wide enough for every dungeon's whole name, NEW and the levels
    LIST_ROW = 24,
    TERRITORY_ICON = 14,    -- whose ground a dungeon is on, after its levels
    TERRITORY_GAP = 6,
    FACTION_W = 26,         -- each half of the faction switch beside the search
    FACTION_ICON = 18,
    FACTION_OFF = 0.35,     -- a half that is off: its crest greyed to this
    FACTION_GAP = 6,        -- the search to the switch
    LIST_NAME_SIZE = 13,    -- a dungeon's name in the list
    LIST_COUNT_SIZE = 12,   -- its BiS count and levels
    LIST_BAR = 4,           -- the list's scrollbar, shown once it runs past the window
    LIST_BAR_GAP = 2,
    GROUP_H = 22,           -- a group's title in the list
    SEARCH_H = 24,
    LOGO_SIZE = 32,         -- the logo in the title bar
    BAR_ICON = 18,          -- the title bar's icons (list, Filters, Opacity)
    SLIDER_W = 90,
    SLIDER_H = 4,
    KNOB = 12,
    KNOB_GLOW = 22,
    OPACITY_MIN = 40,       -- percent
    PANEL_W = 380,          -- beside the map, and Boss Loot at Cursor
    PANEL_PAD = 10,
    PANEL_HEADER = 30,
    PANEL_BUTTONS = 34,     -- a side panel's buttons along its bottom

    -- The game's small role icons, by the Team's role codes, and the roles' names.
    ROLE_ATLAS = { T = "UI-LFG-RoleIcon-Tank-Micro", H = "UI-LFG-RoleIcon-Healer-Micro",
        D = "UI-LFG-RoleIcon-DPS-Micro" },
    ROLE_NAME = { T = "Tank", H = "Healer", D = "Damage" },
}
