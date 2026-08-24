-------------------------------------------------------------------------------
--  NaowhUI_TankReminder_Abilities.lua -- tank busters the game does not flag.
--
--  GENERATED. Regenerate rather than hand-editing.
--
--  This addon reads everything else out of the player's own client on purpose, and this
--  file is the one deliberate exception. The reason is measured, not assumed.
--
--  The engine-played callout is registered against every catalogue ability carrying
--  Blizzard's TankRole bit. Checked against a live 870-event catalogue: of the 31 boss
--  tank busters in this season's pool, 23 exist in that catalogue and only 13 carry the
--  bit. So the bit alone is correctly silent on nearly half of them, and correct silence
--  is indistinguishable from a broken feature from where the player is sitting.
--
--  So this list is ADDITIVE and never a replacement. An ability is called if Blizzard
--  says so OR this list does, which means the feature keeps working unchanged on content
--  this file has never heard of.
--
--  Keyed by SPELL ID, not by encounterEventID. Event ids are a client-side index that can
--  be reallocated between builds; a spell id is stable, and the catalogue is plain so the
--  join happens at runtime on the player's own client.
--
--  The value is the DAMAGE TYPE rather than a flag, because which defensive helps depends
--  on whether the hit is physical or magical, and a later version can use it to choose.
--
--  Ability classification is derived from Tactyks' public Season 2 dungeon spreadsheet.
--  Spell ids and names are Blizzard's own.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

