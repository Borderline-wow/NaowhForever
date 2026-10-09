-- Style.lua: the Top Bar's own look: its glyphs, the pills, the badges, the readout's bands and its tooltips' colors (ns.TopBar.Style).
local ns = _G.NaowhForever

local MEDIA = "Interface\\AddOns\\NaowhForever_TopBar\\Media\\"

ns.TopBar.Style = setmetatable({
    MEDIA = MEDIA,
    GLYPH = {
        NaowhForeverJournal = MEDIA .. "icon-journal.png",
        NaowhForeverBiS = MEDIA .. "icon-bis.png",
        NaowhForeverGroup = MEDIA .. "icon-group.png",
        NaowhForeverTraining = MEDIA .. "icon-training.png",
        NaowhForeverDiscovery = MEDIA .. "icon-discovery.png",
    },
    ICON = {
        friends = MEDIA .. "icon-friends.png",
        guild = MEDIA .. "icon-guild.png",
        hearth = MEDIA .. "icon-hearth.png",
    },
    RESTING = MEDIA .. "resting.blp",

    PILL_BG = { r = 0.03, g = 0.03, b = 0.04 },
    PILL_LINE_ALPHA = 0.55,
    FRIENDS_RGB = { r = 0.3, g = 1, b = 0.3 },
    GUILD_RGB = { r = 1, g = 0.62, b = 0.1 },
    GUILD_COUNT_RGB = { r = 1, g = 0.6, b = 0.1 },
    GUILD_NAME_RGB = { r = 0.1, g = 1, b = 0.1 },
    BNET_RGB = { r = 0.51, g = 0.77, b = 1 },
    READY_RGB = { r = 0.3, g = 1, b = 0.3 },
    COOLDOWN_RGB = { r = 1, g = 0.3, b = 0.3 },
    NO_CLASS_RGB = { r = 1, g = 1, b = 1 },
    AWAY_GREY = "|cff808080",

    FPS_GREAT_RGB = { r = 0.25, g = 1, b = 0.25 },
    FPS_GOOD_RGB = { r = 0.55, g = 1, b = 0.25 },
    FPS_OK_RGB = { r = 1, g = 1, b = 0.25 },
    FPS_LOW_RGB = { r = 1, g = 0.35, b = 0.25 },
    MS_GOOD_RGB = { r = 0.25, g = 1, b = 0.25 },
    MS_OK_RGB = { r = 1, g = 1, b = 0.25 },
    MS_HIGH_RGB = { r = 1, g = 0.35, b = 0.25 },

    WHITE = 1,
    LABEL_GREY = 0.7,
    EMPTY_GREY = 0.6,
    MORE_GREY = 0.5,
}, { __index = ns.Shared.Style })
