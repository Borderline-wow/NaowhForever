-- Spells.lua: the next-swing attacks and paladin seals the Swing Timer colors its bars by, by spell ID.
local ns = _G.NaowhForever

ns.SwingTimer.SPELLS = {
    NEXT_SWING = {
        WARRIOR = { 78, 845 },
        DRUID = { 6807 },
        HUNTER = { 2973 },
    },
    QUEUE_OWN_COLOR = { [845] = "cleaveColor" },
    SEALS = {
        { id = 20154, key = "sealRighteousColor", label = "Seal of Righteousness" },
        { id = 21082, key = "sealCrusaderColor", label = "Seal of the Crusader" },
        { id = 20375, key = "sealCommandColor", label = "Seal of Command" },
        { id = 20164, key = "sealJusticeColor", label = "Seal of Justice" },
        { id = 20165, key = "sealLightColor", label = "Seal of Light" },
        { id = 20166, key = "sealWisdomColor", label = "Seal of Wisdom" },
        { id = 1311649, key = "sealFuryColor", label = "Seal of Fury" },
        { id = 407798, key = "sealMartyrdomColor", label = "Seal of Martyrdom" },
    },
    HEROIC_STRIKE = 78,
}