ns.TANK_ABILITIES = {
    [265910] = "Physical",   -- The Golden Serpent: Tail Thrash
    [266237] = "Physical",   -- The Council of Tribes: Debilitating Backhand
    [268586] = "Physical",   -- Dazar, The First King: Blade Combo
    [372808] = "Physical",   -- Melidrussa Chillworn: Frigid Shard
    [372858] = "Mixed",   -- Kokia Blazehoof: Searing Blows
    [381512] = "Mixed",   -- Kyrakka and Erkhart Stormvein: Stormslam
    [473898] = "Physical",   -- Xathuux the Annihilator: Legion Strike
    [1222642] = "Magical",   -- Atroxus: Hulking Claw
    [1222795] = "Mixed",   -- Zaen Bladesorrow: Envenom
    [1230298] = "Magical",   -- Kystia Manaheart: Chaos Barrage
    [1234753] = "Mixed",   -- Lightblossom Trinity: Bedrock Slam
    [1239821] = "Magical",   -- Lightwarden Ruia: Warden's Wrath
    [1247685] = "Mixed",   -- Ziekket: Thornspike
    [1288428] = "Mixed",   -- Adderis and Aspix: Overload
    [1290797] = "Mixed",   -- Merektha: Lightning Bite
    [1296220] = "Magical",   -- Rav'i: Triple Shot
    [1297017] = "Magical",   -- Taz'Rah: Void Blast
    [1297797] = "Physical",   -- Nalorakk: Forceful Slam
    [1298949] = "Physical",   -- The Writhing Coil: Tail Scythe
    [1301350] = "Physical",   -- Zul'jan: Chop Down
    [1303039] = "Physical",   -- Dazar, The First King: Hunting Leap
    [1303446] = "Mixed",   -- Avatar of Sethraliss: Tainted Strike
    [1303490] = "Physical",   -- Dazar, The First King: Savage Maul
    [1311923] = "Magical",   -- Charonus: Dark Waves

    -- Marked as tank hits in publicly available community boss research; damage
    -- type not recorded there, so it is Unknown until observed.
    [466064] = "Unknown",   -- Emberdawn: Searing Beak
    [1241692] = "Unknown",   -- Vorasius: Shadowclaw Slam
    [467620] = "Unknown",   -- Commander Kro'luk: Rampage
    [472888] = "Unknown",   -- Derelict Duo: Bone Hack
    [1247937] = "Unknown",   -- Nysarra: Void Gash
    [1251023] = "Unknown",   -- Rak'tul: Spiritbreaker
    [1251554] = "Unknown",   -- Vor'daza: Drain Soul
    [1253950] = "Unknown",   -- Emberdawn: Searing Rend
    [1268562] = "Unknown",   -- Nymrissa Wavecaller: Water Jet (Mythic only)
    [466091] = "Unknown",   -- Emberdawn: Searing Beak
    [1267049] = "Unknown",   -- Midnight Falls: Heaven's Lance
    [268007] = "Unknown",   -- Avatar of Sethraliss: Heart Attack
    [1221781] = "Unknown",   -- Rotmire: Putrid Fist
    [1233787] = "Unknown",   -- Crown of the Cosmos: Dark Hand
    [1245645] = "Unknown",   -- Vaelgor & Ezzorak: Rakfang
    [1246461] = "Unknown",   -- Crown of the Cosmos: Rift Slash
    [1246736] = "Unknown",   -- Lightblinded Vanguard: Judgement
    [1251857] = "Unknown",   -- Lightblinded Vanguard: Judgement
    [1262623] = "Unknown",   -- Vaelgor & Ezzorak: Nullbeam
    [1265131] = "Unknown",   -- Vaelgor & Ezzorak: Vaelwing
    [1280458] = "Unknown",   -- Vaelgor & Ezzorak: Grappling Maw
    [1280935] = "Unknown",   -- Vashnik the Malignant: Dripping Fangs
    [1284458] = "Unknown",   -- Entombed Sentinels: Empowering Slam
    [1284487] = "Unknown",   -- Entombed Sentinels: Bloodvenom Injection
    [1288538] = "Unknown",   -- The Twin Fangs: Stone Breaker
    [1295854] = "Unknown",   -- The Lost Explorers: Shredding Shards
    [1250803] = "Unknown",   -- Fallen-King Salhadaar: Shattering Twilight
    [1260763] = "Unknown",   -- Belo'ren, Child of Al'ar: Guardian's Edict
    [1277025] = "Unknown",   -- Sszorak: Apex Predator
    [1286573] = "Unknown",   -- The Coiled Altar: Soul Sever
    [1299680] = "Unknown",   -- The Coiled Altar: Sever
    [1307279] = "Unknown",   -- The Coiled Altar: Blighted Sever

    -- Tank hits the community modules gate on a tank role check in code rather than
    -- flagging on the ability, which is why the sheet-derived rows above never carried
    -- them. Found by auditing every Midnight party module for that gate (2026-08-20)
    -- after Den of Nalorakk called nothing at all for a whole dungeon.
    [472662] = "Unknown",   -- The Restless Heart: Tempest Slash
    [474496] = "Unknown",   -- Arcanotron Custos: Repulsing Slam
    [1243569] = "Unknown",   -- Nalorakk: Overwhelming Onslaught
    [1266480] = "Unknown",   -- Murojin and Nekraxx: Flanking Spear
    [1280113] = "Unknown",   -- Degentrius: Hulking Fragment
    -- Classified but NOT fingerprintable from the modules: Ula'tek drives this off
    -- Blizzard event ids rather than bar durations, so there is no duration to key on.
    -- Needs /nutank learn then /nutank tank on a real pull.
    [1298367] = "Unknown",   -- Ula'tek: Mother's Wrath
}

ns.TANK_ABILITIES_COUNT = 61

