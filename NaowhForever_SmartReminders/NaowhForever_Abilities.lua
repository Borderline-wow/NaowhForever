-------------------------------------------------------------------------------
--  NaowhForever_Abilities.lua -- tank busters the game does not flag.
--
--  GENERATED. Regenerate rather than hand-editing.
--
--  The one data set not read from the client: Blizzard's TankRole bit covers only 13
--  of the 31 tank busters this season. Additive -- an ability is called if Blizzard
--  flags it OR it is listed here. Keyed by spell id (encounterEventIDs can be
--  reallocated between builds); the value is the damage type.
--  Classification from Tactyks' public Season 2 dungeon spreadsheet.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
if not ns then return end

ns.TANK_ABILITIES = {
    -- Audited against BigWigs/LittleWigs and DBM source 2026-08-26. Removed because neither
    -- mod broadcasts them: Frigid Shard 372808, Chaos Barrage 1230298, Warden's Wrath
    -- 1239821, Forceful Slam 1297797, Heart Attack 268007, Tainted Strike 1303446, Searing
    -- Beak aura 466091. Do not re-add from the sheet without rechecking the modules.
    [265910] = "Physical",   -- The Golden Serpent: Tail Thrash
    [266237] = "Physical",   -- The Council of Tribes: Debilitating Backhand
    [268586] = "Physical",   -- Dazar, The First King: Blade Combo
    [372858] = "Mixed",   -- Kokia Blazehoof: Searing Blows
    [381512] = "Mixed",   -- Kyrakka and Erkhart Stormvein: Stormslam
    [473898] = "Physical",   -- Xathuux the Annihilator: Legion Strike
    [1222642] = "Magical",   -- Atroxus: Hulking Claw
    [1222795] = "Mixed",   -- Zaen Bladesorrow: Envenom
    [1234753] = "Mixed",   -- Lightblossom Trinity: Bedrock Slam
    [1247685] = "Mixed",   -- Ziekket: Thornspike
    [1311804] = "Mixed",   -- Adderis and Aspix: Overload (was 1288428; BigWigs bars 1311804)
    [1290797] = "Mixed",   -- Merektha: Lightning Bite
    -- 1296220 (Rav'i: Triple Shot) deliberately NOT here: the journal flags it Healer and
    -- BigWigs targets it by mechanic, not threat. Listing it played the tank-hit sound
    -- (RegisterEventSounds's "curated" check) for a healer mechanic.
    [1297017] = "Magical",   -- Taz'Rah: Void Blast
    [1298949] = "Physical",   -- The Writhing Coil: Tail Scythe
    [1301350] = "Physical",   -- Zul'jan: Chop Down
    -- Dazar's Hunting Leap (269230) and Savage Maul (1303488) deliberately NOT here: tank
    -- bleeds, not busters; both mods treat only Blade Combo as a defensive. Live, Savage
    -- Maul called two seconds before Blade Combo and asked for defensives back to back.
    -- Still available from Setup's per-boss checkbox.
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
    [1253950] = "Unknown",   -- Lothraxion: Searing Rend (Nexus Point Xenas)
    -- DBM-only (LittleWigs has it as an aura option with no bar); 1253950 above is the
    -- BigWigs-only mirror.
    [1255335] = "Unknown",   -- Lothraxion: Searing Rend
    [1268562] = "Unknown",   -- Nymrissa Wavecaller: Water Jet (Mythic only)
    [1267049] = "Unknown",   -- Midnight Falls: Heaven's Lance
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
    -- The debuff 1284103 never reaches BigWigs_Message/StartBar; Nekzali.lua's bar is
    -- keyed by 1292036.
    [1292036] = "Unknown",   -- Nek'zali the Soulcoiler: Possession Barrage
    -- Hollowing Strikes (1284110, stacking debuff) deliberately NOT here: default off,
    -- still enabled per-boss from Setup (its Tank tag comes from the journal).

    -- Tank hits the modules gate on a role check in code instead of flagging, so the
    -- sheet missed them (audit 2026-08-20, after Den of Nalorakk called nothing).
    [472662] = "Unknown",   -- The Restless Heart: Tempest Slash
    [474496] = "Unknown",   -- Arcanotron Custos: Repulsing Slam
    [1243569] = "Unknown",   -- Nalorakk: Overwhelming Onslaught
    [1266480] = "Unknown",   -- Murojin and Nekraxx: Flanking Spear
    [1280113] = "Unknown",   -- Degentrius: Hulking Fragment
    -- Driven by Blizzard event ids, not bar durations; needs /nutank learn then /nutank tank.
    [1298367] = "Unknown",   -- Ula'tek: Mother's Wrath
}

-- BigWigs broadcast key -> journal id where they differ; Setup's store is keyed by journal id.
ns.BOSSMOD_KEY_TO_JOURNAL = {
    [1292036] = 1284103,   -- Nek'zali the Soulcoiler: Possession Barrage
}

-- DBM keys some warnings by the aura id; everything here speaks BigWigs ids, so DBM
-- timer ids go through this map before ns.HandleBigWigsAbility.
ns.DBM_TO_BIGWIGS = {
    [1241836] = 1241692,   -- Vorasius: Shadowclaw Slam
    [1288484] = 1288538,   -- The Twin Fangs: Stone Breaker
    [1253024] = 1250803,   -- Fallen-King Salhadaar: Shattering Twilight
    [1287227] = 1307279,   -- The Coiled Altar: Blighted Sever
    [1284103] = 1292036,   -- Nek'zali the Soulcoiler: Possession Barrage
}

-- Timeline-driven BigWigs bars (ENCOUNTER_TIMELINE_EVENT_ADDED, no cast) never teach
-- castSourceGUID a caster, so TankingCaster fell back to "tanking any boss", wrong when
-- each tank holds a different boss. Spell id -> owning boss slot.
--
-- Slot, not npcID: UnitGUID is SecretWhenUnitIdentityRestricted for boss units in a
-- raid. An npcID-keyed map shipped first and missed every Coiled Altar callout.
ns.TANK_ABILITY_OWNER_UNIT = {
    -- DBM: "ALways boss2, unless boss1 is dead".
    [1288538] = 2,   -- The Twin Fangs: Stone Breaker (Ithraz)
    -- Filed under BigWigs' "-- Vexhul" heading.
    [1289192] = 1,   -- The Twin Fangs: Caustic Deluge (Vexhul)

    -- BigWigs registers Malacrass's channel on boss2, leaving Zul'jan boss1.
    [1299680] = 1,   -- The Coiled Altar: Sever (Zul'jan)
    [1286573] = 2,   -- The Coiled Altar: Soul Sever (Hex Lord Malacrass)
    -- Filed under BigWigs' "-- Zul'jan" Stage 3 heading.
    [1307279] = 1,   -- The Coiled Altar: Blighted Sever (Zul'jan)

    -- Explorers.lua: boss1 Gebbo, boss3 Nama, boss4 Iku; DBM checks boss4 too.
    [1295854] = 4,   -- The Lost Explorers: Shredding Shards (Scrollsage Iku)

    -- BigWigs gates the Message on threat but runs the CDBar unconditionally.
    [1284458] = 1,   -- Entombed Sentinels: Empowering Slam (Breath of Ula'tek)
    [1284487] = 2,   -- Entombed Sentinels: Bloodvenom Injection (Blood of Ula'tek)

    -- Adds fill the other boss frames, and tanking one used to trigger this.
    [1298367] = 1,   -- Ula'tek: Mother's Wrath

    -- Single-boss encounters, from the BigWigs/LittleWigs modules: always boss1.
    --
    -- Dungeons.
    [265910] = 1,  -- The Golden Serpent: Tail Thrash
    [268586] = 1,  -- Dazar, The First King: Blade Combo
    [372858] = 1,  -- Kokia Blazehoof: Searing Blows
    [466064] = 1,  -- Emberdawn: Searing Beak
    [467620] = 1,  -- Commander Kro'luk: Rampage
    [472662] = 1,  -- The Restless Heart: Tempest Slash
    [473898] = 1,  -- Xathuux the Annihilator: Legion Strike
    [474496] = 1,  -- Arcanotron Custos: Repulsing Slam
    [1222642] = 1, -- Atroxus: Hulking Claw
    [1222795] = 1, -- Zaen Bladesorrow: Envenom
    [1243569] = 1, -- Nalorakk: Overwhelming Onslaught
    [1247685] = 1, -- Ziekket: Thornspike
    [1247937] = 1, -- Nysarra: Void Gash
    [1251023] = 1, -- Rak'tul: Spiritbreaker
    [1251554] = 1, -- Vor'daza: Drain Soul
    [1253950] = 1, -- Lothraxion: Searing Rend (Nexus Point Xenas)
    [1255335] = 1, -- Lothraxion: Searing Rend
    [1280113] = 1, -- Degentrius: Hulking Fragment
    [1290797] = 1, -- Merektha: Lightning Bite
    [1297017] = 1, -- Taz'Rah: Void Blast
    [1298949] = 1, -- The Writhing Coil: Tail Scythe
    [1301350] = 1, -- Zul'jan: Chop Down
    [1311923] = 1, -- Charonus: Dark Waves

    -- Raid, lairs and world.
    [1221781] = 1, -- Rotmire: Putrid Fist
    [1241692] = 1, -- Vorasius: Shadowclaw Slam
    [1250803] = 1, -- Fallen-King Salhadaar: Shattering Twilight
    [1260763] = 1, -- Belo'ren, Child of Al'ar: Guardian's Edict
    [1268562] = 1, -- Nymrissa Wavecaller: Water Jet (Mythic only)
    [1277025] = 1, -- Sszorak: Apex Predator
    [1280935] = 1, -- Vashnik the Malignant: Dripping Fangs
    [1292036] = 1, -- Nek'zali the Soulcoiler: Possession Barrage

    -- Multi-boss fights the modules pin to a slot themselves.
    -- BigWigs gates Heaven's Lance on ThreatTarget(unit, "boss1").
    [1267049] = 1, -- Midnight Falls: Heaven's Lance
    -- GetOptions files it under "-- Vaelgor", boss1 per the module's own note.
    [1262623] = 1, -- Vaelgor & Ezzorak: Nullbeam
    -- BigWigs gates its sound on ThreatTarget("player", "boss1") -- Vaelgor.
    [1265131] = 1, -- Vaelgor & Ezzorak: Vaelwing
    -- The same check for Ezzorak, boss2, sits commented out beside Rakfang's Message.
    [1245645] = 2, -- Vaelgor & Ezzorak: Rakfang
    -- Triple Shot is a PersonalMessage at whoever BigWigs picked, not aggro-driven; a
    -- slot gate would silence it for its real target.

    -- Deliberately absent, multi-unit fights with no fixed slot: Grappling Maw, Overload
    -- (slot resolved by GUID at fire time), Stormslam, Debilitating Backhand (Council
    -- rotates boss1), Bedrock Slam, Bone Hack, Flanking Spear, both Judgements and both
    -- Crown of the Cosmos abilities. A wrong slot silences a real call, so they keep the
    -- any-boss fallback until a live capture settles the slot.
}

