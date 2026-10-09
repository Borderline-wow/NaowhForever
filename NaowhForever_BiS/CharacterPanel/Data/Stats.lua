-- Stats.lua: the stats the character panel lists for your spec, in order, and what each one does (CP.Stats).
local ns = _G.NaowhForever

local CP = ns.CharacterPanel

CP.Stats = {
    ORDER = { "agi", "str", "int", "spi", "ap", "rap", "spell", "heal", "fire", "frost", "shadow",
        "nature", "arcane", "holy", "crit", "scrit", "hit", "shit", "haste", "dps", "mp5", "def", "dodge",
        "block", "sta", "armor" },
    ALWAYS = { sta = true, armor = true },
    SHORT = { rap = "Ranged AP", mp5 = "Mana / 5 sec" },
    YARDSTICKS = { "agi", "str", "sta", "spell", "heal", "int", "ap" },
    HEADING = { agi = "VS AGI", str = "VS STR", sta = "VS STA", spell = "VS SPELL", heal = "VS HEAL",
        int = "VS INT", ap = "VS AP" },
    PERCENT = { hit = true, shit = true, crit = true, haste = true, scrit = true, dodge = true, block = true },
    DOES = {
        agi = "Attack power, crit chance, dodge and armor.",
        str = "Attack power, and block with a shield.",
        int = "Mana and spell crit chance.",
        spi = "Mana and health back while not casting.",
        ap = "More damage from your weapons.",
        rap = "More damage from your ranged weapon.",
        spell = "More damage from your spells.",
        heal = "More healing from your spells.",
        fire = "More damage from your Fire spells.",
        frost = "More damage from your Frost spells.",
        shadow = "More damage from your Shadow spells.",
        nature = "More damage from your Nature spells.",
        arcane = "More damage from your Arcane spells.",
        holy = "More damage from your Holy spells.",
        crit = "Chance for a hit to deal double damage.",
        scrit = "Chance for a spell to crit.",
        hit = "Chance not to miss: worth the most until you stop missing.",
        shit = "Chance for a spell not to miss: worth the most until you stop missing.",
        haste = "Faster attacks.",
        dps = "Your weapon's damage per second.",
        mp5 = "Mana back every 5 seconds, even while casting.",
        def = "Lowers the chance to be hit, crit and dazed.",
        dodge = "Chance to dodge a melee hit.",
        block = "Chance to block a hit with a shield.",
        sta = "Health.",
        armor = "Less physical damage taken.",
    },
}