-------------------------------------------------------------------------------
--  Every boss ability that damages SOMEBODY -- the tank, the party, or both --
--  derived from the same public damage-classification sheet as the tank list.
--
--  This is the Bosses tab's reference filter: the journal's section tree lists
--  the same spell under several headers and includes plenty of entries that
--  never hurt anyone, and this set is what separates "reference material" from
--  "noise". It gates DISPLAY only; the runtime never reads it.
-------------------------------------------------------------------------------
ns.DAMAGE_ABILITIES = {
    [264172] = "party",   -- Merektha: Burrow
    [265773] = "party",   -- The Golden Serpent: Spit Gold
    [265781] = "party",   -- The Golden Serpent: Serpentine Gust
    [265910] = "tank",   -- The Golden Serpent: Tail Thrash
    [266237] = "tank",   -- The Council of Tribes: Debilitating Backhand
    [266512] = "party",   -- Galvazzt: Consume Charge
    [266951] = "party",   -- The Council of Tribes: Barrel Through
    [267273] = "party",   -- The Council of Tribes: Poison Nova
    [267763] = "party",   -- Mchimba the Embalmer: Wretched Discharge
    [268586] = "tank",   -- Dazar, The First King: Blade Combo
    [268932] = "party",   -- Dazar, The First King: Quaking Leap
    [269369] = "party",   -- Dazar, The First King: Deathly Roar
    [274006] = "party",   -- Galvazzt: Lightning Spire
    [372808] = "tank",   -- Melidrussa Chillworn: Frigid Shard
    [372851] = "party",   -- Melidrussa Chillworn: Chillstorm
    [372858] = "tank",   -- Kokia Blazehoof: Searing Blows
    [373017] = "party",   -- Kokia Blazehoof: Blaze Volley
    [373680] = "party",   -- Melidrussa Chillworn: Frost Overload
    [381512] = "tank",   -- Kyrakka and Erkhart Stormvein: Stormslam
    [381516] = "party",   -- Kyrakka and Erkhart Stormvein: Interrupting Cloudburst
    [381517] = "party",   -- Kyrakka and Erkhart Stormvein: Winds of Change
    [381602] = "party",   -- Kyrakka and Erkhart Stormvein: Inferno Spit
    [384823] = "party",   -- Kokia Blazehoof: Inferno
    [396044] = "party",   -- Melidrussa Chillworn: Hailburst
    [473898] = "tank",   -- Xathuux the Annihilator: Legion Strike
    [474197] = "both",   -- Xathuux the Annihilator: Demonic Rage
    [474408] = "tank",   -- Lithiel Cinderfury: Summon Vilefiend
    [474457] = "party",   -- Lithiel Cinderfury: Fingers of Gul'dan
    [474478] = "party",   -- Zaen Bladesorrow: Killing Spree
    [1201553] = "party",   -- Zaen Bladesorrow: Fel-Infused Freight
    [1214357] = "party",   -- Zaen Bladesorrow: Fire Bomb
    [1214663] = "party",   -- Xathuux the Annihilator: Axe Toss
    [1216945] = "party",   -- Lithiel Cinderfury: Searing Fel Flame
    [1222098] = "party",   -- Taz'Rah: Nether Dash
    [1222642] = "tank",   -- Atroxus: Hulking Claw
    [1222795] = "tank",   -- Zaen Bladesorrow: Envenom
    [1223298] = "party",   -- Charonus: Gravitic Orbs
    [1226031] = "party",   -- Atroxus: Poison Splash
    [1227197] = "party",   -- Charonus: Cosmic Crash
    [1230298] = "both",   -- Kystia Manaheart: Chaos Barrage
    [1234233] = "party",   -- The Hoardmonger: Spoiled Supplies
    [1234681] = "party",   -- The Hoardmonger: Ravenous Bellow
    [1234753] = "both",   -- Lightblossom Trinity: Bedrock Slam
    [1235548] = "party",   -- Sentinel of Winter: Glacial Torment
    [1235564] = "party",   -- Lightblossom Trinity: Lightblossom Beam
    [1235656] = "party",   -- Sentinel of Winter: Frozen Tempest
    [1235751] = "party",   -- Lightblossom Trinity: Lightbloom Overgrowth
    [1235829] = "party",   -- Sentinel of Winter: Winter's Shroud
    [1236709] = "party",   -- Ikuzz the Light Hunter: Thorncaller Roar
    [1236746] = "party",   -- Ikuzz the Light Hunter: Verdant Stomp
    [1237073] = "party",   -- Ikuzz the Light Hunter: Lightcrazed Frenzy
    [1237090] = "party",   -- Ikuzz the Light Hunter: Bloodthirsty Gaze
    [1239821] = "tank",   -- Lightwarden Ruia: Warden's Wrath
    [1239824] = "party",   -- Lightwarden Ruia: Lightfire
    [1240210] = "party",   -- Lightwarden Ruia: Pulverizing Strikes
    [1241058] = "party",   -- Lightwarden Ruia: Grievous Thrash
    [1242860] = "party",   -- Nalorakk: Echoing Maul
    [1243002] = "party",   -- Nalorakk: Fury of the War God
    [1246858] = "party",   -- Ziekket: Lightbloom's Essence
    [1247377] = "party",   -- Ziekket: Oozing Xylem
    [1247685] = "tank",   -- Ziekket: Thornspike
    [1262253] = "party",   -- Nalorakk: Demoralizing Scream
    [1262497] = "party",   -- Atroxus: Monstrous Roar
    [1263590] = "party",   -- Sentinel of Winter: Rimeshatter
    [1264095] = "party",   -- Kystia Manaheart: Mirror Images
    [1264191] = "party",   -- Charonus: Unstable Singularity
    [1265412] = "party",   -- Kystia Manaheart: Light Infusion
    [1272265] = "tank",   -- Lightwarden Ruia: Mangling Claws
    [1282892] = "tank",   -- Atroxus: Sickening Bite
    [1287811] = "party",   -- The Writhing Coil: Uncoil
    [1288235] = "party",   -- Adderis and Aspix: Thunder and Lightning
    [1288428] = "tank",   -- Adderis and Aspix: Overload
    [1288864] = "party",   -- Adderis and Aspix: Tempest Winds
    [1289062] = "party",   -- Adderis and Aspix: Gale Force
    [1289602] = "party",   -- Merektha: Thunder Spit
    [1290031] = "party",   -- Merektha: A Knot of Snakes
    [1290531] = "party",   -- Galvazzt: Induction
    [1290797] = "tank",   -- Merektha: Lightning Bite
    [1293048] = "party",   -- Merektha: Serpentstorm
    [1295455] = "party",   -- Xathuux the Annihilator: Infernal Crush
    [1296220] = "both",   -- Rav'i: Triple Shot
    [1297017] = "tank",   -- Taz'Rah: Void Blast
    [1297792] = "party",   -- Nalorakk: Overwhelming Onslaught
    [1297797] = "tank",   -- Nalorakk: Forceful Slam
    [1298221] = "party",   -- Rav'i: Ssscavenging
    [1298949] = "tank",   -- The Writhing Coil: Tail Scythe
    [1299053] = "party",   -- The Writhing Coil: Death Rattle
    [1299154] = "party",   -- The Writhing Coil: Synchronized Venom
    [1300259] = "party",   -- Taz'Rah: Dark Bloom
    [1300871] = "party",   -- Avatar of Sethraliss: Corrupted Lifeforce
    [1300876] = "party",   -- Zul'jan: Ritual of the Fang
    [1301350] = "tank",   -- Zul'jan: Chop Down
    [1301413] = "party",   -- Zul'jan: Boneslicer
    [1303039] = "tank",   -- Dazar, The First King: Hunting Leap
    [1303267] = "both",   -- Dazar, The First King: Gilded Destruction
    [1303446] = "tank",   -- Avatar of Sethraliss: Tainted Strike
    [1303490] = "tank",   -- Dazar, The First King: Savage Maul
    [1305810] = "both",   -- The Council of Tribes: Arc Lightning
    [1306345] = "party",   -- Rav'i: Messy Eater
    [1307894] = "party",   -- Rav'i: Ravenous Stomp
    [1311923] = "tank",   -- Charonus: Dark Waves
    [1312146] = "party",   -- Mchimba the Embalmer: Awakening Slam
}

