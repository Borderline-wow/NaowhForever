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
    [1298683] = "Physical",   -- Rav'i: Hydrastrike
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
}

ns.TANK_ABILITIES_COUNT = 38

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
    -- Encounter 3456 doubles as the validation row: 8.0 was measured live as
    -- the tank hit (called out both casts) and 25.0/13.0/23.0 as non-tank
    -- (silenced) before the extraction existed; the extraction agrees and adds
    -- the 24.0 late-cast variant live testing had not yet seen.
    [3056] = { ["10.0"] = true, ["13.0"] = true },                 -- Searing Beak
    [3057] = { ["17.3"] = true },                                  -- Bone Hack
    [3058] = { ["3.0"] = true, ["30.0"] = true },                  -- Rampage
    [3102] = { ["26.0"] = true },                                  -- Envenom
    [3103] = { ["6.0"] = true, ["27.0"] = true, ["35.0"] = true }, -- Demonic Rage, Legion Strike
    [3105] = { ["10.0"] = true, ["57.0"] = true },                 -- Summon Vilefiend
    [3199] = { ["5.0"] = true },                                   -- Bedrock Slam
    [3213] = { ["3.0"] = true, ["33.5"] = true },                  -- Drain Soul
    [3214] = { ["4.0"] = true, ["26.4"] = true },                  -- Spiritbreaker
    [3285] = { ["25.0"] = true },                                  -- Void Blast
    [3286] = { ["7.0"] = true, ["10.0"] = true, ["20.0"] = true, ["25.0"] = true }, -- Hulking Claw
    [3287] = { ["34.0"] = true },                                  -- Dark Waves
    [3332] = { ["3.0"] = true, ["16.9"] = true },                  -- Umbral Lash
    [3333] = { ["2.0"] = true, ["26.0"] = true },                  -- Searing Rend
    [3456] = { ["8.0"] = true, ["24.0"] = true },                  -- Triple Shot
    [3457] = { ["7.0"] = true, ["16.0"] = true },                  -- Tail Scythe
    [3458] = { ["26.0"] = true, ["30.0"] = true },                 -- Chop Down
}
