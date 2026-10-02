-------------------------------------------------------------------------------
--  Data/Maps.lua -- each dungeon's map, by hand: the game's own map art for it and where its
--  bosses stand on it. Forever's world map has no dungeon floors, but the client still holds
--  the old world map's dungeon art: Interface\WorldMap\<art>\<art><floor>_<tile>, twelve
--  256px tiles four across, of which the map shows the top left 1002 by 668.
--
--  [dungeon key] = {
--      art = the folder, floors = how many, names = { a name per floor } (else "Floor n"),
--      entrance = { floor, x, y },
--      pins = { [NPC ID] = { floor, x, y } },   a chest by minus its object ID
--  }
--  x and y run 0 to 1 across and down the map. Placed in game: /nf mappins, drag each pin,
--  then Copy (UI/DungeonMap.lua). /nf mapcheck says which art and floors the client has.
--  A dungeon not listed has no Map; the ones new in Forever have no art in the client yet,
--  nor has Zul'Farrak (not under "ZulFarrak"). Floor counts as /nf mapcheck found them in
--  the client, build 1.60.1.70170.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

ns.Journal.Maps = {
    RagefireChasm = { art = "Ragefire", floors = 1,
        entrance = { 1, 0.61, 0.075 },
        pins = {
            [11517] = { 1, 0.561, 0.378 },   -- Oggleflint
            [11520] = { 1, 0.405, 0.57 },   -- Taragaman the Hungerer
            [11518] = { 1, 0.34, 0.815 },   -- Jergosh the Invoker
            [11519] = { 1, 0.422, 0.842 },   -- Bazzalan
        },
    },
    WailingCaverns = { art = "WailingCaverns", floors = 1,
        entrance = { 1, 0.465, 0.59 },
        pins = {
            [3654] = { 1, 0.345, 0.13 },   -- Mutanus the Devourer
            [3653] = { 1, 0.385, 0.35 },   -- Kresh
            [3671] = { 1, 0.31, 0.43 },   -- Lady Anacondra
            [3670] = { 1, 0.545, 0.46 },   -- Lord Pythas
            [3674] = { 1, 0.615, 0.53 },   -- Skum
            [3669] = { 1, 0.155, 0.57 },   -- Lord Cobrahn
            [5912] = { 1, 0.58, 0.6 },   -- Deviate Faerie Dragon
            [3673] = { 1, 0.6, 0.66 },   -- Lord Serpentis
            [5775] = { 1, 0.615, 0.745 },   -- Verdan the Everliving
        },
    },
    Deadmines = { art = "TheDeadmines", floors = 2,
        entrance = { 1, 0.295, 0.135 },
        pins = {
            [3586] = { 1, 0.535, 0.52 },   -- Miner Johnson
            [644] = { 1, 0.365, 0.61 },   -- Rhahk'Zor
            [642] = { 1, 0.475, 0.865 },   -- Sneed's Shredder
            [643] = { 1, 0.535, 0.865 },   -- Sneed
            [646] = { 2, 0.515, 0.17 },   -- Mr. Smite
            [647] = { 2, 0.575, 0.35 },   -- Captain Greenskin
            [645] = { 2, 0.665, 0.43 },   -- Cookie
            [639] = { 2, 0.605, 0.452 },   -- Edwin VanCleef
            [1763] = { 2, 0.122, 0.755 },   -- Gilnid
        },
    },
    ShadowfangKeep = { art = "ShadowfangKeep", floors = 7,
        entrance = { 1, 0.705, 0.605 },
        pins = {
            [3864] = { 1, 0.45, 0.56 },   -- Fel Steed / Shadow Charger
            [3886] = { 1, 0.275, 0.6 },   -- Razorclaw the Butcher
            [3914] = { 1, 0.67, 0.715 },   -- Rethilgore
            [3887] = { 2, 0.305, 0.755 },   -- Baron Silverlaine
            [4278] = { 3, 0.52, 0.3 },   -- Commander Springvale
            [3872] = { 3, 0.48, 0.6 },   -- Deathsworn Captain
            [4279] = { 4, 0.54, 0.53 },   -- Odo the Blindwatcher
            [4274] = { 6, 0.68, 0.32 },   -- Fenrus the Devourer
            [3927] = { 6, 0.56, 0.62 },   -- Wolf Master Nandos
            [4627] = { 7, 0.52, 0.6 },   -- Arugal's Voidwalker
            [4275] = { 7, 0.595, 0.825 },   -- Archmage Arugal
        },
    },
    BlackfathomDeeps = { art = "BlackFathomDeeps", floors = 3,
        entrance = { 1, 0.455, 0.085 },
        pins = {
            [4831] = { 1, 0.11, 0.385 },   -- Lady Sarevess
            [6243] = { 1, 0.54, 0.575 },   -- Gelihast
            [4887] = { 1, 0.325, 0.605 },   -- Ghamoo-ra
            [12902] = { 2, 0.325, 0.7 },   -- Lorgus Jett
            [12876] = { 2, 0.42, 0.72 },   -- Baron Aquanis
            [4832] = { 2, 0.525, 0.81 },   -- Twilight Lord Kelris
            [4829] = { 2, 0.855, 0.86 },   -- Aku'mai
            [4830] = { 3, 0.585, 0.29 },   -- Old Serra'kis
        },
    },
    Stockade = { art = "TheStockade", floors = 1,
        entrance = { 1, 0.5, 0.815 },
        pins = {
            [1720] = { 1, 0.5, 0.19 },   -- Bruegal Ironknuckle
            [1716] = { 1, 0.215, 0.255 },   -- Bazil Thredd
            [1666] = { 1, 0.32, 0.38 },   -- Kam Deepfury
            [1696] = { 1, 0.44, 0.445 },   -- Targorr the Dread
            [1717] = { 1, 0.78, 0.455 },   -- Hamhock
            [1663] = { 1, 0.735, 0.575 },   -- Dextren Ward
        },
    },
    Gnomeregan = { art = "Gnomeregan", floors = 4,
        entrance = { 1, 0.642, 0.278 },
        pins = {
            [7361] = { 1, 0.776, 0.671 },   -- Grubbis
            [7079] = { 2, 0.76, 0.469 },   -- Viscous Fallout
            [6235] = { 2, 0.245, 0.684 },   -- Electrocutioner 6000
            [6229] = { 3, 0.434, 0.883 },   -- Crowd Pummeler 9-60
            [7800] = { 4, 0.315, 0.299 },   -- Mekgineer Thermaplugg
        },
    },
    RazorfenKraul = { art = "RazorfenKraul", floors = 1,
        entrance = { 1, 0.714, 0.84 },
        pins = {
            [4421] = { 1, 0.221, 0.313 },   -- Charlga Razorflank
            [4420] = { 1, 0.576, 0.313 },   -- Overlord Ramtusk
            [4428] = { 1, 0.876, 0.419 },   -- Death Speaker Jargba
            [4424] = { 1, 0.808, 0.521 },   -- Aggem Thorncurse
            [4422] = { 1, 0.082, 0.686 },   -- Agathelos the Raging
        },
    },
    ScarletMonastery = { art = "ScarletMonastery", floors = 4,
        entrance = { 1, 0.841, 0.831 },
        pins = {
            [4543] = { 1, 0.246, 0.566 },   -- Bloodmage Thalnos
            [3983] = { 1, 0.724, 0.6 },   -- Interrogator Vishas
        },
    },
    RazorfenDowns = { art = "RazorfenDowns", floors = 1, pins = {} },
    Uldaman = { art = "Uldaman", floors = 2, pins = {} },
    Maraudon = { art = "Maraudon", floors = 2, pins = {} },
    SunkenTemple = { art = "TheTempleOfAtalHakkar", floors = 1, pins = {} },
    BlackrockDepths = { art = "BlackrockDepths", floors = 2, pins = {} },
    DireMaul = { art = "DireMaul", floors = 6, pins = {} },
    LowerBlackrockSpire = { art = "BlackrockSpire", floors = 7, pins = {} },
    UpperBlackrockSpire = { art = "BlackrockSpire", floors = 7, pins = {} },
    Scholomance = { art = "Scholomance", floors = 4, pins = {} },
    Stratholme = { art = "Stratholme", floors = 2, pins = {} },
}
