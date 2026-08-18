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
    [474197] = "Physical",   -- Xathuux the Annihilator: Demonic Rage
    [474408] = "Magical",   -- Lithiel Cinderfury: Summon Vilefiend
    [1222642] = "Magical",   -- Atroxus: Hulking Claw
    [1222795] = "Mixed",   -- Zaen Bladesorrow: Envenom
    [1230298] = "Magical",   -- Kystia Manaheart: Chaos Barrage
    [1234753] = "Mixed",   -- Lightblossom Trinity: Bedrock Slam
    [1239821] = "Magical",   -- Lightwarden Ruia: Warden's Wrath
    [1247685] = "Mixed",   -- Ziekket: Thornspike
    [1272265] = "Physical",   -- Lightwarden Ruia: Mangling Claws
    [1282892] = "Magical",   -- Atroxus: Sickening Bite
    [1288428] = "Mixed",   -- Adderis and Aspix: Overload
    [1290797] = "Mixed",   -- Merektha: Lightning Bite
    [1296220] = "Magical",   -- Rav'i: Triple Shot
    [1297017] = "Magical",   -- Taz'Rah: Void Blast
    [1297797] = "Physical",   -- Nalorakk: Forceful Slam
    [1298949] = "Physical",   -- The Writhing Coil: Tail Scythe
    [1301350] = "Physical",   -- Zul'jan: Chop Down
    [1303039] = "Physical",   -- Dazar, The First King: Hunting Leap
    [1303267] = "Magical",   -- Dazar, The First King: Gilded Destruction
    [1303446] = "Mixed",   -- Avatar of Sethraliss: Tainted Strike
    [1303490] = "Physical",   -- Dazar, The First King: Savage Maul
    [1305810] = "Magical",   -- The Council of Tribes: Arc Lightning
    [1311923] = "Magical",   -- Charonus: Dark Waves

    -- Marked as tank hits in publicly available community boss research; damage
    -- type not recorded there, so it is Unknown until observed.
    [466064] = "Unknown",   -- Emberdawn: Searing Beak
    [467620] = "Unknown",   -- Commander Kro'luk: Rampage
    [472888] = "Unknown",   -- Derelict Duo: Bone Hack
    [1247937] = "Unknown",   -- Nysarra: Void Gash
    [1251023] = "Unknown",   -- Rak'tul: Spiritbreaker
    [1251554] = "Unknown",   -- Vor'daza: Drain Soul
    [1253950] = "Unknown",   -- Emberdawn: Searing Rend
    [1268562] = "Unknown",   -- Nymrissa Wavecaller: Water Jet (Mythic only)
    [466091] = "Unknown",   -- Emberdawn: Searing Beak
    [1222085] = "Unknown",   -- Taz'Rah: Cosmic Spike
    [1267049] = "Unknown",   -- Midnight Falls: Heaven's Lance
    [268007] = "Unknown",   -- Avatar of Sethraliss: Heart Attack
}

ns.TANK_ABILITIES_COUNT = 42