ns.DAMAGE_ABILITIES_COUNT = 102

-- The same damaging abilities, by NAME. The join key problem this solves: the sheet and
-- the curated list carry the CAST spell id, but the journal's section rows often carry a
-- different record entirely (the display aura of the same ability), so an id-only match
-- silently dropped real tank busters from the reference list -- Triple Shot on the very
-- boss the fingerprints were validated on. Names are how a human matched them, so names
-- are the fallback key. Lowercased; enUS as authored, which is the data's limit.
ns.DAMAGE_NAMES = {
    ["a knot of snakes"] = true,
    ["arc lightning"] = true,
    ["awakening slam"] = true,
    ["axe toss"] = true,
    ["barrel through"] = true,
    ["bedrock slam"] = true,
    ["blade combo"] = true,
    ["blaze volley"] = true,
    ["bloodthirsty gaze"] = true,
    ["bone hack"] = true,
    ["boneslicer"] = true,
    ["burrow"] = true,
    ["chaos barrage"] = true,
    ["chillstorm"] = true,
    ["chop down"] = true,
    ["consume charge"] = true,
    ["corrupted lifeforce"] = true,
    ["cosmic crash"] = true,
    ["dark bloom"] = true,
    ["dark waves"] = true,
    ["death rattle"] = true,
    ["deathly roar"] = true,
    ["debilitating backhand"] = true,
    ["demonic rage"] = true,
    ["demoralizing scream"] = true,
    ["drain soul"] = true,
    ["echoing maul"] = true,
    ["envenom"] = true,
    ["fel-infused freight"] = true,
    ["fingers of gul'dan"] = true,
    ["fire bomb"] = true,
    ["forceful slam"] = true,
    ["frigid shard"] = true,
    ["frost overload"] = true,
    ["frozen tempest"] = true,
    ["fury of the war god"] = true,
    ["gale force"] = true,
    ["gilded destruction"] = true,
    ["glacial torment"] = true,
    ["gravitic orbs"] = true,
    ["grievous thrash"] = true,
    ["hailburst"] = true,
    ["hulking claw"] = true,
    ["hunting leap"] = true,
    -- NOT here: "hydrastrike". The sheet classifies it as tank damage and it is, but it
    -- is a PASSIVE -- the reference lists are casts only, and the journal's record for it
    -- is not flagged passive, so the exclusion has to live in the data. Confirmed by the
    -- reporter on the boss itself. Add future damaging-but-passive rows here the same way.
    ["induction"] = true,
    ["infernal crush"] = true,
    ["inferno"] = true,
    ["inferno spit"] = true,
    ["interrupting cloudburst"] = true,
    ["killing spree"] = true,
    ["legion strike"] = true,
    ["light infusion"] = true,
    ["lightbloom overgrowth"] = true,
    ["lightbloom's essence"] = true,
    ["lightblossom beam"] = true,
    ["lightcrazed frenzy"] = true,
    ["lightfire"] = true,
    ["lightning bite"] = true,
    ["lightning spire"] = true,
    ["mangling claws"] = true,
    ["messy eater"] = true,
    ["mirror images"] = true,
    ["monstrous roar"] = true,
    ["nether dash"] = true,
    ["oozing xylem"] = true,
    ["overload"] = true,
    ["overwhelming onslaught"] = true,
    ["poison nova"] = true,
    ["poison splash"] = true,
    ["pulverizing strikes"] = true,
    ["quaking leap"] = true,
    ["rampage"] = true,
    ["ravenous bellow"] = true,
    ["ravenous stomp"] = true,
    ["rimeshatter"] = true,
    ["ritual of the fang"] = true,
    ["savage maul"] = true,
    ["searing beak"] = true,
    ["searing blows"] = true,
    ["searing fel flame"] = true,
    ["searing rend"] = true,
    ["serpentine gust"] = true,
    ["serpentstorm"] = true,
    ["sickening bite"] = true,
    ["spiritbreaker"] = true,
    ["spit gold"] = true,
    ["spoiled supplies"] = true,
    ["ssscavenging"] = true,
    ["stormslam"] = true,
    ["summon vilefiend"] = true,
    ["synchronized venom"] = true,
    ["tail scythe"] = true,
    ["tail thrash"] = true,
    ["tainted strike"] = true,
    ["tempest winds"] = true,
    ["thorncaller roar"] = true,
    ["thornspike"] = true,
    ["thunder and lightning"] = true,
    ["thunder spit"] = true,
    ["triple shot"] = true,
    ["uncoil"] = true,
    ["unstable singularity"] = true,
    ["verdant stomp"] = true,
    ["void blast"] = true,
    ["void gash"] = true,
    ["warden's wrath"] = true,
    ["winds of change"] = true,
    ["winter's shroud"] = true,
    ["wretched discharge"] = true,
    ["water jet"] = true,
    ["cosmic spike"] = true,
    ["heaven's lance"] = true,
}

