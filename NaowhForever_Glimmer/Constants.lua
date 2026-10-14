-- Constants.lua: the names, settings, timings and limits Glimmer's files share.
local ns = _G.NaowhForever

ns.Glimmer.C = {
    PAGE = "Glimmer/Settings",
    UNIT = "softinteract",
    BOBBER = 35591,
    GUID_OBJECT = "^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-",
    PROFESSION_OF = { ore = 186, herb = 182 },
    SKILL_ORANGE = 25, SKILL_YELLOW = 50, SKILL_GREEN = 100,
    SOFT_CVARS = {
        SoftTargetInteract = "3",
        SoftTargetInteractOnlyInRange = "0",
    },
    RANGE_CVAR = "SoftTargetInteractRange",
    ARC_CVAR = "SoftTargetInteractArc",
    PLATE_CVAR = "SoftTargetNameplateInteract",
    SPARKLE_CVARS = {
        outlineModeShowLootEffectWhenDisabled = "1",
        graphicsOutlineMode = "0",
        OutlineEngineMode = "0",
        raidGraphicsOutlineMode = "0",
        RAIDOutlineEngineMode = "0",
    },
    SPARKLE_RESETS = { graphicsquality = true, raidgraphicsquality = true },
    SPARKLE_AGAIN = 1,
    CURSOR_WORDS = { herb = "herb", mine = "ore" },
    CURSOR_UNABLE = "unable",
    STATE_CHECK = 0.15,
    STATE_HOLD = 0.15,
    OTHER_ADDONS = { "Lueur", "ForeverLootSparkles" },
}