-------------------------------------------------------------------------------
--  Tank-buster fingerprints per boss, authored once and shipped.
--
--  Why data and not code: on a live timeline event, spellID and icons are
--  SECRET (measured live -- every event, every pull, and the boss's own cast
--  bar is sealed too), so no client can ask "is this ability a tank buster"
--  at runtime. The one plain per-ability handle is the event's base duration,
--  stable across pulls. Classification is therefore done ONCE by a person
--  with /nutank tank, exported with /nutank export, and pasted here. Players
--  install and it simply works.
--
--  A fingerprint identifies an ability WITHIN its encounter, never across
--  encounters. Keys are dungeonEncounterID; values are base durations
--  formatted "%.1f", matching FingerprintFor. A wrong entry is correctable
--  in game with /nutank mute, which runs after this filter.
--
--  Coverage is generated by Tools/extract_fingerprints.py, which joins
--  publicly available community boss-timeline research (read as FACTS --
--  encounter ids, base durations, ability names -- never copied as code)
--  against our own curated tank buster classification. Regenerate per season,
--  then /nutank tank + export patches anything the join missed.
--
--  This table lives in this file rather than its own for two reasons learned
--  the hard way. A brand-new TOC entry needs a full client relaunch before it
--  exists at all, so shipping data in an existing file makes every future
--  update a plain /reload. And the standalone file bound its namespace with
--  `local _, ns = ...` -- the addon's PRIVATE vararg table -- while this addon
--  shares `_G.NaowhUITankReminder`, so the file loaded fine and wrote its data
--  where no reader looks. Every file here must bind ns from the global.
-------------------------------------------------------------------------------
ns.TANK_FINGERPRINTS = {
    -- Encounter 3456 doubles as the validation row: 8.0 was measured live as the tank hit
    -- and 25.0/13.0/23.0 as non-tank before the extraction existed; it agrees.
    -- 3379 (Nymrissa) and 3183 (Midnight Falls) round to whole seconds upstream and carry
    -- stage-dependent duration reuse, so they lean on the tolerant whole-second match and
    -- may over-call on shared durations; /nutank mute is the correction.
    -- 2143 (Dazar) reuses 10.0 for Hunting Leap and Deathly Roar on alternate casts,
    -- and 2606 (Kokia) shares 40.0 with Ritual of Blazebinding; same over-call, same fix.
    [2124] = { ["31.0"] = true, ["36.0"] = true },   -- Overload
    [2125] = { ["5.0"] = true },   -- Lightning Bite
    [2139] = { ["8.0"] = true, ["25.0"] = true },   -- Tail Thrash
    [2140] = { ["2.0"] = true, ["7.0"] = true, ["14.0"] = true, ["22.0"] = true },   -- Arc Lightning, Debilitating Backhand
    [2143] = { ["8.0"] = true, ["10.0"] = true, ["23.0"] = true, ["24.0"] = true, ["30.0"] = true, ["36.0"] = true, ["38.0"] = true },   -- Blade Combo, Gilded Destruction, Hunting Leap, Savage Maul
    [2606] = { ["28.0"] = true, ["40.0"] = true },   -- Searing Blows
    [2623] = { ["5.0"] = true, ["22.5"] = true },   -- Stormslam
    [3056] = { ["10.0"] = true, ["13.0"] = true },   -- Searing Beak
    [3057] = { ["17.3"] = true },   -- Bone Hack
    [3058] = { ["3.0"] = true, ["30.0"] = true },   -- Rampage
    [3102] = { ["26.0"] = true },   -- Envenom
    [3103] = { ["6.0"] = true, ["27.0"] = true, ["35.0"] = true },   -- Demonic Rage, Legion Strike
    [3105] = { ["10.0"] = true, ["57.0"] = true },   -- Summon Vilefiend
    [3183] = { ["20.0"] = true, ["23.0"] = true, ["30.0"] = true, ["40.0"] = true },   -- Heaven's Lance
    [3199] = { ["5.0"] = true },   -- Bedrock Slam
    [3202] = { ["18.0"] = true, ["26.0"] = true, ["45.0"] = true, ["50.0"] = true },   -- Thornspike
    [3213] = { ["3.0"] = true, ["33.5"] = true },   -- Drain Soul
    [3214] = { ["4.0"] = true, ["26.4"] = true },   -- Spiritbreaker
    [3285] = { ["5.0"] = true, ["22.5"] = true, ["25.0"] = true },   -- Cosmic Spike, Void Blast
    [3286] = { ["7.0"] = true, ["10.0"] = true, ["20.0"] = true, ["25.0"] = true },   -- Hulking Claw
    [3287] = { ["34.0"] = true },   -- Dark Waves
    [3332] = { ["3.0"] = true, ["16.9"] = true },   -- Umbral Lash
    [3333] = { ["2.0"] = true, ["26.0"] = true },   -- Searing Rend
    [3379] = { ["17.0"] = true, ["29.0"] = true, ["40.0"] = true },   -- Water Jet
    [3456] = { ["8.0"] = true, ["24.0"] = true },   -- Triple Shot
    [3457] = { ["7.0"] = true, ["16.0"] = true },   -- Tail Scythe
    [3458] = { ["26.0"] = true, ["30.0"] = true },   -- Chop Down
}

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

