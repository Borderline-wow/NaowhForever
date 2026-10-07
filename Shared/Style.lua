-------------------------------------------------------------------------------
--  Style.lua -- the house look every module shares (ns.Shared.Style): colours, icons and
--  sizes, in one place. A module keeps its own Style for what only it draws, and reads
--  these through it (setmetatable(..., { __index = ns.Shared.Style })).
--
--  Names end in what they hold: _CODE a colour escape ("|cffb06bff"), _RGB a colour table
--  { r, g, b } (0-1). The theme's own colours (T.fg, T.muted, T.accent...) come from the
--  addon's theme instead; they are read when a row is made, so a theme change shows after
--  a /reload. Sizes are in pixels at the addon's UI scale.
-------------------------------------------------------------------------------
local Shared = _G.NaowhForever.Shared

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"

Shared.Style = {
    ---------------------------------------------------------------------------
    --  Colours
    ---------------------------------------------------------------------------
    -- Naowh's house style: a 1px black border round cards, badges, chips, icons, buttons
    -- and panels. The accent (Naowh blue, the theme's T.accent) marks what is picked.
    BORDER_RGB = { r = 0, g = 0, b = 0 },
    BACKDROP_ALPHA = 0.97,
    HUD_SHADOW_RGB = { r = 0, g = 0, b = 0 },
    HUD_SHADOW_ALPHA = 0.8,
    HUD_SHADOW_X = 1,
    HUD_SHADOW_Y = -1,
    HUD_CARD_ALPHA = 0.85,
    -- HUD text without the card (Parts.HudBackdrop): Soft fades from HUD_SOFT_ALPHA behind the text
    -- to clear over HUD_SOFT_FADE, HUD_SOFT_INSET of it inside the card's edge; its text shadow is at
    -- full strength. None has no backdrop: the shadow at full strength, as close (2px doubles small text).
    HUD_SOFT_ALPHA = 0.7,
    HUD_SOFT_FADE = 32,
    HUD_SOFT_INSET = 12,
    HUD_SOFT_SHADOW_ALPHA = 1,
    HUD_BARE_SHADOW_ALPHA = 1,
    HUD_BARE_SHADOW_X = 1,
    HUD_BARE_SHADOW_Y = -1,
    -- An item level above yours; bags with no room left.
    RED_CODE = "|cfff87171",
    RED_RGB = { r = 0.97, g = 0.44, b = 0.44 },
    -- Running low, or likely junk: few bag slots left, food and potions you have outlevelled.
    WARN_CODE = "|cfffb923c",
    WARN_RGB = { r = 0xfb / 255, g = 0x92 / 255, b = 0x3c / 255 },
    -- Naowh's gold: tips, and the contested zones.
    GOLD_CODE = "|cffe6cc80",
    TIP_RGB = { r = 0.9, g = 0.8, b = 0.5 },
    -- Your BiS list's ranks: your BiS (#1) an orange star, legendary orange so it stands apart
    -- from blue item names; your second pick a silver one, and the rest a muted number.
    BIS_CODE = "|cffff8000",
    BIS_RGB = { r = 1, g = 0.5, b = 0 },
    SECOND_CODE = "|cffc7ccdb",
    SECOND_RGB = { r = 0xc7 / 255, g = 0xcc / 255, b = 0xdb / 255 },
    -- New looks (appearances) in cyan, clear of BiS orange for colour-blind eyes too.
    LOOK_CODE = "|cff66d9ef",
    LOOK_RGB = { r = 0x66 / 255, g = 0xd9 / 255, b = 0xef / 255 },
    -- Upgrade, in the game's uncommon green.
    UPGRADE_CODE = "|cff1eff00",
    -- You have it: what you wear (its bar), a party member with the quest.
    HAVE_RGB = { r = 0.3, g = 0.82, b = 0.48 },
    -- WoW Forever's own: the pale gold of its logo, on what is new in Forever.
    FOREVER_CODE = "|cffeed69e",
    FOREVER_RGB = { r = 0xee / 255, g = 0xd6 / 255, b = 0x9e / 255 },
    -- What you carry and can hand in, in the game's quest gold.
    CARRIED_RGB = { r = 1, g = 0.82, b = 0 },
    TIME_OK_RGB = { r = 0.29, g = 0.87, b = 0.5 },
    TIME_LOW_RGB = { r = 0.98, g = 0.8, b = 0.08 },
    TIME_OUT_RGB = { r = 0.97, g = 0.27, b = 0.27 },
    -- A boss picked on a dungeon map: its pin's ring, in the same gold, until the player
    -- picks an Accent of their own.
    PICKED_RGB = { r = 1, g = 0.82, b = 0 },
    -- The HUD Editor's guides: where a dragged element lines up, in amber so it never reads as
    -- the accent's selection.
    GUIDE_RGB = { r = 0xf2 / 255, g = 0xa3 / 255, b = 0x3a / 255 },

    ---------------------------------------------------------------------------
    --  Icons: the addon's own (Media/, drawn by Tools/make_media.py, white so they take
    --  any colour) and the game's
    ---------------------------------------------------------------------------
    ARROW = MEDIA .. "chevron",             -- section titles and links; turned down while open
    UP = MEDIA .. "chevron_up",             -- move a pick up; turned over, down
    HANGER = MEDIA .. "hanger",             -- new looks
    STAR = MEDIA .. "star",                 -- your BiS in BIS_RGB, your second pick in SECOND_RGB
    UPGRADE_ATLAS = "bags-greenarrow",      -- an upgrade: the game's own green arrow from the bags
    SCRAP_ATLAS = "bags-icon-scrappable",   -- scrap to sell at a vendor: the game's own bag scrap icon
    SCRAP_RATIO = 32 / 36,                  -- that icon's height to its width
    CLOCK_ATLAS = "auctionhouse-icon-clock",
    QUEST_ATLAS = "smallquestbang",
    PIN = MEDIA .. "pin",                   -- waypoints and places
    INFO = MEDIA .. "info",                 -- Naowh's tip
    LOGO = MEDIA .. "LogoAddon",            -- the Naowh logo, left of a window's title
    LOGO_SMALL = MEDIA .. "LogoSmall",      -- the same at text size, in a tooltip line
    BAG = MEDIA .. "bag",                   -- loot
    CROSS = MEDIA .. "cross",               -- remove, or turn a filter off
    PLUS = MEDIA .. "plus",                 -- add
    FUNNEL = MEDIA .. "funnel",             -- Filters
    TICK = MEDIA .. "check",                -- a ticked box in a menu
    OPACITY = MEDIA .. "opacity",           -- a window's opacity
    WAND = MEDIA .. "wand",                 -- fill in for you
    SCALES = MEDIA .. "scales",             -- Stat Weights: what each stat weighs
    FOREVER = MEDIA .. "infinity",          -- new in WoW Forever: its infinity sign, 32 by 16
    FOREVER_ICON = MEDIA .. "infinity_outlined", -- the same with a dark outline, on an item's icon
    ELBOW = MEDIA .. "elbow",               -- a tree line's rounded corner, 8 by 8, drawn at that size
    IMPORT = MEDIA .. "import",             -- bring in a shared string
    EXPORT = MEDIA .. "export",             -- make one to share
    ROUND = MEDIA .. "circle_mask",         -- a filled circle (128px: load it "TRILINEAR", or it is jagged small): the slider's knob and ends
    LIST_SHOWN = MEDIA .. "sidebar_shown",  -- a window's list button, while the list shows
    LIST_HIDDEN = MEDIA .. "sidebar_hidden",
    SEARCH = MEDIA .. "Navigation\\search.tga",
    PLAY = MEDIA .. "play",
    PAUSE = MEDIA .. "pause",
    RESET = MEDIA .. "reset",
    SOFT_SHADE = MEDIA .. "soft_shade",   -- round, opaque in the middle and clear at its edge: Soft's fade
    -- The game's ready check: done, had.
    CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready",
    -- Between a place and a person, or what an item is and its level: a middle dot.
    PLACE_DOT = " \194\183 ",

    ---------------------------------------------------------------------------
    --  A page
    ---------------------------------------------------------------------------
    GAP = 6,                -- between the parts of a row
    INDENT = 20,            -- notes line up here
    SECTION_H = 28,         -- a section title over its line
    SECTION_TIGHT_H = 20,
    SECTION_SPACE = 8,      -- under a section title, before what it holds
    NOTE_PAD = 6,           -- under a note
    ACTION = 16,            -- an icon button in a row
    STRIPE = 0.025,         -- every other row of a long list: a faint band in the text colour
    HOVER = 0.05,           -- the row under the mouse: a band in the text colour, a little stronger

    -- Cards: a faint fill with a hairline edge, as many across as fit at CARD_MIN_W each,
    -- up to MAX_COLUMNS; the cards in a row share a height.
    CARD_FILL = 0.025,      -- the fill: the text colour, this faint
    CARD_PAD = 10,          -- from the card's edge to its contents
    CARD_GAP = 10,          -- between cards, across and down
    CARD_BOTTOM = 6,        -- under the last row
    CARD_MIN_W = 310,
    MAX_COLUMNS = 3,
    CARD_HEADER_H = 38,     -- a card's header (a boss's, a slot's)
    CARD_NAME_SIZE = 15,    -- the name in it

    -- Item rows: the icon in its black border, beside two lines, the name in its quality
    -- colour.
    ICON = 30,
    ITEM_H = 40,

    ---------------------------------------------------------------------------
    --  A window: a title bar, cards on a gradient, a footer
    ---------------------------------------------------------------------------
    WINDOW_FOOTER = 20,     -- the strip under the cards
    WINDOW_HEADER = 52,     -- the title bar, to its rule
    WINDOW_PAD = 12,
    WINDOW_CARD_FILL = 0.035,   -- a window's cards, over its gradient
    WINDOW_CARD_EDGE = 0.7,
    CONTENT_INSET = 22,     -- from a window card's edge to what is in it
    SCROLLBAR = 16,
    SEARCH_H = 24,
    TAB_SIZE = 12,          -- a switch's words
    TAB_H = 26,
    TAB_LINE = 2,           -- the accent under the part shown
    TAB_FILL = 0.16,        -- the part shown: a fill in the accent, this faint
    TAB_GAP = 6,            -- a switch to what is under it
    LOGO_SIZE = 32,         -- the logo in the title bar
    BAR_ICON = 18,          -- the title bar's icons
    BAR_GAP = 12,           -- between them
    SLIDER_W = 90,
    SLIDER_H = 4,
    KNOB = 12,
    KNOB_GLOW = 22,
    OPACITY_MIN = 40,       -- percent
    PANEL_W = 380,          -- a panel beside a window or the map
    PANEL_PAD = 10,
    PANEL_HEADER = 30,
    PANEL_BUTTONS = 34,     -- a side panel's buttons along its bottom

    ---------------------------------------------------------------------------
    --  A tracker (Parts.TrackerPanel): a small window kept on screen, its rows a table with
    --  a waypoint pin in a column of its own
    ---------------------------------------------------------------------------
    TRACKER_W = 320,
    TRACKER_SLOT = 24,      -- the progress bar and the dropdown under its title
    TRACKER_BAR_RGB = { r = 0x14 / 255, g = 0x16 / 255, b = 0x19 / 255 },  -- behind the bar, the theme's panel once changed
    TRACKER_GAP = 6,        -- under each of them
    TRACKER_SCROLL = 20,    -- the body's right edge to the window's, for the scrollbar, while it scrolls
    CLOSE_ROOM = 34,        -- the title stops short of the close button
    ROW_LEFT = 6,           -- a row's pin column, from its left edge
    WAYPOINT_SLOT = 20,     -- the pin's column
    ROW_TOP = 6,            -- over a row's text
    ROW_LINE_GAP = 3,       -- between its text and the line under it
    ROW_BOTTOM = 8,         -- under its text
    ROW_RIGHT = 10,         -- right of its text
    ROW_HOVER = 0.04,       -- the row under the mouse: a band in the text colour
    ROW_DIVIDER = 0.6,      -- the line under each row, in the theme's line colour
    ROW_TICK = 16,          -- the tick in the pin's column once a row is done
}
