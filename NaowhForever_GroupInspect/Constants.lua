-- Constants.lua: the numbers and lists several of Group Inspect's files share (GI.C).
local ns = _G.NaowhForever

local PARTY_SIZE, RAID_SIZE = 4, 40

local C = {
    STALE = 300,
    MAIN_HAND = 16,
    OFF_HAND = 17,
    TREE_COUNT = 3,
    TENTHS = 10,
    ROUND = 0.5,
    PERCENT = 100,
    STAT_KEYS = { "STR", "AGI", "STA", "INT", "SPI", "AP", "SP", "CRIT", "HIT", "ARMOR" },
    STAT_MAX = { 99999, 99999, 99999, 99999, 99999, 99999, 99999, 1000, 1000, 999999 },
    PARTY_UNITS = {},
    RAID_UNITS = {},
}
for i = 1, PARTY_SIZE do C.PARTY_UNITS[i] = "party" .. i end
for i = 1, RAID_SIZE do C.RAID_UNITS[i] = "raid" .. i end
ns.GroupInspect.C = C
