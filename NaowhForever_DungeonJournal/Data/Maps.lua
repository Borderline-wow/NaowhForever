-------------------------------------------------------------------------------
--  Data/Maps.lua -- each dungeon's map, by hand: the game's own map art for it and where its
--  bosses stand on it. Forever's world map has no dungeon floors, but the client still holds
--  the old world map's dungeon art: Interface\WorldMap\<art>\<art><floor>_<tile>, twelve
--  256px tiles four across, of which the map shows the top left 1002 by 668.
--
--  [dungeon key] = {
--      art = the folder, floors = how many, names = { a name per floor } (else "Floor n"),
--      order = { the art's floors in the order you walk them }, where the art's own numbers
--      are not that order, or it has floors of another dungeon (the switch offers only these,
--      stepping and numbering them so; pins keep the art's number),
--      or image = the addon's own picture (Media/Maps), for a dungeon the game has no art
--      for yet: a 1024 square TGA with the map in its top 1024 by 683, a floor after the
--      first its own picture with the floor's number after the name (Dalaran2). Its pins
--      are placed on that picture, so when the game's art comes they are placed again.
--      images = { [floor] = picture }, with art: floors the art lacks, as the addon's pictures.
--      floor = the one floor it is on, where dungeons share the art (Scarlet Monastery's wings),
--      entrance = { floor, x, y },
--      pins = { [NPC ID] = { floor, x, y } },   a chest by minus its object ID
--  }
--  x and y run 0 to 1 across and down the map. Placed in game: /nf mappins, drag each pin,
--  then Copy (UI/DungeonMap.lua). /nf mapcheck says which art and floors the client has.
--  A dungeon not listed has no Map; the ones new in Forever have no art in the client yet
--  (four have the addon's own picture until they do), nor has Zul'Farrak (not under
--  "ZulFarrak"). Floor counts as /nf mapcheck found them in the client, build 1.60.1.70170.
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
    -- Santiago Reyes's recreation, as Ruins of Lordaeron's is.
    HallOfThanes = { image = "Interface\\AddOns\\NaowhForever\\Media\\Maps\\HallOfThanes", floors = 1,
        entrance = { 1, 0.512, 0.95 },
        pins = {
            [261306] = { 1, 0.479, 0.671 },   -- Faldrim Anvilmar
            [261316] = { 1, 0.72, 0.47 },   -- Magmatus
            [261311] = { 1, 0.51, 0.519 },   -- Plunder
            [261319] = { 1, 0.51, 0.17 },   -- Durgen Dirgehammer
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
            [644] = { 1, 0.365, 0.61 },   -- Rhahk'Zor
            [642] = { 1, 0.475, 0.865 },   -- Sneed's Shredder
            [643] = { 1, 0.535, 0.865 },   -- Sneed
            [1763] = { 2, 0.122, 0.755 },   -- Gilnid
            [646] = { 2, 0.515, 0.17 },   -- Mr. Smite
            [647] = { 2, 0.575, 0.35 },   -- Captain Greenskin
            [639] = { 2, 0.605, 0.452 },   -- Edwin VanCleef
            [645] = { 2, 0.665, 0.43 },   -- Cookie
            [3586] = { 1, 0.529, 0.503 },   -- Miner Johnson
        },
    },
    -- Santiago Reyes's recreation (Atlas de Azeroth: Forever, 2026), credited on the map,
    -- until the game has art of its own for Forever's Ruins of Lordaeron.
    RuinsOfLordaeron = { image = "Interface\\AddOns\\NaowhForever\\Media\\Maps\\RuinsOfLordaeron", floors = 1,
        entrance = { 1, 0.616, 0.217 },
        pins = {
            [250483] = { 1, 0.707, 0.397 },   -- Witherfang
            [250660] = { 1, 0.594, 0.694 },   -- The Baron
            [256035] = { 1, 0.382, 0.675 },   -- Viktor the Vile
            [250631] = { 1, 0.406, 0.532 },   -- The Abandoned
            [256097] = { 1, 0.409, 0.309 },   -- Bjork
            [250657] = { 1, 0.468, 0.616 },   -- Rath'mael
            [255699] = { 1, 0.349, 0.378 },   -- Lordaeron Captain
        },
    },
    -- The art's seventh floor is the third you reach.
    ShadowfangKeep = { art = "ShadowfangKeep", floors = 7, order = { 1, 2, 7, 3, 4, 5, 6 },
        entrance = { 1, 0.705, 0.605 },
        pins = {
            [3914] = { 1, 0.67, 0.715 },   -- Rethilgore
            [3886] = { 2, 0.47, 0.288 },   -- Razorclaw the Butcher
            [3887] = { 2, 0.304, 0.767 },   -- Baron Silverlaine
            [4278] = { 1, 0.277, 0.6 },   -- Commander Springvale
            [4279] = { 7, 0.595, 0.825 },   -- Odo the Blindwatcher
            [4274] = { 4, 0.543, 0.536 },   -- Fenrus the Devourer
            [3927] = { 6, 0.56, 0.62 },   -- Wolf Master Nandos
            [4275] = { 6, 0.626, 0.192 },   -- Archmage Arugal
            [3872] = { 7, 0.428, 0.825 },   -- Deathsworn Captain
            [3864] = { 1, 0.336, 0.579 },   -- Fel Steed
            [4627] = { 7, 0.52, 0.6 },   -- Arugal's Voidwalker
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
    -- Santiago Reyes's recreation, as Ruins of Lordaeron's is: the Underbelly, where you come in,
    -- and the city above.
    Dalaran = { image = "Interface\\AddOns\\NaowhForever\\Media\\Maps\\Dalaran", floors = 2,
        names = { [1] = "The Underbelly", [2] = "City of Dalaran" },
        entrance = { 1, 0.188, 0.846 },
        pins = {
            [247126] = { 1, 0.544, 0.515 },   -- Atrexis the Grave Knight
            [245999] = { 2, 0.525, 0.844 },   -- Arcane Anomaly
            [246003] = { 2, 0.522, 0.558 },   -- Fel Ancient
            [246017] = { 2, 0.613, 0.412 },   -- Unstable Sentinel
            [246020] = { 2, 0.566, 0.235 },   -- Shade of the Archmage
            [246016] = { 2, 0.68, 0.51 },   -- Arcanic Enigma
        },
    },
    -- Santiago Reyes's recreation, as Ruins of Lordaeron's is.
    ExcavationSite = { image = "Interface\\AddOns\\NaowhForever\\Media\\Maps\\ExcavationSite",
        floors = 1,
        entrance = { 1, 0.888, 0.258 },
        pins = {
            [260322] = { 1, 0.486, 0.464 },   -- Saltspine
            [260325] = { 1, 0.343, 0.464 },   -- Shadetooth
            [260808] = { 1, 0.080, 0.460 },   -- Highland Horror
            [260326] = { 1, 0.340, 0.665 },   -- Relic Guardian
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
    -- Scarlet Monastery's wings share its art, a floor each, in the order the art has them.
    ScarletMonasteryGraveyard = { art = "ScarletMonastery", floors = 4, floor = 1,
        entrance = { 1, 0.841, 0.831 },
        pins = {
            [4543] = { 1, 0.246, 0.566 },   -- Bloodmage Thalnos
            [3983] = { 1, 0.724, 0.6 },   -- Interrogator Vishas
        },
    },
    ScarletMonasteryLibrary = { art = "ScarletMonastery", floors = 4, floor = 2,
        pins = {
            [3974] = { 2, 0.308, 0.878 },   -- Houndmaster Loksey
            [6487] = { 2, 0.832, 0.745 },   -- Arcanist Doan
        },
    },
    ScarletMonasteryArmory = { art = "ScarletMonastery", floors = 4, floor = 3,
        pins = {
            [3975] = { 3, 0.786, 0.108 },   -- Herod
        },
    },
    ScarletMonasteryCathedral = { art = "ScarletMonastery", floors = 4, floor = 4,
        pins = {
            [4542] = { 4, 0.554, 0.261 },   -- High Inquisitor Fairbanks
            [3976] = { 4, 0.491, 0.272 },   -- Scarlet Commander Mograine
            [3977] = { 4, 0.49, 0.169 },   -- High Inquisitor Whitemane
        },
    },
    RazorfenDowns = { art = "RazorfenDowns", floors = 1,
        pins = {
            [7355] = { 1, 0.594, 0.339 },   -- Tuten'kash
            [7357] = { 1, 0.858, 0.466 },   -- Mordresh Fire Eye
            [8567] = { 1, 0.352, 0.682 },   -- Glutton
            [7358] = { 1, 0.443, 0.602 },   -- Amnennar the Coldbringer
            [7354] = { 1, 0.366, 0.523 },   -- Ragglesnout
            [7356] = { 1, 0.522, 0.716 },   -- Plaguemaw the Rotting
            [14686] = { 1, 0.785, 0.226 },   -- Lady Falther'ess
        },
    },
    Uldaman = { art = "Uldaman", floors = 2,
        entrance = { 1, 0.683, 0.726 },
        pins = {
            [6910] = { 1, 0.533, 0.726 },   -- Revelosh
            [7228] = { 1, 0.37, 0.739 },   -- Ironaya
            [7023] = { 1, 0.289, 0.607 },   -- Obsidian Sentinel
            [7206] = { 1, 0.475, 0.451 },   -- Ancient Stone Keeper
            [7291] = { 1, 0.269, 0.331 },   -- Galgann Firehammer
            [4854] = { 1, 0.219, 0.262 },   -- Grimlok
            [2748] = { 1, 0.417, 0.166 },   -- Archaedas
            [6906] = { 1, 0.592, 0.917 },   -- Baelog
            [6907] = { 1, 0.599, 0.953 },   -- Eric "The Swift"
            [6908] = { 1, 0.629, 0.93 },   -- Olaf
        },
    },
    Maraudon = { art = "Maraudon", floors = 2,
        entrance = { 1, 0.768, 0.66 },
        pins = {
            [13282] = { 1, 0.356, 0.093 },   -- Noxxion
            [12258] = { 1, 0.161, 0.339 },   -- Razorlash
            [12236] = { 1, 0.376, 0.722 },   -- Lord Vyletongue
            [12225] = { 2, 0.247, 0.138 },   -- Celebras the Cursed
            [12203] = { 2, 0.413, 0.496 },   -- Landslide
            [13601] = { 2, 0.509, 0.675 },   -- Tinkerer Gizlock
            [13596] = { 2, 0.412, 0.814 },   -- Rotgrip
            [12201] = { 2, 0.261, 0.784 },   -- Princess Theradras
            [12237] = { 1, 0.236, 0.69 },   -- Meshlok the Harvester
        },
    },
    SunkenTemple = { art = "TheTempleOfAtalHakkar", floors = 1,
        pins = {
            [5721] = { 1, 0.472, 0.419 },   -- Dreamscythe
            [5720] = { 1, 0.526, 0.419 },   -- Weaver
            [5710] = { 1, 0.743, 0.41 },   -- Jammal'an the Prophet
            [5711] = { 1, 0.787, 0.408 },   -- Ogom the Wretched
            [5719] = { 1, 0.473, 0.87 },   -- Morphaz
            [5722] = { 1, 0.522, 0.87 },   -- Hazzas
            [5709] = { 1, 0.669, 0.88 },   -- Shade of Eranikus
            [8443] = { 1, 0.239, 0.457 },   -- Avatar of Hakkar
        },
    },
    BlackrockDepths = { art = "BlackrockDepths", floors = 2,
        entrance = { 1, 0.332, 0.794 },
        pins = {
            [9018] = { 1, 0.479, 0.93 },   -- High Interrogator Gerstahn
            [9025] = { 1, 0.57, 0.667 },   -- Lord Roccor
            [9319] = { 1, 0.543, 0.575 },   -- Houndmaster Grebmar
            [9017] = { 1, 0.568, 0.309 },   -- Lord Incendius
            [9056] = { 1, 0.637, 0.207 },   -- Fineous Darkvire
            [9016] = { 1, 0.254, 0.53 },   -- Bael'Gar
            [9033] = { 2, 0.366, 0.827 },   -- General Angerforge
            [8983] = { 2, 0.365, 0.649 },   -- Golem Lord Argelmach
            [9502] = { 2, 0.499, 0.639 },   -- Phalanx
            [9156] = { 2, 0.54, 0.483 },   -- Ambassador Flamelash
            [9938] = { 2, 0.801, 0.115 },   -- Magmus
            [9019] = { 2, 0.932, 0.143 },   -- Emperor Dagran Thaurissan
            [8923] = { 2, 0.489, 0.351 },   -- Panzor the Invincible
            [8929] = { 2, 0.932, 0.081 },   -- Princess Moira Bronzebeard
            [9041] = { 2, 0.557, 0.663 },   -- Warder Stilgiss
            [9042] = { 2, 0.649, 0.663 },   -- Verek
            [-161495] = { 2, 0.603, 0.663 },   -- Secret Safe
            [-169243] = { 2, 0.544, 0.248 },   -- Chest of The Seven
        },
    },
    DireMaul = { art = "DireMaul", floors = 6,
        entrance = { 1, 0.719, 0.925 },
        pins = {
            [14354] = { 5, 0.437, 0.472 },   -- Pusillin
            [11490] = { 6, 0.523, 0.707 },   -- Zevrim Thornhoof
            [13280] = { 6, 0.582, 0.744 },   -- Hydrospawn
            [14327] = { 6, 0.554, 0.603 },   -- Lethtendris
            [11492] = { 6, 0.565, 0.286 },   -- Alzzin the Wildshaper
            [11489] = { 2, 0.335, 0.534 },   -- Tendris Warpwood
            [11488] = { 2, 0.211, 0.788 },   -- Illyanna Ravenoak
            [11487] = { 3, 0.335, 0.448 },   -- Magister Kalendris
            [11496] = { 4, 0.349, 0.579 },   -- Immol'thar
            [11486] = { 4, 0.618, 0.228 },   -- Prince Tortheldrin
            [11467] = { 3, 0.329, 0.13 },   -- Tsu'zee
            [14506] = { 4, 0.306, 0.652 },   -- Lord Hel'nurath
            [14326] = { 1, 0.694, 0.763 },   -- Guard Mol'dar
            [14322] = { 1, 0.612, 0.684 },   -- Stomper Kreeg
            [14321] = { 1, 0.498, 0.786 },   -- Guard Fengus
            [14323] = { 1, 0.269, 0.568 },   -- Guard Slip'kik
            [14325] = { 1, 0.317, 0.502 },   -- Captain Kromcrush
            [11501] = { 1, 0.32, 0.265 },   -- King Gordok
            [14324] = { 1, 0.366, 0.265 },   -- Cho'Rush the Observer
        },
    },
    -- The art's seventh floor is Upper Blackrock Spire's.
    LowerBlackrockSpire = { art = "BlackrockSpire", floors = 7, order = { 1, 2, 3, 4, 5, 6 },
        pins = {
            [9196] = { 3, 0.366, 0.566 },   -- Highlord Omokk
            [9236] = { 2, 0.557, 0.682 },   -- Shadow Hunter Vosh'gajin
            [9237] = { 1, 0.525, 0.545 },   -- War Master Voone
            [10596] = { 4, 0.447, 0.553 },   -- Mother Smolderweb
            [9736] = { 5, 0.544, 0.853 },   -- Quartermaster Zigris
            [10268] = { 5, 0.36, 0.842 },   -- Gizrul the Slavener
            [10220] = { 5, 0.401, 0.844 },   -- Halycon
            [9568] = { 6, 0.566, 0.563 },   -- Overlord Wyrmthalak
            [9219] = { 3, 0.32, 0.656 },   -- Spirestone Butcher
            [9218] = { 3, 0.409, 0.656 },   -- Spirestone Battle Lord
            [9217] = { 3, 0.365, 0.656 },   -- Spirestone Lord Magus
            [9596] = { 1, 0.472, 0.643 },   -- Bannok Grimaxe
            [10376] = { 2, 0.62, 0.767 },   -- Crystal Fang
            [9718] = { 5, 0.354, 0.735 },   -- Ghok Bashguud
            [10263] = { 3, 0.631, 0.63 },   -- Burning Felguard
        },
    },
    -- Lower's are the art's first six floors; the art has only the seventh of Upper's levels.
    -- The other two are screenshots of Blizzard's later map (Wowhead screenshots 852258 and
    -- 852257), until the client has them. You walk them backwards: in at Dragonspire Hall (9),
    -- Emberseer and Solakar on 8, Rend and Drakkisath on the art's 7.
    UpperBlackrockSpire = { art = "BlackrockSpire", floors = 9, order = { 9, 8, 7 },
        names = { [8] = "Hall of Binding and the Rookery", [9] = "Dragonspire Hall" },
        images = {
            [8] = "Interface\\AddOns\\NaowhForever\\Media\\Maps\\UpperBlackrockSpire8",
            [9] = "Interface\\AddOns\\NaowhForever\\Media\\Maps\\UpperBlackrockSpire9",
        },
        entrance = { 9, 0.374, 0.326 },
        pins = {
            [9816] = { 8, 0.308, 0.271 },   -- Pyroguard Emberseer
            [10264] = { 8, 0.383, 0.378 },   -- Solakar Flamewreath
            [10339] = { 7, 0.485, 0.16 },   -- Gyth
            [10429] = { 7, 0.491, 0.247 },   -- Warchief Rend Blackhand
            [10430] = { 7, 0.645, 0.312 },   -- The Beast
            [10363] = { 7, 0.338, 0.468 },   -- General Drakkisath
            [10509] = { 7, 0.574, 0.466 },   -- Jed Runewatcher
        },
    },
    Scholomance = { art = "Scholomance", floors = 4,
        entrance = { 1, 0.18, 0.709 },
        pins = {
            [10506] = { 1, 0.651, 0.602 },   -- Kirtonos the Herald
            [10503] = { 2, 0.604, 0.177 },   -- Jandice Barov
            [11622] = { 2, 0.483, 0.262 },   -- Rattlegore
            [10505] = { 3, 0.191, 0.316 },   -- Instructor Malicia
            [11261] = { 3, 0.503, 0.748 },   -- Doctor Theolen Krastinov
            [10901] = { 3, 0.81, 0.32 },   -- Lorekeeper Polkelt
            [10507] = { 4, 0.237, 0.322 },   -- The Ravenian
            [10504] = { 4, 0.506, 0.823 },   -- Lord Alexei Barov
            [10502] = { 4, 0.822, 0.322 },   -- Lady Illucia Barov
            [1853] = { 4, 0.502, 0.331 },   -- Darkmaster Gandling
        },
    },
    Stratholme = { art = "Stratholme", floors = 2,
        pins = {
            [10808] = { 1, 0.491, 0.186 },   -- Timmy the Cruel
            [10516] = { 1, 0.738, 0.196 },   -- The Unforgiven
            [10558] = { 1, 0.6, 0.324 },   -- Hearthsinger Forresten
            [10997] = { 1, 0.033, 0.5 },   -- Cannon Master Willey
            [10811] = { 1, 0.276, 0.748 },   -- Archivist Galford
            [10813] = { 1, 0.205, 0.821 },   -- Balnazzar
            [10812] = { 1, 0.159, 0.821 },   -- Grand Crusader Dathrohan
            [10435] = { 2, 0.572, 0.155 },   -- Magistrate Barthilas
            [10436] = { 2, 0.751, 0.463 },   -- Baroness Anastari
            [10437] = { 2, 0.569, 0.463 },   -- Nerub'enkan
            [10438] = { 2, 0.677, 0.215 },   -- Maleki the Pallid
            [10439] = { 2, 0.46, 0.192 },   -- Ramstein the Gorger
            [10440] = { 2, 0.386, 0.2 },   -- Baron Rivendare
        },
    },
}