-------------------------------------------------------------------------------
--  What each fingerprint is CALLED, per encounter -- every timeline event the
--  community research names, tank buster or not. Extracted alongside the
--  fingerprints; same provenance, same regeneration.
--
--  This is what turns "event 8.0 is coming" into "Triple Shot is coming": the
--  authored-reminder editor lists a boss's events by these names, and the
--  reminder text is keyed by the fingerprint underneath. Purely cosmetic to
--  the FILTER -- an unnamed fingerprint still works, it just shows as its
--  number in the editor.
-------------------------------------------------------------------------------
ns.EVENT_NAMES = {
    [2124] = { ["1.0"] = "Gale Force", ["4.0"] = "Thunder and Lightning", ["5.0"] = "Gale Force", ["9.0"] = "Thunder and Lightning", ["12.0"] = "Tempest Winds", ["19.0"] = "Gale Force", ["21.0"] = "Tempest Winds", ["26.0"] = "Tempest Winds", ["31.0"] = "Overload", ["36.0"] = "Overload", ["42.0"] = "Gale Force" },
    [2125] = { ["5.0"] = "Lightning Bite", ["13.0"] = "A Knot of Snakes", ["25.0"] = "Thunder Spit", ["36.0"] = "Serpentstorm", ["44.0"] = "Hatch", ["49.0"] = "Burrow" },
    [2126] = { ["5.0"] = "Lightning Spire", ["20.0"] = "Induction", ["22.0"] = "Induction / Lightning Spire" },
    [2127] = { ["15.0"] = "Defiling Taint", ["32.5"] = "Stage One" },
    [2139] = { ["5.0"] = "Spit Gold", ["8.0"] = "Tail Thrash", ["14.0"] = "Serpentine Gust", ["25.0"] = "Spit Gold / Tail Thrash", ["28.0"] = "Serpentine Gust", ["54.0"] = "Lucre's Call" },
    [2140] = { ["2.0"] = "Arc Lightning", ["5.0"] = "Barrel Through", ["7.0"] = "Arc Lightning", ["8.0"] = "Whirling Axes", ["10.0"] = "Poison Nova", ["14.0"] = "Debilitating Backhand", ["14.8"] = "Whirling Axes", ["15.0"] = "Severing Axe", ["16.5"] = "Severing Axe", ["20.0"] = "Barrel Through / Call of the Elements", ["22.0"] = "Debilitating Backhand", ["24.0"] = "Poison Nova", ["24.4"] = "Poison Nova", ["25.2"] = "Poison Nova", ["52.5"] = "Call of the Elements" },
    [2142] = { ["5.0"] = "Drain Fluids", ["20.0"] = "Burn Corruption", ["30.0"] = "Awakening Slam / Burn Corruption", ["32.0"] = "Drain Fluids", ["60.0"] = "Entomb" },
    [2143] = { ["8.0"] = "Hunting Leap", ["9.0"] = "Quaking Leap", ["10.0"] = "Deathly Roar / Hunting Leap", ["14.0"] = "Deathly Roar", ["15.0"] = "Aerial Smash", ["23.0"] = "Blade Combo", ["24.0"] = "Gilded Destruction", ["30.0"] = "Gilded Destruction", ["36.0"] = "Savage Maul", ["38.0"] = "Blade Combo" },
    [2606] = { ["8.0"] = "Ritual of Blazebinding", ["19.0"] = "Molten Boulder", ["20.0"] = "Molten Boulder", ["28.0"] = "Searing Blows", ["40.0"] = "Ritual of Blazebinding / Searing Blows" },
    [2609] = { ["6.0"] = "Hailburst", ["12.0"] = "Frost Overload", ["16.0"] = "Chillstorm", ["27.0"] = "Chillstorm / Hailburst" },
    [2623] = { ["1.0"] = "Roaring Firebreath", ["5.0"] = "Stormslam", ["9.0"] = "Inferno Spit", ["10.0"] = "Winds of Change", ["12.0"] = "Inferno Spit", ["16.0"] = "Inferno Spit / Roaring Firebreath", ["20.0"] = "Inferno Spit / Roaring Firebreath", ["21.0"] = "Interrupting Cloudburst", ["21.5"] = "Winds of Change", ["22.5"] = "Stormslam", ["25.0"] = "Interrupting Cloudburst" },
    [3056] = { ["6.0"] = "Flaming Updraft", ["10.0"] = "Searing Beak", ["13.0"] = "Searing Beak", ["15.0"] = "Burning Gale", ["15.5"] = "Flaming Updraft", ["30.0"] = "Burning Gale" },
    [3057] = { ["8.0"] = "Splattering Spew", ["17.3"] = "Bone Hack", ["22.7"] = "Curse of Darkness", ["27.3"] = "Splattering Spew", ["48.0"] = "Debilitating Shriek" },
    [3058] = { ["0.0"] = "3x in a row on stage change / Bladestorm", ["3.0"] = "Rampage", ["8.0"] = "Bladestorm / Get Rename", ["10.0"] = "Reckless Leap", ["18.0"] = "Intimidating Shout", ["30.0"] = "Rampage", ["37.0"] = "Reckless Leap", ["45.0"] = "Intimidating Shout" },
    [3059] = { ["9.0"] = "Arrow Rain", ["11.0"] = "Arrow Rain", ["21.0"] = "Tempest Slash", ["23.5"] = "Gust Shot", ["24.0"] = "Bullseye Windblast", ["39.0"] = "Bolt Gale", ["53.0"] = "Bullseye Windblast" },
    [3071] = { ["5.0"] = "Repulsing Slam", ["15.0"] = "Arcane Expulsion", ["22.0"] = "Ethereal Shackles", ["22.5"] = "Repulsing Slam", ["23.0"] = "Arcane Expulsion", ["45.0"] = "Get Stage / Refueling Protocol", ["48.0"] = "Refueling Protocol / Set Stage" },
    [3072] = { ["7.0"] = "Runic Mark", ["17.0"] = "Suppression Zone", ["26.0"] = "Hastening Ward", ["29.0"] = "Runic Mark", ["51.0"] = "Wave of Silence" },
    [3073] = { ["5.0"] = "Cosmic Sting / Triplicate", ["8.0"] = "Cosmic Sting", ["16.0"] = "Neural Link", ["29.0"] = "Astral Grasp" },
    [3074] = { ["3.0"] = "Hulking Fragment", ["7.0"] = "Hulking Fragment", ["9.0"] = "Devouring Entropy", ["13.0"] = "Devouring Entropy", ["15.0"] = "Hulking Fragment / Unstable Void Essence", ["16.0"] = "Unstable Void Essence", ["20.0"] = "Devouring Entropy", ["22.0"] = "Devouring Entropy / Hulking Fragment / Unstable Void Essence", ["24.0"] = "Devouring Entropy / Hulking Fragment / Unstable Void Essence", ["31.0"] = "Unstable Void Essence" },
    [3101] = { ["8.0"] = "Fel Spray", ["12.0"] = "Cancel Bar For Spell", ["15.0"] = "Mirror Images", ["25.0"] = "Cancel Bar For Spell", ["27.5"] = "Fel Spray", ["30.0"] = "Mirror Images" },
    [3102] = { ["8.0"] = "Killing Spree", ["12.0"] = "Same-Day Delivery", ["16.0"] = "Same-Day Delivery", ["18.0"] = "Fire Bomb", ["26.0"] = "Envenom", ["36.0"] = "Murder in a Row" },
    [3103] = { ["6.0"] = "Legion Strike", ["15.0"] = "Axe Toss", ["27.0"] = "Legion Strike", ["30.0"] = "Infernal Crush", ["35.0"] = "Demonic Rage" },
    [3105] = { ["10.0"] = "Summon Vilefiend", ["15.0"] = "Fingers of Gul'dan", ["24.0"] = "Malefic Wave", ["55.0"] = "Fingers of Gul'dan", ["57.0"] = "Summon Vilefiend", ["59.0"] = "Malefic Wave" },
    [3182] = { ["6.0"] = "Radiant Echoes", ["8.0"] = "Embers of Beloren", ["10.0"] = "Easy / Infused Quills", ["16.0"] = "Guardian's Edict", ["18.0"] = "Guardian's Edict", ["19.0"] = "Infused Quills", ["20.0"] = "Guardian's Edict", ["21.0"] = "Infused Quills", ["30.0"] = "Eternal Burns", ["34.0"] = "Eternal Burns", ["40.0"] = "Rebirth", ["50.0"] = "Voidlight Convergence" },
    [3183] = { ["3.0"] = "Termination Prism", ["4.0"] = "Dark Constellation Mythic", ["6.0"] = "Dark Constellation / Dark Constellation Mythic", ["7.0"] = "Dark Constellation Mythic", ["10.0"] = "Death's Dirge", ["13.0"] = "Galvanize", ["14.0"] = "The Dark Archangel", ["18.0"] = "Light Siphon", ["20.0"] = "Dark Constellation Mythic / Heaven's Lance / Light Siphon", ["23.0"] = "Dark Constellation Mythic / Heaven's Lance", ["26.0"] = "Dark Constellation / Heaven's Glaives", ["30.0"] = "Galvanize / Heaven's Lance", ["31.0"] = "Grim Symphony / Light Siphon", ["33.0"] = "Core Harvest / Dark Constellation", ["35.0"] = "Heaven's Glaives / Light Siphon", ["38.0"] = "Easy", ["40.0"] = "Dark Quasar / Heaven's Lance", ["45.0"] = "Into The Darkwell", ["55.0"] = "Safeguard Prism / The Dark Archangel", ["57.0"] = "Dark Quasar / The Dark Archangel", ["62.0"] = "Termination Prism", ["70.0"] = "Death's Dirge", ["97.0"] = "Dark Meltdown / Set Stage", ["180.0"] = "Bar / Total Eclipse" },
    [3199] = { ["4.0"] = "Thornblade", ["5.0"] = "Bedrock Slam", ["8.0"] = "Thornblade", ["10.0"] = "Thornblade", ["20.0"] = "Lightsower Dash", ["35.0"] = "Lightblossom Beam" },
    [3200] = { ["6.0"] = "Verdant Stomp", ["20.0"] = "Thorncaller Roar", ["22.0"] = "Thorncaller Roar", ["29.0"] = "Verdant Stomp", ["40.0"] = "Bloodthirsty Gaze", ["50.0"] = "Bloodthirsty Gaze" },
    [3201] = { ["0.5"] = "Shapeshift: Moonkin", ["2.5"] = "Spirits of the Vale", ["3.0"] = "Grievous Thrash", ["5.0"] = "Lightfire", ["7.3"] = "Lightfire", ["9.0"] = "Pulverizing Strikes", ["15.3"] = "Grievous Thrash", ["18.0"] = "Lightfall", ["23.3"] = "Lightfall", ["31.3"] = "Pulverizing Strikes", ["32.0"] = "Grievous Thrash / Lightfall / Lightfire / Pulverizing Strikes" },
    [3202] = { ["4.0"] = "Awaken the Lightbloom", ["14.0"] = "Lightbloom's Essence", ["18.0"] = "Thornspike", ["26.0"] = "Thornspike", ["32.0"] = "Concentrated Lightbeam", ["40.0"] = "Concentrated Lightbeam", ["45.0"] = "Awaken the Lightbloom / Concentrated Lightbeam / Thornspike", ["50.0"] = "Awaken the Lightbloom / Concentrated Lightbeam / Lightbloom's Essence / Thornspike" },
    [3207] = { ["6.0"] = "Ravenous Bellow", ["16.0"] = "Earthshatter Slam", ["30.0"] = "Spoiled Supplies" },
    [3208] = { ["7.0"] = "Glacial Torment", ["13.0"] = "Raging Squall", ["25.0"] = "Shattering Frostspike", ["50.0"] = "Frozen Tempest" },
    [3209] = { ["5.0"] = "Echoing Maul", ["10.0"] = "Echoing Maul", ["13.0"] = "Overwhelming Onslaught", ["25.0"] = "Echoing Maul / Fury of the War God / Overwhelming Onslaught", ["54.0"] = "Fury of the War God" },
    [3212] = { ["5.0"] = "Flanking Spear", ["12.0"] = "Infected Pinions", ["20.0"] = "Freezing Trap", ["28.0"] = "Fetid Quillstorm", ["35.0"] = "Barrage", ["41.0"] = "Carrion Swoop", ["45.0"] = "Barrage / Carrion Swoop / Fetid Quillstorm / Flanking Spear / Freezing Trap / Infected Pinions" },
    [3213] = { ["3.0"] = "Drain Soul", ["14.2"] = "Wrest Phantoms", ["25.3"] = "Unmake", ["33.5"] = "Drain Soul / Unmake / Wrest Phantoms", ["70.0"] = "Necrotic Convergence" },
    [3214] = { ["4.0"] = "Spiritbreaker", ["17.2"] = "Crush Souls", ["26.4"] = "Crush Souls / Spiritbreaker", ["70.0"] = "Soulrending Roar" },
    [3285] = { ["5.0"] = "Cosmic Spike", ["6.0"] = "Nether Dash", ["12.0"] = "Dark Rift", ["16.0"] = "Umbral Rupture", ["22.5"] = "Cosmic Spike", ["25.0"] = "Void Blast", ["31.0"] = "Dark Bloom", ["35.0"] = "Gather Shadows", ["50.0"] = "Dark Rift / Gather Shadows" },
    [3286] = { ["5.0"] = "Poison Splash", ["7.0"] = "Hulking Claw", ["10.0"] = "Hulking Claw", ["13.0"] = "Poison Splash", ["15.0"] = "Noxious Breath", ["17.0"] = "Provoke Creeper", ["20.0"] = "Hulking Claw / Poison Splash", ["21.0"] = "Noxious Breath", ["23.0"] = "Poison Splash", ["25.0"] = "Hulking Claw", ["30.0"] = "Noxious Breath", ["35.0"] = "Monstrous Roar / Provoke Creeper", ["42.0"] = "Monstrous Stomp" },
    [3287] = { ["5.0"] = "Unstable Singularity", ["17.0"] = "Cosmic Crash", ["19.0"] = "Cosmic Crash", ["28.0"] = "Gravitic Orbs", ["34.0"] = "Dark Waves", ["36.0"] = "Gravitic Orbs", ["40.0"] = "Unstable Singularity", ["43.0"] = "Void Cascade", ["44.0"] = "Gravitic Orbs", ["44.8"] = "Cosmic Crash" },
    [3328] = { ["1.0"] = "Leyline Array", ["5.0"] = "Reflux Charge", ["10.0"] = "Flux Collapse", ["11.0"] = "Leyline Array", ["12.0"] = "Reflux Charge", ["13.0"] = "Flux Collapse", ["38.0"] = "Corespark Detonation" },
    [3332] = { ["3.0"] = "Umbral Lash", ["5.0"] = "Eclipsing Step", ["15.0"] = "Devour the Unworthy / Null Vanguard", ["16.9"] = "Umbral Lash", ["18.0"] = "Eclipsing Step", ["28.0"] = "Lightscar Flare", ["61.0"] = "Lightscar Flare / Null Vanguard" },
    [3333] = { ["2.0"] = "Searing Rend", ["10.0"] = "Flicker", ["11.0"] = "Brilliant Dispersion", ["24.0"] = "Flicker", ["25.0"] = "Brilliant Dispersion", ["26.0"] = "Searing Rend", ["52.0"] = "Divine Guile" },
    [3379] = { ["3.0"] = "Mythic", ["9.0"] = "Abyssal Rain", ["13.0"] = "Water Flurry", ["17.0"] = "Water Jet", ["20.0"] = "Frost Barrage", ["24.0"] = "Frost Barrage", ["27.0"] = "Alluring Bubble", ["29.0"] = "Water Jet", ["30.0"] = "Water Flurry", ["31.0"] = "Frost Barrage", ["33.0"] = "Frost Barrage", ["40.0"] = "Water Jet", ["46.0"] = "Frost Barrage", ["49.0"] = "Water Flurry", ["51.0"] = "Frost Barrage", ["64.0"] = "Tidepiercer's Rush", ["68.0"] = "Tidepiercer's Rush" },
    [3456] = { ["8.0"] = "Triple Shot", ["13.0"] = "Regurgitate", ["23.0"] = "Ravenous Stomp", ["24.0"] = "Triple Shot", ["25.0"] = "Ssscavenging", ["45.0"] = "Ssscavenging" },
    [3457] = { ["1.0"] = "Synchronized Venom", ["7.0"] = "Tail Scythe", ["10.0"] = "Synchronized Venom / Toxic Atrophy", ["14.0"] = "Preparing Toxin", ["16.0"] = "Tail Scythe", ["23.0"] = "Preparing Toxin", ["25.0"] = "Assimilation", ["30.0"] = "Vindictive Onslaught", ["39.0"] = "Vindictive Onslaught", ["44.0"] = "Death Rattle", ["53.0"] = "Death Rattle" },
    [3458] = { ["14.0"] = "Axegrinder / Boneslicer", ["26.0"] = "Chop Down", ["30.0"] = "Chop Down", ["32.0"] = "Boneslicer", ["64.0"] = "Ritual of the Fang" },
}
